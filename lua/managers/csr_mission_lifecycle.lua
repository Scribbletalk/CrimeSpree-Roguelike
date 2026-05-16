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

Hooks:PostHook(MissionEndState, "at_enter", "CSR_MissionLifecycle_AtEnter", function(self)
	if self._server_left or self._kicked then
		return
	end
	if not managers.csr or not managers.csr:is_active() then
		return
	end
	if self._success then
		local gain = managers.csr:constant("rank_per_heist") or 1
		managers.csr:progress_rank(gain)
		-- Mirror vanilla on_mission_completed: clear the played mission and roll
		-- a fresh set so the lobby shows new cards on return.
		managers.csr:generate_mission_set()
		log_csr("mission completed: +" .. tostring(gain) .. " rank (flat); new mission set rolled")
	else
		log_csr("mission failed (no rank change this slice)")
	end
end)

log_csr("csr_mission_lifecycle.lua loaded (Slice 7 wiring)")
