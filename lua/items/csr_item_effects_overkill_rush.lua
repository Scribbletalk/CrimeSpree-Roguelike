-- CSR item-effect dispatcher — weapon_speed_streak (kill-streak weapon buff).
--
-- effect = { kind = "weapon_speed_streak", bonus_per_kill, max_kill_stacks, duration }
--   * CopDamage side: each confirmed local-player kill bumps EVERY owned
--     weapon_speed_streak item's own streak (its own kill_stacks, capped at its
--     own max_kill_stacks, with its own decay timer).
--   * NewRaycastWeaponBase side: fire_rate_multiplier and reload_speed_multiplier
--     are scaled by (1 + total_bonus), where total_bonus SUMS across owned items:
--       Σ kill_stacks_i * (item_stacks_i + 1) * bonus_per_kill_i
--     each term dropping to zero once its item's `duration` passes without a kill.
--
-- Fully composable: any number of weapon_speed_streak items (CSR's Overkill Rush
-- plus addon items) each track an independent streak keyed by item type and
-- contribute additively. For a single item this reduces exactly to the legacy
-- 6.2 behaviour.
--
-- This file is listed under TWO hook targets (copdamage + newraycastweaponbase),
-- so SuperBLT loads the chunk TWICE and the two loads do NOT share file-locals.
-- The per-type streak table therefore lives on the shared manager
-- (managers.csr._weapon_speed_streaks), which both loads reach. It is transient
-- runtime state: not part of _state, never serialised by save(), so it resets on
-- a fresh manager (new session) and is expired lazily within a session.
--
-- Critical Rule #1 exception: fire_rate_multiplier / reload_speed_multiplier
-- RETURN values, which Hooks:PostHook cannot carry. Raw chain wrap is the
-- established CSR convention for return-value hooks
-- (feedback_rule1_return_value_exception). Per-target _G guards stop a hot-reload
-- from re-wrapping the already-wrapped functions and compounding the bonus.

if not RequiredScript then
	return
end

local function game_time()
	if not TimerManager then
		return nil
	end
	local game = TimerManager:game()
	return game and game:time() or nil
end

-- CopDamage side: register one confirmed local-player kill into every owned
-- weapon_speed_streak item's streak.
local function on_enemy_killed(cop, attack_data)
	if not cop._dead or cop._csr_overkill_handled then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	cop._csr_overkill_handled = true

	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() or not mgr.items_of_kind then
		return
	end
	local now = game_time()
	if not now then
		return
	end
	local pid = mgr:local_peer_id()
	local items = mgr:items_of_kind("weapon_speed_streak")
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

-- NewRaycastWeaponBase side: summed active fire-rate/reload bonus across owned
-- weapon_speed_streak items (0 when none are live/owned/in a run). The loop is
-- bounded by the (tiny) number of weapon_speed_streak items; an inactive item's
-- streak has kill_stacks == 0 so it costs only a field read.
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

if CopDamage and not _G._CSR_OVERKILL_KILL_HOOKED then
	_G._CSR_OVERKILL_KILL_HOOKED = true

	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_OverkillRush_Bullet", on_enemy_killed)
	if CopDamage.damage_melee then
		Hooks:PostHook(CopDamage, "damage_melee", "CSR_OverkillRush_Melee", on_enemy_killed)
	end
	if CopDamage.damage_explosion then
		Hooks:PostHook(CopDamage, "damage_explosion", "CSR_OverkillRush_Explosion", on_enemy_killed)
	end
	if CopDamage.damage_dot then
		Hooks:PostHook(CopDamage, "damage_dot", "CSR_OverkillRush_Dot", on_enemy_killed)
	end
end

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
