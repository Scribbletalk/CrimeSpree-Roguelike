-- Dozer Guide (contraband) — tank trade: tankier, slower, can't dodge.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local ARMOR_BONUS = 0.50
local SPEED_PENALTY = 0.15
local SPEED_MIN = 0.40
local DODGE_PENALTY = 5 -- display units; /100 for the dodge fraction

local function run_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
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
	loc_macros = {
		armor_pct = string.format("%g", ARMOR_BONUS * 100),
		speed_pct = string.format("%g", SPEED_PENALTY * 100),
		speed_min_pct = string.format("%g", SPEED_MIN * 100),
		dodge = DODGE_PENALTY,
	},

	hooks = {
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
