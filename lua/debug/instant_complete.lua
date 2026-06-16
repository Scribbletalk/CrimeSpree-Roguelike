-- DEBUG keybind: instantly WIN the current heist. Host/SP only. Strip before release.
-- Replays vanilla ElementMissionEnd "success" flow, so CSR's MissionEndState hook
-- (mission_lifecycle.lua) awards rank/tokens/loot exactly like a real completion.

if not (Network and Network:is_server() and managers.network:session()) then
	csr_log("[CSR][DEBUG] instant_complete: ignored (guest or no session)")
	return
end

if not managers.platform or managers.platform:presence() ~= "Playing" then
	csr_log("[CSR][DEBUG] instant_complete: ignored (not in a heist)")
	return
end

local num_winners = managers.network:session():amount_of_alive_players()
managers.network:session():send_to_peers("mission_ended", true, num_winners)
game_state_machine:change_state_by_name("victoryscreen", {
	num_winners = num_winners,
	personal_win = alive(managers.player:player_unit()),
})
csr_log("[CSR][DEBUG] instant_complete: forced heist WIN")
