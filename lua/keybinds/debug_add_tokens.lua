-- CSR debug keybind: credit 100 Gage Tokens to the local player.
--
-- Gage Tokens have no earning path yet (the shop was ported first; earning is a
-- later slice), so this is the dev hook that makes the shop testable. Local-only:
-- the wallet is per-peer and lives on the local CSRGameManager state.
--
-- This is a DEV keybind. It MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if not _G.CSR_Shop or not managers or not managers.csr then
	log("[CSR][debug] add-tokens: shop/manager not ready")
	return
end

local pid = CSR_Shop.local_peer_id()
CSR_Shop.credit(pid, 100)
log("[CSR][debug] credited 100 Gage Tokens; wallet=" .. tostring(CSR_Shop.tokens(pid)))
