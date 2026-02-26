-- Crime Spree Roguelike - Bags and Kills level bonuses via PostHook
-- Adds levels for secured bags (uncapped) and kills (scales with player count)

if not RequiredScript then
	return
end



-- PreHook: save current level BEFORE vanilla runs
Hooks:PreHook(CrimeSpreeManager, "on_mission_completed", "CSR_SaveOldLevel", function(self, mission_id)
	if not self:is_active() then
		return
	end

	-- Store the old level for checking forced-modifier thresholds later
	self._csr_old_level = self._global.spree_level or 0
end)

-- PostHook: add bonus levels for bags and kills AFTER vanilla runs
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_BagsKillsBonus", function(self, mission_id)
	if not self:is_active() or self:has_failed() then
		return
	end

	local bonus = 0

	-- === BAGS BONUS ===
	local bonus_bags = managers.loot:get_secured_bags_amount() or 0
	if bonus_bags > 0 then
		bonus = bonus + bonus_bags
	end

	-- === KILLS BONUS (escalating threshold) ===
	-- First rank costs 50 kills, each next rank costs +25 more (scaled by player count)
	-- Solo: 50 -> 75 -> 100 -> 125 -> ... (cumulative: 50, 125, 225, 350, ...)
	-- 2 players: 100 -> 150 -> 200 -> 250 -> ...
	-- Resets each mission — prevents infinite farming on easy maps
	local mission_kills = self._csr_mission_kills or 0
	local player_count = 1

	if managers.network and managers.network:session() then
		player_count = managers.network:session():amount_of_players() or 1
	end

	local base_kills = 50 * player_count
	local kill_increment = 25 * player_count
	local bonus_kills = 0
	local remaining = mission_kills
	local current_threshold = base_kills

	while remaining >= current_threshold do
		remaining = remaining - current_threshold
		bonus_kills = bonus_kills + 1
		current_threshold = current_threshold + kill_increment
	end

	if bonus_kills > 0 then
		bonus = bonus + bonus_kills
	end

	-- === APPLY BONUS ===
	if bonus > 0 then
		local old_level = self._global.spree_level
		self._global.spree_level = self._global.spree_level + bonus

		-- Update highest level for meta-progress
		self:_check_highest_level(self._global.spree_level)

		-- Update reward_level (drives experience/coins calculation)
		self._global.reward_level = self._global.reward_level + bonus

		-- Update rewards (experience, continental_coins, cash)
		self._global.unshown_rewards = self._global.unshown_rewards or {}
		for _, reward in ipairs(tweak_data.crime_spree.rewards) do
			self._global.unshown_rewards[reward.id] = (self._global.unshown_rewards[reward.id] or 0) + bonus * reward.amount
		end
	else
	end

	-- Store for UI display (bags_ui.lua and kills_ui.lua read these values)
	self._csr_bonus_bags = bonus_bags
	self._csr_bonus_kills = bonus_kills
	self._csr_total_kills = mission_kills
end)

-- PostHook: update meta-progress stats
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_UpdateMetaProgress", function(self)
	if not self:is_active() or self:has_failed() then
		return
	end

	if CSR_MetaProgress then
		CSR_MetaProgress:AddMission()
		CSR_MetaProgress:AddKills(self._csr_total_kills or 0)
		CSR_MetaProgress:AddBags(self._csr_bonus_bags or 0)

		-- Update highest level for the current difficulty
		local current_difficulty = self._global.selected_difficulty or CSR_CurrentDifficulty or "normal"
		CSR_MetaProgress:UpdateHighestLevelForDifficulty(current_difficulty, self:spree_level())

		-- Record cash and coins earned
		if self._global.unshown_rewards then
			if self._global.unshown_rewards.cash then
				CSR_MetaProgress:AddCash(self._global.unshown_rewards.cash)
			end
			if self._global.unshown_rewards.continental_coins then
				CSR_MetaProgress:AddCoins(self._global.unshown_rewards.continental_coins)
			end
		end

		CSR_MetaProgress:Save()
	end
end)

