-- Lobby node redirect — vanilla's on_enter_lobby routes by gamemode, which CSR
-- never enables, so the player always lands in the empty "lobby" node. Two paths:
--   1. Host self-redirect via Global.CSR_RETURN_TO_LOBBY (one-shot flag).
--   2. Joining client pings host via mp_sync.lua LOBBY_PING.
-- Plus tears down the orphaned end-screen HUD backdrop that survives the transition.
-- See csr_mp_architecture.md.

if not RequiredScript then
	return
end

-- CSRHUDStageEndScreen._backdrop lives on the PERSISTENT fullscreen workspace and
-- nothing in vanilla destroys it on the CSR temp-job return path. close() removes
-- _panel + workspaces; nilling _hud_stage_endscreen lets the next setup build fresh.
local function csr_teardown_endscreen_hud()
	local hud = managers and managers.hud
	local screen = hud and hud._hud_stage_endscreen

	if screen and screen._backdrop then
		screen._backdrop:close()
		hud._hud_stage_endscreen = nil
		csr_log("[CSR] lobby routing: tore down stale end-screen HUD backdrop")
	end
end

-- Exposed so mp_sync.lua's LOBBY_CSR handler can reroute a joining client.
function _G.CSR_reroute_client_to_csr_lobby()
	local active = managers.menu and managers.menu:active_menu()
	local logic = active and active.logic
	if not logic then
		csr_log("[CSR] lobby routing: client reroute skipped (no active menu logic)")
		return
	end
	logic:select_node("crime_spree_lobby", true, {})
	csr_log("[CSR] lobby routing: client rerouted -> crime_spree_lobby (host confirmed CSR)")
end

Hooks:PostHook(MenuManager, "on_enter_lobby", "CSR_OnEnterLobbyRoute", function(self)
	csr_log("[CSR] lobby routing: on_enter_lobby PostHook fired (flag=" .. tostring(Global.CSR_RETURN_TO_LOBBY) .. ")")

	-- Joining CLIENT: ping the host; the reply reroutes us. Self-gates on is_client.
	if _G.CSR_MP and _G.CSR_MP.lobby_ping_host then
		_G.CSR_MP.lobby_ping_host()
	end

	if not Global.CSR_RETURN_TO_LOBBY then
		return
	end

	Global.CSR_RETURN_TO_LOBBY = nil

	-- Tear down the end-screen backdrop FIRST so it goes even if logic is nil below.
	csr_teardown_endscreen_hud()

	local active = managers.menu and managers.menu:active_menu()
	local logic = active and active.logic

	if not logic then
		log("[CSR] lobby routing: no active menu logic, cannot reroute to CSR lobby")

		return
	end

	logic:select_node("crime_spree_lobby", true, {})
	csr_log("[CSR] lobby routing: rerouted on_enter_lobby -> crime_spree_lobby node")
end)

csr_log("[CSR] lobby_routing.lua loaded")
