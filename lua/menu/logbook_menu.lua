-- Crime Spree Roguelike - Logbook Menu Component
-- Interactive item catalogue with icons, statistics, and achievement tabs

if not RequiredScript then
	return
end



-- Item data table, sorted by rarity
local ITEMS_DATA = {
	-- COMMON
	{
		id = "dog_tags",
		icon = "csr_dog_tags",
		rarity = "common",
		name_en = "DOG TAGS",
		effect_en = "Increases maximum health by 10% (+10% per stack, linear).",
	},
	{
		id = "duct_tape",
		icon = "csr_duct_tape",
		rarity = "common",
		name_en = "DUCT TAPE",
		effect_en = "Increases interaction speed by 5% (+5% per stack, linear).\nInteraction speed affects lockpicking, bagging loot, reviving and repairing, etc.",
	},
	{
		id = "escape_plan",
		icon = "csr_escape_plan",
		rarity = "common",
		name_en = "ESCAPE PLAN",
		effect_en = "Increases movement speed by 3% (+3% per stack, hyperbolic).",
	},
	{
		id = "worn_bandaid",
		icon = "csr_worn_bandaid",
		rarity = "common",
		name_en = "WORN BAND-AID",
		effect_en = "Increases health regeneration by 5 (+5 per stack, linear) every 10 seconds.",
	},
	{
		id = "rebar",
		icon = "csr_rebar",
		rarity = "common",
		name_en = "PIECE OF REBAR",
		effect_en = "First hit on an enemy deals +20% (+10% per stack, linear) damage.",
	},

	-- UNCOMMON
	{
		id = "evidence_rounds",
		icon = "csr_bullets",
		rarity = "uncommon",
		name_en = "EVIDENCE ROUNDS",
		effect_en = "Increases damage from ALL sources by 10% (+10% per stack, linear).",
	},
	{
		id = "falcogini_keys",
		icon = "csr_falcogini_keys",
		rarity = "uncommon",
		name_en = "FALCOGINI KEYS",
		effect_en = "Increases chance to dodge by 5% (+5% per stack, hyperbolic).\nSuccessful dodging blocks incoming damage (does not work on self-inflicted damage).",
	},
	{
		id = "wolfs_toolbox",
		icon = "csr_toolbox",
		rarity = "uncommon",
		name_en = "WOLF'S TOOLBOX",
		effect_en = "Killing light or heavy SWAT reduces active drill/saw timer by 0.1 second(s) (+0.05 per stack, linear).\nKilling special enemies reduces timer by 1 second(s) (+0.5 per stack, linear).",
	},
	{
		id = "pink_slip",
		icon = "csr_pink_slip",
		rarity = "uncommon",
		name_en = "PINK SLIP",
		effect_en = "Killing any enemy restores 5 (+2.5 per stack, linear) health.",
	},
	{
		id = "overkill_rush",
		icon = "csr_overkill_rush",
		rarity = "uncommon",
		name_en = "OVERKILL RUSH",
		effect_en = "Killing any enemy grants you a rush stack. For each rush stack your fire rate and reload speed increase by 2% (+1% per stack, linear).\nAll rush stacks expire 4 seconds after the last kill.",
	},

	-- RARE
	{
		id = "bonnie_chip",
		icon = "csr_bonnie_chip",
		rarity = "rare",
		name_en = "BONNIE'S LUCKY CHIP",
		effect_en = "Gain 5% (+5% per stack, hyperbolic) chance to instantly kill an enemy on hit.\nHas 1.5 second cooldown.",
	},
	{
		id = "plush_shark",
		icon = "csr_plush_shark",
		rarity = "rare",
		name_en = "PLUSH SHARK",
		effect_en = "Protects from lethal damage once per life.\nOn activation restores 20% maximum health and grants invulnerability that lasts 10 seconds (+20 per stack, linear).\nCan be activated again if you were freed from custody.",
		lore_en = "BLÅHAJ from IKEA. This cute plushie friend will save you even in the most hopeless situation. Just don't ask how.",
	},
	{
		id = "jiro_last_wish",
		icon = "csr_jiro_last_wish",
		rarity = "rare",
		name_en = "JIRO'S LAST WISH",
		effect_en = "Grants an ability to sprint while charging a melee attack. Increases melee damage by 50% (+50% per stack, linear).",
	},
	{
		id = "dearest_possession",
		icon = "csr_dearest_possession",
		rarity = "rare",
		name_en = "DEAREST POSSESSION",
		effect_en = "Healing received at full HP is converted into temporary shields. Shield cap: 50% of maximum health (+50% per stack, linear). Shields decay at 20% per second.",
	},
	{
		id = "viklund_vinyl",
		icon = "csr_viklund_vinyl",
		rarity = "rare",
		name_en = "VIKLUND'S VINYL",
		effect_en = "Dealing damage chains 20% of it to 2 nearby enemies (7m radius).\nChain chance per wave: min(100%, (stacks + 2 - wave) × 50%). Stops when chance reaches 0.",
	},
	-- CONTRABAND
	{
		id = "dozer_guide",
		icon = "csr_dozer_guide",
		rarity = "contraband",
		name_en = "DOZER GUIDE",
		effect_en = "Increases armor by 50% (+50% per stack, linear) and damage by 5% (+5% per stack, linear) from ranged and melee weapons.\nBut decreases movement speed by 15% (+15% per stack, linear) (cannot be lower than 60% of normal movement speed) and chance to dodge by 5% (+5% per stack, linear).",
	},
	{
		id = "glass_pistol",
		icon = "csr_glass_pistol",
		rarity = "contraband",
		name_en = "GLASS PISTOL",
		effect_en = "Multiplies damage from ranged and melee weapons by x1.5 (x1.5 per stack, multiplicative).\nBut divides max health and armor by 2 (+2 per stack, multiplicative).",
	},
	{
		id = "equalizer",
		icon = "csr_equalizer",
		rarity = "contraband",
		name_en = "EQUALIZER",
		effect_en = "Increases damage against special enemies by 50% (+50% per stack, linear).\nBut reduces damage against regular enemies by 50% (-50% per stack, linear).",
	},
	{
		id = "crooked_badge",
		icon = "csr_crooked_badge",
		rarity = "contraband",
		name_en = "CROOKED BADGE",
		effect_en = "After each assault, 30% (+20%, hyperbolic) chance to restore 1 down. Chance above 100% guarantees multiple downs.\nBut bleedout timer is reduced by 10 (+1s, hyperbolic) seconds.",
	},
	{
		id = "dead_mans_trigger",
		icon = "csr_dead_mans_trigger",
		rarity = "contraband",
		name_en = "DEAD MAN'S TRIGGER",
		effect_en = "When going down you explode dealing 480 (+240 per stack, linear) damage in a 3 (+2 per stack, linear) meter radius. Damage scales with Crime Spree level.",
	}
}

