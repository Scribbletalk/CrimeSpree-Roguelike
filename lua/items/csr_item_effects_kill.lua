-- CSR item-effect dispatcher — kill-triggered effects (CopDamage + weapon/timer surfaces).
--
-- Single home for every effect that FIRES ON A KILL, so a modder studying "what
-- happens when the local player kills an enemy" reads one file. Three kinds today:
--   * heal_on_kill        (Pink Slip)      — heal the local player on a kill
--   * weapon_speed_streak (Overkill Rush)  — kills build a fire-rate/reload streak
--   * drill_timer_on_kill (Wolf's Toolbox) — kills cut active drill/saw timers
--
-- Two kill-detection styles coexist ON PURPOSE (do NOT unify them):
--   * damage_* PostHooks gated on cop._dead + a once-per-corpse dedup flag
--     (cop._csr_kill_handled). They carry attack_data, so they know the ATTACKER —
--     required by heal_on_kill and weapon_speed_streak (local-player only). They
--     miss deaths whose final blow is not bullet/melee/explosion/dot.
--   * CopDamage:die PostHook fires once per death from ANY cause (fire, tase,
--     fall, ...). Used by drill_timer_on_kill so a fire/tase kill still cuts the
--     drill. die also carries attack_data for the attacker check.
--
-- Hook targets (one mod.txt entry each): copdamage (both kill styles),
-- newraycastweaponbase (weapon_speed_streak consumer), timergui (drill tracking).
-- SuperBLT loads this chunk once per target and does NOT share file-locals across
-- loads, so all cross-load state lives on the manager (managers.csr): transient
-- _weapon_speed_streaks and _wolfs_drills (neither in _state, neither serialised).
-- Each install block is fenced by its own _G._CSR_*_HOOKED guard (also stops a
-- hot-reload from re-wrapping / double-registering) and is class-gated, so load
-- order is irrelevant.
--
-- Critical Rule #1 exception: NewRaycastWeaponBase fire_rate_multiplier /
-- reload_speed_multiplier RETURN values, which Hooks:PostHook cannot carry, so a
-- raw chain wrap is used per the CSR return-value convention
-- (feedback_rule1_return_value_exception).

if not RequiredScript then
	return
end

local function csr_run_active()
	local mgr = managers and managers.csr
	return mgr and mgr.is_run_active and mgr:is_run_active()
end

local function game_time()
	if not TimerManager then
		return nil
	end
	local game = TimerManager:game()
	return game and game:time() or nil
end

-- ============ heal_on_kill (Pink Slip) ============
-- Sum of heal (internal HP units) across owned heal_on_kill items. Per-kill
-- heal = max_hp*base_pct + (base_flat + (stacks-1)*extra_flat) display HP, the
-- flat part divided by the display scale (vanilla = 10) to reach internal units.
local function csr_kill_heal_internal(mgr, pid, dmg)
	local scale = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local max_hp = dmg:_max_health()
	local total = 0
	local items = mgr:items_of_kind("heal_on_kill")
	for i = 1, #items do
		local e = items[i].effect
		local stacks = mgr:item_count(pid, items[i].type)
		if stacks > 0 then
			local display = max_hp * scale * (e.base_pct or 0) + (e.base_flat or 0) + (stacks - 1) * (e.extra_flat or 0)
			total = total + display / scale
		end
	end
	return total
end

local function apply_kill_heal(mgr)
	if #mgr:items_of_kind("heal_on_kill") == 0 then
		return
	end
	local pu = managers.player and managers.player:player_unit()
	if not pu or not alive(pu) then
		return
	end
	local dmg = pu:character_damage()
	if not dmg then
		return
	end
	local heal = csr_kill_heal_internal(mgr, mgr:local_peer_id(), dmg)
	if heal > 0 then
		dmg:set_health(dmg:get_real_health() + heal)
		if mgr:debug_enabled() then
			mgr:debug_log(string.format("pink_slip heal +%.2f (internal) on kill", heal))
		end
	end
end

-- ============ weapon_speed_streak (Overkill Rush) — bump side ============
-- A confirmed local-player kill bumps EVERY owned weapon_speed_streak item's own
-- streak (own kill_stacks capped at own max_kill_stacks, own decay timer).
local function bump_weapon_speed_streaks(mgr)
	local items = mgr:items_of_kind("weapon_speed_streak")
	if #items == 0 then
		return
	end
	local now = game_time()
	if not now then
		return
	end
	local pid = mgr:local_peer_id()
	for i = 1, #items do
		local item = items[i]
		if mgr:item_count(pid, item.type) > 0 then
			local streaks = mgr._weapon_speed_streaks
			if not streaks then
				streaks = {}
				mgr._weapon_speed_streaks = streaks
			end
			local e = item.effect
			local s = streaks[item.type]
			if not s then
				s = { kill_stacks = 0, last_kill_time = -999 }
				streaks[item.type] = s
			end
			-- An expired streak resets before this kill is counted.
			if now - s.last_kill_time >= (e.duration or 4.0) then
				s.kill_stacks = 0
			end
			s.kill_stacks = math.min(s.kill_stacks + 1, e.max_kill_stacks or 4)
			s.last_kill_time = now
			if mgr:debug_enabled() then
				mgr:debug_log(string.format("overkill '%s' streak=%d", item.type, s.kill_stacks))
			end
		end
	end
end

-- weapon_speed_streak consumer: summed active fire-rate/reload bonus across owned
-- items (0 when none live/owned/in a run). An inactive item's streak has
-- kill_stacks == 0 so it costs only a field read.
local function active_weapon_speed_bonus()
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() or not mgr.items_of_kind then
		return 0
	end
	local streaks = mgr._weapon_speed_streaks
	if not streaks then
		return 0
	end
	local now = game_time()
	if not now then
		return 0
	end
	local pid = mgr:local_peer_id()
	local items = mgr:items_of_kind("weapon_speed_streak")
	local bonus = 0
	for i = 1, #items do
		local item = items[i]
		local s = streaks[item.type]
		if s and s.kill_stacks > 0 then
			local e = item.effect
			if now - s.last_kill_time >= (e.duration or 4.0) then
				s.kill_stacks = 0 -- lazily expire
			else
				local stacks = mgr:item_count(pid, item.type)
				if stacks > 0 then
					bonus = bonus + s.kill_stacks * (stacks + 1) * (e.bonus_per_kill or 0.01)
				end
			end
		end
	end
	return bonus
end

-- ============ Shared damage_* kill handler (heal + streak) ============
-- Fires once per corpse on the local player's killing blow (bullet/melee/
-- explosion/dot), then dispatches to every damage_*-detected kill effect. Each
-- sub-dispatcher is a no-op if the player owns no item of its kind.
local function on_enemy_damage(cop, attack_data)
	if not csr_run_active() then
		return
	end
	if not cop._dead or cop._csr_kill_handled then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	cop._csr_kill_handled = true

	local mgr = managers.csr
	if not mgr or not mgr.items_of_kind then
		return
	end
	apply_kill_heal(mgr)
	bump_weapon_speed_streaks(mgr)
