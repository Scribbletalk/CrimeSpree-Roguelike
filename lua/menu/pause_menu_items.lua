-- Inserts "Return to Lobby" into the in-game pause menu (ESC overlay).
-- Visibility-gated by return_to_csr_lobby_visible (contract_callbacks.lua) so it
-- only shows on briefing + endscreen, never in the active heist or post-heist lobby.
-- Click action + lobby reroute live in contract_callbacks.lua / lobby_routing.lua.

if not RequiredScript then
	return
end

-- Vanilla "back to main menu" callbacks across pause-menu states; we render just above this row.
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

-- Fallback: land BEFORE any trailing back/last_item sentinel.
local function find_trailing_back_index(items)
	for i = #items, 1, -1 do
		local item = items[i]
		local params = item.parameters and item:parameters()
		if not params or (not params.back and not params.last_item) then
			return i + 1
		end
	end
	return #items + 1
end

-- Pause-menu root node is keyed "pause" (NOT "pause_menu") — see CSR critical rule.
Hooks:Add("MenuManagerBuildCustomMenus", "CSR_PauseMenuReturnToLobby", function(menu_manager, nodes)
	if not nodes or not nodes.pause then
		return
	end

	local node = nodes.pause

	-- Idempotency: hook can fire on manager re-init / VR toggle.
	if node._items then
		for _, item in ipairs(node._items) do
			if item.parameters and item:parameters().name == "csr_return_to_lobby" then
				return
			end
		end
	end

	local data = { type = "CoreMenuItem.Item" }
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
