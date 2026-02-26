-- Crime Spree Roguelike Alpha 1 - Player items tab (with scrolling)

if not RequiredScript then
	return
end



-- === RARITY COLORS ===
-- Easy-to-change constants for text and frame colors
local RARITY_COLOR_COMMON = Color.white                -- White
local RARITY_COLOR_UNCOMMON = Color(0, 0.95, 0)       -- Green (95%)
local RARITY_COLOR_RARE = Color(0.4, 0.6, 1)          -- Blue
local RARITY_COLOR_CONTRABAND = Color(1, 0.4, 0)      -- Orange

-- === PLAYER ITEMS PAGE CLASS ===
-- Check that the parent class is available
if not CrimeSpreeModifierDetailsPage then
	return
end


-- Inherit from CrimeSpreeModifierDetailsPage for correct click handling
CrimeSpreePlayerItemsPage = CrimeSpreePlayerItemsPage or class(CrimeSpreeModifierDetailsPage)

function CrimeSpreePlayerItemsPage:init(name_id, page_panel, fullscreen_panel, parent)
	-- Call parent constructor
	CrimeSpreePlayerItemsPage.super.init(self, name_id, page_panel, fullscreen_panel, parent)

	self._scroll_offset = 0
	self._scroll_speed = 50
	self._fullscreen_panel = fullscreen_panel

	if self:panel() then
		local panel = self:panel()
		local screen_h = fullscreen_panel and fullscreen_panel:h() or 720
		local panel_y = panel:world_y()
		local new_height = screen_h - panel_y - 80

		panel:set_h(math.max(new_height, 400))
		panel:clear()
		self:_setup_items()
	end
end

