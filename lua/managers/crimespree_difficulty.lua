-- Crime Spree Roguelike - Difficulty Application
-- Applies the player-selected difficulty to Crime Spree missions
-- Also persists selected_difficulty across save/load and defensively
-- restores it around reset_crime_spree (vanilla save() does not include
-- selected_difficulty, which caused abandon-at-rank-0 to reset to Overkill).

if not RequiredScript then
	return
end

-- Mapping from display difficulty names to internal game IDs.
-- Mirrored to _G.CSR_DifficultyMap so other CSR files (e.g. multiplayer_sync.lua's
-- handshake handler) can resolve display->engine without duplicating the table.
local DIFFICULTY_MAP = {
	["normal"] = "normal",
	["hard"] = "hard",
	["very_hard"] = "overkill",
	["overkill"] = "overkill_145",
	["mayhem"] = "easy_wish",
	["death_wish"] = "overkill_290",
	["death_sentence"] = "sm_wish",
}
_G.CSR_DifficultyMap = DIFFICULTY_MAP

-- FULL FUNCTION OVERRIDE (same approach used by the Restoration mod)
-- Required because the Restoration mod also overrides this function
-- and forces overkill_145 as the default difficulty
function CrimeSpreeManager:_setup_global_from_mission_id(mission_id)
	local mission_data = self:get_mission(mission_id)
	if mission_data then
		-- Only the host resolves and applies the CSR difficulty.
		-- Clients receive Global.game_settings.difficulty via the engine's Global
		-- sync and must not overwrite it with their own local CS run's difficulty —
		-- doing so causes enemy health desync (each client sees their own stats).
		if Network:is_server() then
			local selected_difficulty = nil

			-- Priority 1: Global.crime_spree.selected_difficulty (set by enable_crime_spree hook)
			if Global.crime_spree and Global.crime_spree.selected_difficulty then
				selected_difficulty = Global.crime_spree.selected_difficulty
			-- Priority 2: managers.crime_spree._global.selected_difficulty
			elseif self._global and self._global.selected_difficulty then
				selected_difficulty = self._global.selected_difficulty
			-- Priority 3: Loaded from seed file (persists across restarts)
			elseif CSR_CurrentDifficulty then
				selected_difficulty = CSR_CurrentDifficulty
			-- Priority 4: UI selection (only matters for brand new CS)
			elseif _G.CSR_SelectedDifficulty then
				selected_difficulty = _G.CSR_SelectedDifficulty
			else
				selected_difficulty = "overkill"
			end

			local difficulty_id = DIFFICULTY_MAP[selected_difficulty] or "normal"
			Global.game_settings.difficulty = difficulty_id
		end

		Global.game_settings.one_down = false
		Global.game_settings.level_id = mission_data.level.level_id
		Global.game_settings.mission = mission_data.mission or "none"
	end
end

-- ==========================================
-- Persistence across save/load and reset
-- ==========================================
-- Vanilla CrimeSpreeManager:save (crimespreemanager.lua:128-151) does not
-- include selected_difficulty in save_data, so the field is lost on any
-- save→load cycle. Combined with reset_crime_spree being called inside
-- start_crime_spree, abandoning at rank 0 + reopening the CS contract
-- menu can land the priority chain on the "overkill" fallback.
--
-- Fix: piggyback on the vanilla save payload to persist the field, and
-- defensively capture/restore around reset_crime_spree so any future
-- vanilla change that clears it doesn't silently break this.

Hooks:PostHook(CrimeSpreeManager, "save", "CSR_SaveSelectedDifficulty", function(self, data)
	if data and data.crime_spree and self._global and self._global.selected_difficulty then
		data.crime_spree.selected_difficulty = self._global.selected_difficulty
	end
end)

Hooks:PostHook(CrimeSpreeManager, "load", "CSR_LoadSelectedDifficulty", function(self, data, version)
	if data and data.crime_spree and data.crime_spree.selected_difficulty then
		local diff = data.crime_spree.selected_difficulty
		self._global.selected_difficulty = diff
		-- Mirror to the other storage locations so the UI (difficulty_select.lua)
		-- and the heist-start resolver (_setup_global_from_mission_id above) all
		-- see consistent state without depending on load order.
		if Global.crime_spree then
			Global.crime_spree.selected_difficulty = diff
		end
		_G.CSR_CurrentDifficulty = diff
		_G.CSR_SelectedDifficulty = diff
	end
end)

Hooks:PreHook(CrimeSpreeManager, "reset_crime_spree", "CSR_CaptureDifficultyPreReset", function(self)
	if self._global and self._global.selected_difficulty then
		self._csr_pre_reset_difficulty = self._global.selected_difficulty
	end
end)

Hooks:PostHook(CrimeSpreeManager, "reset_crime_spree", "CSR_RestoreDifficultyPostReset", function(self)
	local diff = self._csr_pre_reset_difficulty
	if diff then
		self._global.selected_difficulty = diff
		if Global.crime_spree then
			Global.crime_spree.selected_difficulty = diff
		end
		_G.CSR_SelectedDifficulty = diff
		_G.CSR_CurrentDifficulty = _G.CSR_CurrentDifficulty or diff
		self._csr_pre_reset_difficulty = nil
	end
end)