-- Rarity colours
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 0.95, 0),
	rare = Color(0, 0.5, 1),
	contraband = Color(1, 0.5, 0)
}

CrimeSpreeLogbookMenuComponent = CrimeSpreeLogbookMenuComponent or class()

function CrimeSpreeLogbookMenuComponent:init(ws, fullscreen_ws, node)

	-- Guard: component must be initialised in a valid menu context
	if not ws or not fullscreen_ws then
		return
	end

	-- Guard: core managers must be available
	if not managers or not managers.menu then
		return
	end

	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()

	self._items = {}  -- Icon table: {bitmap, panel, data, original_size, highlight}
	self._hovered_item = nil
	self._selected_item = nil  -- Item currently open in detail view
	self._tooltip = nil
	self._input_focus = 1  -- Request keyboard input focus
	self._current_tab = "items"  -- Active tab: items, statistics, achievements
	self._tab_buttons = {}  -- Tab button references
	self._tab_panels = {}  -- Tab content panels

	self:_setup_logbook()
end

function CrimeSpreeLogbookMenuComponent:close()
	if self._panel and alive(self._panel) and self._ws then
		self._ws:panel():remove(self._panel)
	end
end

function CrimeSpreeLogbookMenuComponent:input_focus()
	return self._input_focus or 0
end

-- Diesel fires special_btn_pressed for ESC, not key_pressed
function CrimeSpreeLogbookMenuComponent:special_btn_pressed(button)
	-- Guard: component must be initialised
	if not self._content_panel then
		return false
	end


	-- ESC button
	if button == Idstring("esc") then
		if self._selected_item then
			-- Details view → Grid view
			self:_close_details()
			return true
		else
			-- Grid view → Close Logbook (return to Crime Spree)
			managers.menu:back()
			return true
		end
	end

	return false
