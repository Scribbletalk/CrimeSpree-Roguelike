-- Crime Spree Roguelike - Logbook Page
-- Item logbook with unlock system

if not RequiredScript then
	return
end

if not CrimeSpreeModifierDetailsPage then
	return
end

CrimeSpreeLogbookPage = CrimeSpreeLogbookPage or class(CrimeSpreeModifierDetailsPage)

-- All item data (generated from centralized registry)
local ITEMS_DATA = { common = {}, uncommon = {}, rare = {}, contraband = {}, wildcard = {} }
for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
	if ITEMS_DATA[item.rarity] then
		table.insert(ITEMS_DATA[item.rarity], { id = item.type, icon = item.icon })
	end
end

-- Rarity colors
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 1, 0),
	rare = Color(0.3, 0.7, 1),
	contraband = Color(1, 0.4, 0),
	wildcard = Color(1, 0.3, 0.8),
}

function CrimeSpreeLogbookPage:init(name_id, page_panel, fullscreen_panel, parent)
	CrimeSpreeLogbookPage.super.init(self, name_id, page_panel, fullscreen_panel, parent)
	-- Empty — logbook opens via set_active_page hook below, not on init
end

function CrimeSpreeLogbookPage:_setup_logbook()
	local panel = self:panel()
	if not panel then
		return
	end

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
			layer = -1,
		})
	end

	-- Create content panel
	if not self._content_panel then
		self._content_panel = panel:panel({
			name = "csr_logbook_content",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
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
		alpha = 0.3,
	})
	y = y + 10

	-- === MAIN AREA: GRID ON LEFT + DETAILS ON RIGHT ===
	local grid_width = math.floor(content:w() * 0.4) -- 40% for the grid
	local details_width = content:w() - grid_width - padding * 3 -- remainder for details

	-- Item grid panel
	self._grid_panel = content:panel({
		name = "items_grid",
		x = padding,
		y = y,
		w = grid_width,
		h = content:h() - y - padding,
	})

	-- Item details panel
	self._details_panel = content:panel({
		name = "item_details",
		x = padding + grid_width + padding,
		y = y,
		w = details_width,
		h = content:h() - y - padding,
	})

	-- Border around details panel
	self._details_panel:rect({
		x = 0,
		y = 0,
		w = details_width,
		h = 2,
		color = Color.white,
		alpha = 0.3,
	})

	-- Draw item grid
	self:_draw_items_grid()

	-- If an item is selected, show its details
	if self._selected_item then
		self:_draw_item_details()
	else
		-- Placeholder
		self._details_panel:text({
			text = "Select an item",
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = padding,
			y = 50,
		})
	end

	-- Decorative corner border
	self:_create_corners()
end

-- Create rarity tabs
function CrimeSpreeLogbookPage:_create_rarity_tabs(content, x, y)
	local tab_names = {
		common = "COMMON",
		uncommon = "UNCOMMON",
		rare = "RARE",
		contraband = "CONTRABAND",
		wildcard = "WILDCARD",
	}

	local tab_width = 140
	local tab_height = 30
	local tab_spacing = 10
	local tab_x = x

	for _, rarity in ipairs({ "common", "uncommon", "rare", "contraband", "wildcard" }) do
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
			layer = 1,
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
			layer = 2,
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
	if not self._grid_panel then
		return
	end
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
	self._item_hitboxes = {} -- Clear old hitboxes

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
			layer = 0,
		})

		if is_unlocked then
			-- Show real icon
			if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
				local icon_data = tweak_data.hud_icons[item_data.icon]
				local scaled = icon_size
				self._grid_panel:bitmap({
					texture = icon_data.texture,
					texture_rect = icon_data.texture_rect,
					w = scaled,
					h = scaled,
					x = x + (icon_size - scaled) / 2,
					y = y + (icon_size - scaled) / 2,
					color = Color.white,
					layer = 1,
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
					layer = 1,
				})
			end
			-- Darkening overlay
			self._grid_panel:rect({
				x = x,
				y = y,
				w = icon_size,
				h = icon_size,
				color = Color.black,
				alpha = 0.55,
				layer = 2,
			})
			-- Padlock: body
			local lc = Color(0.75, 0.75, 0.65)
			local cx = x + icon_size / 2
			local cy = y + icon_size / 2
			self._grid_panel:rect({
				x = cx - 11,
				y = cy + 1,
				w = 22,
				h = 14,
				color = lc,
				alpha = 0.9,
				layer = 3,
			})
			-- Padlock: shackle (outer part)
			self._grid_panel:rect({
				x = cx - 8,
				y = cy - 11,
				w = 16,
				h = 14,
				color = lc,
				alpha = 0.9,
				layer = 3,
			})
			-- Padlock: shackle cutout (makes it hollow)
			self._grid_panel:rect({
				x = cx - 5,
				y = cy - 9,
				w = 10,
				h = 10,
				color = Color(0.08, 0.08, 0.08),
				alpha = 0.95,
				layer = 4,
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
				layer = 2,
			})
			self._grid_panel:rect({
				x = x - 2,
				y = y + icon_size,
				w = icon_size + 4,
				h = 2,
				color = RARITY_COLORS[self._current_rarity],
				layer = 2,
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
			rarity = self._current_rarity,
		})
	end
