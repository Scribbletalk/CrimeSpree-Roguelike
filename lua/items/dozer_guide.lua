-- Dozer Guide (contraband) -- "become a wall": much tankier, but slow and undodgy.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/dozerguide.lua was a passport stub; the mechanic
-- lived across playermanager/playerstandard).
--
-- Three independent chain-wraps (per stack):
--   * max armor      x (1 + ARMOR_BONUS*stacks)                  (PlayerDamage:_max_armor)
--   * walk speed     x max(SPEED_MIN, 1 - SPEED_PENALTY*stacks)  (PlayerStandard:_get_max_walk_speed)
--   * dodge chance   - (DODGE_PENALTY/100)*stacks, floored at 0  (PlayerManager:skill_dodge_chance)
--
-- The 6.2 +5%/stack ranged+melee damage bonus was DROPPED for U1 (per design):
-- Dozer Guide is now a pure tank trade (armor up, mobility down), no offense.
--
-- NOT ported: 6.2's explosion_immunity_override.lua. That is a GLOBAL tweak to how
-- much explosion damage enemy bulldozers take (50% instead of vanilla immunity) --
-- nothing to do with the player owning this item, and not part of its effect text.
--
-- Values mirror the 6.2 constants (dozer_armor_bonus 0.50 / dozer_speed_penalty
-- 0.15 / dozer_speed_min 0.40 / dozer_dodge_penalty 5). Keep the localization
-- fallback in sync (logbook display).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local ARMOR_BONUS = 0.50
local SPEED_PENALTY = 0.15
local SPEED_MIN = 0.40
local DODGE_PENALTY = 5 -- display units; /100 -> dodge fraction (0..1)

local function run_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.is_run_active and mgr:is_run_active() then
		return mgr
	end
	return nil
end

_G.CSR.register_item({
	type = "dozer_guide",
	rarity = "contraband",
	name = "csr_logbook_dozer_guide_name",
	desc = "csr_item_dozer_guide_desc",
	full_desc = "csr_logbook_dozer_guide_effect",
	notes = "csr_logbook_dozer_guide_notes",
	icon = "csr_dozer_guide",
	icon_scale = 0.9,

	hooks = {
		-- Max armor: +ARMOR_BONUS per stack (additive).
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_DOZER_GUIDE_ARMOR_HOOKED then
				return
			end
			_G._CSR_DOZER_GUIDE_ARMOR_HOOKED = true
			local orig = PlayerDamage._max_armor
			if not orig then
				return
			end
			function PlayerDamage:_max_armor()
				local v = orig(self)
				local mgr = run_mgr()
				if not mgr or type(v) ~= "number" or v <= 0 then
					return v
				end
				local stacks = mgr:owned("dozer_guide")
				if stacks > 0 then
					v = v * (1 + ARMOR_BONUS * stacks)
				end
				return v
			end
		end,

		-- Walk speed: -SPEED_PENALTY per stack, never below SPEED_MIN of normal.
		["lib/units/beings/player/states/playerstandard"] = function()
			if _G._CSR_DOZER_GUIDE_SPEED_HOOKED then
				return
			end
			_G._CSR_DOZER_GUIDE_SPEED_HOOKED = true
			local orig = PlayerStandard._get_max_walk_speed
			if not orig then
				return
			end
			function PlayerStandard:_get_max_walk_speed(t, force_run)
				local speed = orig(self, t, force_run)
				if type(speed) ~= "number" then
					return speed
				end
				local mgr = run_mgr()
				if not mgr then
					return speed
				end
				local stacks = mgr:owned("dozer_guide")
				if stacks > 0 then
					speed = speed * math.max(SPEED_MIN, 1 - SPEED_PENALTY * stacks)
				end
				return speed
			end
		end,

		-- Dodge: subtract (DODGE_PENALTY/100) per stack, floored at 0. Vanilla
		-- signature is (running, crouching, on_zipline, override_armor,
		-- detection_risk) -- forward all args via "...".
		["lib/managers/playermanager"] = function()
			if _G._CSR_DOZER_GUIDE_DODGE_HOOKED then
				return
			end
			_G._CSR_DOZER_GUIDE_DODGE_HOOKED = true
			local orig = PlayerManager.skill_dodge_chance
			if not orig then
				return
			end
			function PlayerManager:skill_dodge_chance(...)
				local chance = orig(self, ...)
				if type(chance) ~= "number" then
					return chance
				end
				local mgr = run_mgr()
				if not mgr then
					return chance
				end
				local stacks = mgr:owned("dozer_guide")
				if stacks > 0 then
					chance = math.max(0, chance - (DODGE_PENALTY / 100) * stacks)
				end
				return chance
			end
		end,
	},
})
