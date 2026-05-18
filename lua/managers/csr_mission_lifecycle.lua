-- CSR mission lifecycle (Slice 7 wiring).
--
-- Hooks MissionEndState:at_enter so a CSR run progresses rank when the player
-- completes a heist. Mirrors the vanilla call site at
-- lib/states/missionendstate.lua:95-101 (success -> on_mission_completed,
-- failure -> on_mission_failed), but routes into managers.csr instead.
--
-- Rank gain on success is a flat amount per completed heist (rebalance
-- 2026-05-16: mission length/difficulty no longer scales rank — every heist is
-- worth the same). The amount comes from managers.csr:constant("rank_per_heist")
-- so the balance value stays out of code per CLAUDE.md "no hardcoded balance
-- values"; the 1 here is only a defensive fallback if the constant is missing.
--
-- Failure path is a log-only stub for this slice. Roguelike end-on-death and
-- vanilla-style rank-regression are both deferred.

local function log_csr(msg)
	log("[CSR] " .. tostring(msg))
end

-- No-leak gate (feedback_csr_only_no_vanilla_leak). managers.csr:is_active() is
-- a persisted csr_save.json flag and end_run() is never driven in 6.3, so after
-- the first start_run() it stays true across sessions. Gating ONLY on it meant
-- completing a VANILLA heist after a CSR run granted rank, counted a mission and
-- rerolled the mission set for that vanilla heist (user report 2026-05-18).
--
-- The correctly-scoped signal is the active job, not the flag: a CSR-launched
-- heist runs the temporary "crime_spree" job (activate_temporary_job on launch)
-- with vanilla Crime Spree NOT enabled; a vanilla heist carries its real job id.
-- This is byte-identical to csr_briefing_wiring.lua:csr_briefing_active() — the
-- already-verified run-scoped CSR-exclusive signal. The job is still set at
-- MissionEndState:at_enter (vanilla calls on_mission_completed here, which reads
-- job/level), so the signal is valid at this hook point.
local function csr_heist_active()
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

Hooks:PostHook(MissionEndState, "at_enter", "CSR_MissionLifecycle_AtEnter", function(self)
	if self._server_left or self._kicked then
		return
	end
	if not managers.csr or not csr_heist_active() then
		return
	end
	if self._success then
		local gain = managers.csr:constant("rank_per_heist") or 1
		managers.csr:progress_rank(gain)
		-- Track completed-heist count for the run independently of rank (the
		-- lobby header shows it next to RANK; the two are distinct concepts).
		managers.csr:record_mission_completed()
		-- Mirror vanilla on_mission_completed: clear the played mission and roll
		-- a fresh set so the lobby shows new cards on return.
		managers.csr:generate_mission_set()
		log_csr("mission completed: +" .. tostring(gain) .. " rank (flat); new mission set rolled")
	else
		log_csr("mission failed (no rank change this slice)")
	end
end)

log_csr("csr_mission_lifecycle.lua loaded (Slice 7 wiring)")
