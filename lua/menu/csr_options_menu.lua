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

Hooks:Add("LocalizationManagerPostInit", "CSR_OptionsLocalization", function(loc)
	loc:add_localized_strings({
		csr_options_menu_title = "Crime Spree Roguelike",
		csr_options_menu_desc = "Settings for the Crime Spree Roguelike mod.",
		csr_debug_mode_title = "Debug Logging",
		csr_debug_mode_desc = "Writes verbose CSR diagnostics to the BLT log (mods/logs). "
			.. "Use it to verify items are working. No gameplay effect.",
		csr_debug_menu_title = "Debug Tools",
		csr_debug_menu_desc = "Testing shortcuts for development.",
		csr_grant_items_title = "Grant All Items",
		csr_grant_items_desc = "Gives your character one of every item currently in the mod "
			.. "(bypasses the selection window). Click again to add another stack of each.",
	})
end)

Hooks:Add("MenuManagerInitialize", "CSR_OptionsCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_debug_mode_changed = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.set_setting then
			mgr:set_setting("debug_mode", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_grant_all_items = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.grant_all_items then
			mgr:grant_all_items()
		end
	end

	MenuCallbackHandler.csr_options_back = function(self, item)
		-- No special teardown.
	end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_OptionsSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_options_menu")
	MenuHelper:NewMenu("csr_debug_menu")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_OptionsBuild", function(menu_manager, nodes)
	nodes.csr_options_menu = MenuHelper:BuildMenu("csr_options_menu", { back_callback = "csr_options_back" })
	MenuHelper:AddMenuItem(nodes.blt_options, "csr_options_menu", "csr_options_menu_title", "csr_options_menu_desc")

	-- Debug Tools sub-menu, nested under the CSR options menu.
	nodes.csr_debug_menu = MenuHelper:BuildMenu("csr_debug_menu", { back_callback = "csr_options_back" })
	MenuHelper:AddMenuItem(nodes.csr_options_menu, "csr_debug_menu", "csr_debug_menu_title", "csr_debug_menu_desc")
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_OptionsPopulate", function(menu_manager, nodes)
	local mgr = managers.csr
	local debug_value = (mgr and mgr.setting and mgr:setting("debug_mode")) or false

	MenuHelper:AddToggle({
		id = "csr_debug_mode",
		title = "csr_debug_mode_title",
		desc = "csr_debug_mode_desc",
		callback = "csr_debug_mode_changed",
		value = debug_value,
		menu_id = "csr_options_menu",
		priority = 1,
	})

	MenuHelper:AddButton({
		id = "csr_grant_all_items",
		title = "csr_grant_items_title",
		desc = "csr_grant_items_desc",
		callback = "csr_grant_all_items",
		menu_id = "csr_debug_menu",
		priority = 1,
	})
end)
