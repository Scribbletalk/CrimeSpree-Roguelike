-- CSR end-screen routing (part 1 of 2) — companion to csr_stage_endscreen.lua /
-- csr_hud_stage_endscreen.lua. The HUDManager:setup_endscreen_hud override
-- lives in csr_endscreen_hud_wiring.lua (see the split note below).
--
-- The end screen is built by two vanilla entry points, and NEITHER
-- early-returns on a CSR condition (verified in source), so a PostHook would
-- fire only after vanilla already built the wrong class. The only SuperBLT
-- primitive that swaps the instantiated class while preserving other mods'
-- pre/post hooks is Hooks:OverrideFunction (mirrors csr_briefing_wiring.lua).
-- The vanilla body is reproduced verbatim for every non-CSR path:
--
--   MenuComponentManager:create_stage_endscreen_gui
--   (menucomponentmanager.lua:3440-3463) — unconditionally
--   `StageEndScreenGui:new(self._ws, self._fullscreen_ws)`. For a CSR heist
--   managers.crime_spree:is_active() is false, so vanilla
--   StageEndScreenGui:init would take the NON-CS stats path. We build
--   CSRStageEndScreenGui instead (forces the CS-style layout + CSR result
--   tab).
--
-- SPLIT (load-order — Critical Rule #5): this file is hooked on
-- lib/managers/menu/menucomponentmanager, where MenuComponentManager exists but
-- HUDManager is NOT yet defined. Calling Hooks:OverrideFunction(HUDManager, ...)
-- here indexed a nil object and raised a SuperBLT FATAL that aborted the entire
-- menumanagerpd2 require chain (MenuManager:on_enter_lobby et al. never got
-- defined -> Return-to-Lobby routing and ESC-on-endscreen broke). The
-- HUDManager:setup_endscreen_hud override therefore moved to
-- csr_endscreen_hud_wiring.lua, hooked on lib/managers/hudmanagerpd2 (where
-- HUDManager + setup_endscreen_hud are defined — the same proven hook point as
-- csr_briefing_wiring.lua's setup_mission_briefing_hud override).
--
-- No-leak gate (feedback_csr_only_no_vanilla_leak): route to the fork ONLY
-- when the active job is the temporary "crime_spree" job AND
-- managers.crime_spree is NOT active — the same run-scoped CSR-exclusive
-- signal csr_briefing_wiring.lua / csr_mission_lifecycle.lua use, NOT the
-- persisted (leaky) managers.csr:is_active() flag. The job is still set at
-- end-screen build time (MissionEndState deactivates it later, in
-- :at_exit -> _load_start_menu). Walked:
--   normal heist                         job ~= "crime_spree"  -> vanilla
--   normal + stale csr is_active on disk  same                 -> vanilla
--   vanilla CS    job == "crime_spree", cs:is_active true       -> vanilla CS
--   Skirmish      job ~= "crime_spree"                          -> vanilla
--   CSR heist     job == "crime_spree", cs:is_active false      -> CSR fork
-- Host and client both run these locally with the same job/manager state for
-- a CSR heist, so both route to the fork; no network packet is involved here
-- (feedback_check_host_and_client).

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

Hooks:OverrideFunction(MenuComponentManager, "create_stage_endscreen_gui", function(self)
	if not self._stage_endscreen_gui then
		if csr_endscreen_active() and CSRStageEndScreenGui then
			self._stage_endscreen_gui = CSRStageEndScreenGui:new(self._ws, self._fullscreen_ws)
			log("[CSR] wiring: stage endscreen built from CSRStageEndScreenGui")
		else
			-- Verbatim vanilla.
			self._stage_endscreen_gui = StageEndScreenGui:new(self._ws, self._fullscreen_ws)
		end
	end

	game_state_machine:current_state():set_continue_button_text()
	self._stage_endscreen_gui:show()

	if self._endscreen_predata then
		if self._endscreen_predata.cash_summary then
			self:show_endscreen_cash_summary()
		end

		if self._endscreen_predata.stats then
			self:feed_endscreen_statistics(self._endscreen_predata.stats)
		end

		if self._endscreen_predata.continue then
			self:set_endscreen_continue_button_text(
				self._endscreen_predata.continue[1],
				self._endscreen_predata.continue[2]
			)
		end

		self._endscreen_predata = nil
	end
end)

log("[CSR] csr_endscreen_wiring.lua loaded (stage endscreen routing; HUD routing in csr_endscreen_hud_wiring.lua)")
