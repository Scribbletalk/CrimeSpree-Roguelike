-- Crime Spree Roguelike - Options Menu using MenuHelper

local CSR_OPT_EN = {
	csr_menu_title = "Crime Spree Roguelike",
	csr_menu_desc = "Settings for Crime Spree Roguelike mod",
	csr_language_title = "Language",
	csr_language_desc = "Requires game restart to apply.",
	csr_skip_blackscreen_title = "Skip Intro Blackscreen",
	csr_skip_blackscreen_desc = "Automatically skip the heist intro briefing (black screen with dialogue). Host only.",
	csr_block_item_healing_title = "Block Item Healing (Berserker)",
	csr_block_item_healing_desc = "Disables healing from Worn Band-Aid and Pink Slip. Use this if you run a Berserker/Frenzy build.",
	csr_lobby_filter_title = "CSR-Only Lobby Filter",
	csr_lobby_filter_desc = "Hides non-CSR Crime Spree lobbies in Crime.Net and auto-kicks players without the mod. Enable if you only want to play with other CSR players.",
	csr_item_settings_title = "Items Settings",
	csr_item_settings_desc = "Per-item sound volume and other item-specific options.",
	csr_bonnie_chip_sound_title = "Bonnie's Lucky Chip: Activation Volume",
	csr_bonnie_chip_sound_desc = "",
	csr_plush_shark_sound_title = "Plush Shark: Activation Volume",
	csr_plush_shark_sound_desc = "",
	csr_the_edge_sound_title = "The Edge: Activation Volume",
	csr_the_edge_sound_desc = "",
	csr_debug_mode_title = "Verbose Logging",
	csr_debug_mode_desc = "Enables verbose logging to the BLT log file.",
	csr_heist_settings_title = "Heist Specific Settings",
	csr_heist_settings_desc = "Toggle heist-specific tweaks that improve Crime Spree gameplay.",
	csr_heist_diamond_bile_title = "The Diamond: Bile Stays",
	csr_heist_diamond_bile_desc = "Prevents Bile's helicopter from leaving after collecting 4 bags. Host only.",
	csr_custom_huds_title = "Custom HUDs",
	csr_custom_huds_desc = "Compatibility options for custom HUD mods.",
	csr_vhudplus_settings_title = "VanillaHUD Plus Cooldowns",
	csr_vhudplus_settings_desc = "Toggle cooldown timers for each item on the VanillaHUD Plus buff bar. Requires VanillaHUD Plus.",
	csr_vhudplus_the_edge_title = "The Edge",
	csr_vhudplus_the_edge_desc = "Show cooldown and invulnerability timers for The Edge.",
	csr_vhudplus_overkill_rush_title = "Overkill Rush",
	csr_vhudplus_overkill_rush_desc = "Show kill streak timer and stacks for Overkill Rush.",
	csr_vhudplus_bonnie_chip_title = "Bonnie's Lucky Chip",
	csr_vhudplus_bonnie_chip_desc = "Show cooldown timer for Bonnie's Chip (fires on every hit attempt).",
	csr_vhudplus_plush_shark_title = "Plush Shark",
	csr_vhudplus_plush_shark_desc = "Show invulnerability duration for Plush Shark.",
	csr_vhudplus_dmt_title = "Dead Man's Trigger",
	csr_vhudplus_dmt_desc = "Show cooldown timer for Dead Man's Trigger explosion.",
	csr_vhudplus_bandaid_title = "Worn Band-Aid",
	csr_vhudplus_bandaid_desc = "Show regen cycle timer for Worn Band-Aid.",
	csr_wfhud_settings_title = "Warframe HUD Cooldowns",
	csr_wfhud_settings_desc = "Toggle cooldown timers for each item on the Warframe HUD buff bar. Requires Warframe HUD.",
	csr_wfhud_the_edge_title = "The Edge",
	csr_wfhud_the_edge_desc = "Show cooldown and invulnerability timers for The Edge.",
	csr_wfhud_overkill_rush_title = "Overkill Rush",
	csr_wfhud_overkill_rush_desc = "Show kill streak timer and bonus percentage for Overkill Rush.",
	csr_wfhud_bonnie_chip_title = "Bonnie's Lucky Chip",
	csr_wfhud_bonnie_chip_desc = "Show cooldown timer for Bonnie's Chip (fires on every hit attempt).",
	csr_wfhud_plush_shark_title = "Plush Shark",
	csr_wfhud_plush_shark_desc = "Show invulnerability duration for Plush Shark.",
	csr_wfhud_dmt_title = "Dead Man's Trigger",
	csr_wfhud_dmt_desc = "Show cooldown timer for Dead Man's Trigger explosion.",
	csr_wfhud_bandaid_title = "Worn Band-Aid",
	csr_wfhud_bandaid_desc = "Show regen cycle timer for Worn Band-Aid.",
	csr_pocohud_settings_title = "PocoHud3 Cooldowns",
	csr_pocohud_settings_desc = "Toggle cooldown timers for each item on the PocoHud3 buff bar. Requires PocoHud3.",
	csr_pocohud_the_edge_title = "The Edge",
	csr_pocohud_the_edge_desc = "Show cooldown and invulnerability timers for The Edge.",
	csr_pocohud_overkill_rush_title = "Overkill Rush",
	csr_pocohud_overkill_rush_desc = "Show kill streak timer and bonus percentage for Overkill Rush.",
	csr_pocohud_bonnie_chip_title = "Bonnie's Lucky Chip",
	csr_pocohud_bonnie_chip_desc = "Show cooldown timer for Bonnie's Chip (fires on every hit attempt).",
	csr_pocohud_plush_shark_title = "Plush Shark",
	csr_pocohud_plush_shark_desc = "Show invulnerability duration for Plush Shark.",
	csr_pocohud_dmt_title = "Dead Man's Trigger",
	csr_pocohud_dmt_desc = "Show cooldown timer for Dead Man's Trigger explosion.",
	csr_pocohud_bandaid_title = "Worn Band-Aid",
	csr_pocohud_bandaid_desc = "Show regen cycle timer for Worn Band-Aid.",
}

