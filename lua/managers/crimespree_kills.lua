-- Crime Spree Roguelike - Kills Add CS Levels + Kill Cash
-- Escalating threshold: first rank costs 50 kills, each next costs +25 more
-- Scaled by player count (solo: 50/75/100/..., 2p: 100/150/200/..., etc.)
-- Resets each mission to prevent infinite farming on easy maps
-- Kill Cash: each enemy kill adds instant cash shown on TAB screen
-- Inspired by Risk of Rain 2 progression system

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

-- Per-mission kill cash accumulator (reset each mission)
_G.CSR_MissionKillCash = 0

-- Initialize the kill counter when a mission starts
Hooks:PostHook(CrimeSpreeManager, "on_mission_started", "CSR_InitKillsCounter", function(self)
	if not self:is_active() then
		return
	end

	-- Reset the kill counter and kill cash for the current mission
	self._csr_mission_kills = 0
	_G.CSR_MissionKillCash = 0
	_G.CSR_BulletsFiredToday = 0

	-- Reset bag counter (incremented by sync_secure_loot hook below)
	_G.CSR_MissionBagCount = 0

	-- Reset previous mission's UI bonus values so TAB screen shows fresh data
	self._csr_bonus_bags = 0
	self._csr_bonus_kills = 0
	self._csr_total_kills = 0
end)

-- Track kills for the entire team (all criminals — players + bots).
-- killed_by_anyone fires for every criminal kill, not just local player,
-- so the escalating threshold (50 * player_count) works correctly in MP.
if StatisticsManager then
	local original_killed_by_anyone = StatisticsManager.killed_by_anyone
	_G.CSR_SafeOverride(
		StatisticsManager,
		"killed_by_anyone",
		"Kill Tracking",
		original_killed_by_anyone,
		function(self, data, ...)
			original_killed_by_anyone(self, data, ...)

			-- Guard: must be in an active Crime Spree
			if not managers.crime_spree or not managers.crime_spree:is_active() then
				return
			end

			-- Guard: must be an enemy (not a civilian or converted enemy)
			-- killed_by_anyone does not set data.type, so derive from tweak_data
			if data and data.name then
				local char_tweak = tweak_data.character and tweak_data.character[data.name]
				local char_type = char_tweak and char_tweak.challenges and char_tweak.challenges.type
				if char_type == "civilians" or char_type == "civilian" or char_type == "converted_enemy" then
					return
				end

				-- Increment the kill counter
				managers.crime_spree._csr_mission_kills = (managers.crime_spree._csr_mission_kills or 0) + 1

				-- Accumulate kill cash (scales with CS rank).
				-- Use server_spree_level so all peers compute the same cash_per_kill
				-- amount for the same kill — clients' local spree_level() is 0 until
				-- catchup syncs and could even diverge from host's rank during a run,
				-- which previously caused the host and clients to bank different
				-- amounts of kill cash for the same shared enemy deaths.
				local C = _G.CSR_ItemConstants or {}
				local base_cash = C.kill_cash_per_kill or 100
				local per_rank = C.kill_cash_per_rank or 1
				local rank = managers.crime_spree:server_spree_level() or 0
				local cash_per_kill = base_cash + rank * per_rank
				_G.CSR_MissionKillCash = (_G.CSR_MissionKillCash or 0) + cash_per_kill

				-- Log every 25 kills
				local kills = managers.crime_spree._csr_mission_kills
				if kills % 25 == 0 then
					CSR_log("[CSR Kills] mission_kills=" .. kills .. " kill_cash=" .. tostring(_G.CSR_MissionKillCash))
				end
			end
		end
	)
end

-- Deduct cleaner cost from kill cash when a civilian is killed
if MoneyManager then
	Hooks:PostHook(MoneyManager, "civilian_killed", "CSR_CivilianKillCashDeduct", function(self)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		local deduction = 0
		pcall(function()
			deduction = self:get_civilian_deduction()
		end)
		if deduction > 0 then
			_G.CSR_MissionKillCash = (_G.CSR_MissionKillCash or 0) - deduction
			CSR_log(
				"[CSR Kills] Civilian killed, deducted "
					.. deduction
					.. " from kill cash, now="
					.. tostring(_G.CSR_MissionKillCash)
			)
		end
	end)
end

-- Bonus levels for kills are applied in crimespree_mission_bonus.lua
-- (inside the on_mission_completed PostHook, AFTER vanilla logic)
-- kills_ui.lua adds UI elements to the vanilla bonuses system for sequential animation
