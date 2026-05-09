-- Crime Spree Roguelike - Client SELECT ITEM UI
-- Shows SELECT ITEM button for clients in lobby and end screen.
-- Ready system disabled — host can start freely.

if not RequiredScript then
	return
end

local key = ModPath .. "\t" .. RequiredScript
if _G[key] then
	return
else
	_G[key] = true
end

local required = RequiredScript:lower()

-- Routes:
--   menumanager: SELECT ITEM UI for clients + network handler
--   menucomponentmanager: PostHook on LobbyCharacterData for "SELECTING ITEM" text
--   missionendstate: PostHook on MissionEndState:update for end screen UI
if
	required ~= "lib/managers/menumanager"
	and required ~= "lib/managers/menu/menumanagercrimespreecallbacks"
	and required ~= "lib/states/missionendstate"
	and required ~= "lib/managers/menu/menucomponentmanager"
then
	return
end

-- === Route: menumanagercrimespreecallbacks ===
-- Ready system disabled — host can start freely. Keep route for future re-enable.
if required == "lib/managers/menu/menumanagercrimespreecallbacks" then
	return
end

-- === Route: menucomponentmanager ===
-- PostHook on LobbyCharacterData:update_character_menu_state to show "SELECTING ITEM".
-- LobbyCharacterData is loaded via require inside menucomponentmanager.lua, so it exists here.
-- This runs every frame (from CrimeSpreeContractBoxGui:update → update_character), so the
-- override persists even if vanilla resets the text via sync state RPCs.
-- Verified: LobbyCharacterData:update_character_menu_state at lobbycharacterdata.lua:163
if required == "lib/managers/menu/menucomponentmanager" then
	if LobbyCharacterData then
		Hooks:PostHook(
			LobbyCharacterData,
			"update_character_menu_state",
			"CSR_SelectingItemOverride",
			function(self, new_state)
				local selecting = _G._csr_selecting_peers
				if not selecting then
					return
				end
				if not self._peer then
					return
				end
				local peer_id = self._peer:id()
				if selecting[peer_id] then
					self._state_text:set_text(
						managers.localization:to_upper_text("menu_lobby_menu_state_selecting_item")
					)
				end
			end
		)
	end
	return
end

-- === Route: missionendstate ===
-- PostHook on MissionEndState:update to run SELECT ITEM UI during victory/gameover screens.
-- Neither MenuUpdate nor GameSetupUpdate fires during MissionEndState.
if required == "lib/states/missionendstate" then
	if MissionEndState then
		Hooks:PostHook(MissionEndState, "update", "CSR_ReadySystem_EndScreen", function(self, t, dt)
			if _G.csr_ready_update then
				_G.csr_ready_update(t, dt)
			end
		end)
		log("[CSR] MissionEndState SELECT ITEM PostHook registered")
	end
	return -- Done with this route
end

-- === Route: menumanager ===
-- Ready system disabled — this file now only provides SELECT ITEM UI for clients
-- and "SELECTING ITEM" lobby status sync.

-- Global table tracking which peers are currently selecting items.
-- Updated by network handler (remote peers) and _node_selected PostHook (local peer).
-- Read by LobbyCharacterData PostHook (menucomponentmanager route) to override display text.
_G._csr_selecting_peers = _G._csr_selecting_peers or {}

-- Network handler: track which peers are selecting items
Hooks:Add("NetworkReceivedData", "CSR_SelectingItemSync", function(sender, id, data)
	if id ~= "CSR_SelectingItem" then
		return
	end
	local peer_id = tonumber(sender)
	if not peer_id then
		return
	end
	_G._csr_selecting_peers[peer_id] = (data == "1") or nil
end)

-- Track local player's selection state and notify peers
if MenuManager then
	Hooks:PostHook(MenuManager, "_node_selected", "CSR_SelectingItemStatus", function(self, menu_name, node)
		if not node then
			return
		end
		local node_name = node:parameters() and node:parameters().name
		if not node_name then
			return
		end
		local session = managers.network and managers.network:session()
		if not session then
			return
		end
		local peer = session:local_peer()
		if not peer then
			return
		end
		if node_name == "crime_spree_select_modifiers" then
			_G._csr_selecting_peers[peer:id()] = true
			LuaNetworking:SendToPeers("CSR_SelectingItem", "1")
		elseif _G._csr_was_selecting_item then
			_G._csr_selecting_peers[peer:id()] = nil
			LuaNetworking:SendToPeers("CSR_SelectingItem", "0")
		end
		_G._csr_was_selecting_item = (node_name == "crime_spree_select_modifiers")
	end)
