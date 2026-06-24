-- Inserts "Return to Lobby" into the ESC pause menu.
-- Visibility gated by return_to_csr_lobby_visible (contract_callbacks.lua); click + routing in lobby_routing.lua.

if not RequiredScript then
	return
end

-- Vanilla quit callbacks across pause-menu states; our button lands just above this row.
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

-- Fallback: land before any trailing back/last_item sentinel.
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

-- Node is keyed "pause" not "pause_menu".
Hooks:Add("MenuManagerBuildCustomMenus", "CSR_PauseMenuReturnToLobby", function(menu_manager, nodes)
	if not nodes or not nodes.pause then
		return
	end

	local node = nodes.pause

	-- Hide vanilla "abort_mission" in CSR heists; CSR owns quit via Return to Lobby.
	-- STANDARD gamemode lets abort_mission's crime_spree_not_is_active callback pass, so we must suppress it.
	-- Item:visible() AND-s all callbacks (coremenuitem.lua), so injecting false hides it only in CSR.
	if node._items then
		for _, item in ipairs(node._items) do
			local p = item.parameters and item:parameters()
			if p and p.name == "abort_mission" and not item._csr_hidden_in_heist then
				item._csr_hidden_in_heist = true
				item._visible_callback_list = item._visible_callback_list or {}
				table.insert(item._visible_callback_list, function()
					return not (managers and managers.csr and managers.csr.in_csr_heist and managers.csr:in_csr_heist())
				end)
			end
		end
	end

	-- Idempotency guard: hook can re-fire on manager re-init or VR toggle.
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
