-- Client-only nil guards for the mission-state restore path. Vanilla AND Celer
-- both miss these — they crash a guest joining certain heists. See
-- csr_mission_element_safety.md for root-cause notes + crash reports.
-- Not CSR-gated: pure nil-guards, inert when data is already complete.

if not RequiredScript then
	return
end

-- ElementAreaTrigger:load -> operation_set_interval(nil) -> arithmetic crash.
if ElementAreaTrigger and ElementAreaTrigger.load and not _G._CSR_AREA_INTERVAL_GUARD then
	_G._CSR_AREA_INTERVAL_GUARD = true

	Hooks:PreHook(ElementAreaTrigger, "load", "CSR_AreaTriggerNilIntervalGuard", function(self, data)
		if data and data.interval == nil then
			data.interval = (self._values and self._values.interval) or 0
		end
	end)

	csr_log("[CSR] mission_element_safety: ElementAreaTrigger interval guard installed")
end

-- MissionScript:load does pairs(state[self._name]) without a nil-check; fill any
-- missing slot with an empty table BEFORE the scripts iterate.
if MissionManager and MissionManager.load and not _G._CSR_MISSION_STATE_GUARD then
	_G._CSR_MISSION_STATE_GUARD = true

	Hooks:PreHook(MissionManager, "load", "CSR_MissionScriptNilStateGuard", function(self, data)
		local state = data and data.MissionManager
		if type(state) ~= "table" or type(self._scripts) ~= "table" then
			return
		end
		for _, script in pairs(self._scripts) do
			local name = script and script._name
			if name and state[name] == nil then
				state[name] = {}
			end
		end
	end)

	csr_log("[CSR] mission_element_safety: MissionManager state guard installed")
end
