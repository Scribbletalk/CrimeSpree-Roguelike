-- Swap vanilla HUDMissionBriefing for CSRMissionBriefing on CSR heists.
-- Hooks:OverrideFunction is the only primitive that can swap the instantiated
-- class without letting the crashing vanilla path run first. See
-- csr_vanilla_intercepts.md.

if not RequiredScript then
	return
end

local function csr_briefing_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

Hooks:OverrideFunction(HUDManager, "setup_mission_briefing_hud", function(self)
	local hud = managers.hud:script(IngameWaitingForPlayersState.GUI_FULLSCREEN)
	local workspace = self:workspace("fullscreen_workspace", "menu")

	-- Guest case: setup_mission_briefing_hud runs from the ORIGINAL at_enter body
	-- before our at_enter PostHook clears host_seed, so is_guesting() is reliable
	-- here even if current_job hasn't settled to "crime_spree" yet. Host/SP use job.
	local is_csr = csr_briefing_active() or (managers.csr and managers.csr.is_guesting and managers.csr:is_guesting())

	if _G.CSR_DEBUG then
		local C = managers.csr
		csr_log(
			string.format(
				"[CSR][mpdbg] setup_mission_briefing_hud: job_id=%s csr_active=%s is_guesting=%s host_seed=%s -> is_csr=%s",
				tostring(managers.job and managers.job:current_job_id()),
				tostring(csr_briefing_active()),
				tostring(C and C.is_guesting and C:is_guesting()),
				tostring(C and C._state and C._state.mp_session and C._state.mp_session.host_seed),
				tostring(is_csr and CSRMissionBriefing ~= nil)
			)
		)
	end
	if is_csr and CSRMissionBriefing then
		self._hud_mission_briefing = CSRMissionBriefing:new(hud, workspace)
		csr_log("[CSR] wiring: mission briefing built from CSRMissionBriefing")
		return
	end

	-- Verbatim vanilla — every non-CSR path is byte-for-byte unchanged.
	self._hud_mission_briefing = HUDMissionBriefing:new(hud, workspace)
end)

csr_log("[CSR] briefing_wiring.lua loaded")
