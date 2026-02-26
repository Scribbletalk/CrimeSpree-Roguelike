-- Crime Spree Roguelike - Options Menu using MenuHelper

-- Menu localization
Hooks:Add("LocalizationManagerPostInit", "CSR_OptionsLocalization", function(loc)
	local strings = {
		-- Menu
		csr_menu_title = "Crime Spree Roguelike",
		csr_menu_desc = "Settings for Crime Spree Roguelike mod",

		-- Language
		csr_language_title = "Language",
		csr_language_desc = "Select language for item names and descriptions. Requires game restart.",
		csr_language_en = "English",
		csr_language_ru = "Russian",

		-- Skip Blackscreen
		csr_skip_blackscreen_title = "Skip Intro Blackscreen",
		csr_skip_blackscreen_desc = "Automatically skip the heist intro briefing (black screen with dialogue). Host only."
	}

	loc:add_localized_strings(strings)

	-- Russian localization if system is Russian
	if Idstring("russian"):key() == SystemInfo:language():key() then
		loc:add_localized_strings({
			csr_menu_title = "Crime Spree Roguelike",
			csr_menu_desc = "Настройки мода Crime Spree Roguelike",
			csr_language_title = "Язык",
			csr_language_desc = "Выберите язык для названий и описаний предметов. Требуется перезапуск игры.",
			csr_language_en = "English",
			csr_language_ru = "Русский",
			csr_skip_blackscreen_title = "Пропуск интро",
			csr_skip_blackscreen_desc = "Автоматически пропускать брифинг перед ограблением (чёрный экран с диалогом). Только для хоста."
		})
	end
end)

-- Callbacks
Hooks:Add("MenuManagerInitialize", "CSR_MenuCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_language_changed = function(self, item)
		local value = tonumber(item:value())
		if CSR_Settings then
			CSR_Settings:SetValue("language", value == 2 and "ru" or "en")
		end
	end

	MenuCallbackHandler.csr_skip_blackscreen_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("skip_blackscreen", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_menu_back = function(self, item)
		-- Nothing special on back
	end
end)

-- Create menu
Hooks:Add("MenuManagerSetupCustomMenus", "CSR_SetupMenus", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_options_menu")
end)

-- Build menu
Hooks:Add("MenuManagerBuildCustomMenus", "CSR_BuildMenus", function(menu_manager, nodes)
	nodes.csr_options_menu = MenuHelper:BuildMenu("csr_options_menu", {back_callback = "csr_menu_back"})
	MenuHelper:AddMenuItem(nodes.blt_options, "csr_options_menu", "csr_menu_title", "csr_menu_desc")
end)

-- Populate menu
Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_PopulateMenus", function(menu_manager, nodes)
	local lang_value = 1
	local skip_blackscreen_value = false

	if CSR_Settings then
		lang_value = CSR_Settings:GetLanguage() == "ru" and 2 or 1
		skip_blackscreen_value = CSR_Settings:IsSkipBlackscreen()
	end

	-- Language selector
	MenuHelper:AddMultipleChoice({
		id = "csr_language",
		title = "csr_language_title",
		desc = "csr_language_desc",
		callback = "csr_language_changed",
		items = {"csr_language_en", "csr_language_ru"},
		value = lang_value,
		menu_id = "csr_options_menu",
		priority = 2
	})

	-- Skip Blackscreen toggle
	MenuHelper:AddToggle({
		id = "csr_skip_blackscreen",
		title = "csr_skip_blackscreen_title",
		desc = "csr_skip_blackscreen_desc",
		callback = "csr_skip_blackscreen_changed",
		value = skip_blackscreen_value,
		menu_id = "csr_options_menu",
		priority = 1
	})

end)
