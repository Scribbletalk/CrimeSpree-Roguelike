-- Crime Spree Roguelike — mod options menu (SuperBLT Mod Options).
--
-- The mod's settings surface. Adds a "Crime Spree Roguelike" entry under BLT's
-- Mod Options (nodes.blt_options) with the first setting: Debug Logging.
--
-- Storage is the manager, not a sidecar json: the toggle writes through
-- managers.csr:set_setting("debug_mode", ...) (persisted in csr_save.json, the
-- single U1 settings home) and reads its initial value from
-- managers.csr:setting("debug_mode"). The manager caches it as a boolean for
-- cheap hot-path gating (CSRGameManager:debug_enabled). Future settings add one
-- more AddToggle/AddSlider + one more callback here.
--
-- Standard SuperBLT MenuHelper lifecycle (verified in mods/base/req/core/
-- MenuHelper.lua + mods/base/lua/MenuManager.lua): Initialize -> register
-- callbacks; SetupCustomMenus -> NewMenu; BuildCustomMenus -> BuildMenu +
-- attach to blt_options; PopulateCustomMenus -> AddToggle.

-- Read a CSR setting for the menu display. managers.csr does NOT exist yet when
-- these menus are populated (populate runs during MenuManager:init, before the
-- Setup:init_managers PostHook that creates the manager), so prefer the live
-- instance but fall back to the static save reader -- otherwise every launch
-- shows defaults (Debug Logging OFF, etc.) regardless of the saved value.
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
			-- Slider is 0..100; store the 0..1 fraction sound.lua reads.
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

	MenuCallbackHandler.csr_options_back = function(self, item)
		-- No special teardown.
	end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_OptionsSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("options_menu")
	MenuHelper:NewMenu("debug_menu")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_OptionsBuild", function(menu_manager, nodes)
	nodes.csr_options_menu = MenuHelper:BuildMenu("options_menu", { back_callback = "options_back" })
	MenuHelper:AddMenuItem(nodes.blt_options, "options_menu", "options_menu_title", "options_menu_desc")

	-- Debug Tools sub-menu, nested under the CSR options menu.
	nodes.csr_debug_menu = MenuHelper:BuildMenu("debug_menu", { back_callback = "options_back" })
	MenuHelper:AddMenuItem(nodes.csr_options_menu, "debug_menu", "debug_menu_title", "debug_menu_desc")
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_OptionsPopulate", function(menu_manager, nodes)
	local debug_value = csr_read_setting("debug_mode", false) == true

	MenuHelper:AddToggle({
		id = "debug_mode",
		title = "debug_mode_title",
		desc = "debug_mode_desc",
		callback = "debug_mode_changed",
		value = debug_value,
		menu_id = "options_menu",
		priority = 1,
	})

	local sfx_value = csr_read_setting("sfx_volume", 1.0)
	MenuHelper:AddSlider({
		id = "sfx_volume",
		title = "sfx_volume_title",
		desc = "sfx_volume_desc",
		callback = "sfx_volume_changed",
		value = sfx_value * 100,
		min = 0,
		max = 100,
		step = 5,
		show_value = true,
		menu_id = "options_menu",
		priority = 2,
	})

	MenuHelper:AddButton({
		id = "grant_all_items",
		title = "grant_items_title",
		desc = "grant_items_desc",
		callback = "grant_all_items",
		menu_id = "debug_menu",
		priority = 2,
	})

	MenuHelper:AddButton({
		id = "grant_cup_of_joe",
		title = "grant_coj_title",
		desc = "grant_coj_desc",
		callback = "grant_cup_of_joe",
		menu_id = "debug_menu",
		priority = 1,
	})
end)