-- Count stacks by ID prefix
local function count_stacks(id_prefix)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end

	local count = 0
	local active_modifiers = managers.crime_spree:active_modifiers() or {}
	for _, mod_data in ipairs(active_modifiers) do
		if mod_data.id and string.find(mod_data.id, id_prefix, 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Old create_frame_bg function removed (not used in grid layout)

-- Old vertical list functions removed (replaced by grid layout with tooltips)

function CrimeSpreePlayerItemsPage:_setup_items()
	local panel = self:panel()
	if not panel then return end

	-- Create dark background
	if not self._background then
		self._background = panel:rect({
			name = "csr_items_background",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			color = Color.black,
			alpha = 0.4,
			layer = -1
		})
	end

	-- Create nested panel for content (no scrollbar needed, content won't be that long)
	if not self._content_panel then
		self._content_panel = panel:panel({
			name = "csr_items_content",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h()
		})
	end

	local content = self._content_panel
	content:clear()

	-- Check if Crime Spree is active
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		local placeholder = managers.localization:text("menu_csr_items_placeholder")
		content:text({
			text = placeholder,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 20,
			y = 25
		})
		return
	end

	-- Count stacks and collect item data
	local items = {}
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")

	-- DOG TAGS
	local health_stacks = count_stacks("player_health_boost")
	if health_stacks > 0 then
		local total_percent = health_stacks * 10
		table.insert(items, {
			icon = "csr_dog_tags",
			frame = "csr_frame_common",
			color = RARITY_COLOR_COMMON,
			name = lang == "ru" and "ЖЕТОНЫ" or "DOG TAGS",
			stacks = health_stacks,
			desc = "Increases your max health.",
		})
	end

	-- EVIDENCE ROUNDS
	local damage_stacks = count_stacks("player_damage_boost")
	if damage_stacks > 0 then
		local total_percent = damage_stacks * 10
		table.insert(items, {
			icon = "csr_bullets",
			frame = "csr_frame_uncommon",
			color = RARITY_COLOR_UNCOMMON,
			name = lang == "ru" and "УЛИКИ" or "EVIDENCE ROUNDS",
			stacks = damage_stacks,
			desc = "All your attacks deal more damage.",
		})
	end

	-- DOZER GUIDE
	local dozer_stacks = count_stacks("player_dozer_guide")
	if dozer_stacks > 0 then
		local armor_total = dozer_stacks * 50
		local dmg_total = dozer_stacks * 5
		local speed_percent = math.floor((1 - math.max(0.4, 1 - 0.15 * dozer_stacks)) * 100)
		table.insert(items, {
			icon = "csr_dozer_guide",
			frame = "csr_frame_contraband",
			color = RARITY_COLOR_CONTRABAND,
			name = lang == "ru" and "СПРАВОЧНИК ДОЗЕРА" or "DOZER GUIDE",
			stacks = dozer_stacks,
			desc = "Greatly increases your armor and damage,\nbut slows you down.",
		})
	end

	-- BONNIE'S LUCKY CHIP
	local bonnie_stacks = count_stacks("player_bonnie_chip")
	if bonnie_stacks > 0 then
		local total_chance = (1 - math.pow(1 - 0.05, bonnie_stacks)) * 100
		table.insert(items, {
			icon = "csr_bonnie_chip",
			frame = "csr_frame_rare",
			color = RARITY_COLOR_RARE,
			name = lang == "ru" and "СЧАСТЛИВАЯ ФИШКА БОННИ" or "BONNIE'S LUCKY CHIP",
			stacks = bonnie_stacks,
			desc = "Each hit has a small chance to instantly kill the target.",
		})
	end

	-- GLASS PISTOL
	local glass_stacks = count_stacks("player_glass_pistol")
	if glass_stacks > 0 then
		-- Multiplicative stacking: each stack multiplies by 1.5 (damage) and divides by 2 (HP/armor)
		local dmg_mult = math.pow(1.5, glass_stacks)  -- 1.5^stacks
		local hp_armor_divisor = math.pow(2, glass_stacks)  -- 2^stacks

		table.insert(items, {
			icon = "csr_glass_pistol",
			frame = "csr_frame_contraband",
			color = RARITY_COLOR_CONTRABAND,
			name = lang == "ru" and "СТЕКЛЯННЫЙ ПИСТОЛЕТ" or "GLASS PISTOL",
			stacks = glass_stacks,
			desc = "Massively increases all damage,\nbut halves your HP and armor.",
		})
	end

	-- FALCOGINI KEYS
	local keys_stacks = count_stacks("player_car_keys")
	if keys_stacks > 0 then
		local k = 1.0 / 19.0
		local dodge_percent = (1 - 1/(1 + k * keys_stacks)) * 100
		table.insert(items, {
			icon = "csr_falcogini_keys",
			frame = "csr_frame_uncommon",
			color = RARITY_COLOR_UNCOMMON,
			name = lang == "ru" and "КЛЮЧИ FALCOGINI" or "FALCOGINI KEYS",
			stacks = keys_stacks,
			desc = "Gives you a chance to dodge incoming damage.",
		})
	end

	-- PLUSH SHARK
	local shark_stacks = count_stacks("player_plush_shark")
	if shark_stacks > 0 then
		local invuln_duration = 10 + (shark_stacks - 1) * 20
		table.insert(items, {
			icon = "csr_plush_shark",
			frame = "csr_frame_rare",
			color = RARITY_COLOR_RARE,
			name = lang == "ru" and "ПЛЮШЕВАЯ АКУЛА" or "PLUSH SHARK",
			stacks = shark_stacks,
			desc = "Saves you from a killing blow once per life,\nthen grants brief invulnerability.",
		})
	end

	-- WOLF'S TOOLBOX
	local toolbox_stacks = count_stacks("player_wolfs_toolbox")
	if toolbox_stacks > 0 then
		local normal_reduction = 0.1 + (0.05 * toolbox_stacks)
		local special_reduction = 1.0 + (0.5 * toolbox_stacks)
		table.insert(items, {
			icon = "csr_toolbox",
			frame = "csr_frame_uncommon",
			color = RARITY_COLOR_UNCOMMON,
			name = "WOLF'S TOOLBOX",
			stacks = toolbox_stacks,
			desc = "Killing enemies reduces the timer\non active drills and saws.",
		})
	end

	-- DUCT TAPE
	local duct_tape_stacks = count_stacks("player_duct_tape")
	if duct_tape_stacks > 0 then
		local total_bonus = duct_tape_stacks * 5
		table.insert(items, {
			icon = "csr_duct_tape",
			frame = "csr_frame_common",
			color = RARITY_COLOR_COMMON,
			name = lang == "ru" and "ИЗОЛЕНТА" or "DUCT TAPE",
			stacks = duct_tape_stacks,
			desc = "Makes you faster at interacting with objects.",
		})
	end

	-- ESCAPE PLAN
	local sneakers_stacks = count_stacks("player_escape_plan")
	if sneakers_stacks > 0 then
		local k = 3.0 / 47.0
		local speed_percent = 0.5 * (1 - 1 / (1 + k * sneakers_stacks)) * 100
		table.insert(items, {
			icon = "csr_escape_plan",
			frame = "csr_frame_common",
			color = RARITY_COLOR_COMMON,
			name = lang == "ru" and "ПОТЁРТЫЕ КРОССОВКИ" or "ESCAPE PLAN",
			stacks = sneakers_stacks,
			desc = "Increases your movement speed.",
		})
	end

	-- WORN BAND-AID
	local bandaid_stacks = count_stacks("player_worn_bandaid")
	if bandaid_stacks > 0 then
		local total_regen = 5 * bandaid_stacks
		table.insert(items, {
			icon = "csr_worn_bandaid",
			frame = "csr_frame_common",
			color = RARITY_COLOR_COMMON,
			name = lang == "ru" and "ПОТЁРТЫЙ ПЛАСТЫРЬ" or "WORN BAND-AID",
			stacks = bandaid_stacks,
			desc = "Slowly regenerates a small amount of health over time.",
		})
	end

	-- PIECE OF REBAR
	local rebar_stacks = count_stacks("player_rebar_")
	if rebar_stacks > 0 then
		local bonus = (rebar_stacks + 1) * 10
		table.insert(items, {
			icon = "csr_rebar",
			frame = "csr_frame_common",
			color = RARITY_COLOR_COMMON,
			name = "PIECE OF REBAR",
			stacks = rebar_stacks,
			desc = "Your first hit on an enemy deals bonus damage.",
		})
	end

	-- PINK SLIP (Kill to Heal)
	local pink_slip_stacks = count_stacks("player_pink_slip_")
	if pink_slip_stacks > 0 then
		local C = _G.CSR_ItemConstants or {}
		local ps_base  = C.pink_slip_base_heal  or 5
		local ps_extra = C.pink_slip_extra_heal or 2.5
		local heal = ps_base + (pink_slip_stacks - 1) * ps_extra
		table.insert(items, {
			icon = "csr_pink_slip",
			frame = "csr_frame_uncommon",
			color = RARITY_COLOR_UNCOMMON,
			name = "PINK SLIP",
			stacks = pink_slip_stacks,
			desc = "Killing an enemy restores health.",
		})
	end

	-- OVERKILL RUSH (Kill Streak: Fire Rate + Reload Speed)
	local overkill_rush_stacks = count_stacks("player_overkill_rush_")
	if overkill_rush_stacks > 0 then
		local C = _G.CSR_ItemConstants or {}
		local ok_extra  = (C.overkill_rush_extra_bonus  or 0.01) * 100
		local ok_max    = C.overkill_rush_max_stacks or 4
		local ok_dur    = C.overkill_rush_duration   or 4.0
		local bonus_per_kill = (overkill_rush_stacks + 1) * ok_extra
		local max_bonus = ok_max * bonus_per_kill
		table.insert(items, {
			icon = "csr_overkill_rush",
			frame = "csr_frame_uncommon",
			color = RARITY_COLOR_UNCOMMON,
			name = "OVERKILL RUSH",
			stacks = overkill_rush_stacks,
			desc = "Killing enemies temporarily increases fire rate and reload speed.",
		})
	end

	-- JIRO'S LAST WISH
	local jiro_stacks = count_stacks("player_jiro_last_wish")
	if jiro_stacks > 0 then
		local melee_bonus = jiro_stacks * 50
		table.insert(items, {
			icon = "csr_jiro_last_wish",
			frame = "csr_frame_rare",
			color = RARITY_COLOR_RARE,
			name = "JIRO'S LAST WISH",
			stacks = jiro_stacks,
			desc = "Sprint while charging a melee attack. Increases melee damage.",
		})
	end

	-- DEAREST POSSESSION
	local dp_stacks = count_stacks("player_dearest_possession")
	if dp_stacks > 0 then
		local shield_cap = dp_stacks * 50
		table.insert(items, {
			icon = "csr_dearest_possession",
			frame = "csr_frame_rare",
			color = RARITY_COLOR_RARE,
			name = "DEAREST POSSESSION",
			stacks = dp_stacks,
			desc = "Healing at full HP converts to temporary shields that quickly fade away.",
		})
	end

	-- VIKLUND'S VINYL
	local vv_stacks = count_stacks("player_viklund_vinyl")
	if vv_stacks > 0 then
		local max_waves = vv_stacks + 1
		table.insert(items, {
			icon = "csr_viklund_vinyl",
			frame = "csr_frame_rare",
			color = RARITY_COLOR_RARE,
			name = "VIKLUND'S VINYL",
			stacks = vv_stacks,
			desc = "...and his beats were electric.",
		})
	end

	-- EQUALIZER
	local eq_stacks = count_stacks("player_equalizer_")
	if eq_stacks > 0 then
		local special_mult = 1 + 0.5 * eq_stacks
		local normal_mult = math.max(0, 1 - 0.5 * eq_stacks)
		table.insert(items, {
			icon = "csr_equalizer",
			frame = "csr_frame_contraband",
			color = RARITY_COLOR_CONTRABAND,
			name = "EQUALIZER",
			stacks = eq_stacks,
			desc = "Greatly increases damage against special enemies,\nbut reduces it against regular ones.",
		})
	end

	-- CROOKED BADGE
	local cb_stacks = count_stacks("player_crooked_badge_")
	if cb_stacks > 0 then
		table.insert(items, {
			icon = "csr_crooked_badge",
			frame = "csr_frame_contraband",
			color = RARITY_COLOR_CONTRABAND,
			name = "CROOKED BADGE",
			stacks = cb_stacks,
			desc = "Chance to restore a down after each assault.\nBut your bleedout timer is reduced.",
		})
	end

	-- DEAD MAN'S TRIGGER
	local dmt_stacks = count_stacks("player_dead_mans_trigger_")
	if dmt_stacks > 0 then
		local radius_m = dmt_stacks * 3
		local cs_level = (managers.crime_spree and managers.crime_spree:spree_level()) or 0
		local level_mult = 1 + cs_level * 0.02
		local dmg_display = math.floor(dmt_stacks * 500 * level_mult)
		table.insert(items, {
			icon = "csr_dead_mans_trigger",
			frame = "csr_frame_contraband",
			color = RARITY_COLOR_CONTRABAND,
			name = "DEAD MAN'S TRIGGER",
			stacks = dmt_stacks,
			desc = "Going down triggers an explosion around you.\nBut allies also receive damage from it.",
		})
	end

	-- No items to display
	if #items == 0 then
		local placeholder = managers.localization:text("menu_csr_items_placeholder")
		content:text({
			text = placeholder,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 20,
			y = 25
		})
		return
	end

	-- Build icon grid (horizontal layout with wrapping)
	local icon_size = 36
	local frame_size = 64  -- Fixed frame size
	local gap = 14  -- Gap between icons
	local icon_cell = frame_size + gap  -- 78px per cell
	local start_x = 20
	local start_y = 25
	local content_width = content:w() - 40  -- Account for padding
	local icons_per_row = math.floor(content_width / icon_cell)


	-- Array of icon positions for mouse hover detection
	self._item_positions = {}

	-- Draw icons in grid
	for i, item in ipairs(items) do
		local col = (i - 1) % icons_per_row
		local row = math.floor((i - 1) / icons_per_row)
		local x = start_x + col * icon_cell
		local y = start_y + row * icon_cell

		-- Frame
		if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
			local frame_data = tweak_data.hud_icons[item.frame]
			content:bitmap({
				texture = frame_data.texture,
				texture_rect = frame_data.texture_rect,
				w = frame_size,
				h = frame_size,
				x = x,
				y = y,
				color = item.color or Color.white,
				layer = 0
			})
		else
		end

		-- Icon (centered in frame)
		if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
			local icon_data = tweak_data.hud_icons[item.icon]
			local icon_offset = (frame_size - icon_size) / 2  -- Center icon within frame
			content:bitmap({
				texture = icon_data.texture,
				texture_rect = icon_data.texture_rect,
				w = icon_size,
				h = icon_size,
				x = x + icon_offset,
				y = y + icon_offset,
				color = Color.white,
				layer = 1
			})
		end

		-- Stack counter (top right corner)
		if item.stacks and item.stacks > 1 then
			local stack_str = "x" .. tostring(item.stacks)
			local text_x = x + frame_size - 28
			local text_y = y + 2

			-- Text shadow (black outline for readability)
			for dx = -1, 1 do
				for dy = -1, 1 do
					if not (dx == 0 and dy == 0) then
						content:text({
							text = stack_str,
							font = tweak_data.menu.pd2_medium_font,
							font_size = 16,
							color = Color.black,
							x = text_x + dx,
							y = text_y + dy,
							layer = 2,
							align = "right",
							vertical = "top"
						})
					end
				end
			end

			-- Main text (white, on top of shadow)
			content:text({
				text = stack_str,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 16,
				color = Color.white,
				x = text_x,
				y = text_y,
				layer = 3,
				align = "right",
				vertical = "top"
			})
		end

		-- Save position for hit detection
		table.insert(self._item_positions, {
			x1 = x,
			y1 = y,
			x2 = x + frame_size,
			y2 = y + frame_size,
			item = item
		})
	end

	-- Create tooltip panel (hidden by default)
	if not self._tooltip_panel then
		self._tooltip_panel = content:panel({
			name = "csr_tooltip",
			visible = false,
			layer = 100
		})
	end


	-- Decorative border
	self:_create_corners()
end

-- Create decorative corners (BoxGuiObject - same as in logbook)
function CrimeSpreePlayerItemsPage:_create_corners()
	local panel = self:panel()
	if not panel then return end

	if BoxGuiObject then
		self._box = BoxGuiObject:new(panel, {
			sides = { 1, 1, 1, 1 },
			color = Color.white
		})
	else
	end
end

-- Scrollbar no longer needed (grid items fit in available space)

function CrimeSpreePlayerItemsPage:get_legend()
	return {}
end

-- Handle mouse hover to show tooltip
-- NOTE: Diesel Engine passes event object (o) as first parameter, then coordinates
function CrimeSpreePlayerItemsPage:mouse_moved(o, x, y)
	-- Validate that coordinates are numbers
	if type(x) ~= "number" or type(y) ~= "number" then
		return false
	end

	if not self._item_positions or not self._tooltip_panel then
		return false
	end

	local content = self._content_panel
	if not content then
		return false
	end

	-- Safely get panel world coordinates
	local world_x = content:world_x()
	local world_y = content:world_y()

	if type(world_x) ~= "number" or type(world_y) ~= "number" then
		return false
	end

	-- Convert mouse coordinates to content panel local coordinates
	local local_x = x - world_x
	local local_y = y - world_y

	-- Check if mouse is hovering over an icon
	local hovered_item = nil
	local hovered_pos = nil
	for _, pos in ipairs(self._item_positions) do
		if local_x >= pos.x1 and local_x <= pos.x2 and local_y >= pos.y1 and local_y <= pos.y2 then
			hovered_item = pos.item
			hovered_pos = pos
			break
		end
	end

	if hovered_item and hovered_pos then
		-- Anchor tooltip below the item frame, not at cursor position
		self:_show_tooltip(hovered_item, hovered_pos.x1, hovered_pos.y2)
	else
		-- Hide tooltip
		if self._tooltip_panel:visible() then
			self._tooltip_panel:set_visible(false)
		end
	end

	return false  -- Do NOT block other mouse events (important for button clicks)
end

-- Show tooltip for item
function CrimeSpreePlayerItemsPage:_show_tooltip(item, mouse_x, mouse_y)
	local tooltip = self._tooltip_panel
	if not tooltip then
		return
	end

	-- Validate coordinate types
	if type(mouse_x) ~= "number" or type(mouse_y) ~= "number" then
		return
	end

	tooltip:clear()

	local tooltip_w = 280
	local padding = 10

	-- Measure description text height by creating it first
	local desc_text = tooltip:text({
		text = item.desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		x = padding,
		y = padding + 25,
		w = tooltip_w - padding * 2,
		wrap = true,
		word_wrap = true,
		layer = 2
	})

	-- Get actual rendered text height
	local _, _, _, desc_h = desc_text:text_rect()
	local tooltip_h = padding + 25 + desc_h + padding

	-- Position tooltip
	local panel = self:panel()
	if not panel then return end

	local panel_w = panel:w()
	local panel_h = panel:h()

	if type(panel_w) ~= "number" or type(panel_h) ~= "number" then
		return
	end

	local tooltip_x = mouse_x
	local tooltip_y = mouse_y + 5

	local max_x = panel_w - tooltip_w - 10
	local max_y = panel_h - tooltip_h - 10
	tooltip_x = math.min(tooltip_x, max_x)
	tooltip_y = math.clamp(tooltip_y, 10, max_y)

	tooltip:set_shape(tooltip_x, tooltip_y, tooltip_w, tooltip_h)

	-- Background
	tooltip:rect({
		color = Color.black,
		alpha = 0.9,
		layer = 0
	})

	-- Border (4 thin rects)
	local border_color = item.color or Color.white
	local border_size = 2

	tooltip:rect({ x = 0, y = 0, w = tooltip_w, h = border_size, color = border_color, alpha = 0.4, layer = 1 })
	tooltip:rect({ x = 0, y = tooltip_h - border_size, w = tooltip_w, h = border_size, color = border_color, alpha = 0.4, layer = 1 })
	tooltip:rect({ x = 0, y = 0, w = border_size, h = tooltip_h, color = border_color, alpha = 0.4, layer = 1 })
	tooltip:rect({ x = tooltip_w - border_size, y = 0, w = border_size, h = tooltip_h, color = border_color, alpha = 0.4, layer = 1 })

	-- Title
	local title_text = string.format("%s x%d", item.name, item.stacks)
	tooltip:text({
		text = title_text,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = item.color or Color.white,
		x = padding,
		y = padding,
		layer = 2
	})

	tooltip:set_visible(true)
end

function CrimeSpreePlayerItemsPage:mouse_wheel_up(x, y)
	return false  -- Scrolling removed
end

function CrimeSpreePlayerItemsPage:mouse_wheel_down(x, y)
	return false  -- Scrolling removed
end

-- === HOOK TO ADD TAB ===
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddPlayerItemsTab", function(self, tabs_data)
	table.insert(tabs_data, 1, {
		name_id = "menu_csr_items",
		width_multiplier = 1,
		page_class = "CrimeSpreePlayerItemsPage"
	})
end)

