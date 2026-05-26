-- CSR debug keybind: toggle a fake remote peer (with a few owned items) so the
-- per-peer items panel can be checked in SOLO without a second instance. Press in
-- the lobby with the Items feature panel open: a second peer section appears /
-- disappears. Exercises the remote-peer store + panel enumeration that the MP item
-- sync (M2b) fills for real.
--
-- This is a DEV keybind. It MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if not managers or not managers.csr or not managers.csr.debug_toggle_fake_peer then
	log("[CSR][debug] mp-fake-peer: manager not ready")
	return
end

local injected = managers.csr:debug_toggle_fake_peer()

-- Repaint the items panel so the fake peer shows/hides immediately. No-op when not
-- in the CSR lobby.
local comp = managers.menu_component and managers.menu_component._crime_spree_missions
if comp and comp.refresh_for_rank_change then
	comp:refresh_for_rank_change()
end

local msg = injected and "fake remote peer ON" or "fake remote peer OFF"
log("[CSR][debug] " .. msg)
if managers.chat then
	managers.chat:_receive_message(1, "[CSR Debug]", msg, Color(1, 1, 0.6, 0))
end