end

if CopDamage and not _G._CSR_ITEM_EFFECTS_KILL_HOOKED then
	_G._CSR_ITEM_EFFECTS_KILL_HOOKED = true

	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_KillEvent_Bullet", on_enemy_damage)
	if CopDamage.damage_melee then
		Hooks:PostHook(CopDamage, "damage_melee", "CSR_KillEvent_Melee", on_enemy_damage)
	end
	if CopDamage.damage_explosion then
		Hooks:PostHook(CopDamage, "damage_explosion", "CSR_KillEvent_Explosion", on_enemy_damage)
	end
	if CopDamage.damage_dot then
		Hooks:PostHook(CopDamage, "damage_dot", "CSR_KillEvent_Dot", on_enemy_damage)
	end
end

-- ============ weapon_speed_streak — NewRaycastWeaponBase consumer ============
if NewRaycastWeaponBase and not _G._CSR_OVERKILL_WEAPON_HOOKED then
	_G._CSR_OVERKILL_WEAPON_HOOKED = true

	local orig_fire_rate = NewRaycastWeaponBase.fire_rate_multiplier
	if orig_fire_rate then
		function NewRaycastWeaponBase:fire_rate_multiplier(...)
			local result = orig_fire_rate(self, ...)
			local bonus = active_weapon_speed_bonus()
			if bonus > 0 and type(result) == "number" then
				result = result * (1 + bonus) -- higher = faster fire rate
			end
			return result
		end
	end

	local orig_reload_speed = NewRaycastWeaponBase.reload_speed_multiplier
	if orig_reload_speed then
		function NewRaycastWeaponBase:reload_speed_multiplier(...)
			local result = orig_reload_speed(self, ...)
			local bonus = active_weapon_speed_bonus()
			if bonus > 0 and type(result) == "number" then
				result = result * (1 + bonus) -- higher = faster reload
			end
			return result
		end
	end
end

-- ============ drill_timer_on_kill (Wolf's Toolbox) ============
-- Each confirmed local-player kill cuts the timer on active drills/saws. Always
-- triggers (no RNG); a special enemy (priority_shout) cuts more. The reduction
-- SUMS across owned drill_timer_on_kill items: per item,
--   (special and special_base or normal_base) + (stacks-1)*(matching _extra).
--
-- Two timer surfaces, two authority models:
--   * TimerGui drill/saw DEVICES are HOST-authoritative (the host runs the
--     countdown and syncs it). The host reduces directly; a CLIENT kill RPCs the
--     host the reduction AMOUNT it computed from its OWN stacks, and the host
--     applies it. (Fixes a 6.2 bug where the host recomputed from its own stacks
--     and ignored the client unless the host also owned the item.)
--   * Saw INTERACTIONS (the player personally sawing) are PlayerStandard
--     interaction timers, locally owned, so every peer reduces its own directly.
-- Kill detection uses CopDamage:die (fires once per death, so no per-corpse dedup
-- flag is needed). Jammed drills are skipped.

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
	-- drill has started still tracks it on the next _start call.
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
		-- vanilla). Exclude hacking devices. Fallback: a non-hacking unit that still
		-- has a timer_gui counts as a drill (catches overdrill / special drills that
		-- don't set the flag).
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
