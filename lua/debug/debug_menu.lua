-- Crime Spree Roguelike - Debug Menu
-- Loaded conditionally by lua/menu/options.lua via dofile.
-- The entire lua/debug/ folder is physically excluded from release ZIPs
-- (see EXCLUDE_DIRS in release/_build_template.py); release users never see this.

if _G.CSR_DEBUG_MENU_LOADED then
	return
end
_G.CSR_DEBUG_MENU_LOADED = true

local RARITY_ORDER = { "wildcard", "contraband", "rare", "uncommon", "common" }
local RARITY_BASE_PRIORITY = {
	wildcard = 220,
	contraband = 200,
	rare = 180,
	uncommon = 160,
	common = 140,
}
local RARITY_HEADER_KEY = {
	wildcard = "csr_debug_header_wildcard",
	contraband = "csr_debug_header_contraband",
	rare = "csr_debug_header_rare",
	uncommon = "csr_debug_header_uncommon",
	common = "csr_debug_header_common",
}

-- Registry types don't always match the logbook's name keys. Keep in sync with
-- localization.lua's csr_logbook_<key>_name strings whenever item_registry.lua
-- types change.
local LOC_NAME_OVERRIDE = {
	health = "dog_tags",
	damage = "evidence_rounds",
	car_keys = "falcogini_keys",
}

local function loc_name_key(item_type)
	local key = LOC_NAME_OVERRIDE[item_type] or item_type
	return "csr_logbook_" .. key .. "_name"
end

local function callback_id(item_type)
	return "csr_debug_grant_" .. item_type
end

local function button_id(item_type)
	return "csr_debug_grant_" .. item_type
end

Hooks:Add("LocalizationManagerPostInit", "CSR_DebugMenuLoc", function(loc)
	loc:add_localized_strings({
		csr_debug_menu_title = "[DEBUG] Items",
		csr_debug_menu_desc = "Testing tools for development. Physically excluded from release builds.",
		csr_debug_grant_desc = "Add one stack of this item. Crime Spree must be active. Grant is MP-synced to all peers.",
		csr_debug_header_wildcard = "--- Wildcard ---",
		csr_debug_header_contraband = "--- Contraband ---",
		csr_debug_header_rare = "--- Rare ---",
		csr_debug_header_uncommon = "--- Uncommon ---",
		csr_debug_header_common = "--- Common ---",
		csr_debug_header_layout = "--- Layout ---",
		csr_debug_fake_4_title = "Emulate 4 Players (Items Tab)",
		csr_debug_fake_4_desc = "Render the Items tab as if 4 players are present, even in singleplayer. Each fake peer shows the local player's items.",
		csr_debug_separator = "--- DEBUG ---",
		csr_debug_heists_menu_title = "[DEBUG] Heists",
		csr_debug_heists_menu_desc = "Force-select specific heists for testing. Crime Spree must be active.",
		csr_debug_force_born_title = "Biker Heist Day 1",
		csr_debug_force_born_desc = "Injects Biker Day 1 into slot 1 of available missions and selects it. Crime Spree must be active.",
		csr_debug_force_rvd1_title = "Reservoir Dogs Day 1",
		csr_debug_force_rvd1_desc = "Injects Reservoir Dogs Day 1 into slot 1 of available missions and selects it. Crime Spree must be active.",
		csr_debug_force_kenaz_title = "Golden Grin Casino",
		csr_debug_force_kenaz_desc = "Injects Golden Grin Casino into slot 1 of available missions and selects it. Crime Spree must be active.",
		csr_debug_force_roberts_title = "Go Bank",
		csr_debug_force_roberts_desc = "Injects Go Bank into slot 1 of available missions and selects it. Crime Spree must be active.",
		csr_debug_instant_win_title = "Instant Win (Current Heist)",
		csr_debug_instant_win_desc = "Force the current heist to victory. Must be in a heist (game state ingame_standard / ingame_waiting_for_players). Also bindable via Mod Keybinds.",
		csr_debug_force_catchup_title = "Force MP Catch-up (All Clients)",
		csr_debug_force_catchup_desc = "Host only: reset every connected client's catch-up snapshot to 0 and re-send their catch-up grant. Useful when a client joined but didn't receive items/tokens.",
		csr_debug_grant_tokens_title = "Grant 50 Tokens",
		csr_debug_grant_tokens_desc = "Add 50 Gage Tokens to the local player's wallet. If host, also bumps the cumulative host_earned counter so future late-join catch-ups include the granted amount. Not broadcast to other peers.",
	})
end)

