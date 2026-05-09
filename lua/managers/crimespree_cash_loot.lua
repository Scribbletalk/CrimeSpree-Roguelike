-- Crime Spree Roguelike - Cash/Loot Fixes
-- Reroll cost scaling + free starting levels

if not RequiredScript then
	return
end

-- Override reroll cost — scales with current Crime Spree level
-- Levels 0-9 = 1 coin, 10-19 = 2 coins, 20-29 = 3 coins, etc.
local original_randomization_cost = CrimeSpreeManager.randomization_cost
function CrimeSpreeManager:randomization_cost()
	local level = self._global and self._global.spree_level or 0
	return math.floor(level / 10) + 1
end

-- Free starting levels: costs are zeroed in CrimeSpreeTweakData:init (crimespree.lua)
-- NOTE: previous PostHook on "enable_crime_spree" was dead code (method doesn't exist in vanilla)
