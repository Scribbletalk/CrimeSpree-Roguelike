-- Swap vanilla HUDStageEndScreen for CSRHUDStageEndScreen on CSR heists.
-- Separated from endscreen_wiring.lua so HUDManager exists at this hook point
-- (lib/managers/hudmanagerpd2). See csr_vanilla_intercepts.md.

if not RequiredScript then
	return
end

local function csr_endscreen_active()
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

Hooks:OverrideFunction(HUDManager, "setup_endscreen_hud", function(self)
	local ws = self:workspace("fullscreen_workspace", "menu")
	local hud = managers.hud:script(MissionEndState.GUI_ENDSCREEN)

	local is_csr = csr_endscreen_active() or (managers.csr and managers.csr.is_guesting and managers.csr:is_guesting())
	if is_csr and CSRHUDStageEndScreen then
		self._hud_stage_endscreen = CSRHUDStageEndScreen:new(hud, ws)
		csr_log("[CSR] wiring: endscreen HUD built from CSRHUDStageEndScreen")
		return
	end

	-- Verbatim vanilla — every non-CSR path is byte-for-byte unchanged.
	if game_state_machine:gamemode().id == GamemodeCrimeSpree.id then
		self._hud_stage_endscreen = HUDStageEndCrimeSpreeScreen:new(hud, ws)
	else
		self._hud_stage_endscreen = HUDStageEndScreen:new(hud, ws)
	end
end)

csr_log("[CSR] endscreen_hud_wiring.lua loaded")
