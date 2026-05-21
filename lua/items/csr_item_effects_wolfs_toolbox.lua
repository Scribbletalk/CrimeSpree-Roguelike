-- CSR item-effect dispatcher — Wolf's Toolbox (drill_timer_on_kill).
--
-- effect = { kind = "drill_timer_on_kill", normal_base, normal_extra, special_base, special_extra }
-- Each confirmed local-player kill cuts the timer on active drills/saws. Always
-- triggers (no RNG); a special enemy (priority_shout) cuts more. The reduction
-- SUMS across owned drill_timer_on_kill items: per item,
--   (special and special_base or normal_base) + (stacks-1)*(matching _extra).
--
-- Two timer surfaces, two authority models:
--   * TimerGui drill/saw DEVICES are HOST-authoritative (the host runs the
--     countdown and syncs it). The host reduces directly; a CLIENT kill RPCs the
--     host the reduction AMOUNT it computed from its OWN stacks, and the host
--     applies it. (This fixes a 6.2 bug where the host recomputed from its own
--     stacks and ignored the client entirely unless the host also owned the item.)
--   * Saw INTERACTIONS (the player personally sawing — No Mercy teddy saw,
--     apartment saws, ...) are PlayerStandard interaction timers, locally owned,
--     so every peer reduces its own directly.
--
-- Hooked on copdamage (kill) + timergui (device tracking) => SuperBLT loads the
-- chunk twice; file-locals are not shared, so the tracked-device set lives on the
-- manager (managers.csr._wolfs_drills, transient — not in _state, not serialised).
-- Jammed drills are skipped. Kill detection uses CopDamage:die (fires once per
-- death, so no per-corpse dedup flag is needed, unlike the damage_* dispatchers).

if not RequiredScript then
	return
end

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

-- Run active AND the local player owns >= 1 drill_timer_on_kill item.
local function wolfs_active(mgr)
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() or not mgr.items_of_kind then
		return false
	end
	local pid = mgr:local_peer_id()
	local items = mgr:items_of_kind("drill_timer_on_kill")
	for i = 1, #items do
		if mgr:item_count(pid, items[i].type) > 0 then
			return true
		end
	end
	return false
end

-- Total seconds to cut, summed across owned drill_timer_on_kill items.
local function wolfs_reduction(mgr, is_special)
	local pid = mgr:local_peer_id()
	local items = mgr:items_of_kind("drill_timer_on_kill")
	local total = 0
	for i = 1, #items do
		local e = items[i].effect
		local stacks = mgr:item_count(pid, items[i].type)
		if stacks > 0 then
			if is_special then
				total = total + (e.special_base or 1.0) + (stacks - 1) * (e.special_extra or 0.5)
			else
				total = total + (e.normal_base or 0.2) + (stacks - 1) * (e.normal_extra or 0.1)
			end
		end
	end
	return total
end

-- The local player's current saw-interaction state, or nil. Locally owned, so
-- this is valid on every peer.
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
local function has_active_drill(mgr)
	local drills = mgr._wolfs_drills
	if not drills then
		return false
	end
	for unit in pairs(drills) do
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
local function apply_drill_reduction(mgr, seconds)
	if seconds <= 0 then
		return
	end
	local drills = mgr._wolfs_drills
	if not drills then
		return
	end
	for unit in pairs(drills) do
		if alive(unit) then
			local tg = unit:timer_gui()
			if tg and not tg._jammed and tg._current_timer and tg._current_timer > 0 then
				tg._current_timer = math.max(0, tg._current_timer - seconds)
			end
		else
			drills[unit] = nil
		end
	end
end

-- =====================================================
-- Kill handler (CopDamage:die) + drill tracking (TimerGui) + host RPC
-- =====================================================

if CopDamage and not _G._CSR_WOLFS_KILL_HOOKED then
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
		local reduction = wolfs_reduction(mgr, is_special)
		if reduction <= 0 then
			return
		end

		-- Saw interactions are locally owned — reduce directly on every peer.
		local saw_state = local_saw_state()
		if saw_state then
			saw_state._interact_expire_t = math.max(0, saw_state._interact_expire_t - reduction)
			if mgr:debug_enabled() then
				mgr:debug_log(
					string.format("wolfs_toolbox saw interaction -%.2fs (special=%s)", reduction, tostring(is_special))
				)
			end
		end

		-- TimerGui drills are host-authoritative.
		if not has_active_drill(mgr) then
			return
		end
		if Network:is_client() then
			-- Send the AMOUNT we computed from our own stacks; the host applies it.
			LuaNetworking:SendToPeer(1, WOLF_KILL_RPC, string.format("%.4f", reduction))
			if mgr:debug_enabled() then
				mgr:debug_log(string.format("wolfs_toolbox client kill -> RPC host -%.2fs", reduction))
			end
		else
			apply_drill_reduction(mgr, reduction)
			if mgr:debug_enabled() then
				mgr:debug_log(string.format("wolfs_toolbox drill -%.2fs (special=%s)", reduction, tostring(is_special)))
			end
		end
	end)

	-- Host applies a client's kill reduction to its (authoritative) drill timers.
	Hooks:Add("NetworkReceivedData", "CSR_WolfsToolbox_NetKill", function(sender, id, data)
		if id ~= WOLF_KILL_RPC then
			return
		end
		if not Network:is_server() then
			return
		end
		local mgr = managers and managers.csr
		if not mgr or not mgr._wolfs_drills then
			return
		end
		local reduction = tonumber(data) or 0
		apply_drill_reduction(mgr, reduction)
		if mgr:debug_enabled() then
			mgr:debug_log(string.format("wolfs_toolbox host applied client kill -%.2fs", reduction))
		end
	end)
end

if TimerGui and not _G._CSR_WOLFS_TIMER_HOOKED then
	_G._CSR_WOLFS_TIMER_HOOKED = true

	-- Register a drill/saw device as active. Tracked on every peer (devices are
	-- synced): the host uses the set to reduce; a client uses it to decide whether
	-- a kill is worth RPCing. Gated only on a live run, so picking the item after a
	-- drill has started still tracks it (the device is already in TimerGui:_start's
	-- scope on the next call -- and most drills (re)start often enough).
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
		-- Drills and saws only. is_drill / is_saw are boolean fields (verified in
		-- vanilla, e.g. interactionext.lua / drill.lua). Exclude hacking devices.
		-- Fallback: a non-hacking unit that still has a timer_gui counts as a drill
		-- (catches overdrill / special drills that don't set the flag).
		local is_valid = base.is_drill or base.is_saw or (not base.is_hacking_device and unit:timer_gui())
		if not is_valid then
			return
		end
		mgr._wolfs_drills = mgr._wolfs_drills or {}
		mgr._wolfs_drills[unit] = true
	end)

	Hooks:PostHook(TimerGui, "done", "CSR_WolfsToolbox_TimerDone", function(self)
		local mgr = managers and managers.csr
		local drills = mgr and mgr._wolfs_drills
		if drills and self._unit then
			drills[self._unit] = nil
		end
	end)
end