local CSR_OPT_RU = {
	csr_menu_title = "Crime Spree Roguelike",
	csr_menu_desc = "Настройки мода Crime Spree Roguelike",
	csr_language_title = "Язык",
	csr_language_desc = "Требует перезапуска игры.",
	csr_skip_blackscreen_title = "Пропустить вступительный экран",
	csr_skip_blackscreen_desc = "Автоматически пропускает черный экран со вступительным диалогом задания. Только для хоста.",
	csr_block_item_healing_title = "Блокировать лечение от предметов (Берсерк)",
	csr_block_item_healing_desc = "Отключает лечение от Потрепанного пластыря и Розовой квитанции. Используйте с билдом Берсерка или Ярости.",
	csr_lobby_filter_title = "Фильтр лобби только с CSR модом",
	csr_lobby_filter_desc = "Скрывает лобби Crime Spree без мода и авто-киком выкидывает игроков без CSR. Включите для игры только с игроками CSR.",
	csr_item_settings_title = "Настройки предметов",
	csr_item_settings_desc = "Громкость звуков и прочие настройки предметов.",
	csr_bonnie_chip_sound_title = "Фишка Бонни: громкость активации",
	csr_bonnie_chip_sound_desc = "",
	csr_plush_shark_sound_title = "Плюшевая акула: громкость активации",
	csr_plush_shark_sound_desc = "",
	csr_the_edge_sound_title = "На грани: громкость активации",
	csr_the_edge_sound_desc = "",
	csr_debug_mode_title = "Подробное логирование",
	csr_debug_mode_desc = "Включает подробное логирование в файл BLT.",
	csr_heist_settings_title = "Настройки заданий",
	csr_heist_settings_desc = "Параметры, улучшающие геймплей Crime Spree на конкретных заданиях.",
	csr_heist_diamond_bile_title = "Бриллиант: Байл остается",
	csr_heist_diamond_bile_desc = "Предотвращает отлет вертолета Байла после сбора 4 сумок. Только для хоста.",
	csr_custom_huds_title = "Сторонние HUD",
	csr_custom_huds_desc = "Настройки совместимости со сторонними HUD.",
	csr_vhudplus_settings_title = "VanillaHUD Plus: таймеры перезарядки",
	csr_vhudplus_settings_desc = "Таймеры перезарядки для каждого предмета. Требуется VanillaHUD Plus.",
	csr_vhudplus_the_edge_title = "На грани",
	csr_vhudplus_the_edge_desc = "Показывать таймеры перезарядки и неуязвимости.",
	csr_vhudplus_overkill_rush_title = "Безжалостный напор",
	csr_vhudplus_overkill_rush_desc = "Показывать таймер серии убийств и бонус.",
	csr_vhudplus_bonnie_chip_title = "Фишка Бонни",
	csr_vhudplus_bonnie_chip_desc = "Показывать таймер перезарядки.",
	csr_vhudplus_plush_shark_title = "Плюшевая акула",
	csr_vhudplus_plush_shark_desc = "Показывать длительность неуязвимости.",
	csr_vhudplus_dmt_title = "Предсмертный курок",
	csr_vhudplus_dmt_desc = "Показывать таймер перезарядки взрыва.",
	csr_vhudplus_bandaid_title = "Потрепанный пластырь",
	csr_vhudplus_bandaid_desc = "Показывать таймер регенерации.",
	csr_wfhud_settings_title = "Warframe HUD: таймеры перезарядки",
	csr_wfhud_settings_desc = "Таймеры перезарядки для каждого предмета. Требуется Warframe HUD.",
	csr_wfhud_the_edge_title = "На грани",
	csr_wfhud_the_edge_desc = "Показывать таймеры перезарядки и неуязвимости.",
	csr_wfhud_overkill_rush_title = "Безжалостный напор",
	csr_wfhud_overkill_rush_desc = "Показывать таймер серии убийств и бонус.",
	csr_wfhud_bonnie_chip_title = "Фишка Бонни",
	csr_wfhud_bonnie_chip_desc = "Показывать таймер перезарядки.",
	csr_wfhud_plush_shark_title = "Плюшевая акула",
	csr_wfhud_plush_shark_desc = "Показывать длительность неуязвимости.",
	csr_wfhud_dmt_title = "Предсмертный курок",
	csr_wfhud_dmt_desc = "Показывать таймер перезарядки взрыва.",
	csr_wfhud_bandaid_title = "Потрепанный пластырь",
	csr_wfhud_bandaid_desc = "Показывать таймер регенерации.",
	csr_pocohud_settings_title = "PocoHud3: таймеры перезарядки",
	csr_pocohud_settings_desc = "Таймеры перезарядки для каждого предмета. Требуется PocoHud3.",
	csr_pocohud_the_edge_title = "На грани",
	csr_pocohud_the_edge_desc = "Показывать таймеры перезарядки и неуязвимости.",
	csr_pocohud_overkill_rush_title = "Безжалостный напор",
	csr_pocohud_overkill_rush_desc = "Показывать таймер серии убийств и бонус.",
	csr_pocohud_bonnie_chip_title = "Фишка Бонни",
	csr_pocohud_bonnie_chip_desc = "Показывать таймер перезарядки.",
	csr_pocohud_plush_shark_title = "Плюшевая акула",
	csr_pocohud_plush_shark_desc = "Показывать длительность неуязвимости.",
	csr_pocohud_dmt_title = "Предсмертный курок",
	csr_pocohud_dmt_desc = "Показывать таймер перезарядки взрыва.",
	csr_pocohud_bandaid_title = "Потрепанный пластырь",
	csr_pocohud_bandaid_desc = "Показывать таймер регенерации.",
}

