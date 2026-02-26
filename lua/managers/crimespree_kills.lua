-- Crime Spree Roguelike - Kills Add CS Levels
-- Escalating threshold: first rank costs 50 kills, each next costs +25 more
-- Scaled by player count (solo: 50/75/100/..., 2p: 100/150/200/..., etc.)
-- Resets each mission to prevent infinite farming on easy maps
-- Inspired by Risk of Rain 2 progression system

if not RequiredScript then
	return
end



-- Initialize the kill counter when a mission starts
Hooks:PostHook(CrimeSpreeManager, "on_mission_started", "CSR_InitKillsCounter", function(self)
	if not self:is_active() then
		return
	end

	-- Reset the kill counter for the current mission
	self._csr_mission_kills = 0
end)

-- Track kills for the entire team
if StatisticsManager then
	local original_killed = StatisticsManager.killed
	function StatisticsManager:killed(data, ...)
		original_killed(self, data, ...)

		-- Guard: must be in an active Crime Spree
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end

		-- Guard: must be an enemy (not a civilian or converted enemy)
		if data and data.name and data.type then
			-- Skip civilians and converted enemies
			if data.type == "civilian" or data.type == "converted_enemy" then
				return
			end

			-- Increment the kill counter
			managers.crime_spree._csr_mission_kills = (managers.crime_spree._csr_mission_kills or 0) + 1

			-- Log every 10 kills
			local kills = managers.crime_spree._csr_mission_kills
			if kills % 10 == 0 then
			end
		end
	end
end

-- Bonus levels for kills are applied in crimespree_bags.lua
-- (inside the on_mission_completed PostHook, AFTER vanilla logic)
-- kills_ui.lua adds UI elements to the vanilla bonuses system for sequential animation

