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

	-- TEMP B4 diag: dump every pause-node item (id + text_id + localized text) so we can identify the
	-- exact standard-mode quit button the user sees as "Terminate Contract". STRIP after B4. [CSR][mptest]
	-- Gated on CSR_DEBUG via csr_log (debug-only; B4 is fixed -- kept behind the toggle, not unconditional).
	csr_log(
		"[CSR][mptest][pausemenu] build hook fired; node="
			.. tostring(node)
			.. " items="
			.. tostring(node and node._items)
	)
	if node and node._items then
		for _, it in ipairs(node._items) do
			local p = it.parameters and it:parameters()
			if p then
				local tid = p.text_id
				local txt = (tid and managers and managers.localization and managers.localization:text(tid)) or "?"
				csr_log(
					"[CSR][mptest][pausemenu] name="
						.. tostring(p.name)
						.. " text_id="
						.. tostring(tid)
						.. " text="
						.. tostring(txt)
				)
			end
		end
	end

	-- Hide the vanilla "Terminate contract" quit (item "abort_mission") inside CSR runs only.
	-- CSR owns the quit flow via its own "Return to Lobby"; this standard-mode quit leaks in CSR
	-- heists because they run the STANDARD gamemode (job_id "crime_spree"), so abort_mission's
	-- crime_spree_not_is_active callback passes. We append a CSR-gated visible_callback: Item:visible()
	-- AND-s every callback (coremenuitem.lua), so returning false here forces the item hidden whenever
	-- in_csr_heist() is true. in_csr_heist() is job_id-based -> covers host AND guest, and stays false
	-- in vanilla heists and real Crime Spree, so those keep their normal quit. Idempotent via a flag.
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
