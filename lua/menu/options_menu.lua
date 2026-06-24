-- SuperBLT mod options page. Adds CSR under blt_options; storage via managers.csr:set_setting.
-- Debug Tools sub-menu is in lua/debug/debug_menu.lua (strip before release).

-- managers.csr isn't ready when MenuManager:init runs; fall back to peek_setting for first-launch.
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
	})
end)

Hooks:Add("MenuManagerInitialize", "CSR_OptionsCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_debug_mode_changed = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.set_setting then
			mgr:set_setting("debug_mode", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_options_back = function(self, item) end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_OptionsSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_options_menu")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_OptionsBuild", function(menu_manager, nodes)
	nodes.csr_options_menu = MenuHelper:BuildMenu("csr_options_menu", { back_callback = "csr_options_back" })
	MenuHelper:AddMenuItem(nodes.blt_options, "csr_options_menu", "csr_options_menu_title", "csr_options_menu_desc")
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_OptionsPopulate", function(menu_manager, nodes)
	MenuHelper:AddToggle({
		id = "debug_mode",
		title = "csr_debug_mode_title",
		desc = "csr_debug_mode_desc",
		callback = "csr_debug_mode_changed",
		value = csr_read_setting("debug_mode", false) == true,
		menu_id = "csr_options_menu",
		priority = 1,
	})
end)
