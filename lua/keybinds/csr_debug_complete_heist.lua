-- CSR debug keybind: instantly complete the current heist as a SUCCESS.
--
-- Mirrors the canonical vanilla mission-end element verbatim
-- (pd2_source_code/lib/managers/mission/elementmissionend.lua:20-28, the
-- `state == "success"` branch) — the same path the game itself uses when a
-- heist is won. Nothing invented: amount_of_alive_players /
-- send_to_peers("mission_ended", true, n) / change_state_by_name(
-- "victoryscreen", { num_winners, personal_win }) are all 1:1 from there.
--
-- Host-only: the vanilla element executes server-side and
-- session:send_to_peers is a host->clients broadcast; a client press would
-- desync, so it is a logged no-op for clients (a debug tool — host drives the
-- heist end, clients follow via the mission_ended RPC + state change exactly
-- as in a normal win). Guarded on managers.platform:presence() == "Playing"
-- (vanilla's own guard at elementmissionend.lua:20) so it cannot fire in
-- menus / the lobby. Fully nil-guarded for early/!session presses.
--
-- This is a DEV keybind. It MUST be stripped from the staging mod.txt before
-- any preview/release build (project_pack_time_strip_debug_keybinds).

if not managers or not managers.platform or managers.platform:presence() ~= "Playing" then
	log("[CSR][debug] complete-heist: ignored (not in a heist)")
	return
end

if not Network:is_server() then
	log("[CSR][debug] complete-heist: client press ignored (host-only)")
	return
end

local session = managers.network and managers.network:session()
if not session then
	log("[CSR][debug] complete-heist: no network session")
	return
end

local num_winners = session:amount_of_alive_players()

session:send_to_peers("mission_ended", true, num_winners)
game_state_machine:change_state_by_name("victoryscreen", {
	num_winners = num_winners,
	personal_win = alive(managers.player:player_unit()),
})

log("[CSR][debug] heist force-completed (SUCCESS) — num_winners=" .. tostring(num_winners))
