-- Crime Spree Roguelike - Logbook Page
-- Item logbook with unlock system

if not RequiredScript then
	return
end



if not CrimeSpreeModifierDetailsPage then
	return
end

CrimeSpreeLogbookPage = CrimeSpreeLogbookPage or class(CrimeSpreeModifierDetailsPage)

-- All item data
local ITEMS_DATA = {
	common = {
		{ id = "dog_tags", icon = "csr_dog_tags" },
		{ id = "duct_tape", icon = "csr_duct_tape" },
		{ id = "escape_plan", icon = "csr_escape_plan" },
		{ id = "worn_bandaid", icon = "csr_worn_bandaid" },
		{ id = "rebar", icon = "csr_rebar" }
	},
	uncommon = {
		{ id = "ap_rounds", icon = "csr_bullets" },
		{ id = "falcogini_keys", icon = "csr_falcogini_keys" },
		{ id = "wolfs_toolbox", icon = "csr_toolbox" }
	},
	rare = {
		{ id = "bonnie_chip", icon = "csr_bonnie_chip" },
		{ id = "plush_shark", icon = "csr_plush_shark" },
		{ id = "jiro_last_wish", icon = "csr_jiro_last_wish" },
		{ id = "dearest_possession", icon = "csr_dearest_possession" },
		{ id = "viklund_vinyl", icon = "csr_viklund_vinyl" }
	},
	contraband = {
		{ id = "dozer_guide", icon = "csr_dozer_guide" },
		{ id = "glass_pistol", icon = "csr_glass_pistol" },
		{ id = "equalizer", icon = "csr_equalizer" },
		{ id = "crooked_badge", icon = "csr_crooked_badge" },
		{ id = "dead_mans_trigger", icon = "csr_dead_mans_trigger" }
	}
}

-- Rarity colors
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 1, 0),
	rare = Color(0.4, 0.6, 1),
	contraband = Color(1, 0.4, 0)
}

function CrimeSpreeLogbookPage:init(name_id, page_panel, fullscreen_panel, parent)
	CrimeSpreeLogbookPage.super.init(self, name_id, page_panel, fullscreen_panel, parent)

	self._scroll_offset = 0
	self._scroll_speed = 50
	self._fullscreen_panel = fullscreen_panel
	self._current_rarity = "common"  -- currently selected tab
	self._selected_item = nil  -- item selected for display on the right

	if self:panel() then
		local panel = self:panel()
		local screen_h = fullscreen_panel and fullscreen_panel:h() or 720
		local panel_y = panel:world_y()
		local new_height = screen_h - panel_y - 80

		panel:set_h(math.max(new_height, 400))

		if panel.set_clip then
			panel:set_clip(false)
		end

		panel:clear()
		self:_setup_logbook()
	end
end

function CrimeSpreeLogbookPage:_setup_logbook()
	local panel = self:panel()
	if not panel then return end

	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")

	-- Dark background
	if not self._background then
		self._background = panel:rect({
			name = "csr_logbook_background",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			color = Color.black,
			alpha = 0.4,
			layer = -1
		})
	end

	-- Create content panel
	if not self._content_panel then
		self._content_panel = panel:panel({
			name = "csr_logbook_content",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h()
		})
	end

	local content = self._content_panel
	content:clear()

	local padding = 10
	local y = padding

	-- === RARITY TABS ===
	self:_create_rarity_tabs(content, padding, y)
	y = y + 40

	-- Divider
	content:rect({
		x = padding,
		y = y,
		w = content:w() - padding * 2,
		h = 2,
		color = Color.white,
		alpha = 0.3
	})
	y = y + 10

	-- === MAIN AREA: GRID ON LEFT + DETAILS ON RIGHT ===
	local grid_width = math.floor(content:w() * 0.4)  -- 40% for the grid
	local details_width = content:w() - grid_width - padding * 3  -- remainder for details

	-- Item grid panel
	self._grid_panel = content:panel({
		name = "items_grid",
		x = padding,
		y = y,
		w = grid_width,
		h = content:h() - y - padding
	})

	-- Item details panel
	self._details_panel = content:panel({
		name = "item_details",
		x = padding + grid_width + padding,
		y = y,
		w = details_width,
		h = content:h() - y - padding
	})

	-- Border around details panel
	self._details_panel:rect({
		x = 0,
		y = 0,
		w = details_width,
		h = 2,
		color = Color.white,
		alpha = 0.3
	})

	-- Draw item grid
	self:_draw_items_grid()

	-- If an item is selected, show its details
	if self._selected_item then
		self:_draw_item_details()
	else
		-- Placeholder
		self._details_panel:text({
			text = lang == "ru" and "Выберите предмет" or "Select an item",
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = padding,
			y = 50
		})
	end

	-- Decorative corner border
	self:_create_corners()

