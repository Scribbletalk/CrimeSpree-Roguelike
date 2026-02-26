-- Crime Spree Roguelike - Cash and Loot Rewards Fix
-- Applies the difficulty multiplier to cash rewards and adds a guaranteed loot drop

if not RequiredScript then
	return
end



-- CASH reward multipliers (1/10th of the XP multipliers)
local DIFFICULTY_CASH_MULTIPLIERS = {
	normal = 0.04,           -- 0.4 / 10
	hard = 0.065,            -- 0.65 / 10
	very_hard = 0.08,        -- 0.8 / 10
	overkill = 0.1,          -- 1.0 / 10
	overkill_145 = 0.125,    -- 1.25 / 10 (Mayhem)
	easy_wish = 0.15,        -- 1.5 / 10 (Death Wish)
	overkill_290 = 0.2       -- 2.0 / 10 (Death Sentence)
}

-- Hook on Crime Spree mission completion — apply difficulty multiplier to cash
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_AdjustCash", function(self)

	if not self._global or not self._global.unshown_rewards then
		return
	end

	-- Read current difficulty
	local difficulty = self._global.selected_difficulty or CSR_CurrentDifficulty or "normal"
	local cash_multiplier = DIFFICULTY_CASH_MULTIPLIERS[difficulty] or 0.16


	-- Log state before modification

	-- APPLY MULTIPLIER ONLY TO CASH AND COINS
	-- (experience is already handled via reward_level)
	if self._global.unshown_rewards.cash then
		local original_cash = self._global.unshown_rewards.cash
		local modified_cash = math.floor(original_cash * cash_multiplier)
		self._global.unshown_rewards.cash = modified_cash
	end

	-- Also apply to continental coins
	if self._global.unshown_rewards.continental_coins then
		local original_coins = self._global.unshown_rewards.continental_coins
		local modified_coins = math.floor(original_coins * cash_multiplier)
		self._global.unshown_rewards.continental_coins = modified_coins
	end
end)

-- Mission counter (used to determine reroll cost)
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_MissionCounter", function(self)
	if not self._global then
		return
	end
	self._global.csr_missions_completed = (self._global.csr_missions_completed or 0) + 1
end)

-- Override reroll cost — scales with number of completed missions
-- 0 missions = free, 1 mission = 1 coin, 2 missions = 2 coins, etc.
local original_randomization_cost = CrimeSpreeManager.randomization_cost
function CrimeSpreeManager:randomization_cost()
	local missions = self._global and self._global.csr_missions_completed or 0
	return missions
end

-- Reset mission counter when starting/selecting crime spree level
-- Also zero out tweakdata costs so future free-level starts aren't charged
-- (MAX button restores them to vanilla values before lobby creation; this resets them after)
Hooks:PostHook(CrimeSpreeManager, "enable_crime_spree", "CSR_ResetMissionCounter", function(self)
	if self._global then
		self._global.csr_missions_completed = 0
	end
	tweak_data.crime_spree.initial_cost = 0
	tweak_data.crime_spree.cost_per_level = 0
end)

Hooks:PostHook(CrimeSpreeManager, "set_starting_level", "CSR_ResetMissionCounter2", function(self)
	if self._global then
		self._global.csr_missions_completed = 0
	end
end)

