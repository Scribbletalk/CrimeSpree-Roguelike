-- CSR main-menu buttons.
--
-- Inserts two new items into the main menu (nodes.main) directly below the
-- vanilla "Play Offline" entry, in this order:
--   csr_play_online   — sits after  "crimenet_offline"
--   csr_play_offline  — sits after  "csr_play_online"
-- (Anchored as a chain so both end up below vanilla Play Offline.)
--
-- For now the callbacks just chain to vanilla play_online_game /
-- play_single_player so the buttons land on CrimeNet exactly like the vanilla
-- ones do. The CSR-run activation will be wired in a follow-up.

if not RequiredScript then
	return
end

Hooks:Add("LocalizationManagerPostInit", "CSR_MainMenuLocalization", function(loc)
	loc:add_localized_strings({
		csr_play_online_title = "Play Roguelike Online",
		csr_play_online_desc = "Start a Crime Spree Roguelike run with online matchmaking.",
		csr_play_offline_title = "Play Roguelike Offline",
		csr_play_offline_desc = "Start a Crime Spree Roguelike run in single-player.",
	})
end)

Hooks:Add("MenuManagerInitialize", "CSR_MainMenuCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_play_online_callback = function(self, item)
		log("[CSR] csr_play_online_callback fired (CSR-mode flag wiring TBD)")
		if MenuCallbackHandler.play_online_game then
			MenuCallbackHandler:play_online_game()
		end
	end

	MenuCallbackHandler.csr_play_offline_callback = function(self, item)
		log("[CSR] csr_play_offline_callback fired (CSR-mode flag wiring TBD)")
		if MenuCallbackHandler.play_single_player then
			MenuCallbackHandler:play_single_player()
		end
	end
end)

-- Helper: insert `item` right after the existing entry whose name matches
-- `anchor_name`. Returns true if the anchor was found, false otherwise (in
-- which case the item is appended to the end).
local function insert_after(parent_node, item, anchor_name)
	for i, existing in ipairs(parent_node._items) do
		local p = existing._parameters
		if p and p.name == anchor_name then
			table.insert(parent_node._items, i + 1, item)
			return true
		end
	end
	table.insert(parent_node._items, item)
	return false
end

local function has_item(parent_node, item_name)
	for _, existing in ipairs(parent_node._items) do
		local p = existing._parameters
		if p and p.name == item_name then
			return true
		end
	end
	return false
end

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_MainMenuButtons", function(menu_manager, nodes)
	local node_main = nodes and nodes.main
	if not node_main then
		return
	end

	-- Guard: BuildCustomMenus can fire more than once across the session
	-- (mod reloads, returning to main menu). Don't add the items twice.
	if has_item(node_main, "csr_play_online") and has_item(node_main, "csr_play_offline") then
		return
	end

	if not has_item(node_main, "csr_play_online") then
		local online_item = node_main:create_item({
			name = "csr_play_online",
			type = "CoreMenuItem.Item",
		}, {
			name = "csr_play_online",
			text_id = "csr_play_online_title",
			help_id = "csr_play_online_desc",
			callback = "csr_play_online_callback",
			next_node = "crimenet",
		})
		insert_after(node_main, online_item, "crimenet_offline")
	end

	if not has_item(node_main, "csr_play_offline") then
		local offline_item = node_main:create_item({
			name = "csr_play_offline",
			type = "CoreMenuItem.Item",
		}, {
			name = "csr_play_offline",
			text_id = "csr_play_offline_title",
			help_id = "csr_play_offline_desc",
			callback = "csr_play_offline_callback",
			next_node = "crimenet_single_player",
		})
		insert_after(node_main, offline_item, "csr_play_online")
	end

	log("[CSR] main-menu: CSR Play Online / Offline buttons installed")
end)