end

-- Create rarity tabs
function CrimeSpreeLogbookPage:_create_rarity_tabs(content, x, y)
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")
	local tab_names = {
		common = lang == "ru" and "ОБЫЧНЫЕ" or "COMMON",
		uncommon = lang == "ru" and "НЕОБЫЧНЫЕ" or "UNCOMMON",
		rare = lang == "ru" and "РЕДКИЕ" or "RARE",
		contraband = lang == "ru" and "КОНТРАБАНДА" or "CONTRABAND"
	}

	local tab_width = 140
	local tab_height = 30
	local tab_spacing = 10
	local tab_x = x

	for _, rarity in ipairs({"common", "uncommon", "rare", "contraband"}) do
		local is_selected = (self._current_rarity == rarity)
		local tab_color = is_selected and RARITY_COLORS[rarity] or Color(0.3, 0.3, 0.3)

		-- Tab background
		local tab_bg = content:rect({
			name = "tab_" .. rarity,
			x = tab_x,
			y = y,
			w = tab_width,
			h = tab_height,
			color = tab_color,
			alpha = is_selected and 0.8 or 0.4,
			layer = 1
		})

		-- Tab label
		content:text({
			text = tab_names[rarity],
			font = tweak_data.menu.pd2_medium_font,
			font_size = 16,
			color = Color.white,
			x = tab_x,
			y = y + 5,
			w = tab_width,
			h = tab_height,
			align = "center",
			vertical = "center",
			layer = 2
		})

		-- Store for click handling
		if not self._tab_buttons then
			self._tab_buttons = {}
		end
		self._tab_buttons[rarity] = { x = tab_x, y = y, w = tab_width, h = tab_height }

		tab_x = tab_x + tab_width + tab_spacing
	end
end

