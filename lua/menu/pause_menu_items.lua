-- CSR pause-menu additions.
--
-- Adds a "Return to Lobby" button to the in-game pause menu (the overlay
-- the player gets by pressing ESC). The button is visibility-gated by
-- MenuCallbackHandler:return_to_csr_lobby_visible (see contract_callbacks.lua)
-- so it only shows on the BRIEFING screen and the ENDSCREEN
-- (victoryscreen / gameoverscreen) -- never in the active heist and never
-- in the post-heist lobby itself.
--
-- The actual click action -- a confirm dialog into the CSR-routed lobby
-- reload -- is already implemented in MenuCallbackHandler:return_to_csr_lobby
-- (contract_callbacks.lua) and the on_enter_lobby reroute in
-- lobby_routing.lua. This file only WIRES that existing pipeline into
-- the pause menu UI.
--
-- Insertion strategy: scan node._items for the FIRST item whose callback
-- name list contains a vanilla "leave to main menu" callback (quit_game /
-- leave_lobby / menu_quit_lobby cover the variations PD2 uses across
-- ingame / lobby / endscreen states). Insert our item at that index so we
-- render directly ABOVE the existing quit-to-main-menu row. Fallback: if
-- no quit row is found (mod conflict or vanilla rename), insert near the
-- end (just before any trailing back-button row) so we still appear in
-- the menu rather than vanishing silently.
--
-- Hook: MenuManagerBuildCustomMenus. SuperBLT's base mod fires this hook
-- from MenuManagerPostInitialize for both menu_main and menu_pause (see
-- mods/base/lua/MenuManager.lua _base_process_menu). The hook receives
-- the resolved `_nodes` table for the menu being processed; for menu_pause
-- the ROOT node is keyed `pause` (default_node="pause" in pause_menu.menu),
-- NOT `pause_menu`. We gate on nodes.pause to distinguish the menu_pause
-- call from menu_main (which has no `pause` node).
--
-- Critical Rule #1: this is Hooks:Add registration, not a function
-- override; the listener is purely additive. The vanilla
-- node:insert_item call is the published API for menu nodes
-- (coremenunode.lua: function MenuNode:insert_item(item, i)) and is used
-- by base PD2 itself, so we're not patching internals.

if not RequiredScript then
	return
end

-- Vanilla callback names for "back to main menu" across the states where
-- the pause menu can open. Any item whose callback list contains one of
-- these is our insertion anchor.
local QUIT_TO_MAIN_CALLBACKS = {
	quit_game = true,
	leave_lobby = true,
	menu_quit_lobby = true,
	end_game = true,
}

local function find_quit_index(items)
	for i, item in ipairs(items) do
		local params = item.parameters and item:parameters()
		local cb_list = params and params.callback_name
		if cb_list then
			for _, cb in ipairs(cb_list) do
				if QUIT_TO_MAIN_CALLBACKS[cb] then
					return i
				end
			end
		end
	end
	return nil
end

local function find_trailing_back_index(items)
	-- Last meaningful insertion point if no quit row was found. Vanilla
	-- puts a "back" / "last_item" sentinel at the very end of some nodes
	-- (see MenuNode:add_item logic), so we land BEFORE that if it exists.
	for i = #items, 1, -1 do
		local item = items[i]
		local params = item.parameters and item:parameters()
		if not params or (not params.back and not params.last_item) then
			return i + 1
		end
	end
	return #items + 1
end

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_PauseMenuReturnToLobby", function(menu_manager, nodes)
	if not nodes or not nodes.pause then
		return
	end

	local node = nodes.pause

	-- Idempotency: SuperBLT can fire this hook more than once across menu
	-- lifecycle (manager re-init on reconnect / VR toggle). Skip if our
	-- item is already present.
	if node._items then
		for _, item in ipairs(node._items) do
			if item.parameters and item:parameters().name == "csr_return_to_lobby" then
				return
			end
		end
	end

	local data = {
		type = "CoreMenuItem.Item",
	}
	local params = {
		name = "csr_return_to_lobby",
		text_id = "csr_pause_return_to_lobby",
		help_id = "csr_pause_return_to_lobby_desc",
		callback = "return_to_csr_lobby",
		visible_callback = "return_to_csr_lobby_visible",
		localize = "true",
	}

	local new_item = node:create_item(data, params)

	local insert_at = find_quit_index(node._items) or find_trailing_back_index(node._items)
	node:insert_item(new_item, insert_at)

	csr_log(
		"[CSR] csr_pause_menu_items: inserted Return to Lobby at index "
			.. tostring(insert_at)
			.. " of pause node (total items now "
			.. tostring(#node._items)
			.. ")"
	)
end)

csr_log("[CSR] pause_menu_items.lua loaded")
