-- Crash safety net for the CLIENT-side mission-state restore. MissionManager:load
-- / MissionScript:load / ElementAreaTrigger:load run only on a guest (the host is
-- mission-authoritative and never restores), which is why these crashes happen when
-- JOINING a CSR heist but never when hosting. Two independent client crashes, both
-- because the synced mission state is incomplete and NEITHER vanilla NOR the Celer
-- mod guards it:
--
--  1) ElementAreaTrigger:load(data) -> operation_set_interval(data.interval) with a
--     nil interval -> arithmetic-on-nil in MissionScript:add (coreevent.lua)
--     (crash_report_2026_05_26_17_28). Guard: default a nil interval to the
--     element's own value (or 0).
--
--  2) MissionScript:load(state) does `local s = state[self._name]` then `pairs(s)`
--     / `s[id]` with NO nil guard -- in BOTH vanilla (coremissionmanager.lua:689)
--     AND Celer's client-only override (coremissionmanager.lua:262). When the synced
--     MissionManager state has no entry for a script's name, s is nil -> crash
--     (crash_report_2026_05_26_19_03, The Search). Guard: in MissionManager:load,
--     fill every script's missing state slot with an empty table BEFORE the scripts
--     iterate. GENERIC -- covers ALL heists, not one mission at a time.
--
-- Both are pure nil-guards (inert when the data is already complete) and NOT
-- CSR-gated: they defend vanilla/Celer crash points and only act on otherwise-fatal
-- nil data. Hooked on coreelementarea (ElementAreaTrigger) AND coremissionmanager
-- (MissionManager); each guard installs once via a _G flag when its class appears.
if not RequiredScript then
	return
end

if ElementAreaTrigger and ElementAreaTrigger.load and not _G._CSR_AREA_INTERVAL_GUARD then
	_G._CSR_AREA_INTERVAL_GUARD = true

	Hooks:PreHook(ElementAreaTrigger, "load", "CSR_AreaTriggerNilIntervalGuard", function(self, data)
		if data and data.interval == nil then
			data.interval = (self._values and self._values.interval) or 0
		end
	end)

	log("[CSR] mission_element_safety.lua: ElementAreaTrigger:load nil-interval guard installed")
end

if MissionManager and MissionManager.load and not _G._CSR_MISSION_STATE_GUARD then
	_G._CSR_MISSION_STATE_GUARD = true

	Hooks:PreHook(MissionManager, "load", "CSR_MissionScriptNilStateGuard", function(self, data)
		local state = data and data.MissionManager
		if type(state) ~= "table" or type(self._scripts) ~= "table" then
			return
		end
		-- Fill every script's missing state slot so MissionScript:load (vanilla AND
		-- Celer) never does pairs(nil) / nil[id]. An empty table restores nothing,
		-- which is exactly right for a script the synced state had no entry for.
		for _, script in pairs(self._scripts) do
			local name = script and script._name
			if name and state[name] == nil then
				state[name] = {}
			end
		end
	end)

	log("[CSR] mission_element_safety.lua: MissionManager:load nil-state guard installed")
end