-- Draw item grid
function CrimeSpreeLogbookPage:_draw_items_grid()
	if not self._grid_panel then return end
	self._grid_panel:clear()

	local items = ITEMS_DATA[self._current_rarity] or {}
	local icon_size = 64
	local padding = 10
	local x_offset = 0
	local y_offset = 0
	local items_per_row = math.floor(self._grid_panel:w() / (icon_size + padding))

	if not self._item_hitboxes then
		self._item_hitboxes = {}
	end
	self._item_hitboxes = {}  -- Clear old hitboxes

	for i, item_data in ipairs(items) do
		local is_unlocked = CSR_Logbook and CSR_Logbook:is_unlocked(item_data.id) or false

		-- Calculate position
		local col = (i - 1) % items_per_row
		local row = math.floor((i - 1) / items_per_row)
		local x = padding + col * (icon_size + padding)
		local y = padding + row * (icon_size + padding)

		-- Icon background
		local bg = self._grid_panel:rect({
			x = x - 2,
			y = y - 2,
			w = icon_size + 4,
			h = icon_size + 4,
			color = Color.black,
			alpha = 0.6,
			layer = 0
		})

		if is_unlocked then
			-- Show real icon
			if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
				local icon_data = tweak_data.hud_icons[item_data.icon]
				self._grid_panel:bitmap({
					texture = icon_data.texture,
					texture_rect = icon_data.texture_rect,
					w = icon_size,
					h = icon_size,
					x = x,
					y = y,
					color = Color.white,
					layer = 1
				})
			end
		else
			-- Locked: faint icon + padlock
			if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
				local icon_data = tweak_data.hud_icons[item_data.icon]
				self._grid_panel:bitmap({
					texture = icon_data.texture,
					texture_rect = icon_data.texture_rect,
					w = icon_size,
					h = icon_size,
					x = x,
					y = y,
					color = Color(0.2, 0.2, 0.2),
					alpha = 0.25,
					layer = 1
				})
			end
			-- Darkening overlay
			self._grid_panel:rect({
				x = x, y = y, w = icon_size, h = icon_size,
				color = Color.black, alpha = 0.55, layer = 2
			})
			-- Padlock: body
			local lc = Color(0.75, 0.75, 0.65)
			local cx = x + icon_size / 2
			local cy = y + icon_size / 2
			self._grid_panel:rect({
				x = cx - 11, y = cy + 1, w = 22, h = 14,
				color = lc, alpha = 0.9, layer = 3
			})
			-- Padlock: shackle (outer part)
			self._grid_panel:rect({
				x = cx - 8, y = cy - 11, w = 16, h = 14,
				color = lc, alpha = 0.9, layer = 3
			})
			-- Padlock: shackle cutout (makes it hollow)
			self._grid_panel:rect({
				x = cx - 5, y = cy - 9, w = 10, h = 10,
				color = Color(0.08, 0.08, 0.08), alpha = 0.95, layer = 4
			})
		end

		-- Selection highlight border
		if self._selected_item and self._selected_item.id == item_data.id then
			self._grid_panel:rect({
				x = x - 2,
				y = y - 2,
				w = icon_size + 4,
				h = 2,
				color = RARITY_COLORS[self._current_rarity],
				layer = 2
			})
			self._grid_panel:rect({
				x = x - 2,
				y = y + icon_size,
				w = icon_size + 4,
				h = 2,
				color = RARITY_COLORS[self._current_rarity],
				layer = 2
			})
		end

		-- Store hitbox for click detection
		table.insert(self._item_hitboxes, {
			x = x,
			y = y,
			w = icon_size,
			h = icon_size,
			item_id = item_data.id,
			is_unlocked = is_unlocked,
			rarity = self._current_rarity
		})
	end

end

-- Draw item details
function CrimeSpreeLogbookPage:_draw_item_details()
	if not self._details_panel or not self._selected_item then return end
	self._details_panel:clear()

	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")
	local padding = 10
	local y = padding

	local item = self._selected_item
	local is_unlocked = CSR_Logbook and CSR_Logbook:is_unlocked(item.id) or false

	if not is_unlocked then
		-- Show "???" for locked items
		self._details_panel:text({
			text = "? ? ?",
			font = tweak_data.menu.pd2_large_font,
			font_size = 32,
			color = Color(0.3, 0.3, 0.3),
			x = padding,
			y = y
		})
		y = y + 50

		self._details_panel:text({
			text = lang == "ru" and "Предмет ещё не найден" or "Item not yet discovered",
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = Color(0.5, 0.5, 0.5),
			x = padding,
			y = y
		})
		return
	end

	-- Large icon
	local icon_size = 96
	if tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
		local icon_data = tweak_data.hud_icons[item.icon]
		self._details_panel:bitmap({
			texture = icon_data.texture,
			texture_rect = icon_data.texture_rect,
			w = icon_size,
			h = icon_size,
			x = padding,
			y = y,
			color = Color.white,
			layer = 1
		})
	end

	-- Name + rarity
	local name_text = managers.localization:text("csr_logbook_" .. item.id .. "_name")
	local rarity_text = managers.localization:text("csr_logbook_rarity_" .. item.rarity)

	self._details_panel:text({
		text = name_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = 24,
		color = RARITY_COLORS[item.rarity],
		x = padding + icon_size + 10,
		y = y + 10
	})

	self._details_panel:text({
		text = rarity_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = RARITY_COLORS[item.rarity],
		x = padding + icon_size + 10,
		y = y + 40
	})

	y = y + icon_size + 20

	-- Divider
	self._details_panel:rect({
		x = padding,
		y = y,
		w = self._details_panel:w() - padding * 2,
		h = 2,
		color = Color.white,
		alpha = 0.3
	})
	y = y + 10

	local effect_text = managers.localization:text("csr_logbook_" .. item.id .. "_effect")
	self._details_panel:text({
		text = effect_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		x = padding,
		y = y,
		w = self._details_panel:w() - padding * 2,
		wrap = true,
		word_wrap = true
	})
	y = y + 60

	-- Divider
	self._details_panel:rect({
		x = padding,
		y = y,
		w = self._details_panel:w() - padding * 2,
		h = 2,
		color = Color.white,
		alpha = 0.3
	})
	y = y + 10

	-- Lore
	local lore_label = lang == "ru" and "ИСТОРИЯ:" or "LORE:"
	self._details_panel:text({
		text = lore_label,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 18,
		color = Color(1, 0.85, 0.1),
		x = padding,
		y = y
	})
	y = y + 25

	local lore_text = managers.localization:text("csr_logbook_" .. item.id .. "_lore")
	self._details_panel:text({
		text = lore_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 14,
		color = Color(0.7, 0.7, 0.7),
		x = padding,
		y = y,
		w = self._details_panel:w() - padding * 2,
		wrap = true,
		word_wrap = true
	})