end

function CrimeSpreeLogbookMenuComponent:_close_details()
	if self._details_panel and alive(self._details_panel) then
		self._panel:remove(self._details_panel)
		self._details_panel = nil
	end
	-- Restore the grid view (re-show content_panel with the icon grid)
	if self._content_panel and alive(self._content_panel) then
		self._content_panel:set_visible(true)
	end
	self._selected_item = nil
end

function CrimeSpreeLogbookMenuComponent:_setup_logbook()
	-- Clear "new" flag when logbook is opened
	if _G.CSR_Logbook then
		_G.CSR_Logbook:clear_new()
	end

	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = parent:panel({
		name = "csr_logbook_panel",
		layer = self._init_layer + 10
	})

	local panel_w = 900
	local panel_h = 600

	self._content_panel = self._panel:panel({
		name = "content_panel",
		w = panel_w,
		h = panel_h,
		layer = 10
	})

	self._content_panel:set_center_x(self._panel:w() / 2)
	self._content_panel:set_center_y(self._panel:h() / 2)

	-- Panel background
	self._content_panel:rect({
		color = Color.black,
		alpha = 0.8,
		layer = -1
	})

	-- Border
	BoxGuiObject:new(self._content_panel, {
		sides = {2, 2, 2, 2}
	})

	-- Title
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")
	local title_text = lang == "ru" and "ЖУРНАЛ" or "LOGBOOK"

	self._content_panel:text({
		name = "title",
		text = title_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = Color.white,
		x = 20,
		y = 10,
		layer = 10
	})

	-- Close hint (ESC)
	local close_hint = lang == "ru" and "[ESC] ЗАКРЫТЬ" or "[ESC] CLOSE"

	self._content_panel:text({
		name = "close_hint",
		text = close_hint,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		align = "right",
		x = 0,
		y = 10,
		w = panel_w - 20,
		layer = 10
	})

	-- Build tabs and their content panels
	self:_create_tabs()
	self:_create_tab_panels()

	-- Activate the first tab
	self:_switch_tab("items")
end

