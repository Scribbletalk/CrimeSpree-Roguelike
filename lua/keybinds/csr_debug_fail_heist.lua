-- CSR debug keybind: instantly end the current heist as a FAILURE.
--
-- Mirrors the canonical vanilla mission-end element verbatim
-- (pd2_source_code/lib/managers/mission/elementmissionend.lua:29-31, the
-- `state == "failed"` branch) — the exact path the game uses on a real loss.
-- Nothing invented: send_to_peers("mission_ended", false, 0) +
-- change_state_by_name("gameoverscreen") are 1:1 from there.
--
-- Host-only / presence-guarded for the same reasons as
-- csr_debug_complete_heist.lua (the element runs server-side; send_to_peers
-- is host->clients; clients follow via the RPC + state change). This drives
-- the Slice B fail flow (failed-state -> locked lobby -> paid Continue /
-- End Spree) once that lands; today it just shows the failed end screen.
--
-- DEV keybind — strip from staging mod.txt before any build
-- (project_pack_time_strip_debug_keybinds).

if not managers or not managers.platform or managers.platform:presence() ~= "Playing" then
	log("[CSR][debug] fail-heist: ignored (not in a heist)")
	return
end

if not Network:is_server() then
	log("[CSR][debug] fail-heist: client press ignored (host-only)")
	return
end

local session = managers.network and managers.network:session()
if not session then
	log("[CSR][debug] fail-heist: no network session")
	return
end

session:send_to_peers("mission_ended", false, 0)
game_state_machine:change_state_by_name("gameoverscreen")

log("[CSR][debug] heist force-failed (FAILURE)")