end

-- Draw item details
function CrimeSpreeLogbookPage:_draw_item_details()
	if not self._details_panel or not self._selected_item then
		return
	end
	self._details_panel:clear()

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
			y = y,
		})
		y = y + 50

		self._details_panel:text({
			text = "Item not yet discovered",
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = Color(0.5, 0.5, 0.5),
			x = padding,
			y = y,
		})
		return
	end

	-- Large icon
	local icon_size = 96
	local text_x = padding + icon_size + 10
	local text_w = self._details_panel:w() - text_x - padding
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
			layer = 1,
		})
	end

	-- Name + rarity + effect (all in right column alongside icon)
	local name_text = managers.localization:text("csr_logbook_" .. item.id .. "_name")
	local rarity_text = managers.localization:text("csr_logbook_rarity_" .. item.rarity)

	self._details_panel:text({
		text = name_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = 24,
		color = RARITY_COLORS[item.rarity],
		x = text_x,
		y = y + 10,
	})

	self._details_panel:text({
		text = rarity_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = RARITY_COLORS[item.rarity],
		x = text_x,
		y = y + 40,
	})

	local effect_text = managers.localization:text("csr_logbook_" .. item.id .. "_effect")
	local effect_panel = self._details_panel:panel({
		x = text_x,
		y = y + 65,
		w = text_w,
		h = icon_size - 65 + 40,
	})
	local effect_obj = effect_panel:text({
		text = effect_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		x = 0,
		y = 0,
		w = text_w,
		wrap = true,
		word_wrap = true,
	})

	-- Color positive values green, negative values red
	local COLOR_POS = Color(0.7, 1, 0.7)
	local COLOR_NEG = Color(1, 0.5, 0.5)
	-- Positive: +N%, +Ns, +Nm, +N HP, xN.N, Gain, Increases, Protects, Grants, restores
	-- Negative: -N%, -Ns, ÷N, divides, reduces, decreases, But
	for _, pat in ipairs({
		{ "(%+%d[%d%.]*%%%)?)", COLOR_POS },
		{ "(%+%d[%d%.]*s?m?)", COLOR_POS },
		{ "(%+%d[%d%.]* HP)", COLOR_POS },
		{ "(x%d[%d%.]*)", COLOR_POS },
		{ "(×%d[%d%.]*)", COLOR_POS },
		{ "(%-%d[%d%.]*%%%)?)", COLOR_NEG },
		{ "(%-%d[%d%.]*s)", COLOR_NEG },
		{ "(÷%d[%d%.]*)", COLOR_NEG },
	}) do
		local pattern, color = pat[1], pat[2]
		local search_start = 1
		while true do
			local s, e = string.find(effect_text, pattern, search_start)
			if not s then
				break
			end
			effect_obj:set_range_color(s - 1, e, color)
			search_start = e + 1
		end
	end
	y = y + icon_size + 20

	-- Divider
	self._details_panel:rect({
		x = padding,
		y = y,
		w = self._details_panel:w() - padding * 2,
		h = 2,
		color = Color.white,
		alpha = 0.3,
	})
	y = y + 10

	-- Lore
	local notes_label = "NOTES:"
	self._details_panel:text({
		text = notes_label,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 18,
		color = Color(1, 0.85, 0.1),
		x = padding,
		y = y,
	})
	y = y + 25

	local notes_params = item.id == "evidence_rounds"
			and { rounds = tostring(math.max(31, _G.CSR_BulletsFiredToday or 0)) }
		or nil
	local notes_text = managers.localization:text("csr_logbook_" .. item.id .. "_notes", notes_params)
	self._details_panel:text({
		text = notes_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 14,
		color = Color(0.7, 0.7, 0.7),
		x = padding,
		y = y,
		w = self._details_panel:w() - padding * 2,
		wrap = true,
		word_wrap = true,
	})
end

-- Play a standard menu sound
function CrimeSpreeLogbookPage:_play_sound(event)
	if managers.menu_component and managers.menu_component.post_event then
		managers.menu_component:post_event(event)
	end
end

