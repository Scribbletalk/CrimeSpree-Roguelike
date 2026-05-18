-- CSR end-screen routing (part 2 of 2) — the HUDManager:setup_endscreen_hud
-- override. Split out of csr_endscreen_wiring.lua for load order.
--
-- Why a separate file (Critical Rule #5): csr_endscreen_wiring.lua is hooked on
-- lib/managers/menu/menucomponentmanager so it can override
-- MenuComponentManager:create_stage_endscreen_gui. At that point in the require
-- chain HUDManager is NOT yet defined, so calling
-- Hooks:OverrideFunction(HUDManager, ...) there indexed a nil object and raised
-- a SuperBLT FATAL that aborted the whole menumanagerpd2 require chain (every
-- function defined after the failure point — MenuManager:on_enter_lobby and
-- friends — silently never got defined, breaking Return-to-Lobby routing and
-- ESC handling on the end screen).
--
-- This file is hooked on lib/managers/hudmanagerpd2, where HUDManager AND
-- HUDManager:setup_endscreen_hud (hudmanagerpd2.lua:1946) are defined — the
-- exact, already-proven hook point csr_briefing_wiring.lua uses for the sibling
-- HUDManager:setup_mission_briefing_hud override.
--
-- HUDManager:setup_endscreen_hud (hudmanagerpd2.lua:1946-1955) branches on
-- gamemode == GamemodeCrimeSpree.id. CSR runs a temporary "crime_spree" job
-- WITHOUT the CS gamemode, so vanilla takes the `else` branch (the heavy
-- 3567-line HUDStageEndScreen). We build the lightweight CSRHUDStageEndScreen
-- backdrop instead. Every non-CSR path is reproduced byte-for-byte.
--
-- No-leak gate (feedback_csr_only_no_vanilla_leak): route to the fork ONLY when
-- the active job is the temporary "crime_spree" job AND managers.crime_spree is
-- NOT active — the same run-scoped CSR-exclusive signal csr_endscreen_wiring.lua
-- / csr_briefing_wiring.lua / csr_mission_lifecycle.lua use, NOT the persisted
-- (leaky) managers.csr:is_active() flag. The job is still set at end-screen
-- build time (MissionEndState deactivates it later, in :at_exit ->
-- _load_start_menu). Host and client both run this locally with the same
-- job/manager state for a CSR heist, so both route to the fork; no network
-- packet is involved (feedback_check_host_and_client).
--
-- The csr_endscreen_active helper is duplicated here (not shared via a global)
-- on purpose: it is the established CSR per-file-local convention for this
-- run-scoped signal (byte-identical copies already live in
-- csr_endscreen_wiring.lua, csr_briefing_wiring.lua, csr_mission_lifecycle.lua).

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

	if csr_endscreen_active() and CSRHUDStageEndScreen then
		self._hud_stage_endscreen = CSRHUDStageEndScreen:new(hud, ws)
		log("[CSR] wiring: endscreen HUD built from CSRHUDStageEndScreen")
		return
	end

	-- Verbatim vanilla — every non-CSR path is byte-for-byte unchanged.
	if game_state_machine:gamemode().id == GamemodeCrimeSpree.id then
		self._hud_stage_endscreen = HUDStageEndCrimeSpreeScreen:new(hud, ws)
	else
		self._hud_stage_endscreen = HUDStageEndScreen:new(hud, ws)
	end
end)

log("[CSR] csr_endscreen_hud_wiring.lua loaded (endscreen HUD routing)")
