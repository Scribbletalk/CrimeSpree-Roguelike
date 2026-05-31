-- CSR mod options (SuperBLT Mod Options). Adds "Crime Spree Roguelike" under
-- blt_options with Debug Logging, SFX volume, and a Debug Tools sub-menu.
-- Storage routes through managers.csr:set_setting (persisted in csr_save.json).

-- managers.csr doesn't exist yet when MenuManager:init populates these menus,
-- so fall back to the static peek_setting so first-launch shows saved values.
local function csr_read_setting(key, default)
	local mgr = managers and managers.csr
	local v
	if mgr and mgr.setting then
		v = mgr:setting(key)
	elseif CSRGameManager and CSRGameManager.peek_setting then
		v = CSRGameManager.peek_setting(key)
	end
	if v == nil then
		return default
	end
	return v
end

Hooks:Add("LocalizationManagerPostInit", "CSR_OptionsLocalization", function(loc)
	loc:add_localized_strings({
		csr_options_menu_title = "Crime Spree Roguelike",
		csr_options_menu_desc = "Settings for the Crime Spree Roguelike mod.",
		csr_debug_mode_title = "Debug Logging",
		csr_debug_mode_desc = "Writes verbose CSR diagnostics to the BLT log (mods/logs). "
			.. "Use it to verify items are working. No gameplay effect.",
		csr_sfx_volume_title = "Item Sound Effects Volume",
		csr_sfx_volume_desc = "Volume of CSR item sound effects (e.g. Bonnie's Lucky Chip proc). "
			.. "100% = full volume, 0% = muted.",
		csr_debug_menu_title = "Debug Tools",
		csr_debug_menu_desc = "Testing shortcuts for development.",
		csr_grant_items_title = "Grant All Items",
		csr_grant_items_desc = "Gives your character one of every item currently in the mod "
			.. "(bypasses the selection window). Click again to add another stack of each.",
		csr_grant_coj_title = "Grant Cup of Joe",
		csr_grant_coj_desc = "Gives one Cup of Joe (the per-item-file test item) to isolate its "
			.. "effect. Click again for another stack.",
		csr_force_fwb_title = "Force: First World Bank",
		csr_force_fwb_desc = "Sets your next heist to First World Bank (red2) so you can test it. "
			.. "Requires an active run: click this, then open the Crime Spree contract -- it will be the only "
			.. "card. Pick a difficulty and start as usual.",
		csr_add_tokens_title = "Add 100 Tokens",
		csr_add_tokens_desc = "Credits 100 Gage Tokens to your account. For testing the shop.",
	})
end)

Hooks:Add("MenuManagerInitialize", "CSR_OptionsCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_debug_mode_changed = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.set_setting then
			mgr:set_setting("debug_mode", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_sfx_volume_changed = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.set_setting then
			-- Slider 0..100 → store 0..1 fraction.
			mgr:set_setting("sfx_volume", item:value() / 100)
		end
	end

	MenuCallbackHandler.csr_grant_all_items = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.grant_all_items then
			mgr:grant_all_items()
		end
	end

	MenuCallbackHandler.csr_grant_cup_of_joe = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.add_item then
			mgr:add_item(mgr:local_peer_id(), "cup_of_joe")
		end
	end

	MenuCallbackHandler.csr_force_fwb = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.debug_force_mission then
			mgr:debug_force_mission("red2")
		end
	end

	MenuCallbackHandler.csr_add_tokens = function(self, item)
		CSR_Shop.credit(CSR_Shop.local_peer_id(), 100)
	end

	MenuCallbackHandler.csr_options_back = function(self, item) end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_OptionsSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_options_menu")
	MenuHelper:NewMenu("csr_debug_menu")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_OptionsBuild", function(menu_manager, nodes)
	nodes.csr_options_menu = MenuHelper:BuildMenu("csr_options_menu", { back_callback = "csr_options_back" })
	MenuHelper:AddMenuItem(nodes.blt_options, "csr_options_menu", "csr_options_menu_title", "csr_options_menu_desc")

	nodes.csr_debug_menu = MenuHelper:BuildMenu("csr_debug_menu", { back_callback = "csr_options_back" })
	MenuHelper:AddMenuItem(nodes.csr_options_menu, "csr_debug_menu", "csr_debug_menu_title", "csr_debug_menu_desc")
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_OptionsPopulate", function(menu_manager, nodes)
	local debug_value = csr_read_setting("debug_mode", false) == true

	MenuHelper:AddToggle({
		id = "debug_mode",
		title = "csr_debug_mode_title",
		desc = "csr_debug_mode_desc",
		callback = "csr_debug_mode_changed",
		value = debug_value,
		menu_id = "csr_options_menu",
		priority = 1,
	})

	local sfx_value = csr_read_setting("sfx_volume", 1.0)
	MenuHelper:AddSlider({
		id = "sfx_volume",
		title = "csr_sfx_volume_title",
		desc = "csr_sfx_volume_desc",
		callback = "csr_sfx_volume_changed",
		value = sfx_value * 100,
		min = 0,
		max = 100,
		step = 5,
		show_value = true,
		menu_id = "csr_options_menu",
		priority = 2,
	})

	MenuHelper:AddButton({
		id = "grant_all_items",
		title = "csr_grant_items_title",
		desc = "csr_grant_items_desc",
		callback = "csr_grant_all_items",
		menu_id = "csr_debug_menu",
		priority = 2,
	})

	MenuHelper:AddButton({
		id = "grant_cup_of_joe",
		title = "csr_grant_coj_title",
		desc = "csr_grant_coj_desc",
		callback = "csr_grant_cup_of_joe",
		menu_id = "csr_debug_menu",
		priority = 1,
	})

	MenuHelper:AddButton({
		id = "force_fwb",
		title = "csr_force_fwb_title",
		desc = "csr_force_fwb_desc",
		callback = "csr_force_fwb",
		menu_id = "csr_debug_menu",
		priority = 3,
	})

	MenuHelper:AddButton({
		id = "add_tokens",
		title = "csr_add_tokens_title",
		desc = "csr_add_tokens_desc",
		callback = "csr_add_tokens",
		menu_id = "csr_debug_menu",
		priority = 4,
	})
end)
