-- Wolf's Toolbox (uncommon) -- killing enemies cuts active drill/saw timers.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Two hook targets in one file: CopDamage (kill -> cut timer) and TimerGui
-- (track active devices). The tracked-device set is a file-local upvalue shared
-- by both hook closures (the file is dofile'd once).
--
-- Always triggers (no RNG); a special enemy (priority_shout) cuts more. Two timer
-- surfaces, two authority models:
--   * TimerGui drill/saw DEVICES are HOST-authoritative. The host reduces
--     directly; a CLIENT kill RPCs the host the reduction it computed from its
--     OWN stacks, and the host applies it.
--   * Saw INTERACTIONS (player personally sawing) are local PlayerStandard
--     timers -- every peer reduces its own directly.
-- Kill detection uses CopDamage:die (fires once per death from ANY cause, so a
-- fire/tase kill still cuts the drill; no per-corpse dedup flag needed).
-- Values mirror the 6.2 register line (normal_base 0.2 / _normal_extra 0.1 /
-- special_base 1.0 / _special_extra 0.5).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local NORMAL_BASE = 0.2
local NORMAL_EXTRA = 0.1
local SPECIAL_BASE = 1.0
local SPECIAL_EXTRA = 0.5
local WOLF_KILL_RPC = "CSR_WolfKill"

-- Saw-based timed INTERACTIONS (InteractionExt timers, not TimerGui devices).
local SAW_INTERACTIONS = {
	hospital_saw = true,
	hospital_saw_jammed = true,
	apartment_saw = true,
	apartment_saw_jammed = true,
	secret_stash_saw = true,
	secret_stash_saw_jammed = true,
	gen_pku_saw = true,
	gen_pku_saw_axis = true,
	gen_int_saw = true,
	gen_int_saw_jammed = true,
}

-- Alive, non-jammed TimerGui drill/saw devices the local session has seen start.
-- Tracked on every peer (devices are synced): the host uses it to reduce, a
-- client to decide whether a kill is worth RPCing.
local tracked_drills = {}

-- Run active AND the local player owns >= 1 Wolf's Toolbox.
local function wolfs_active(mgr)
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return false
	end
	return mgr:owned("wolfs_toolbox") > 0
end

-- Seconds to cut for one kill, given owned stacks and whether the kill was special.
local function wolfs_reduction(stacks, is_special)
	if is_special then
		return SPECIAL_BASE + (stacks - 1) * SPECIAL_EXTRA
	end
	return NORMAL_BASE + (stacks - 1) * NORMAL_EXTRA
end

-- The local player's current saw-interaction state, or nil. Locally owned, so
-- valid on every peer.
local function local_saw_state()
	local player = managers.player and managers.player:player_unit()
	if not alive(player) then
		return nil
	end
	local movement = player:movement()
	local state = movement and movement:current_state()
	if not state or not state._interact_expire_t then
		return nil
	end
	local params = state._interact_params
	if not params or not params.tweak_data or not SAW_INTERACTIONS[params.tweak_data] then
		return nil
	end
	return state
end

-- True if any tracked TimerGui drill/saw device is alive and not jammed.
local function has_active_drill()
	for unit in pairs(tracked_drills) do
		if alive(unit) then
			local tg = unit:timer_gui()
			if tg and not tg._jammed then
				return true
			end
		end
	end
	return false
end

-- Reduce every alive, non-jammed tracked drill/saw timer by `seconds`. Prunes
-- dead units in passing. Host / SP only (drill timers are host-authoritative).
local function apply_drill_reduction(seconds)
	if seconds <= 0 then
		return
	end
	for unit in pairs(tracked_drills) do
		if alive(unit) then
			local tg = unit:timer_gui()
			if tg and not tg._jammed and tg._current_timer and tg._current_timer > 0 then
				tg._current_timer = math.max(0, tg._current_timer - seconds)
			end
		else
			tracked_drills[unit] = nil
		end
	end
end

_G.CSR.register_item({
	type = "wolfs_toolbox",
	rarity = "uncommon",
	name = "csr_logbook_wolfs_toolbox_name",
	desc = "csr_item_wolfs_toolbox_desc",
	full_desc = "csr_logbook_wolfs_toolbox_effect",
	notes = "csr_logbook_wolfs_toolbox_notes",
	-- Icon id is "toolbox" in hudicons.lua (legacy name), not csr_wolfs_toolbox.
	icon = "csr_toolbox",
	icon_scale = 1.0,

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_WOLFS_KILL_HOOKED then
				return
			end
			_G._CSR_WOLFS_KILL_HOOKED = true

			Hooks:PostHook(CopDamage, "die", "CSR_WolfsToolbox_Kill", function(self, attack_data)
				local mgr = managers and managers.csr
				if not wolfs_active(mgr) then
					return
				end
				local au = attack_data and attack_data.attacker_unit
				if not au or not au:base() or au:base().is_local_player ~= true then
					return
				end

				local is_special = (self._char_tweak and self._char_tweak.priority_shout) and true or false
				local reduction = wolfs_reduction(mgr:owned("wolfs_toolbox"), is_special)
				if reduction <= 0 then
					return
				end

				-- Saw interactions are locally owned -- reduce directly on every peer.
				local saw_state = local_saw_state()
				if saw_state then
					saw_state._interact_expire_t = math.max(0, saw_state._interact_expire_t - reduction)
					if mgr:debug_enabled() then
						mgr:debug_log(
							string.format(
								"wolfs_toolbox saw interaction -%.2fs (special=%s)",
								reduction,
								tostring(is_special)
							)
						)
					end
				end

				-- TimerGui drills are host-authoritative.
				if not has_active_drill() then
					return
				end
				if Network:is_client() then
					LuaNetworking:SendToPeer(1, WOLF_KILL_RPC, string.format("%.4f", reduction))
					if mgr:debug_enabled() then
						mgr:debug_log(string.format("wolfs_toolbox client kill -> RPC host -%.2fs", reduction))
					end
				else
					apply_drill_reduction(reduction)
					if mgr:debug_enabled() then
						mgr:debug_log(
							string.format("wolfs_toolbox drill -%.2fs (special=%s)", reduction, tostring(is_special))
						)
					end
				end
			end)

			-- Host applies a client's kill reduction to its authoritative timers.
			Hooks:Add("NetworkReceivedData", "CSR_WolfsToolbox_NetKill", function(sender, id, data)
				if id ~= WOLF_KILL_RPC then
					return
				end
				if not Network:is_server() then
					return
				end
				apply_drill_reduction(tonumber(data) or 0)
			end)
		end,

		["lib/units/props/timergui"] = function()
			if _G._CSR_WOLFS_TIMER_HOOKED then
				return
			end
			_G._CSR_WOLFS_TIMER_HOOKED = true

			-- Register a drill/saw device as active. Gated only on a live run, so
			-- picking the item after a drill has started still tracks it on the next
			-- _start call.
			Hooks:PostHook(TimerGui, "_start", "CSR_WolfsToolbox_TimerStart", function(self)
				local mgr = managers and managers.csr
				if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
					return
				end
				local unit = self._unit
				if not unit or not alive(unit) then
					return
				end
				local base = unit:base()
				if not base then
					return
				end
				-- Drills and saws only (is_drill / is_saw are boolean fields). Exclude
				-- hacking devices. Fallback: a non-hacking unit that still has a
				-- timer_gui counts (catches overdrill / special drills missing the flag).
				local is_valid = base.is_drill or base.is_saw or (not base.is_hacking_device and unit:timer_gui())
				if not is_valid then
					return
				end
				tracked_drills[unit] = true
			end)

			Hooks:PostHook(TimerGui, "done", "CSR_WolfsToolbox_TimerDone", function(self)
				if self._unit then
					tracked_drills[self._unit] = nil
				end
			end)
		end,
	},
})
