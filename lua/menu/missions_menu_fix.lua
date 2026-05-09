-- Crime Spree Roguelike - Fix crashes in CrimeSpreeMissionButton
-- Vanilla update_info_text and _get_mission_category crash when mission_data
-- is incomplete (nil .add, .level, .icon). Happens on client after completing a mission.

if not RequiredScript then
	return
end

if CrimeSpreeMissionButton then
	local original_get_mission_category = CrimeSpreeMissionButton._get_mission_category

	function CrimeSpreeMissionButton:_get_mission_category(mission)
		if not mission or not mission.add then
			return "short"
		end

		return original_get_mission_category(self, mission)
	end

	local original_update_button_text = CrimeSpreeMissionButton.update_button_text

	function CrimeSpreeMissionButton:update_button_text(text, mission_data, dont_reset_pos)
		mission_data = mission_data or self._mission_data
		if not mission_data or not mission_data.level then
			return
		end

		return original_update_button_text(self, text, mission_data, dont_reset_pos)
	end

	local original_update_info_text = CrimeSpreeMissionButton.update_info_text

	function CrimeSpreeMissionButton:update_info_text(mission_data)
		mission_data = mission_data or self._mission_data
		if not mission_data or not mission_data.level or not mission_data.add then
			return
		end

		return original_update_info_text(self, mission_data)
	end
end
