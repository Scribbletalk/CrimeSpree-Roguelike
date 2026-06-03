-- Overkill Rush (uncommon) — kills build a temporary fire-rate + reload streak.
-- fire rate:   kill_stacks * (item_stacks + 1) * 0.005  (max 4% at 4 stacks, 1 item)
-- reload:      kill_stacks * (item_stacks + 1) * 0.01   (max 8% at 4 stacks, 1 item)

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local FIRE_RATE_BONUS_PER_KILL = 0.005
local RELOAD_BONUS_PER_KILL = 0.01
local MAX_KILL_STACKS = 4
local DURATION = 4.0

-- File-local shared by kill-bump and consumer closures.
local streak = { kill_stacks = 0, last_kill_time = -999 }

local function game_time()
	local game = TimerManager and TimerManager:game()
	return game and game:time() or nil
end

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

local function active_bonus(per_kill)
	local mgr = managers and managers.csr
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
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
		streak.kill_stacks = 0
		return 0
	end
	local stacks = mgr:owned("overkill_rush")
	if stacks <= 0 then
		return 0
	end
	return streak.kill_stacks * (stacks + 1) * per_kill
end

-- Hook CopDamage:die (not damage_*) so a later hit/DOT on a corpse can't bump the streak.
local function on_enemy_die(_cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
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
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_OVERKILL_KILL_HOOKED then
				return
			end
			_G._CSR_OVERKILL_KILL_HOOKED = true
			Hooks:PostHook(CopDamage, "die", "CSR_Overkill_Kill", on_enemy_die)
		end,

		["lib/units/weapons/newraycastweaponbase"] = function()
			if _G._CSR_OVERKILL_WEAPON_HOOKED then
				return
			end
			_G._CSR_OVERKILL_WEAPON_HOOKED = true

			local orig_fire_rate = NewRaycastWeaponBase.fire_rate_multiplier
			if orig_fire_rate then
				function NewRaycastWeaponBase:fire_rate_multiplier(...)
					local result = orig_fire_rate(self, ...)
					local bonus = active_bonus(FIRE_RATE_BONUS_PER_KILL)
					if bonus > 0 and type(result) == "number" then
						result = result * (1 + bonus)
					end
					return result
				end
			end

			local orig_reload_speed = NewRaycastWeaponBase.reload_speed_multiplier
			if orig_reload_speed then
				function NewRaycastWeaponBase:reload_speed_multiplier(...)
					-- PD2 caches this getter in _current_reload_speed_multiplier at reload
					-- start and early-returns it on later reads. Apply the bonus only on a
					-- cache MISS, else every cached read re-multiplies it (bonus -> ~bonus^2).
					local was_cached = self._current_reload_speed_multiplier
					local result = orig_reload_speed(self, ...)
					if not was_cached and type(result) == "number" then
						local bonus = active_bonus(RELOAD_BONUS_PER_KILL)
						if bonus > 0 then
							result = result * (1 + bonus)
						end
					end
					return result
				end
			end
		end,
	},
})