function CrimeSpreeLogbookMenuComponent:_create_tabs()
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")
	local tabs = {
		{id = "items", label = lang == "ru" and "ПРЕДМЕТЫ" or "ITEMS"},
		{id = "statistics", label = lang == "ru" and "СТАТИСТИКА" or "STATISTICS"},
		{id = "achievements", label = lang == "ru" and "ДОСТИЖЕНИЯ" or "ACHIEVEMENTS"}
	}

	local panel_w = self._content_panel:w()
	local margin_left = 20
	local margin_right = 20
	local tab_spacing = 10
	local tab_height = 30
	local start_y = 60

	-- Compute tab width so tabs fill the full panel width evenly
	local available_width = panel_w - margin_left - margin_right - (tab_spacing * (#tabs - 1))
	local tab_width = available_width / #tabs

	for i, tab_data in ipairs(tabs) do
		local x = margin_left + (i - 1) * (tab_width + tab_spacing)

		-- Tab background
		local tab_bg = self._content_panel:rect({
			name = "tab_bg_" .. tab_data.id,
			color = Color(0.2, 0.2, 0.2),
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 5
		})

		-- Tab label
		local tab_text = self._content_panel:text({
			name = "tab_text_" .. tab_data.id,
			text = tab_data.label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			align = "center",
			vertical = "center",
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 6
		})

		-- Store references for tab switching
		self._tab_buttons[tab_data.id] = {
			bg = tab_bg,
			text = tab_text,
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height
		}
	end

	-- Divider line below the tabs
	self._content_panel:rect({
		name = "tabs_divider",
		color = Color(0.4, 0.4, 0.4),
		x = margin_left,
		y = start_y + tab_height + 5,
		w = panel_w - margin_left - margin_right,
		h = 2,
		layer = 5
	})
end

function CrimeSpreeLogbookMenuComponent:_create_tab_panels()
	local panel_w = self._content_panel:w() - 40
	local panel_h = self._content_panel:h() - 120
	local panel_x = 20
	local panel_y = 100  -- Sits below the tab bar (was 90)

	-- Items tab panel
	self._tab_panels["items"] = self._content_panel:panel({
		name = "items_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8
	})

	-- Statistics tab panel
	self._tab_panels["statistics"] = self._content_panel:panel({
		name = "statistics_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8
	})

	-- Achievements tab panel
	self._tab_panels["achievements"] = self._content_panel:panel({
		name = "achievements_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8
	})

	-- Populate each tab with its content
	self:_populate_items_tab()
	self:_populate_statistics_tab()
	self:_populate_achievements_tab()
end

function CrimeSpreeLogbookMenuComponent:_switch_tab(tab_id)
	self._current_tab = tab_id

	-- Update tab button colours
	for id, button in pairs(self._tab_buttons) do
		if id == tab_id then
			-- Active tab: dark gold
			button.bg:set_color(Color(0.85, 0.7, 0.2))
			button.text:set_color(Color.black)  -- Black text for contrast on gold
		else
			-- Inactive tab: near-black
			button.bg:set_color(Color(0.15, 0.15, 0.15))
			button.text:set_color(Color(0.5, 0.5, 0.5))  -- Grey text
		end
	end

	-- Show/hide tab content panels
	for id, panel in pairs(self._tab_panels) do
		panel:set_visible(id == tab_id)
	end
end

function CrimeSpreeLogbookMenuComponent:_populate_items_tab()
	-- Delegate to the icon grid builder
	self._items_panel_ref = self._tab_panels["items"]  -- Temporary reference consumed by _create_icons_grid
	self:_create_icons_grid()
	self._items_panel_ref = nil
end

function CrimeSpreeLogbookMenuComponent:_populate_statistics_tab()
	-- Delegate to the statistics builder
	self._stats_panel_ref = self._tab_panels["statistics"]  -- Temporary reference consumed by _create_statistics
	self:_create_statistics()
	self._stats_panel_ref = nil
end

function CrimeSpreeLogbookMenuComponent:_populate_achievements_tab()
	local panel = self._tab_panels["achievements"]
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")

	-- Placeholder
	local placeholder = lang == "ru" and "ДОСТИЖЕНИЯ БУДУТ ДОБАВЛЕНЫ В БУДУЩИХ ОБНОВЛЕНИЯХ" or "ACHIEVEMENTS COMING IN FUTURE UPDATES"

	panel:text({
		name = "achievements_placeholder",
		text = placeholder,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.text,
		align = "center",
		vertical = "center",
		w = panel:w(),
		h = panel:h(),
		layer = 10
	})
end

function CrimeSpreeLogbookMenuComponent:_create_statistics()
	if not CSR_MetaProgress then
		return
	end

	local stats = CSR_MetaProgress:GetStats()
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")

	local stats_y = 20
	local stats_x = 10
	local font = tweak_data.menu.pd2_small_font
	local font_size = tweak_data.menu.pd2_small_font_size

	-- Use the tab's own panel instead of the master content panel
	local panel = self._stats_panel_ref or self._content_panel

	-- Section heading
	local stats_title = lang == "ru" and "СТАТИСТИКА" or "STATISTICS"
	panel:text({
		name = "stats_title",
		text = stats_title,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color(1, 0.8, 0.8, 1),  -- Pale yellow
		x = stats_x,
		y = stats_y,
		layer = 10
	})

	-- Format large numbers with thousands separators (1000 → 1,000)
	local function format_number(num)
		local formatted = tostring(num)
		local k
		while true do
			formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
			if k == 0 then
				break
			end
		end
		return formatted
	end

	-- Format cash as $1.2M / $1.2K / $123
	local function format_cash(amount)
		if amount >= 1000000 then
			return string.format("$%.1fM", amount / 1000000)
		elseif amount >= 1000 then
			return string.format("$%.1fK", amount / 1000)
		else
			return "$" .. amount
		end
	end

	-- Statistics list (3 columns)
	local stats_list = {
		-- Left column
		{
			label = lang == "ru" and "Миссий пройдено:" or "Missions Completed:",
			value = format_number(stats.total_missions),
			x = stats_x,
			y = stats_y + 35
		},
		{
			label = lang == "ru" and "Убийств всего:" or "Total Kills:",
			value = format_number(stats.total_kills),
			x = stats_x,
			y = stats_y + 55
		},
		{
			label = lang == "ru" and "Сумок добыто:" or "Bags Secured:",
			value = format_number(stats.total_bags),
			x = stats_x,
			y = stats_y + 75
		},
		-- Middle column
		{
			label = lang == "ru" and "Максимальный уровень:" or "Highest Level:",
			value = format_number(stats.highest_level),
			x = stats_x + 300,
			y = stats_y + 35
		},
		{
			label = lang == "ru" and "Заработано денег:" or "Total Cash Earned:",
			value = format_cash(stats.total_cash),
			x = stats_x + 300,
			y = stats_y + 55
		},
		{
			label = lang == "ru" and "Заработано монет:" or "Total Coins Earned:",
			value = format_number(math.floor(stats.total_coins or 0)),
			x = stats_x + 300,
			y = stats_y + 75
		}
	}

	-- Render each stat row
	for i, stat in ipairs(stats_list) do
		-- Label
		panel:text({
			name = "stat_label_" .. i,
			text = stat.label,
			font = font,
			font_size = font_size,
			color = tweak_data.screen_colors.text,
			x = stat.x,
			y = stat.y,
			layer = 10
		})

		-- Value (right of the label)
		local value_text = panel:text({
			name = "stat_value_" .. i,
			text = stat.value,
			font = font,
			font_size = font_size,
			color = Color.white,
			x = stat.x + 200,
			y = stat.y,
			layer = 10
		})
	end

	-- Divider line
	panel:rect({
		name = "stats_divider",
		color = Color.white,
		alpha = 0.3,
		x = stats_x,
		y = stats_y + 100,
		w = 840,
		h = 2,
		layer = 9
	})
end

function CrimeSpreeLogbookMenuComponent:_create_icons_grid()
	local icon_size = 64
	local padding = 20
	local start_x = 20
	local start_y = 30  -- Vertically aligned with the statistics tab

	-- Use the tab's own panel instead of the master content panel
	local panel = self._items_panel_ref or self._content_panel

	-- Border around the full icon area
	local border_margin = 10
	local items_per_row = 10
	local grid_width = items_per_row * (icon_size + padding) - padding + border_margin * 2
	local grid_height = math.ceil(#ITEMS_DATA / items_per_row) * (icon_size + padding) - padding + border_margin * 2

	local border_color = Color(0.4, 0.4, 0.4)  -- Dark grey

	-- Background for the icon grid area
	local grid_bg = panel:rect({
		name = "items_grid_bg",
		color = Color.black,
		alpha = 0.3,
		x = start_x - border_margin,
		y = start_y - border_margin,
		w = grid_width,
		h = grid_height,
		layer = 0
	})

	-- Border (4 lines)
	-- Top
	panel:rect({
		color = border_color,
		x = start_x - border_margin,
		y = start_y - border_margin,
		w = grid_width,
		h = 2,
		layer = 1
	})
	-- Bottom
	panel:rect({
		color = border_color,
		x = start_x - border_margin,
		y = start_y - border_margin + grid_height - 2,
		w = grid_width,
		h = 2,
		layer = 1
	})
	-- Left
	panel:rect({
		color = border_color,
		x = start_x - border_margin,
		y = start_y - border_margin,
		w = 2,
		h = grid_height,
		layer = 1
	})
	-- Right
	panel:rect({
		color = border_color,
		x = start_x - border_margin + grid_width - 2,
		y = start_y - border_margin,
		w = 2,
		h = grid_height,
		layer = 1
	})

	for i, item_data in ipairs(ITEMS_DATA) do
		local x = start_x + ((i - 1) % 10) * (icon_size + padding)
		local y = start_y + math.floor((i - 1) / 10) * (icon_size + padding)

		-- Per-item panel (used for positioning and hit-testing)
		local item_panel = panel:panel({
			name = "item_" .. item_data.id,
			x = x,
			y = y,
			w = icon_size,
			h = icon_size,
			layer = 5
		})

		-- Highlight overlay (invisible by default)
		local highlight = item_panel:rect({
			name = "highlight",
			color = Color.white,
			alpha = 0,
			layer = 0,
			blend_mode = "add"
		})

		-- Check whether this item has been unlocked in the logbook
		local is_unlocked = (not _G.CSR_Logbook) or _G.CSR_Logbook:is_unlocked(item_data.id)

		if is_unlocked then
			-- Unlocked: show icon and add to the clickable items list
			if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
				local icon_data = tweak_data.hud_icons[item_data.icon]
				local bitmap = item_panel:bitmap({
					name = "icon",
					texture = icon_data.texture,
					texture_rect = icon_data.texture_rect,
					w = icon_size,
					h = icon_size,
					color = Color.white,
					layer = 1
				})

				table.insert(self._items, {
					bitmap = bitmap,
					panel = item_panel,
					data = item_data,
					original_size = icon_size,
					original_x = x,
					original_y = y,
					highlight = highlight
				})
			end
		else
			-- Locked: dark background + large "?" marker, not clickable
			item_panel:rect({
				name = "locked_bg",
				color = Color(0.08, 0.08, 0.08),
				w = icon_size,
				h = icon_size,
				layer = 1
			})
			item_panel:text({
				name = "locked_indicator",
				text = "?",
				font = tweak_data.menu.pd2_large_font,
				font_size = 48,
				color = Color(0.5, 0.5, 0.5),
				align = "center",
				vertical = "center",
				w = icon_size,
				h = icon_size,
				layer = 2
			})
		end
	end
end

-- Open the item detail panel
function CrimeSpreeLogbookMenuComponent:_show_item_details(item_data)
	-- Hide tooltip when opening details
	if self._tooltip and alive(self._tooltip) then
		self._content_panel:remove(self._tooltip)
		self._tooltip = nil
	end

	-- Hide the grid view — the details panel takes the full screen
	self._content_panel:set_visible(false)

	-- Remove any existing details panel
	if self._details_panel and alive(self._details_panel) then
		self._panel:remove(self._details_panel)
	end

	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")
	local panel_w = 900
	local panel_h = 600

	-- Create details_panel as a sibling of content_panel, not a child
	self._details_panel = self._panel:panel({
		name = "details_panel",
		w = panel_w,
		h = panel_h,
		layer = 10
	})

	self._details_panel:set_center(self._panel:w() / 2, self._panel:h() / 2)

	-- Background
	self._details_panel:rect({
		color = Color.black,
		alpha = 0.95,
		layer = -1
	})

	BoxGuiObject:new(self._details_panel, {
		sides = {2, 2, 2, 2}
	})

	local y_pos = 20

	-- Large icon
	local icon_size = 96
	if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
		local icon_data = tweak_data.hud_icons[item_data.icon]
		self._details_panel:bitmap({
			texture = icon_data.texture,
			texture_rect = icon_data.texture_rect,
			w = icon_size,
			h = icon_size,
			x = 30,
			y = y_pos,
			color = Color.white,
			layer = 5
		})
	end

	-- Item name
	local name_text = item_data.name_en
	local rarity_color = RARITY_COLORS[item_data.rarity] or Color.white

	self._details_panel:text({
		name = "item_name",
		text = name_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = rarity_color,
		x = 30 + icon_size + 20,
		y = y_pos,
		layer = 5
	})

	y_pos = y_pos + icon_size + 30

	-- Effect description (directly after item name, no label)
	local effect_text = item_data.effect_en
	local effect_desc = self._details_panel:text({
		name = "effect_desc",
		text = effect_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		x = 30,
		y = y_pos,
		w = panel_w - 60,
		wrap = true,
		word_wrap = true,
		layer = 5
	})

	-- Calculate actual text height (replaces hardcoded +100)
	local _, _, _, effect_h = effect_desc:text_rect()
	y_pos = y_pos + effect_h + 20  -- 20px spacing

	if item_data.lore_en then
		-- Notes section (only for items that have lore)
		self._details_panel:text({
			name = "lore_title",
			text = "NOTES:",
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = Color.white,
			x = 30,
			y = y_pos,
			layer = 5
		})

		y_pos = y_pos + 30

		self._details_panel:text({
			name = "lore_desc",
			text = item_data.lore_en,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color(1, 0.7, 0.7, 0.7),
			x = 30,
			y = y_pos,
			w = panel_w - 60,
			wrap = true,
			word_wrap = true,
			layer = 5
		})
	else
		self._details_panel:text({
			name = "wip_label",
			text = "WORK IN PROGRESS",
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = Color(0.5, 0.5, 0.5),
			x = 30,
			y = y_pos,
			layer = 5
		})
	end

	-- Close hint
	local close_text = "[ESC] BACK"
	self._details_panel:text({
		name = "close_hint",
		text = close_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size - 2,
		color = tweak_data.screen_colors.text,
		align = "center",
		x = 0,
		y = panel_h - 30,
		w = panel_w,
		layer = 5
	})
end

-- Mouse handlers
function CrimeSpreeLogbookMenuComponent:mouse_moved(o, x, y)
	-- Guard: component must be initialised before handling mouse events
	if not self._content_panel then
		return false
	end

	-- In details view: ignore icon hover events
	if self._selected_item then
		-- Ensure tooltip stays hidden in details view
		if self._tooltip and alive(self._tooltip) then
			self._content_panel:remove(self._tooltip)
			self._tooltip = nil
		end
		return false, "arrow"
	end

	-- Convert world coordinates to local for tab hit-testing
	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Tab hover check (switch cursor to hand)
	for tab_id, button in pairs(self._tab_buttons) do
		if local_x >= button.x and local_x <= button.x + button.w and local_y >= button.y and local_y <= button.y + button.h then
			return true, "link"
		end
	end

	-- Icon hover check only applies on the items tab
	if self._current_tab ~= "items" then
		return false, "arrow"
	end

	-- Clear any existing tooltip
	if self._tooltip and alive(self._tooltip) then
		self._content_panel:remove(self._tooltip)
		self._tooltip = nil
	end

	local new_hovered = nil

	-- x, y are already world coordinates from the engine
	-- Hit-test each icon panel
	for i, item in ipairs(self._items) do
		if alive(item.panel) then
			local panel_x, panel_y = item.panel:world_position()
			local panel_w, panel_h = item.panel:size()

			if x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h then
				new_hovered = item
				if not self._hovered_item or self._hovered_item ~= item then
				end
				break
			end
		end
	end

	-- Update hover highlight (tooltips disabled by user request)
	if new_hovered ~= self._hovered_item then
		-- Clear highlight from previously hovered icon
		if self._hovered_item and alive(self._hovered_item.highlight) then
			self._hovered_item.highlight:set_alpha(0)
		end

		-- Highlight the newly hovered icon
		if new_hovered and alive(new_hovered.highlight) then
			new_hovered.highlight:set_alpha(0.15)
		end

		self._hovered_item = new_hovered
	end

	return true, new_hovered and "link" or "arrow"
end

function CrimeSpreeLogbookMenuComponent:mouse_pressed(o, button, x, y)
	-- Guard: component must be initialised
	if not self._content_panel or not self._items then
		return false
	end

	-- Fall back to managers.mouse_pointer if coordinates were not passed
	if not x or not y then
		if managers.mouse_pointer then
			x, y = managers.mouse_pointer:world_position()
		end
	end

	-- Ignore right clicks
	if button == Idstring("1") then
		return false
	end

	-- In details view: any click closes it
	if self._selected_item then
		self:_close_details()  -- Use centralized method
		return true
	end

	-- Icon click (items tab only)
	if self._current_tab == "items" and self._hovered_item then
		self._selected_item = self._hovered_item.data
		self:_show_item_details(self._selected_item)
		return true
	else
	end

	return false
end

function CrimeSpreeLogbookMenuComponent:mouse_released(o, button, x, y)
	-- Guard: component must be initialised
	if not self._tab_buttons or not self._content_panel then
		return false
	end

	-- Ignore right clicks
	if button == Idstring("1") then
		return false
	end

	-- Fall back to managers.mouse_pointer if coordinates were not passed
	if not x or not y then
		if managers.mouse_pointer then
			x, y = managers.mouse_pointer:world_position()
		end
	end

	-- Convert world coordinates to local
	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Hit-test tab buttons
	for tab_id, button_data in pairs(self._tab_buttons) do
		if local_x >= button_data.x and local_x <= button_data.x + button_data.w and
		   local_y >= button_data.y and local_y <= button_data.y + button_data.h then
			self:_switch_tab(tab_id)
			return true
		end
	end

	return false
end

function CrimeSpreeLogbookMenuComponent:mouse_wheel_up(x, y)
	-- Scroll disabled (not needed yet)
	return true
end

function CrimeSpreeLogbookMenuComponent:mouse_wheel_down(x, y)
	return true
end

