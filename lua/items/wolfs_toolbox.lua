-- Wolf's Toolbox (uncommon) — kills cut drill/saw timers.
-- Two timer surfaces: TimerGui devices (HOST authoritative; client kills RPC the host,
-- host mirrors the cut back to every peer) and saw INTERACTIONS (local PlayerStandard;
-- each peer reduces its own).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local NORMAL_BASE = 0.2
local NORMAL_EXTRA = 0.1
local SPECIAL_BASE = 1.0
local SPECIAL_EXTRA = 0.5
local WOLF_KILL_RPC = "CSR_WolfKill" -- client -> host: my kill
local WOLF_SYNC_RPC = "CSR_WolfSync" -- host -> all: apply this cut locally

-- Saw INTERACTIONS (InteractionExt timers, not TimerGui devices).
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

-- TimerGui devices the session has seen start. Tracked on every peer (synced).
local tracked_drills = {}

-- Debug tracing, gated by the mod-wide _G.CSR_DEBUG toggle.
local function dbg(fmt, ...)
	if _G.CSR_DEBUG and csr_log then
		csr_log("[WT] " .. string.format(fmt, ...))
	end
end

local function wolfs_active(mgr)
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
		return false
	end
	return mgr:owned("wolfs_toolbox") > 0
end

local function wolfs_reduction(stacks, is_special)
	if is_special then
		return SPECIAL_BASE + (stacks - 1) * SPECIAL_EXTRA
	end
	return NORMAL_BASE + (stacks - 1) * NORMAL_EXTRA
end

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

local function apply_drill_reduction(seconds)
	if seconds <= 0 then
		return
	end
	local hits = 0
	for unit in pairs(tracked_drills) do
		if alive(unit) then
			local tg = unit:timer_gui()
			if tg and not tg._jammed and tg._current_timer and tg._current_timer > 0 then
				-- _current_timer is pre-multiplier: update() ticks it by dt/multiplier, so real
				-- seconds left = _current_timer * multiplier. Divide to always cut exactly `seconds`
				-- regardless of drill-speed skills or the Piggy Revenge mutator.
				local mult = tg.get_timer_multiplier and tg:get_timer_multiplier() or 1
				local before = tg._current_timer
				tg._current_timer = math.max(0, before - seconds / mult)
				hits = hits + 1
				dbg(
					"cut drill id=%s mult=%.3f real_left %.2fs -> %.2fs (asked -%.2fs)",
					tostring(unit:id()),
					mult,
					before * mult,
					tg._current_timer * mult,
					seconds
				)
			elseif tg then
				dbg(
					"skip drill id=%s (jammed=%s current=%s)",
					tostring(unit:id()),
					tostring(tg._jammed),
					tostring(tg._current_timer)
				)
			end
		else
			tracked_drills[unit] = nil
			dbg("dropped dead drill from tracking")
		end
	end
	if hits == 0 then
		dbg("apply_drill_reduction(-%.2fs): no eligible drill", seconds)
	end
end

-- Host authority: cut locally, then mirror the same delta to every client. Vanilla stops
-- syncing a drill after "start_timer_gui", so without this a guest's timer never moves.
local function host_apply_and_sync(seconds)
	apply_drill_reduction(seconds)
	local mp = _G.CSR_MP
	if seconds > 0 and mp and mp.is_multiplayer and mp.is_multiplayer() and mp.is_host and mp.is_host() then
		LuaNetworking:SendToPeers(WOLF_SYNC_RPC, string.format("%.4f", seconds))
		dbg("host mirrored -%.2fs to all peers", seconds)
	end
end

-- Local-player kill: cut saw interactions (local) and drill timers (host-authoritative;
-- client kills RPC the host). Shared by the CopDamage and HuskCopDamage die hooks -- the husk
-- class OVERRIDES die(), so a parent-class PostHook never fires for a guest's own kills.
local function wolfs_on_kill(self, attack_data)
	local mgr = managers and managers.csr
	if not wolfs_active(mgr) then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end

	local is_special = (self._char_tweak and self._char_tweak.priority_shout) and true or false
	local stacks = mgr:owned("wolfs_toolbox")
	local reduction = wolfs_reduction(stacks, is_special)
	if reduction <= 0 then
		return
	end

	dbg("kill: stacks=%d special=%s reduction=%.2fs", stacks, is_special and "y" or "n", reduction)

	-- Saw interactions — local, reduce directly.
	local saw_state = local_saw_state()
	if saw_state then
		local before = saw_state._interact_expire_t
		saw_state._interact_expire_t = math.max(0, before - reduction)
		dbg("saw interaction %.2fs -> %.2fs", before, saw_state._interact_expire_t)
	end

	-- TimerGui drills — host-authoritative.
	if not has_active_drill() then
		-- table.size walk stays behind the toggle; this branch is the common case.
		if _G.CSR_DEBUG then
			dbg("no active drill tracked (%d in table) - drill cut skipped", table.size(tracked_drills))
		end
		return
	end
	if Network:is_client() then
		LuaNetworking:SendToPeer(1, WOLF_KILL_RPC, string.format("%.4f", reduction))
		dbg("client kill -> RPC host -%.2fs", reduction)
	else
		host_apply_and_sync(reduction)
	end
