-- Redirects vanilla on_enter_lobby to the CSR lobby node (vanilla gamemode flag never set).

if not RequiredScript then
	return
end

-- End-screen backdrop persists on the fullscreen workspace; vanilla never clears it on CSR's return path.
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
