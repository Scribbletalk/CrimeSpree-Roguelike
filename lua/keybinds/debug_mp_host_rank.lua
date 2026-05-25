-- CSR debug keybind: cycle a fake host_rank so the MP guest-scaling path
-- (rank_passives per-rank player stats, item-selection quota) can be checked in
-- SOLO without a second instance. Cycles off -> 10 -> 25 -> 50 -> off. The
-- manager's debug_force flag makes host_rank() honour the fake value even when
-- not actually guesting.
--
-- This is a DEV keybind. It MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if not managers or not managers.csr or not managers.csr.debug_force_host_rank then
	log("[CSR][debug] mp-host-rank: manager not ready")
	return
end

local STEPS = { false, 10, 25, 50 }
_G.CSR_DebugHostRankCycle = ((_G.CSR_DebugHostRankCycle or 0) % #STEPS) + 1
local value = STEPS[_G.CSR_DebugHostRankCycle]

managers.csr:debug_force_host_rank(value == false and nil or value)

-- Repaint the lobby (RANK readout + item quota/reminder) immediately so the
-- change shows without reopening a panel. No-op when not in the CSR lobby.
local comp = managers.menu_component and managers.menu_component._crime_spree_missions
if comp and comp.refresh_for_rank_change then
	comp:refresh_for_rank_change()
end

local msg = value == false and "host_rank sim OFF (own rank)" or ("host_rank sim = " .. tostring(value))
log("[CSR][debug] " .. msg)
if managers.chat then
	managers.chat:_receive_message(1, "[CSR Debug]", msg, Color(1, 1, 0.6, 0))
end