end

-- Handle mouse clicks
function CrimeSpreeLogbookPage:mouse_pressed(button, x, y)
	if button ~= Idstring("0") then return end  -- left mouse button only

	-- Check tab clicks
	if self._tab_buttons and self._content_panel then
		local content_panel = self._content_panel
		-- Convert coordinates to content_panel local space
		local panel_x = x - content_panel:world_x()
		local panel_y = y - content_panel:world_y()

		for rarity, bounds in pairs(self._tab_buttons) do
			if panel_x >= bounds.x and panel_x <= bounds.x + bounds.w and
			   panel_y >= bounds.y and panel_y <= bounds.y + bounds.h then
				self._current_rarity = rarity
				self._selected_item = nil  -- reset selection
				self:_setup_logbook()  -- redraw
				return true
			end
		end
	end

	-- Check item clicks
	if self._item_hitboxes then
		for _, hitbox in ipairs(self._item_hitboxes) do
			local grid_panel = self._grid_panel
			if not grid_panel then break end

			-- Convert coordinates to grid_panel local space
			local panel_x = x - grid_panel:world_x()
			local panel_y = y - grid_panel:world_y()

			if panel_x >= hitbox.x and panel_x <= hitbox.x + hitbox.w and
			   panel_y >= hitbox.y and panel_y <= hitbox.y + hitbox.h then
				-- Item clicked
				self._selected_item = {
					id = hitbox.item_id,
					rarity = hitbox.rarity,
					icon = self:_get_icon_for_item(hitbox.item_id)
				}
				self:_setup_logbook()  -- redraw
				return true
			end
		end
	end

	return false
end

-- Helper to get an item's icon
function CrimeSpreeLogbookPage:_get_icon_for_item(item_id)
	for rarity, items in pairs(ITEMS_DATA) do
		for _, item in ipairs(items) do
			if item.id == item_id then
				return item.icon
			end
		end
	end
	return nil
end

-- Decorative corner border
function CrimeSpreeLogbookPage:_create_corners()
	local panel = self:panel()
	if not panel then return end

	if BoxGuiObject then
		self._box = BoxGuiObject:new(panel, {
			sides = { 1, 1, 0, 1 },
			color = Color.white
		})
	end
end

function CrimeSpreeLogbookPage:get_legend()
	return {}
end

-- Scroll (unused for now, but required to prevent a crash)
function CrimeSpreeLogbookPage:mouse_wheel_up(x, y)
	-- Scroll not yet supported in logbook
	return false
end

function CrimeSpreeLogbookPage:mouse_wheel_down(x, y)
	-- Scroll not yet supported in logbook
	return false
end

-- === HOOK TO ADD TAB ===
-- COMMENTED OUT: Logbook now opens via a button, not a tab
-- Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddLogbookTab", function(self, tabs_data)
-- 	table.insert(tabs_data, 3, {
-- 		name_id = "menu_csr_logbook",
-- 		width_multiplier = 1,
-- 		page_class = "CrimeSpreeLogbookPage"
-- 	})
-- end)