-- Shared by the keybind script (lua/debug/instant_win.lua) and the Heists debug
-- menu button. Returns true on success, false otherwise so callers can chat-feed.
function _G.CSR_DEBUG_InstantWin()
	if not game_state_machine then
		log("[CSR Instant Win] Not in game")
		return false
	end
	local state_name = game_state_machine:current_state_name()
	log("[CSR Instant Win] Current state: " .. tostring(state_name))
	if state_name ~= "ingame_standard" and state_name ~= "ingame_waiting_for_players" then
		log("[CSR Instant Win] Wrong state for instant win: " .. tostring(state_name))
		return false
	end
	local num_winners = 1
	if managers.network and managers.network:session() then
		num_winners = managers.network:session():amount_of_alive_players() or 1
		managers.network:session():send_to_peers("mission_ended", true, num_winners)
	end
	game_state_machine:change_state_by_name("victoryscreen", {
		num_winners = num_winners,
		personal_win = alive(managers.player:player_unit()),
	})
	log("[CSR Instant Win] Victory triggered!")
	return true
end

local function chat_or_log(msg)
	if managers and managers.chat and ChatManager and ChatManager.GAME then
		managers.chat:feed_system_message(ChatManager.GAME, msg)
	else
		log(msg)
	end
end

-- Persist CSR_PlayerItems to the seed file. CSR_LoadSeed rebuilds the item
-- store from that file on heist-start Lua reload; anything not written there
-- is lost. This mirrors the persist step in crimespree_autosave.lua.
local function persist_items()
	local cs = managers and managers.crime_spree
	if not cs or not _G.CSR_SaveSeed or not _G.CSR_CurrentSeed then
		return
	end
	local diff = (cs._global and cs._global.selected_difficulty) or _G.CSR_CurrentDifficulty or "normal"
	local mods = (cs._global and cs._global.modifiers) or {}
	CSR_SaveSeed(_G.CSR_CurrentSeed, diff, mods)

	-- Keep CSR_SavedModifiers in sync (autosave writes this too, for back-compat).
	_G.CSR_SavedModifiers = {}
	for _, mod in ipairs(mods) do
		table.insert(_G.CSR_SavedModifiers, { id = mod.id, level = mod.level })
	end
	local local_items = _G.CSR_GetLocalItems and CSR_GetLocalItems() or {}
	for _, item in ipairs(local_items) do
		table.insert(_G.CSR_SavedModifiers, { id = item.id, level = item.level })
	end
end

local function grant_item(prefix, display_name)
	if not _G.CSR_AddItem then
		chat_or_log("[CSR DEBUG] CSR_AddItem missing - store not loaded")
		return
	end
	local new_id = CSR_AddItem(prefix)
	-- persist_items relies on CSR_CurrentSeed / a real spree state, so it
	-- only runs when CS is actually active. Outside CS the grant lives in
	-- memory only — fine for safehouse testing of UI like the scrapper menu.
	local cs = managers and managers.crime_spree
	if cs and cs:is_active() then
		persist_items()
	end
	chat_or_log("[CSR DEBUG] Granted " .. display_name .. " (" .. tostring(new_id) .. ")")
	if _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer() and CSR_MP.broadcast_own_items then
		CSR_MP.broadcast_own_items()
	end
end

local function refresh_items_tab()
	if _G.CSR_ItemsPageInstance and _G.CSR_ItemsPageInstance._setup_items then
		pcall(function()
			_G.CSR_ItemsPageInstance:_setup_items()
		end)
	end
end

