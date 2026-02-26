-- Crime Spree Roguelike - Difficulty Application
-- Applies the player-selected difficulty to Crime Spree missions

if not RequiredScript then
	return
end



-- Mapping from display difficulty names to internal game IDs
local DIFFICULTY_MAP = {
	["normal"] = "normal",
	["hard"] = "hard",
	["very_hard"] = "overkill",
	["overkill"] = "overkill_145",
	["mayhem"] = "easy_wish",
	["death_wish"] = "overkill_290",
	["death_sentence"] = "sm_wish"
}

-- FULL FUNCTION OVERRIDE (same approach used by the Restoration mod)
-- Required because the Restoration mod also overrides this function
-- and forces overkill_145 as the default difficulty
function CrimeSpreeManager:_setup_global_from_mission_id(mission_id)
	local mission_data = self:get_mission(mission_id)
	if mission_data then
		-- Read the saved difficulty from Crime Spree data (check BOTH storage locations)
		local selected_difficulty = nil

		-- Priority 1: Global.crime_spree.selected_difficulty
		if Global.crime_spree and Global.crime_spree.selected_difficulty then
			selected_difficulty = Global.crime_spree.selected_difficulty
		-- Priority 2: managers.crime_spree._global.selected_difficulty
		elseif self._global and self._global.selected_difficulty then
			selected_difficulty = self._global.selected_difficulty
		-- Priority 3: Global variable
		elseif _G.CSR_SelectedDifficulty then
			selected_difficulty = _G.CSR_SelectedDifficulty
		-- Fallback: default to Normal
		else
			selected_difficulty = "normal"
		end

		local difficulty_id = DIFFICULTY_MAP[selected_difficulty]

		if not difficulty_id then
			difficulty_id = "normal"
		end

		-- Apply the resolved difficulty to game settings
		Global.game_settings.difficulty = difficulty_id
		Global.game_settings.one_down = false
		Global.game_settings.level_id = mission_data.level.level_id
		Global.game_settings.mission = mission_data.mission or "none"

	end
end

