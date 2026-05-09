-- Crime Spree Roguelike - Forced Modifiers Notification
-- Shows popup after mission when forced modifiers are added
-- v2.50: Fixed mouse_pos crash + added click handling + debug logging

-- Unique callback IDs for update hooks (GameSetupUpdate = in-mission, MenuUpdate = in-menu/lobby)
local HOOK_ID = "CSR_ForcedModsNotification_Update"
local MENU_HOOK_ID = "CSR_ForcedModsNotification_MenuUpdate"

CSRForcedModsNotification = CSRForcedModsNotification or class()

function CSRForcedModsNotification:init(modifiers)
	if not modifiers or #modifiers == 0 then
		return
	end

	-- Save global reference
	_G.CSR_ForcedModsNotificationInstance = self

	-- Vanilla pattern: backdrop on fullscreen_ws, main panel on saferect _ws
	-- Mouse coords from MenuComponentManager are in _ws (saferect) space
	local mc = managers.menu_component
	if mc and mc._ws and alive(mc._ws:panel()) and mc._fullscreen_ws and alive(mc._fullscreen_ws:panel()) then
		self._ws = mc._ws
		self._fullscreen_ws = mc._fullscreen_ws
		self._owns_ws = false
	else
		self._ws = managers.gui_data:create_saferect_workspace()
		self._fullscreen_ws = managers.gui_data:create_fullscreen_workspace()
		self._owns_ws = true
	end
	if not self._ws then
		return
	end

	-- Calculate saferect-to-fullscreen offset for mouse coordinate conversion
	self._safe_offset_x = (self._fullscreen_ws:panel():w() - self._ws:panel():w()) / 2
	self._safe_offset_y = (self._fullscreen_ws:panel():h() - self._ws:panel():h()) / 2

	-- === BACKDROP (fullscreen — covers entire screen) ===
	self._backdrop = self._fullscreen_ws:panel():rect({
		name = "csr_notification_backdrop",
		color = Color.black,
		alpha = 0,
		layer = 999,
		w = self._fullscreen_ws:panel():w(),
		h = self._fullscreen_ws:panel():h(),
	})

	-- Calculate panel height
	local panel_height = self:calculate_height(#modifiers)

	-- === MAIN PANEL (fullscreen — no clipping at screen edges) ===
	self._panel = self._fullscreen_ws:panel():panel({
		name = "csr_forced_mods_notification",
		w = 800,
		h = panel_height,
		layer = 1000,
	})

	-- Center within fullscreen
	self._panel:set_center(self._fullscreen_ws:panel():center())
	self._panel:set_alpha(0)

	-- === BACKGROUND ===
	self._bg = self._panel:rect({
		color = Color.black,
		alpha = 0.95,
		layer = 0,
	})

	if BoxGuiObject then
		pcall(function()
			BoxGuiObject:new(self._panel, { sides = { 2, 2, 2, 2 } })
		end)
	end

	-- === TITLE ===
	local max_level = 0
	for _, mod in ipairs(modifiers) do
		if mod.level and mod.level > max_level then
			max_level = mod.level
		end
	end

	self._title = self._panel:text({
		text = "FORCED MODIFIERS ADDED",
		font = tweak_data.menu.pd2_large_font,
		font_size = 28,
		color = Color(1, 0.85, 0.7, 0.2),
		align = "center",
		vertical = "top",
		y = 15,
		layer = 10,
	})

	if max_level > 0 then
		self._level_text = self._panel:text({
			text = "Level " .. max_level,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 22,
			color = Color(0.7, 0.7, 0.7),
			align = "center",
			vertical = "top",
			y = 50,
			layer = 10,
		})
	end

	-- === LAYOUT CONSTANTS ===
	local cards_top = 110 -- below title + level text + column headers
	local header_labels_y = 78 -- y position of LOUD/STEALTH labels on main panel
	local footer_h = 90 -- hint + close button
	self._header_labels_y = header_labels_y
	local screen_h = self._fullscreen_ws:panel():h()
	local max_panel_h = screen_h * 0.85

	-- === CARDS CLIPPING CONTAINER ===
	-- Cards go inside this panel which clips overflow; scrolled via mouse wheel
	local cards_area_h = panel_height - cards_top - footer_h
	self._cards_panel = self._panel:panel({
		name = "csr_cards_area",
		x = 0,
		y = cards_top,
		w = self._panel:w(),
		h = cards_area_h,
		layer = 5,
	})

	-- Canvas inside the clipping panel (holds all cards, can be taller than container)
	self._cards_canvas = self._cards_panel:panel({
		name = "csr_cards_canvas",
		x = 0,
		y = 0,
		w = self._cards_panel:w(),
		h = cards_area_h, -- will grow after populate
		layer = 1,
	})

	-- === MODIFIER CARDS ===
	self:populate_modifiers(modifiers)

	-- Resize canvas to fit cards (header is outside canvas, on _cards_panel)
	local header_row_h = 30
	local cards_only_h = self:_cards_only_height()
	self._cards_canvas:set_h(cards_only_h)

	-- Cap panel height and set up scrolling
	local total_cards_area = header_row_h + cards_only_h
	local actual_panel_h = cards_top + total_cards_area + footer_h
	local capped_panel_h = math.min(actual_panel_h, max_panel_h)
	self._panel:set_h(capped_panel_h)
	if alive(self._bg) then
		self._bg:set_h(capped_panel_h)
	end

	-- Resize cards clipping area to fit between header and footer
	local visible_cards_h = capped_panel_h - cards_top - footer_h
	self._cards_panel:set_h(visible_cards_h)

	self._panel:set_center(self._fullscreen_ws:panel():center())

	-- Scroll max: entire _cards_panel is scrollable (headers are on main panel now)
	self._scroll_offset = 0
	self._max_scroll = math.max(0, cards_only_h - visible_cards_h)

	-- === SCROLLBAR (only if content overflows) ===
	if self._max_scroll > 0 then
		local bar_track_h = visible_cards_h - 8
		local bar_h = math.max(20, bar_track_h * (visible_cards_h / cards_only_h))
		self._scrollbar_track = self._panel:rect({
			x = self._panel:w() - 12,
			y = cards_top + 4,
			w = 4,
			h = bar_track_h,
			color = Color(1, 0.3, 0.3, 0.3),
			alpha = 0.5,
			layer = 20,
		})
		self._scrollbar = self._panel:rect({
			x = self._panel:w() - 12,
			y = cards_top + 4,
			w = 4,
			h = bar_h,
			color = Color(1, 0.8, 0.8, 0.8),
			alpha = 0.7,
			layer = 21,
		})
		self._scrollbar_range = bar_track_h - bar_h
	end

	-- === HINT TEXT ===
	self._hint = self._panel:text({
		text = self._max_scroll > 0 and "Scroll for more  |  Press ESC or button below" or "Press ESC or button below",
		font = tweak_data.menu.pd2_small_font,
		font_size = 18,
		color = Color(0.7, 0.7, 0.7),
		align = "center",
		vertical = "bottom",
		layer = 10,
	})

	self._hint:set_bottom(self._panel:h() - 70)

	-- === CLOSE BUTTON ===
	local button_panel = self._panel:panel({
		x = (self._panel:w() - 200) / 2,
		y = self._panel:h() - 60,
		w = 200,
		h = 40,
		layer = 15,
	})

	button_panel:rect({
		color = Color(1, 0.3, 0.3, 0.3),
		alpha = 0.9,
		layer = 0,
	})

	self._button_highlight = button_panel:rect({
		color = Color.white,
		alpha = 0,
		blend_mode = "add",
		layer = 1,
	})

	button_panel:text({
		text = "CLOSE",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 22,
		color = Color.white,
		align = "center",
		vertical = "center",
		layer = 10,
	})

	self._close_button = button_panel

	-- === FADE-IN ===
	self:animate_fade_in()

	-- === Shared input handler for both in-game and menu contexts ===
	local function notification_input_handler(t, dt)
		local inst = _G.CSR_ForcedModsNotificationInstance
		if not inst or not alive(inst._panel) then
			return
		end

		-- ESC handling
		if Input:keyboard() and Input:keyboard():pressed(Idstring("esc")) then
			inst:close()
			return
		end

		-- Mouse handling (v2.50: modified_mouse_pos returns TWO numbers, NOT a table!)
		if managers.mouse_pointer then
			local x, y = managers.mouse_pointer:modified_mouse_pos()
			if x and y then
				local used, cursor = inst:mouse_moved(x, y)
				if cursor then
					managers.mouse_pointer:set_pointer_image(cursor)
				end
			end
		end

		-- Mouse click handling (v2.50: LMB press)
		if Input:mouse() and Input:mouse():pressed(Idstring("0")) then
			if managers.mouse_pointer then
				local x, y = managers.mouse_pointer:modified_mouse_pos()
				if x and y then
					inst:mouse_pressed(Idstring("0"), x, y)
				end
			end
		end

		-- Mouse wheel scrolling
		if Input:mouse() and inst._max_scroll and inst._max_scroll > 0 then
			if Input:mouse():pressed(Idstring("mouse wheel down")) then
				inst:scroll_content(40)
			elseif Input:mouse():pressed(Idstring("mouse wheel up")) then
				inst:scroll_content(-40)
			end
		end
	end

	-- Register on both hooks: GameSetupUpdate (in-mission), MenuUpdate (in-menu/lobby)
	Hooks:Add("GameSetupUpdate", HOOK_ID, notification_input_handler)
	Hooks:Add("MenuUpdate", MENU_HOOK_ID, notification_input_handler)

	-- v2.50: Debug logging
end

-- === MODIFIER TEXT ===
function CSRForcedModsNotification:get_modifier_text(mod)
	local name = "Unknown Modifier"
	local desc = ""

	if managers.localization then
		local clean_id = mod.id:gsub("^csr_", "")

		local base_id = clean_id
		local is_stealth_tiered = clean_id:find("^less_pagers_") or clean_id:find("^civilian_alarm_")

		if not is_stealth_tiered then
			base_id = clean_id:gsub("_(%d+)$", "")
		end

		local name_key = "menu_cs_modifier_" .. base_id
		local text = managers.localization:text(name_key)

		if text and not text:find("ERROR", 1, true) then
			local lines = {}
			for line in text:gmatch("[^\n]+") do
				table.insert(lines, line)
			end

			if #lines >= 2 then
				name = lines[1]
				desc = lines[2]
			else
				name = text
				desc = ""
			end
		else
			name = clean_id:gsub("_", " "):upper()
			desc = ""

			local mod_data = self:get_modifier_data(mod)
			if mod_data and mod_data.description then
				desc = mod_data.description
			end
		end
	else
		local clean_id = mod.id:gsub("^csr_", "")
		name = clean_id:gsub("_", " "):upper()
		desc = ""
	end

	return name, desc
end

-- === MODIFIER DATA ===
function CSRForcedModsNotification:get_modifier_data(mod)
	local mod_data = nil

	if managers and managers.crime_spree then
		local ok, result = pcall(function()
			return managers.crime_spree:get_modifier(mod.id)
		end)
		if ok then
			mod_data = result
		end
	end

	if not mod_data and _G.CSR_ForcedModifierLookup then
		mod_data = _G.CSR_ForcedModifierLookup[mod.id]
	end

	-- Fuzzy match by base ID: host/client may have different level suffixes
	-- e.g. host sends "medic_bulldozer_25" but client has "medic_bulldozer_50"
	if not mod_data and _G.CSR_ForcedModifierLookup then
		local base_id = mod.id:match("^(.+)_%d+$")
		if base_id then
			for lookup_id, lookup_data in pairs(_G.CSR_ForcedModifierLookup) do
				local lookup_base = lookup_id:match("^(.+)_%d+$")
				if lookup_base and lookup_base == base_id then
					mod_data = lookup_data
					break
				end
			end
		end
	end

	return mod_data
end

-- Stealth modifier prefixes (everything else is loud)
local STEALTH_PREFIXES = { "csr_less_pagers_", "csr_civilian_alarm_", "csr_less_concealment_" }

local function is_stealth_modifier(mod_id)
	if not mod_id then
		return false
	end
	for _, prefix in ipairs(STEALTH_PREFIXES) do
		if string.find(mod_id, prefix, 1, true) == 1 then
			return true
		end
	end
	return false
end

-- === CREATE A SINGLE CARD ===
function CSRForcedModsNotification:_create_card(parent, mod, x, y, w, h)
	local name, desc = self:get_modifier_text(mod)
	local mod_data = self:get_modifier_data(mod)

	local card = parent:panel({
		x = x,
		y = y,
		w = w,
		h = h,
		layer = 5,
	})

	card:rect({ color = Color(0.2, 0.2, 0.2), alpha = 0.8, layer = 0 })
	card:rect({ color = Color.white, alpha = 0.1, h = 1, blend_mode = "add", layer = 1 })

	-- Icon
	local icon_size = 48
	local text_x = 70

	if mod_data and mod_data.icon then
		local ok, icon_texture, icon_rect = pcall(function()
			return tweak_data.hud_icons:get_icon_data(mod_data.icon)
		end)
		if ok and icon_texture then
			card:bitmap({
				texture = icon_texture,
				texture_rect = icon_rect,
				w = icon_size,
				h = icon_size,
				x = 10,
				y = (h - icon_size) / 2,
				color = Color.white,
				layer = 10,
			})
		end
	end

	-- Name
	local text_w = w - text_x - 10
	card:text({
		text = name,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = Color.white,
		x = text_x,
		y = 8,
		w = text_w,
		h = 20,
		layer = 10,
		wrap = true,
		word_wrap = true,
	})

	-- Description
	card:text({
		text = desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = 18,
		color = Color(0.7, 0.7, 0.7),
		x = text_x,
		y = 32,
		w = text_w,
		h = h - 32 - 5,
		layer = 10,
		wrap = true,
		word_wrap = true,
	})

	return card
end

-- === POPULATE MODIFIER CARDS (two columns: stealth left, loud right) ===
-- Cards are created on self._cards_canvas (inside the clipping _cards_panel)
function CSRForcedModsNotification:populate_modifiers(modifiers)
	local stealth = {}
	local loud = {}
	for _, mod in ipairs(modifiers) do
		if is_stealth_modifier(mod.id) then
			table.insert(stealth, mod)
		else
			table.insert(loud, mod)
		end
	end

	local canvas = self._cards_canvas
	local header_parent = self._panel -- headers on main panel (fixed, above scroll area)
	local header_font_size = 18
	local header_icon_size = header_font_size
	local icon_gap = 4
	local header_row_h = 30
	local card_height = 100
	local card_spacing = 8
	local col_gap = 16
	local side_margin = 20
	local col_w = (canvas:w() - side_margin * 2 - col_gap) / 2
	local left_x = side_margin
	local right_x = side_margin + col_w + col_gap

	-- Column headers: on _cards_panel (fixed), above the scrolling canvas
	local function add_column_header(col_x, texture, label)
		local tmp = header_parent:text({
			text = label,
			font = tweak_data.menu.pd2_medium_font,
			font_size = header_font_size,
		})
		local _, _, tw, _ = tmp:text_rect()
		header_parent:remove(tmp)

		local group_w = header_icon_size + icon_gap + tw
		local gx = col_x + (col_w - group_w) / 2

		local hy = self._header_labels_y or 78
		pcall(function()
			header_parent:bitmap({
				texture = texture,
				w = header_icon_size,
				h = header_icon_size,
				x = gx,
				y = hy + (header_font_size - header_icon_size) / 2,
				color = Color.white,
				layer = 10,
			})
		end)
		header_parent:text({
			text = label,
			font = tweak_data.menu.pd2_medium_font,
			font_size = header_font_size,
			color = Color(0.7, 0.7, 0.7),
			x = gx + header_icon_size + icon_gap,
			y = hy,
			w = tw + 10,
			layer = 10,
		})
	end

	if #loud > 0 then
		add_column_header(left_x, "guis/textures/pd2/cn_playstyle_loud", "LOUD")
	end
	if #stealth > 0 then
		add_column_header(right_x, "guis/textures/pd2/cn_playstyle_stealth", "STEALTH")
	end

	-- Cards start at y=0 inside canvas (headers are on main panel, not here)
	for i, mod in ipairs(loud) do
		local cy = (i - 1) * (card_height + card_spacing)
		self:_create_card(canvas, mod, left_x, cy, col_w, card_height)
	end

	for i, mod in ipairs(stealth) do
		local cy = (i - 1) * (card_height + card_spacing)
		self:_create_card(canvas, mod, right_x, cy, col_w, card_height)
	end

	-- Store counts for height calculation
	self._stealth_count = #stealth
	self._loud_count = #loud
end

-- === CALCULATE HEIGHT ===
function CSRForcedModsNotification:calculate_height(num_mods)
	local header_height = 115
	local footer_height = 100
	local card_height = 100
	local card_spacing = 8

	-- Two columns: height is driven by the taller column
	-- At this point we don't know the split yet, so estimate with ceiling of half
	local max_per_col = math.ceil(num_mods / 2)
	local cards_total = max_per_col * card_height + math.max(max_per_col - 1, 0) * card_spacing
	return header_height + cards_total + footer_height
end

-- Precise height after populate_modifiers has run (knows actual column counts)
function CSRForcedModsNotification:_actual_height()
	return 110 + self:_cards_only_height() + 90
end

-- Height of just the scrollable cards
function CSRForcedModsNotification:_cards_only_height()
	local card_height = 100
	local card_spacing = 8
	local max_col = math.max(self._stealth_count or 0, self._loud_count or 0, 1)
	return max_col * card_height + math.max(max_col - 1, 0) * card_spacing
end

-- === FADE-IN ===
function CSRForcedModsNotification:animate_fade_in()
	self._panel:animate(function(panel)
		local fade_time = 0.3
		local t = 0
		while t < fade_time do
			local dt = coroutine.yield()
			t = t + dt
			local progress = t / fade_time

			if alive(panel) then
				panel:set_alpha(math.lerp(0, 1, progress))
			end

			if alive(self._backdrop) then
				self._backdrop:set_alpha(math.lerp(0, 0.6, progress))
			end
		end

		if alive(panel) then
			panel:set_alpha(1)
		end
		if alive(self._backdrop) then
			self._backdrop:set_alpha(0.6)
		end
	end)
end

-- === CLEANUP ===
function CSRForcedModsNotification:_destroy_gui()
	if self._owns_ws then
		-- We created these workspaces, destroy them
		if self._ws then
			managers.gui_data:destroy_workspace(self._ws)
			self._ws = nil
		end
		if self._fullscreen_ws then
			managers.gui_data:destroy_workspace(self._fullscreen_ws)
			self._fullscreen_ws = nil
		end
	else
		-- Shared workspaces (menu's), only remove our panels
		if self._fullscreen_ws and alive(self._fullscreen_ws:panel()) then
			if alive(self._backdrop) then
				self._fullscreen_ws:panel():remove(self._backdrop)
			end
			if alive(self._panel) then
				self._fullscreen_ws:panel():remove(self._panel)
			end
		end
		self._ws = nil
		self._fullscreen_ws = nil
	end
end

-- === CLOSE ===
function CSRForcedModsNotification:close()
	-- Remove hooks FIRST (both in-game and menu)
	Hooks:Remove(HOOK_ID)
	Hooks:Remove(MENU_HOOK_ID)

	-- Clear global reference immediately
	if _G.CSR_ForcedModsNotificationInstance == self then
		_G.CSR_ForcedModsNotificationInstance = nil
	end

	-- Remove backdrop IMMEDIATELY (it covers the entire screen and blocks input)
	-- Must not wait for animation — removing panel inside its own animate() can fail
	if alive(self._backdrop) then
		pcall(function()
			self._fullscreen_ws:panel():remove(self._backdrop)
		end)
		self._backdrop = nil
	end

	if alive(self._panel) then
		self._panel:animate(function(panel)
			local fade_time = 0.2
			local t = 0

			while t < fade_time do
				local dt = coroutine.yield()
				t = t + dt
				local progress = t / fade_time

				if alive(panel) then
					panel:set_alpha(math.lerp(1, 0, progress))
				end
			end

			-- Remove main panel after fade
			if self._owns_ws then
				if self._ws then
					managers.gui_data:destroy_workspace(self._ws)
					self._ws = nil
				end
				if self._fullscreen_ws then
					managers.gui_data:destroy_workspace(self._fullscreen_ws)
					self._fullscreen_ws = nil
				end
			else
				if self._fullscreen_ws and alive(self._fullscreen_ws:panel()) and alive(panel) then
					self._fullscreen_ws:panel():remove(panel)
				end
			end
		end)
	else
		self:_destroy_gui()
	end
end

-- === SCROLL CONTENT ===
function CSRForcedModsNotification:scroll_content(delta)
	if not self._max_scroll or self._max_scroll <= 0 then
		return
	end
	if not self._cards_canvas or not alive(self._cards_canvas) then
		return
	end

	local old_offset = self._scroll_offset or 0
	local new_offset = math.clamp(old_offset + delta, 0, self._max_scroll)
	if math.abs(new_offset - old_offset) < 0.5 then
		return
	end

	self._scroll_offset = new_offset

	-- Move the canvas inside the clipping panel (negative y = scrolled down)
	self._cards_canvas:set_y(-new_offset)

	-- Update scrollbar position
	if self._scrollbar and alive(self._scrollbar) and self._scrollbar_range and self._scrollbar_range > 0 then
		local ratio = new_offset / self._max_scroll
		local cards_top = self._cards_panel:y()
		self._scrollbar:set_y(cards_top + 4 + ratio * self._scrollbar_range)
	end
end

-- === BUTTON HIT TEST ===
-- Mouse coords are in saferect space, button is in fullscreen space
-- Convert mouse coords by adding the saferect-to-fullscreen offset
function CSRForcedModsNotification:_is_inside_button(x, y)
	if not alive(self._close_button) then
		return false
	end
	local fx = x + (self._safe_offset_x or 0)
	local fy = y + (self._safe_offset_y or 0)
	local bx, by = self._close_button:world_position()
	local bw, bh = self._close_button:size()
	return fx >= bx and fx <= bx + bw and fy >= by and fy <= by + bh
end

-- === MOUSE MOVED ===
function CSRForcedModsNotification:mouse_moved(x, y)
	if not alive(self._panel) then
		return false, "arrow"
	end

	local is_hover = self:_is_inside_button(x, y)

	if alive(self._button_highlight) then
		self._button_highlight:set_alpha(is_hover and 0.2 or 0)
	end

	return is_hover, is_hover and "link" or "arrow"
end

-- === MOUSE PRESSED (blocks clicks behind popup) ===
function CSRForcedModsNotification:mouse_pressed(button, x, y)
	if not alive(self._panel) then
		return false
	end

	if self:_is_inside_button(x, y) then
		self:close()
		return true
	end

	-- Block all other clicks
	return true
end