Hooks:Add("MenuManagerInitialize", "CSR_DebugMenuCallbacks", function(menu_manager)
	for _, def in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
		local prefix = def.id_prefix
		local item_type = def.type
		MenuCallbackHandler[callback_id(item_type)] = function()
			local name = item_type
			if managers and managers.localization then
				name = managers.localization:text(loc_name_key(item_type))
			end
			grant_item(prefix, name)
		end
	end

	MenuCallbackHandler.csr_debug_fake_4_toggle = function(_, item)
		_G.CSR_DEBUG_FAKE_4_PLAYERS = (item:value() == "on")
		refresh_items_tab()
	end

	MenuCallbackHandler.csr_debug_instant_win = function()
		local ok = _G.CSR_DEBUG_InstantWin and _G.CSR_DEBUG_InstantWin() or false
		if not ok then
			chat_or_log("[CSR DEBUG] Instant Win unavailable - not in a heist")
		end
	end

	MenuCallbackHandler.csr_debug_grant_tokens = function()
		if not (CSR_TokensManager and CSR_TokensManager.credit) then
			chat_or_log("[CSR DEBUG] Grant Tokens: CSR_TokensManager missing")
			return
		end
		local pid = (CSR_LocalPeerId and CSR_LocalPeerId()) or 1
		CSR_TokensManager.credit(pid, 50)
		local note = "+50 tokens (wallet=" .. tostring(CSR_TokensManager.get_wallet(pid)) .. ")"
		if Network and Network:is_server() and CSR_TokensManager.add_host_earned then
			CSR_TokensManager.add_host_earned(50)
			note = note .. " host_earned=" .. tostring(CSR_TokensManager.get_host_earned())
		end
		-- Persist immediately so a Lua reload doesn't lose the grant.
		if _G.CSR_SaveSeed and _G.CSR_CurrentSeed then
			local cs = managers and managers.crime_spree
			local diff = (cs and cs._global and cs._global.selected_difficulty) or _G.CSR_CurrentDifficulty or "normal"
			local mods = (cs and cs._global and cs._global.modifiers) or {}
			CSR_SaveSeed(_G.CSR_CurrentSeed, diff, mods)
		end
		-- Refresh shop UI so the new wallet shows up if it's open.
		-- Guard against a stale instance pointer: if the close path didn't
		-- clear the global (or this is racing it), :set_text on a destroyed
		-- panel crashes with C++ access violation. alive() check is mandatory.
		local inst = _G.CSR_GageServicesShopPageInstance
		if inst and type(inst.refresh) == "function" and inst._panel and alive(inst._panel) then
			pcall(function()
				inst:refresh()
			end)
		elseif inst then
			_G.CSR_GageServicesShopPageInstance = nil
		end
		chat_or_log("[CSR DEBUG] " .. note)
	end

	MenuCallbackHandler.csr_debug_force_catchup = function()
		if not (Network and Network:is_server()) then
			chat_or_log("[CSR DEBUG] Force Catch-up: must be host")
			return
		end
		if not (CSR_LateJoinCatchup and CSR_LateJoinCatchup.run_for_peer) then
			chat_or_log("[CSR DEBUG] Force Catch-up: catchup module missing")
			return
		end
		local session = managers.network and managers.network:session()
		if not session then
			chat_or_log("[CSR DEBUG] Force Catch-up: no session")
			return
		end
		local count = 0
		for _, peer in pairs(session:peers() or {}) do
			local pid = peer and peer:id()
			if pid and pid ~= 1 then
				-- Clear the host-side watermark (keyed by user_id) for this peer
				-- so run_for_peer sees delta>0 and grants again.
				local uid = peer.user_id and peer:user_id() or nil
				if uid and uid ~= "" and _G.CSR_HostCatchupSnapshots then
					_G.CSR_HostCatchupSnapshots[uid] = nil
				end
				CSR_LateJoinCatchup.run_for_peer(pid)
				count = count + 1
			end
		end
		chat_or_log("[CSR DEBUG] Force Catch-up: triggered for " .. count .. " client(s)")
	end

	MenuCallbackHandler.csr_debug_force_born = function()
		local cs = managers and managers.crime_spree
		if not cs or not cs:is_active() then
			chat_or_log("[CSR DEBUG] Crime Spree not active - cannot force heist")
			return
		end
		local mission = cs:get_mission("born")
		if not mission then
			chat_or_log("[CSR DEBUG] Mission 'born' not found in tweak_data")
			return
		end
		if cs._global.available_missions then
			cs._global.available_missions[1] = mission
		end
		cs:select_mission("born")
		chat_or_log("[CSR DEBUG] Forced Biker Heist Day 1 (born)")
	end

	MenuCallbackHandler.csr_debug_force_rvd1 = function()
		local cs = managers and managers.crime_spree
		if not cs or not cs:is_active() then
			chat_or_log("[CSR DEBUG] Crime Spree not active - cannot force heist")
			return
		end
		local mission = cs:get_mission("rvd1")
		if not mission then
			chat_or_log("[CSR DEBUG] Mission 'rvd1' not found in tweak_data")
			return
		end
		if cs._global.available_missions then
			cs._global.available_missions[1] = mission
		end
		cs:select_mission("rvd1")
		chat_or_log("[CSR DEBUG] Forced Reservoir Dogs Day 1 (rvd1)")
	end

	MenuCallbackHandler.csr_debug_force_kenaz = function()
		local cs = managers and managers.crime_spree
		if not cs or not cs:is_active() then
			chat_or_log("[CSR DEBUG] Crime Spree not active - cannot force heist")
			return
		end
		local mission = cs:get_mission("kenaz")
		if not mission then
			chat_or_log("[CSR DEBUG] Mission 'kenaz' not found in tweak_data")
			return
		end
		if cs._global.available_missions then
			cs._global.available_missions[1] = mission
		end
		cs:select_mission("kenaz")
		chat_or_log("[CSR DEBUG] Forced Golden Grin Casino (kenaz)")
	end

	MenuCallbackHandler.csr_debug_force_roberts = function()
		local cs = managers and managers.crime_spree
		if not cs or not cs:is_active() then
			chat_or_log("[CSR DEBUG] Crime Spree not active - cannot force heist")
			return
		end
		local mission = cs:get_mission("roberts")
		if not mission then
			chat_or_log("[CSR DEBUG] Mission 'roberts' not found in tweak_data")
			return
		end
		if cs._global.available_missions then
			cs._global.available_missions[1] = mission
		end
		cs:select_mission("roberts")
		chat_or_log("[CSR DEBUG] Forced Go Bank (roberts)")
	end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_DebugMenuSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_debug_menu")
	MenuHelper:NewMenu("csr_debug_heists_menu")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_DebugMenuBuild", function(menu_manager, nodes)
	if not nodes.csr_options_menu then
		log("[CSR DEBUG] csr_options_menu not built - debug submenu skipped")
		return
	end
	nodes.csr_debug_menu = MenuHelper:BuildMenu("csr_debug_menu")
	nodes.csr_debug_heists_menu = MenuHelper:BuildMenu("csr_debug_heists_menu")

	-- Insert "--- DEBUG ---" divider directly after the Custom HUDs navigation entry.
	-- AddMenuItem positions items in _items (positional), not _items_list (priority-sorted),
	-- so the only way to place a divider between navigation entries is via create_item + table.insert.
	local huds_index
	for k, v in ipairs(nodes.csr_options_menu._items) do
		if v._parameters and v._parameters.name == "csr_custom_huds_menu" then
			huds_index = k
			break
		end
	end
	if huds_index then
		local sep = nodes.csr_options_menu:create_item(
			{ type = "MenuItemDivider", size = 8, no_text = false },
			{ name = "csr_debug_separator", text_id = "csr_debug_separator", localize = true, localize_help = true }
		)
		table.insert(nodes.csr_options_menu._items, huds_index + 1, sep)
	end

	MenuHelper:AddMenuItem(nodes.csr_options_menu, "csr_debug_menu", "csr_debug_menu_title", "csr_debug_menu_desc")
	MenuHelper:AddMenuItem(
		nodes.csr_options_menu,
		"csr_debug_heists_menu",
		"csr_debug_heists_menu_title",
		"csr_debug_heists_menu_desc"
	)

	-- Grant 50 Tokens — sits in the parent options menu directly under the
	-- [DEBUG] Heists submenu entry. Use menu:add_item (NOT a raw insert into
	-- _items) so PD2's MenuNode:add_item wires the menu's callback_handler to
	-- the item; without that, clicking does nothing (was masked on host by
	-- other paths during testing, but client click was completely dead).
	-- See coremenunode.lua:152.
	local btn = nodes.csr_options_menu:create_item({ type = "CoreMenuItem.Item" }, {
		name = "csr_debug_grant_tokens_options",
		text_id = "csr_debug_grant_tokens_title",
		help_id = "csr_debug_grant_tokens_desc",
		callback = "csr_debug_grant_tokens",
		localize = true,
		localize_help = true,
		disabled_color = Color(0.25, 1, 1, 1),
	})
	nodes.csr_options_menu:add_item(btn)
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_DebugMenuPopulate", function(menu_manager, nodes)
	local groups = { common = {}, uncommon = {}, rare = {}, contraband = {}, wildcard = {} }
	for _, def in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
		if groups[def.rarity] then
			table.insert(groups[def.rarity], def)
		end
	end

	for _, rarity in ipairs(RARITY_ORDER) do
		local base = RARITY_BASE_PRIORITY[rarity]
		local items = groups[rarity]
		if items and #items > 0 then
			MenuHelper:AddDivider({
				id = "csr_debug_hdr_" .. rarity,
				title = RARITY_HEADER_KEY[rarity],
				size = 16,
				no_text = false,
				menu_id = "csr_debug_menu",
				priority = base,
			})
			for i, def in ipairs(items) do
				MenuHelper:AddButton({
					id = button_id(def.type),
					title = loc_name_key(def.type),
					desc = "csr_debug_grant_desc",
					callback = callback_id(def.type),
					menu_id = "csr_debug_menu",
					priority = base - i,
				})
			end
		end
	end

	-- Layout test toggles. Priority below the lowest rarity (common = 140)
	-- so they sit at the bottom of the debug menu.
	MenuHelper:AddDivider({
		id = "csr_debug_hdr_layout",
		title = "csr_debug_header_layout",
		size = 16,
		no_text = false,
		menu_id = "csr_debug_menu",
		priority = 100,
	})
	MenuHelper:AddToggle({
		id = "csr_debug_fake_4_toggle",
		title = "csr_debug_fake_4_title",
		desc = "csr_debug_fake_4_desc",
		callback = "csr_debug_fake_4_toggle",
		value = _G.CSR_DEBUG_FAKE_4_PLAYERS == true,
		menu_id = "csr_debug_menu",
		priority = 99,
	})

	MenuHelper:AddButton({
		id = "csr_debug_force_born",
		title = "csr_debug_force_born_title",
		desc = "csr_debug_force_born_desc",
		callback = "csr_debug_force_born",
		menu_id = "csr_debug_heists_menu",
		priority = 100,
	})

	MenuHelper:AddButton({
		id = "csr_debug_force_rvd1",
		title = "csr_debug_force_rvd1_title",
		desc = "csr_debug_force_rvd1_desc",
		callback = "csr_debug_force_rvd1",
		menu_id = "csr_debug_heists_menu",
		priority = 100,
	})

	MenuHelper:AddButton({
		id = "csr_debug_force_kenaz",
		title = "csr_debug_force_kenaz_title",
		desc = "csr_debug_force_kenaz_desc",
		callback = "csr_debug_force_kenaz",
		menu_id = "csr_debug_heists_menu",
		priority = 100,
	})

	MenuHelper:AddButton({
		id = "csr_debug_force_roberts",
		title = "csr_debug_force_roberts_title",
		desc = "csr_debug_force_roberts_desc",
		callback = "csr_debug_force_roberts",
		menu_id = "csr_debug_heists_menu",
		priority = 100,
	})

	MenuHelper:AddButton({
		id = "csr_debug_instant_win",
		title = "csr_debug_instant_win_title",
		desc = "csr_debug_instant_win_desc",
		callback = "csr_debug_instant_win",
		menu_id = "csr_debug_heists_menu",
		priority = 99,
	})

	MenuHelper:AddButton({
		id = "csr_debug_force_catchup",
		title = "csr_debug_force_catchup_title",
		desc = "csr_debug_force_catchup_desc",
		callback = "csr_debug_force_catchup",
		menu_id = "csr_debug_heists_menu",
		priority = 98,
	})
end)