end

_G.CSR.register_item({
	type = "wolfs_toolbox",
	rarity = "uncommon",
	name = "csr_logbook_wolfs_toolbox_name",
	desc = "csr_item_wolfs_toolbox_desc",
	full_desc = "csr_logbook_wolfs_toolbox_effect",
	notes = "csr_logbook_wolfs_toolbox_notes",
	-- Icon id is "toolbox" in hudicons.lua (legacy name).
	icon = "csr_toolbox",
	icon_scale = 1.0,
	loc_macros = {
		normal_base = string.format("%g", NORMAL_BASE),
		normal_extra_s = string.format("%gs", NORMAL_EXTRA),
		special_base = string.format("%g", SPECIAL_BASE),
		special_extra_s = string.format("%gs", SPECIAL_EXTRA),
	},

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_WOLFS_KILL_HOOKED then
				return
			end
			_G._CSR_WOLFS_KILL_HOOKED = true

			Hooks:PostHook(CopDamage, "die", "CSR_WolfsToolbox_Kill", wolfs_on_kill)

			if _G.CSR_MP and _G.CSR_MP.register_handler then
				_G.CSR_MP.register_handler(WOLF_KILL_RPC, function(sender, data, sender_num)
					if not Network:is_server() then
						return
					end
					dbg("host got client kill from peer %s: -%ss", tostring(sender_num), tostring(data))
					host_apply_and_sync(tonumber(data) or 0)
				end)

				-- Host mirror of a cut it already applied; clients only replay it locally.
				_G.CSR_MP.register_handler(WOLF_SYNC_RPC, function(sender, data, sender_num, is_from_host)
					if Network:is_server() or not is_from_host then
						return
					end
					dbg("client got host mirror: -%ss", tostring(data))
					apply_drill_reduction(tonumber(data) or 0)
				end)
			end
		end,

		-- MP guest: host-spawned enemies are husks whose die() OVERRIDES the parent, so the
		-- CopDamage:die PostHook never fires for the guest's own kills. Hook the husk too,
		-- which makes the client-kill RPC branch above (previously dead on the guest) live.
		["lib/units/enemies/cop/huskcopdamage"] = function()
			if _G._CSR_WOLFS_KILL_HUSK_HOOKED then
				return
			end
			_G._CSR_WOLFS_KILL_HUSK_HOOKED = true
			Hooks:PostHook(HuskCopDamage, "die", "CSR_WolfsToolbox_Kill_Husk", wolfs_on_kill)
		end,

		["lib/units/props/timergui"] = function()
			if _G._CSR_WOLFS_TIMER_HOOKED then
				return
			end
			_G._CSR_WOLFS_TIMER_HOOKED = true

			Hooks:PostHook(TimerGui, "_start", "CSR_WolfsToolbox_TimerStart", function(self)
				local mgr = managers and managers.csr
				if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
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
				-- Drills + saws only; hacking devices excluded. Fallback catches
				-- overdrill / special drills missing the boolean flag.
				local is_valid = base.is_drill or base.is_saw or (not base.is_hacking_device and unit:timer_gui())
				if not is_valid then
					dbg(
						"TimerGui _start IGNORED id=%s (drill=%s saw=%s hack=%s)",
						tostring(unit:id()),
						tostring(base.is_drill),
						tostring(base.is_saw),
						tostring(base.is_hacking_device)
					)
					return
				end
				tracked_drills[unit] = true
				dbg(
					"TimerGui _start TRACKED id=%s timer=%.1fs mult=%.3f (drill=%s saw=%s)",
					tostring(unit:id()),
					tonumber(self._current_timer) or -1,
					(self.get_timer_multiplier and self:get_timer_multiplier()) or 1,
					tostring(base.is_drill),
					tostring(base.is_saw)
				)
			end)

			Hooks:PostHook(TimerGui, "done", "CSR_WolfsToolbox_TimerDone", function(self)
				if self._unit then
					if tracked_drills[self._unit] then
						dbg("TimerGui done - untracked id=%s", tostring(self._unit:id()))
					end
					tracked_drills[self._unit] = nil
				end
			end)
		end,
	},
})
