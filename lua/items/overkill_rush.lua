-- Overkill Rush (uncommon) -- kills build a temporary fire-rate/reload streak.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Two hook targets in one file: CopDamage (kill -> bump the streak) and
-- NewRaycastWeaponBase (consume the streak). The streak state is a file-local
-- upvalue shared by both hook closures -- the item file is dofile'd ONCE, so its
-- chunk locals are shared across every hook it installs (cleaner than the old
-- manager-stashed state). Local-player-scoped, so MP-symmetric.
--
-- Active bonus = kill_stacks * (item_stacks + 1) * bonus_per_kill, applied
-- EQUALLY to fire rate and reload. Values mirror the 6.2 register line
-- (bonus_per_kill 0.01 / max_kill_stacks 4 / duration 4.0).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BONUS_PER_KILL = 0.01
local MAX_KILL_STACKS = 4
local DURATION = 4.0

-- Single-item streak state, shared by the kill-bump and consumer hooks below.
local streak = { kill_stacks = 0, last_kill_time = -999 }

local function game_time()
	local game = TimerManager and TimerManager:game()
	return game and game:time() or nil
end

-- A confirmed local-player kill bumps the streak (capped, resets if expired).
local function bump_streak(mgr)
	local now = game_time()
	if not now then
		return
	end
	if now - streak.last_kill_time >= DURATION then
		streak.kill_stacks = 0
	end
	streak.kill_stacks = math.min(streak.kill_stacks + 1, MAX_KILL_STACKS)
	streak.last_kill_time = now
	if mgr:debug_enabled() then
		mgr:debug_log(string.format("overkill_rush streak=%d", streak.kill_stacks))
	end
end

-- Active fire-rate/reload bonus (0 when none live/owned/in a run).
local function active_bonus()
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return 0
	end
	if streak.kill_stacks <= 0 then
		return 0
	end
	local now = game_time()
	if not now then
		return 0
	end
	if now - streak.last_kill_time >= DURATION then
		streak.kill_stacks = 0 -- lazily expire
		return 0
	end
	local stacks = mgr:owned("overkill_rush")
	if stacks <= 0 then
		return 0
	end
	return streak.kill_stacks * (stacks + 1) * BONUS_PER_KILL
end

-- Fires on CopDamage:die (once per death, any cause, carrying the killing blow's
-- attacker). Gating on die rather than the four damage_* paths avoids bumping the
-- streak when the local player's later hit/DOT touches a corpse a bot killed (the
-- damage_* PostHook still runs on an already-dead cop). See pink_slip.lua.
local function on_enemy_die(_cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	if mgr:owned("overkill_rush") <= 0 then
		return
	end
	bump_streak(mgr)
end

_G.CSR.register_item({
	type = "overkill_rush",
	rarity = "uncommon",
	name = "csr_logbook_overkill_rush_name",
	desc = "csr_item_overkill_rush_desc",
	full_desc = "csr_logbook_overkill_rush_effect",
	notes = "csr_logbook_overkill_rush_notes",
	icon = "csr_overkill_rush",
	icon_scale = 0.9,

	hooks = {
		-- Kill detection: bump the streak on a confirmed local-player kill.
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_OVERKILL_KILL_HOOKED then
				return
			end
			_G._CSR_OVERKILL_KILL_HOOKED = true
			Hooks:PostHook(CopDamage, "die", "CSR_Overkill_Kill", on_enemy_die)
		end,

		-- Consumer: scale fire rate + reload by (1 + active bonus). Return-value
		-- methods -> raw chain wrap (CSR convention); _G guard stops a double-wrap.
		["lib/units/weapons/newraycastweaponbase"] = function()
			if _G._CSR_OVERKILL_WEAPON_HOOKED then
				return
			end
			_G._CSR_OVERKILL_WEAPON_HOOKED = true

			local orig_fire_rate = NewRaycastWeaponBase.fire_rate_multiplier
			if orig_fire_rate then
				function NewRaycastWeaponBase:fire_rate_multiplier(...)
					local result = orig_fire_rate(self, ...)
					local bonus = active_bonus()
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
					local bonus = active_bonus()
					if bonus > 0 and type(result) == "number" then
						result = result * (1 + bonus) -- higher = faster reload
					end
					return result
				end
			end
		end,
	},
})