end

-- Panel references (global so MenuUpdate can access them)
_G._csr_ready_ui = _G._csr_ready_ui or {}

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR SelectItem] " .. tostring(msg))
	end
end

local function count_peers()
	local session = managers.network and managers.network:session()
	if not session then
		return 1
	end
	local count = 1
	for _, peer in pairs(session:peers() or {}) do
		if peer then
			count = count + 1
		end
	end
	return count
end

-- Get current menu node name
local function current_node_name()
	local active_menu = managers.menu and managers.menu:active_menu()
	local node = active_menu and active_menu.logic and active_menu.logic:selected_node()
	return node and node:parameters() and node:parameters().name
end

-- Ready system disabled — no callback override or network handler needed.

-- ============================================================
-- SELECT ITEM UI via MenuUpdate
-- ============================================================

-- Destroy the overlay panel
local function destroy_select_ui()
	local ui = _G._csr_ready_ui
	if ui.select_panel and alive(ui.select_panel) then
		ui.select_panel:parent():remove(ui.select_panel)
	end
	if ui.items_ready_text and alive(ui.items_ready_text) then
		ui.items_ready_text:parent():remove(ui.items_ready_text)
	end
	_G._csr_ready_ui = {}
end

-- Create SELECT ITEM overlay on fullscreen workspace
local function create_select_ui()
	destroy_select_ui()

	local mcm = managers.menu_component
	if not mcm then
		return
	end

	local ws = mcm._fullscreen_ws
	if not ws or not alive(ws:panel()) then
		return
	end

	local parent = ws:panel()
	local ui = _G._csr_ready_ui

	local large_font = tweak_data.menu.pd2_large_font
	local large_font_size = tweak_data.menu.pd2_large_font_size
	local accent = tweak_data.screen_colors.button_stage_3

	-- SELECT ITEM button (CrimeSpreeButton style, bottom-right)
	ui.select_panel = parent:panel({
		name = "csr_select_item",
		w = parent:w() * 0.35,
		h = large_font_size,
		layer = 500,
	})

	ui.select_text = ui.select_panel:text({
		text = managers.localization:to_upper_text("menu_cs_select_modifier"),
		font = large_font,
		font_size = large_font_size,
		color = accent,
		blend_mode = "add",
		align = "right",
		halign = "right",
		layer = 1,
	})

	ui.select_highlight = ui.select_panel:rect({
		blend_mode = "add",
		alpha = 0,
		color = accent,
		layer = 10,
	})

	-- Position: match vanilla pd2_corner button layout (menunodegui.lua)
	local ws_panel = mcm._ws and mcm._ws:panel()
	local btn_right = ws_panel and (ws_panel:world_x() + ws_panel:w() + 40) or parent:w()
	local btn_bottom = ws_panel and (ws_panel:world_y() + ws_panel:h() + 25) or parent:h()

	local _, _, stw, sth = ui.select_text:text_rect()
	ui.select_panel:set_size(stw, sth)
	ui.select_panel:set_right(btn_right)
	ui.select_panel:set_bottom(btn_bottom)

	-- Green text shown when all items selected
	local green = Color(1, 0.2, 0.8, 0.2)

	ui.items_ready_text = parent:text({
		name = "csr_items_ready",
		text = managers.localization:to_upper_text("csr_items_ready"),
		font = large_font,
		font_size = large_font_size,
		color = green,
		blend_mode = "add",
		align = "right",
		halign = "right",
		w = parent:w() * 0.35,
		h = large_font_size,
		layer = 500,
		visible = false,
	})
	ui.items_ready_text:set_right(btn_right)
	ui.items_ready_text:set_bottom(btn_bottom)

	CSR_log("SELECT ITEM UI created")
end

