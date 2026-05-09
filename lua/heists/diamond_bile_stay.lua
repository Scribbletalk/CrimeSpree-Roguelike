-- The Diamond (mus) — Prevent Bile from leaving after 4 bags
-- Only active when CSR is running and the setting is enabled. Host only.
--
-- managers.crime_spree does not exist yet when lib/managers/missionmanager loads
-- (Setup:init_managers runs later), so all runtime checks go inside the PostHook.

if not RequiredScript then
	return
end

-- Only on The Diamond, only as host
if not Network:is_server() then
	return
end
if not Global.game_settings or Global.game_settings.level_id ~= "mus" then
	return
end

local BILE_ELEMENT_IDS = {
	[137238] = true,
}

Hooks:PostHook(MissionScriptElement, "init", "CSR_DiamondBileStay", function(self, _, data)
	if not BILE_ELEMENT_IDS[data.id] then
		return
	end

	-- Check at element init time, when managers exist
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end

	local setting = _G.CSR_Settings and _G.CSR_Settings.values.heist_diamond_bile_stay
	if setting == false then
		return
	end

	self:set_enabled(false)
end)