-- Menu localization
Hooks:Add("LocalizationManagerPostInit", "CSR_OptionsLocalization", function(loc)
	local lang = CSR_Settings and CSR_Settings.values.language or "en"
	loc:add_localized_strings(lang == "ru" and CSR_OPT_RU or CSR_OPT_EN)
end)

-- Callbacks
Hooks:Add("MenuManagerInitialize", "CSR_MenuCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_skip_blackscreen_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("skip_blackscreen", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_block_item_healing_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("block_item_healing", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_lobby_filter_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("lobby_filter", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_bonnie_chip_sound_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("bonnie_chip_sound_volume", item:value())
		end
	end

	MenuCallbackHandler.csr_plush_shark_sound_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("plush_shark_sound_volume", item:value())
		end
	end

	MenuCallbackHandler.csr_the_edge_sound_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("the_edge_sound_volume", item:value())
		end
	end

	MenuCallbackHandler.csr_heist_diamond_bile_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("heist_diamond_bile_stay", item:value() == "on")
		end
	end

	MenuCallbackHandler.csr_debug_mode_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("debug_mode", item:value() == "on")
		end
	end

	-- VanillaHUD Plus per-item toggles
	local vhudplus_keys =
		{ "the_edge", "overkill_rush", "bonnie_chip", "plush_shark", "dead_mans_trigger", "worn_bandaid" }
	for _, key in ipairs(vhudplus_keys) do
		MenuCallbackHandler["csr_vhudplus_" .. key .. "_changed"] = function(self, item)
			if CSR_Settings then
				CSR_Settings:SetValue("vhudplus_" .. key, item:value() == "on")
			end
		end
	end

	-- Warframe HUD per-item toggles
	local wfhud_keys =
		{ "the_edge", "overkill_rush", "bonnie_chip", "plush_shark", "dead_mans_trigger", "worn_bandaid" }
	for _, key in ipairs(wfhud_keys) do
		MenuCallbackHandler["csr_wfhud_" .. key .. "_changed"] = function(self, item)
			if CSR_Settings then
				CSR_Settings:SetValue("wfhud_" .. key, item:value() == "on")
			end
		end
	end

	-- PocoHud3 per-item toggles
	local pocohud_keys =
		{ "the_edge", "overkill_rush", "bonnie_chip", "plush_shark", "dead_mans_trigger", "worn_bandaid" }
	for _, key in ipairs(pocohud_keys) do
		MenuCallbackHandler["csr_pocohud_" .. key .. "_changed"] = function(self, item)
			if CSR_Settings then
				CSR_Settings:SetValue("pocohud_" .. key, item:value() == "on")
			end
		end
	end

	MenuCallbackHandler.csr_language_changed = function(self, item)
		if CSR_Settings then
			CSR_Settings:SetValue("language", item:value())
		end
	end

	MenuCallbackHandler.csr_menu_back = function(self, item)
		-- Nothing special on back
	end
end)

