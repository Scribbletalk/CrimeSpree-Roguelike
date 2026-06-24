-- Redirects vanilla on_enter_lobby to the CSR lobby node (vanilla gamemode flag never set).

if not RequiredScript then
	return
end

-- Vanilla never clears the end-screen backdrop on CSR's return path; tear it down manually.
local function csr_teardown_endscreen_hud()
	local hud = managers and managers.hud
	local screen = hud and hud._hud_stage_endscreen

	if screen and screen._backdrop then
		screen._backdrop:close()
		hud._hud_stage_endscreen = nil
		csr_log("[CSR] lobby routing: tore down stale end-screen HUD backdrop")
	end
end

-- Hard isolation: a CSR client must never sit in a VANILLA Crime Spree lobby. This covers EVERY join
-- path (Crime.Net browser AND a Steam invite that bypasses the browser + accept_crimenet_contract).
-- Detect from the joined lobby's broadcast attributes: crime_spree>=0 marks a CS lobby; absence of our
-- csr_mod marker (set by apply_matchmake_attributes for CSR hosts) means it is vanilla CS.
local function csr_in_foreign_cs_lobby()
	if not (CSR_MP and CSR_MP.is_client and CSR_MP.is_client()) then
		return false
	end
	local mm = managers.network and managers.network.matchmake
	local lobby_data = mm and mm.get_lobby_data and mm:get_lobby_data()
	if not lobby_data then
		return false
	end
	local cs = tonumber(lobby_data.crime_spree)
	return cs ~= nil and cs >= 0 and not lobby_data.csr_mod
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

	-- Joined a vanilla Crime Spree lobby (any path, incl. Steam invite): leave at once and explain why.
	if csr_in_foreign_cs_lobby() then
		csr_log("[CSR] lobby routing: vanilla Crime Spree lobby detected -> leaving (CSR isolation)")
		MenuCallbackHandler:_dialog_leave_lobby_yes()
		managers.system_menu:show({
			title = managers.localization:text("csr_join_blocked_title"),
			text = managers.localization:text("csr_join_blocked_text"),
			button_list = { { text = managers.localization:text("dialog_ok") } },
		})
		return
	end

	-- Joining CLIENT: ping the host; the reply reroutes us. Self-gates on is_client.
	if _G.CSR_MP and _G.CSR_MP.lobby_ping_host then
		_G.CSR_MP.lobby_ping_host()
	end

	-- RETURNING guest: reroute immediately using the cached host_seed; on briefing->lobby return the
	-- host's LOBBY_PING handler bails (missions not ready yet) so we can't wait for its reply.
	if
		managers.csr
		and managers.csr.is_guesting
		and managers.csr:is_guesting()
		and _G.CSR_reroute_client_to_csr_lobby
	then
		_G.CSR_reroute_client_to_csr_lobby()
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