-- Handle mouse hover for highlight sounds
function CrimeSpreeLogbookPage:mouse_moved(button, x, y)
	local hovered_id = nil

	-- Check tab hover
	if self._tab_buttons and self._content_panel then
		local panel_x = x - self._content_panel:world_x()
		local panel_y = y - self._content_panel:world_y()

		for rarity, bounds in pairs(self._tab_buttons) do
			if
				panel_x >= bounds.x
				and panel_x <= bounds.x + bounds.w
				and panel_y >= bounds.y
				and panel_y <= bounds.y + bounds.h
			then
				hovered_id = "tab_" .. rarity
				break
			end
		end
	end

	-- Check item hover
	if not hovered_id and self._item_hitboxes and self._grid_panel then
		local panel_x = x - self._grid_panel:world_x()
		local panel_y = y - self._grid_panel:world_y()

		for _, hitbox in ipairs(self._item_hitboxes) do
			if
				panel_x >= hitbox.x
				and panel_x <= hitbox.x + hitbox.w
				and panel_y >= hitbox.y
				and panel_y <= hitbox.y + hitbox.h
			then
				hovered_id = "item_" .. hitbox.item_id
				break
			end
		end
	end

	-- Play highlight sound when hovering a new element
	if hovered_id and hovered_id ~= self._last_hovered then
		self:_play_sound("highlight")
	end
	self._last_hovered = hovered_id

	return false, hovered_id and "link" or "arrow"
end

-- Handle mouse clicks
function CrimeSpreeLogbookPage:mouse_pressed(button, x, y)
	if button ~= Idstring("0") then
		return
	end -- left mouse button only

	-- Check tab clicks
	if self._tab_buttons and self._content_panel then
		local content_panel = self._content_panel
		-- Convert coordinates to content_panel local space
		local panel_x = x - content_panel:world_x()
		local panel_y = y - content_panel:world_y()

		for rarity, bounds in pairs(self._tab_buttons) do
			if
				panel_x >= bounds.x
				and panel_x <= bounds.x + bounds.w
				and panel_y >= bounds.y
				and panel_y <= bounds.y + bounds.h
			then
				self:_play_sound("menu_enter")
				self._current_rarity = rarity
				self._selected_item = nil -- reset selection
				self:_setup_logbook() -- redraw
				return true
			end
		end
	end

	-- Check item clicks
	if self._item_hitboxes then
		for _, hitbox in ipairs(self._item_hitboxes) do
			local grid_panel = self._grid_panel
			if not grid_panel then
				break
			end

			-- Convert coordinates to grid_panel local space
			local panel_x = x - grid_panel:world_x()
			local panel_y = y - grid_panel:world_y()

			if
				panel_x >= hitbox.x
				and panel_x <= hitbox.x + hitbox.w
				and panel_y >= hitbox.y
				and panel_y <= hitbox.y + hitbox.h
			then
				self:_play_sound("menu_enter")
				-- Item clicked
				self._selected_item = {
					id = hitbox.item_id,
					rarity = hitbox.rarity,
					icon = self:_get_icon_for_item(hitbox.item_id),
				}
				self:_setup_logbook() -- redraw
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
	if not panel then
		return
	end

	if BoxGuiObject then
		self._box = BoxGuiObject:new(panel, {
			sides = { 1, 1, 0, 1 },
			color = Color.white,
		})
	end
end

function CrimeSpreeLogbookPage:get_legend()
	return {}
end

-- Scroll (unused for now, but required to prevent a crash)
function CrimeSpreeLogbookPage:update(t, dt)
	-- Do NOT call super.update: parent's _next_text and _scroll are destroyed by panel:clear() in init,
	-- calling super.update on a non-host causes a C++ access violation when server_spree_level changes.
end

function CrimeSpreeLogbookPage:mouse_wheel_up(x, y)
	-- Scroll not yet supported in logbook
	return false
end

function CrimeSpreeLogbookPage:mouse_wheel_down(x, y)
	-- Scroll not yet supported in logbook
	return false
end

-- === HOOK TO ADD TAB ===
-- Add LOGBOOK as the last tab (after REWARDS)
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddLogbookTab", function(self, tabs_data)
	table.insert(tabs_data, {
		name_id = "menu_csr_logbook",
		width_multiplier = 1,
		page_class = "CrimeSpreeLogbookPage",
	})
end)

-- Intercept tab switch — LOGBOOK is always the last tab
-- Only accessible when reward_level == 0 (player hasn't completed any heists yet)
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "set_active_page", "CSR_LogbookTabIntercept", function(self, new_index)
	if not self._tabs then
		return
	end
	if new_index == #self._tabs then
		if managers.crime_spree:reward_level() == 0 then
			pcall(function()
				managers.menu:open_node("csr_logbook_screen")
			end)
		end
		self:set_active_page(1)
	end
end)