-- Create menus
Hooks:Add("MenuManagerSetupCustomMenus", "CSR_SetupMenus", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_options_menu")
	MenuHelper:NewMenu("csr_item_settings_menu")
	MenuHelper:NewMenu("csr_heist_settings_menu")
	MenuHelper:NewMenu("csr_custom_huds_menu")
	MenuHelper:NewMenu("csr_vhudplus_settings_menu")
	MenuHelper:NewMenu("csr_wfhud_settings_menu")
	MenuHelper:NewMenu("csr_pocohud_settings_menu")
end)

-- Build menus
Hooks:Add("MenuManagerBuildCustomMenus", "CSR_BuildMenus", function(menu_manager, nodes)
	-- Main CSR options menu
	nodes.csr_options_menu = MenuHelper:BuildMenu("csr_options_menu", { back_callback = "csr_menu_back" })
	MenuHelper:AddMenuItem(nodes.blt_options, "csr_options_menu", "csr_menu_title", "csr_menu_desc")

	-- Item Settings sub-menu (inside CSR options)
	nodes.csr_item_settings_menu = MenuHelper:BuildMenu("csr_item_settings_menu")
	MenuHelper:AddMenuItem(
		nodes.csr_options_menu,
		"csr_item_settings_menu",
		"csr_item_settings_title",
		"csr_item_settings_desc"
	)

	-- Heist Specific Settings sub-menu (inside CSR options)
	nodes.csr_heist_settings_menu = MenuHelper:BuildMenu("csr_heist_settings_menu")
	MenuHelper:AddMenuItem(
		nodes.csr_options_menu,
		"csr_heist_settings_menu",
		"csr_heist_settings_title",
		"csr_heist_settings_desc"
	)

	-- Custom HUDs sub-menu (inside CSR options)
	nodes.csr_custom_huds_menu = MenuHelper:BuildMenu("csr_custom_huds_menu")
	MenuHelper:AddMenuItem(
		nodes.csr_options_menu,
		"csr_custom_huds_menu",
		"csr_custom_huds_title",
		"csr_custom_huds_desc"
	)

	-- VanillaHUD Plus Settings sub-menu (inside Custom HUDs)
	nodes.csr_vhudplus_settings_menu = MenuHelper:BuildMenu("csr_vhudplus_settings_menu")
	MenuHelper:AddMenuItem(
		nodes.csr_custom_huds_menu,
		"csr_vhudplus_settings_menu",
		"csr_vhudplus_settings_title",
		"csr_vhudplus_settings_desc"
	)

	-- Warframe HUD Settings sub-menu (inside Custom HUDs)
	nodes.csr_wfhud_settings_menu = MenuHelper:BuildMenu("csr_wfhud_settings_menu")
	MenuHelper:AddMenuItem(
		nodes.csr_custom_huds_menu,
		"csr_wfhud_settings_menu",
		"csr_wfhud_settings_title",
		"csr_wfhud_settings_desc"
	)

	-- PocoHud3 Settings sub-menu (inside Custom HUDs)
	nodes.csr_pocohud_settings_menu = MenuHelper:BuildMenu("csr_pocohud_settings_menu")
	MenuHelper:AddMenuItem(
		nodes.csr_custom_huds_menu,
		"csr_pocohud_settings_menu",
		"csr_pocohud_settings_title",
		"csr_pocohud_settings_desc"
	)
end)

