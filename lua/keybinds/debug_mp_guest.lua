-- CSR debug keybind: simulate GUESTING in SOLO so the per-host guest session-store
-- redirect (M5) can be checked without a second instance. Toggles a flag that routes
-- the local player's items / tokens / pending offers to a separate per-host session
-- store (in _meta, keyed by a fake host seed) instead of the solo run's _state --
-- which stays untouched, so the sim is fully reversible. Combine with the fake
-- host_rank keybind to also reproduce a guest's scaling + item-selection quota.
--
-- This is a DEV keybind. It MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if not managers or not managers.csr or not managers.csr.debug_toggle_guest_session then
	log("[CSR][debug] mp-guest: manager not ready")
	return
end

local on = managers.csr:debug_toggle_guest_session()

-- Repaint the lobby (Items panel / RANK / quota) so the inventory swap shows without
-- reopening a panel. No-op when not in the CSR lobby.
local comp = managers.menu_component and managers.menu_component._crime_spree_missions
if comp and comp.refresh_for_rank_change then
	comp:refresh_for_rank_change()
end

local msg = on and "guest-session sim ON (inventory -> per-host store)" or "guest-session sim OFF (own inventory)"
log("[CSR][debug] " .. msg)
if managers.chat then
	managers.chat:_receive_message(1, "[CSR Debug]", msg, Color(1, 1, 0.6, 0))
end