function _G.csr_ready_update(t, dt)
	local is_mp = _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer()
	local total = count_peers()
	local node = current_node_name()

	-- Show on CS lobby, mission-end node, or victory/gameover screen
	local on_end_screen = false
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		on_end_screen = state == "victoryscreen" or state == "gameoverscreen"
	end
	-- is_active() can briefly drop on the heist->endscreen boundary; use the union
	-- to avoid a one-frame UI flicker on the SELECT ITEM / READY button.
	local cs = managers.crime_spree
	local cs_active = cs and ((cs.is_active and cs:is_active()) or (cs.in_progress and cs:in_progress()))
	local has_other_players = total > 1
	local should_show = is_mp
		and cs_active
		and has_other_players
		and (
			node == "crime_spree_lobby"
			or node == "crime_spree_mission_end"
			or node == "crime_spree_select_modifiers"
			or on_end_screen
		)

	-- Hide visuals when on selection screen, system dialog, or pause/kit menu
	local visuals_hidden = (node == "crime_spree_select_modifiers")
		or (managers.system_menu and managers.system_menu:is_active() and true or false)
		or (
			managers.menu and (managers.menu:is_open("pause_menu") or managers.menu:is_open("kit_menu")) and true
			or false
		)

	local ui = _G._csr_ready_ui

	if not should_show then
		if ui.select_panel and alive(ui.select_panel) then
			destroy_select_ui()
		end
		return
	end

	-- Create UI if it doesn't exist
	if not ui.select_panel or not alive(ui.select_panel) then
		create_select_ui()
		ui = _G._csr_ready_ui
		if not ui.select_panel then
			return
		end
		CSR_log("Panel created on node: " .. tostring(node))
	end

	-- === ITEM SELECTION (clients only — host has vanilla SELECT ITEM) ===
	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
	local total_drops = _G.CSR_MP_TotalDrops or 0

	-- Pending count must subtract shop/catchup items (they inflate #my_items
	-- but don't bump total_drops). modifiers_to_select("loud") in
	-- crimespree_filter.lua does that math for both roles — use it as the
	-- single source of truth instead of a naive #my_items < total_drops check.
	local has_pending = false
	if is_client and managers.crime_spree and managers.crime_spree.modifiers_to_select then
		local ok, pending = pcall(function()
			return managers.crime_spree:modifiers_to_select("loud") or 0
		end)
		has_pending = ok and pending and pending > 0 or false
	end

	local items_done = not has_pending and total_drops > 0

	ui.select_panel:set_visible(not visuals_hidden and has_pending and is_client)
	if ui.items_ready_text and alive(ui.items_ready_text) then
		ui.items_ready_text:set_visible(false)
	end

	-- Hover effects
	if has_pending and is_client then
		local hx, hy = managers.mouse_pointer:modified_fullscreen_16_9_mouse_pos()
		local sel_color = tweak_data.screen_colors.button_stage_3
		local sel_hover = tweak_data.screen_colors.button_stage_2

		if ui.select_text and alive(ui.select_text) then
			local sx, sy = ui.select_panel:world_position()
			local s_in = hx >= sx and hx <= sx + ui.select_panel:w() and hy >= sy and hy <= sy + ui.select_panel:h()
			ui.select_text:set_color(s_in and sel_hover or sel_color)
			if ui.select_highlight and alive(ui.select_highlight) then
				ui.select_highlight:set_visible(s_in)
				ui.select_highlight:set_alpha(0.2)
				ui.select_highlight:set_color(s_in and sel_hover or sel_color)
			end
		end
	end
end

-- MenuUpdate fires during MenuSetup (lobby, main menu)
-- End screen uses MissionEndState:update PostHook (registered via missionendstate route)
Hooks:Add("MenuUpdate", "CSR_ReadySystemUpdate", csr_ready_update)

-- Click handling via PostHook on MenuComponentManager:mouse_pressed
-- Verified: MenuComponentManager:mouse_pressed exists at menucomponentmanager.lua:1389
-- Verified: managers.gui_data:safe_to_full_16_9 exists at coreguidatamanager.lua:370
-- Verified: managers.menu:open_node exists at menumanager.lua:336
if MenuComponentManager then
	Hooks:PostHook(
		MenuComponentManager,
		"mouse_pressed",
		"CSR_ReadySystem_MousePressed",
		function(self, o, button, x, y)
			if button ~= Idstring("0") then
				return
			end
			local ui = _G._csr_ready_ui
			if not ui then
				return
			end

			-- Convert safe-rect x,y to fullscreen 16:9 coords (our panels live on _fullscreen_ws)
			local fx, fy = managers.gui_data:safe_to_full_16_9(x, y)

			-- SELECT ITEM button
			if ui.select_panel and alive(ui.select_panel) and ui.select_panel:visible() then
				local sx, sy = ui.select_panel:world_position()
				local sw, sh = ui.select_panel:w(), ui.select_panel:h()
				if fx >= sx and fx <= sx + sw and fy >= sy and fy <= sy + sh then
					managers.menu:open_node("crime_spree_select_modifiers", {})
					managers.menu_component:post_event("menu_enter")
				end
			end
		end
	)
end
