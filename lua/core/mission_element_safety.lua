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

-- MissionScript:load crashes when the host's saved state references element ids the client
-- never registered (nil -> "attempt to call method 'load'"). Strip orphan ids before the body runs.
if MissionScript and MissionScript.load and not _G._CSR_MISSIONSCRIPT_ELEM_GUARD then
	_G._CSR_MISSIONSCRIPT_ELEM_GUARD = true

	Hooks:PreHook(MissionScript, "load", "CSR_MissionScriptOrphanElementGuard", function(self, data)
		local state = data and self._name and data[self._name]
		if type(state) ~= "table" or type(self._elements) ~= "table" then
			return
		end
		-- Nil-during-pairs is well-defined in Lua for keys that already exist.
		local dropped
		for id in pairs(state) do
			if self._elements[id] == nil then
				state[id] = nil
				if _G.CSR_DEBUG then
					dropped = dropped or {}
					dropped[#dropped + 1] = tostring(id)
				end
			end
		end
		-- Log drops so we can distinguish cosmetic divergence from missing gameplay elements.
		if _G.CSR_DEBUG and dropped then
			csr_log(
				string.format(
					"[CSR][mpdbg] orphan-element guard: script '%s' dropped %d unknown element id(s): %s",
					tostring(self._name),
					#dropped,
					table.concat(dropped, ",")
				)
			)
		end
	end)

	csr_log("[CSR] mission_element_safety: MissionScript orphan-element guard installed")
end