-- Populate menus
Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_PopulateMenus", function(menu_manager, nodes)
	local skip_blackscreen_value = CSR_Settings and CSR_Settings:IsSkipBlackscreen() or false

	-- Language selector
	local current_lang = CSR_Settings and CSR_Settings.values.language or "en"
	MenuHelper:AddMultipleChoice({
		id = "csr_language",
		title = "csr_language_title",
		desc = "csr_language_desc",
		callback = "csr_language_changed",
		value = current_lang,
		items = { "English", "\208\160\209\131\209\129\209\129\208\186\208\184\208\185" },
		item_values = { "en", "ru" },
		localized_items = false,
		menu_id = "csr_options_menu",
		priority = 4,
	})

	-- Lobby Filter toggle
	local lobby_filter_value = CSR_Settings and CSR_Settings.values.lobby_filter or false
	MenuHelper:AddToggle({
		id = "csr_lobby_filter",
		title = "csr_lobby_filter_title",
		desc = "csr_lobby_filter_desc",
		callback = "csr_lobby_filter_changed",
		value = lobby_filter_value,
		menu_id = "csr_options_menu",
		priority = 3,
	})

	-- Skip Blackscreen toggle
	MenuHelper:AddToggle({
		id = "csr_skip_blackscreen",
		title = "csr_skip_blackscreen_title",
		desc = "csr_skip_blackscreen_desc",
		callback = "csr_skip_blackscreen_changed",
		value = skip_blackscreen_value,
		menu_id = "csr_options_menu",
		priority = 2,
	})

	-- Block Item Healing toggle (in Item Settings)
	local block_healing_value = CSR_Settings and CSR_Settings.values.block_item_healing or false
	MenuHelper:AddToggle({
		id = "csr_block_item_healing",
		title = "csr_block_item_healing_title",
		desc = "csr_block_item_healing_desc",
		callback = "csr_block_item_healing_changed",
		value = block_healing_value,
		menu_id = "csr_item_settings_menu",
		priority = 3,
	})

	-- Verbose Logging toggle (bottom of menu)
	local debug_mode_value = CSR_Settings and CSR_Settings.values.debug_mode or false
	MenuHelper:AddToggle({
		id = "csr_debug_mode",
		title = "csr_debug_mode_title",
		desc = "csr_debug_mode_desc",
		callback = "csr_debug_mode_changed",
		value = debug_mode_value,
		menu_id = "csr_options_menu",
		priority = -1,
	})

	-- === Item Settings (sub-menu items) ===
	local bonnie_vol = CSR_Settings and CSR_Settings.values.bonnie_chip_sound_volume or 1.0
	MenuHelper:AddSlider({
		id = "csr_bonnie_chip_sound",
		title = "csr_bonnie_chip_sound_title",
		desc = "csr_bonnie_chip_sound_desc",
		callback = "csr_bonnie_chip_sound_changed",
		value = bonnie_vol,
		min = 0.0,
		max = 1.0,
		step = 0.05,
		show_value = true,
		is_percentage = true,
		display_scale = 100,
		display_precision = 0,
		menu_id = "csr_item_settings_menu",
		priority = 2,
	})

	local plush_vol = CSR_Settings and CSR_Settings.values.plush_shark_sound_volume or 1.0
	MenuHelper:AddSlider({
		id = "csr_plush_shark_sound",
		title = "csr_plush_shark_sound_title",
		desc = "csr_plush_shark_sound_desc",
		callback = "csr_plush_shark_sound_changed",
		value = plush_vol,
		min = 0.0,
		max = 1.0,
		step = 0.05,
		show_value = true,
		is_percentage = true,
		display_scale = 100,
		display_precision = 0,
		menu_id = "csr_item_settings_menu",
		priority = 1,
	})

	local the_edge_vol = CSR_Settings and CSR_Settings.values.the_edge_sound_volume or 1.0
	MenuHelper:AddSlider({
		id = "csr_the_edge_sound",
		title = "csr_the_edge_sound_title",
		desc = "csr_the_edge_sound_desc",
		callback = "csr_the_edge_sound_changed",
		value = the_edge_vol,
		min = 0.0,
		max = 1.0,
		step = 0.05,
		show_value = true,
		is_percentage = true,
		display_scale = 100,
		display_precision = 0,
		menu_id = "csr_item_settings_menu",
		priority = 0,
	})

	-- === VanillaHUD Plus Cooldown Toggles (sub-menu items) ===
	local vhudplus_items = {
		{
			key = "the_edge",
			title = "csr_vhudplus_the_edge_title",
			desc = "csr_vhudplus_the_edge_desc",
			priority = 6,
		},
		{
			key = "overkill_rush",
			title = "csr_vhudplus_overkill_rush_title",
			desc = "csr_vhudplus_overkill_rush_desc",
			priority = 5,
		},
		{
			key = "bonnie_chip",
			title = "csr_vhudplus_bonnie_chip_title",
			desc = "csr_vhudplus_bonnie_chip_desc",
			priority = 4,
		},
		{
			key = "plush_shark",
			title = "csr_vhudplus_plush_shark_title",
			desc = "csr_vhudplus_plush_shark_desc",
			priority = 3,
		},
		{
			key = "dead_mans_trigger",
			title = "csr_vhudplus_dmt_title",
			desc = "csr_vhudplus_dmt_desc",
			priority = 2,
		},
		{
			key = "worn_bandaid",
			title = "csr_vhudplus_bandaid_title",
			desc = "csr_vhudplus_bandaid_desc",
			priority = 1,
		},
	}
	for _, item in ipairs(vhudplus_items) do
		local val = CSR_Settings and CSR_Settings.values["vhudplus_" .. item.key]
		if val == nil then
			val = true
		end
		MenuHelper:AddToggle({
			id = "csr_vhudplus_" .. item.key,
			title = item.title,
			desc = item.desc,
			callback = "csr_vhudplus_" .. item.key .. "_changed",
			value = val,
			menu_id = "csr_vhudplus_settings_menu",
			priority = item.priority,
		})
	end

	-- === Warframe HUD Cooldown Toggles (sub-menu items) ===
	local wfhud_items = {
		{
			key = "the_edge",
			title = "csr_wfhud_the_edge_title",
			desc = "csr_wfhud_the_edge_desc",
			priority = 6,
		},
		{
			key = "overkill_rush",
			title = "csr_wfhud_overkill_rush_title",
			desc = "csr_wfhud_overkill_rush_desc",
			priority = 5,
		},
		{
			key = "bonnie_chip",
			title = "csr_wfhud_bonnie_chip_title",
			desc = "csr_wfhud_bonnie_chip_desc",
			priority = 4,
		},
		{
			key = "plush_shark",
			title = "csr_wfhud_plush_shark_title",
			desc = "csr_wfhud_plush_shark_desc",
			priority = 3,
		},
		{
			key = "dead_mans_trigger",
			title = "csr_wfhud_dmt_title",
			desc = "csr_wfhud_dmt_desc",
			priority = 2,
		},
		{
			key = "worn_bandaid",
			title = "csr_wfhud_bandaid_title",
			desc = "csr_wfhud_bandaid_desc",
			priority = 1,
		},
	}
	for _, item in ipairs(wfhud_items) do
		local val = CSR_Settings and CSR_Settings.values["wfhud_" .. item.key]
		if val == nil then
			val = true
		end
		MenuHelper:AddToggle({
			id = "csr_wfhud_" .. item.key,
			title = item.title,
			desc = item.desc,
			callback = "csr_wfhud_" .. item.key .. "_changed",
			value = val,
			menu_id = "csr_wfhud_settings_menu",
			priority = item.priority,
		})
	end

	-- === PocoHud3 Cooldown Toggles (sub-menu items) ===
	local pocohud_items = {
		{
			key = "the_edge",
			title = "csr_pocohud_the_edge_title",
			desc = "csr_pocohud_the_edge_desc",
			priority = 6,
		},
		{
			key = "overkill_rush",
			title = "csr_pocohud_overkill_rush_title",
			desc = "csr_pocohud_overkill_rush_desc",
			priority = 5,
		},
		{
			key = "bonnie_chip",
			title = "csr_pocohud_bonnie_chip_title",
			desc = "csr_pocohud_bonnie_chip_desc",
			priority = 4,
		},
		{
			key = "plush_shark",
			title = "csr_pocohud_plush_shark_title",
			desc = "csr_pocohud_plush_shark_desc",
			priority = 3,
		},
		{
			key = "dead_mans_trigger",
			title = "csr_pocohud_dmt_title",
			desc = "csr_pocohud_dmt_desc",
			priority = 2,
		},
		{
			key = "worn_bandaid",
			title = "csr_pocohud_bandaid_title",
			desc = "csr_pocohud_bandaid_desc",
			priority = 1,
		},
	}
	for _, item in ipairs(pocohud_items) do
		local val = CSR_Settings and CSR_Settings.values["pocohud_" .. item.key]
		if val == nil then
			val = true
		end
		MenuHelper:AddToggle({
			id = "csr_pocohud_" .. item.key,
			title = item.title,
			desc = item.desc,
			callback = "csr_pocohud_" .. item.key .. "_changed",
			value = val,
			menu_id = "csr_pocohud_settings_menu",
			priority = item.priority,
		})
	end

	-- === Heist Specific Settings (sub-menu items) ===
	local bile_stay_value = CSR_Settings and CSR_Settings.values.heist_diamond_bile_stay
	if bile_stay_value == nil then
		bile_stay_value = true
	end
	MenuHelper:AddToggle({
		id = "csr_heist_diamond_bile",
		title = "csr_heist_diamond_bile_title",
		desc = "csr_heist_diamond_bile_desc",
		callback = "csr_heist_diamond_bile_changed",
		value = bile_stay_value,
		menu_id = "csr_heist_settings_menu",
		priority = 1,
	})
end)

-- DEV ONLY: Load debug menu if present. The entire lua/debug/ folder is excluded
-- from release ZIPs (see EXCLUDE_DIRS in release/_build_*.py), so this is a no-op
-- for end users. Loaded AFTER the options hooks register so the debug menu's
-- BuildCustomMenus fires after nodes.csr_options_menu is built.
do
	local debug_path = ModPath .. "lua/debug/debug_menu.lua"
	local f = io.open(debug_path, "r")
	if f then
		f:close()
		dofile(debug_path)
	end
end
