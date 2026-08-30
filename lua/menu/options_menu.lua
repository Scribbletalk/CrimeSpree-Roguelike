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

-- The language entry, kept so a switch made in the CSR Preferences panel can resync it. Rebuilt
-- on every populate pass, which is also when the listener below is (re)registered.
local csr_language_item

Hooks:Add("MenuManagerInitialize", "CSR_OptionsCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_language_changed = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.set_setting then
			mgr:set_setting("language", item:value())
		end
		if _G.CSR_Loc then
			_G.CSR_Loc.apply()
		end
		-- This node localized its text when it was rendered; re-render it in the new language.
		if MenuCallbackHandler.refresh_node then
			MenuCallbackHandler:refresh_node(item)
		end
	end

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
	-- Same list the CSR Preferences row cycles, so a new language shows up in both from one place.
	local languages = _G.CSR_Loc and _G.CSR_Loc.LANGUAGES
	if languages then
		local items, values = {}, {}
		for i, lang in ipairs(languages) do
			items[i] = lang.text_key
			values[i] = lang.id
		end
		csr_language_item = MenuHelper:AddMultipleChoice({
			id = "language",
			title = "csr_pref_language_label",
			callback = "csr_language_changed",
			items = items,
			item_values = values,
			localized = true,
			localized_items = true,
			value = csr_read_setting("language", "auto"),
			menu_id = "csr_options_menu",
			priority = 10,
		})
		if not _G.CSR_Loc._options_listener then
			_G.CSR_Loc._options_listener = true
			_G.CSR_Loc.add_listener(function(_, selected)
				if csr_language_item then
					csr_language_item:set_value(selected)
				end
			end)
		end
	end

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
