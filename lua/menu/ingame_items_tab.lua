-- Crime Spree Roguelike - In-game pause menu: MODIFIERS / ITEMS tabs.
-- Adds an ITEMS tab to the Crime Spree contract gui shown when opening the
-- ESC pause menu during a heist. Shows every player's items (like briefing).

if not RequiredScript then
	return
end

if not IngameContractGuiCrimeSpree then
	return
end

local RARITY_COLOR_COMMON = Color.white
local RARITY_COLOR_UNCOMMON = Color(0, 0.95, 0)
local RARITY_COLOR_RARE = Color(0.3, 0.7, 1)
local RARITY_COLOR_CONTRABAND = Color(1, 0.4, 0)
local RARITY_COLOR_WILDCARD = Color(1, 0.3, 0.8)

-- Right-column wildcard slot. Mirrors items_page.lua positional logic:
-- the slot is a square cell derived from per-player section height
-- (section_h * RATIO), and is vertically centered within its section. In
-- singleplayer, the same per-section height is used so the wildcard reads
-- the same physical size in both modes. Carry-1, so the slot only ever
-- holds one icon (or an empty magenta placeholder).
-- Fraction of a per-player section height used for the (square) wildcard
-- slot. Tunable: higher = bigger wildcard icon in the ESC items tab. 0.9
-- leaves a small margin so it can't overflow into the next peer's section
-- in the 4-up MP layout.
local WILDCARD_SLOT_RATIO = 0.9
local WILDCARD_SLOT_GAP = 8
local WILDCARD_SLOT_RIGHT_PAD = 8
local WILDCARD_MAIN_GRID_LEFT_PAD = 8
local WILDCARD_ICON_FRAME_RATIO = 0.5
local WILDCARD_PLACEHOLDER_COLOR = Color(0.35, 1, 0.3, 0.8) -- dim magenta (alpha, r, g, b)

-- Sub-tab constants for the modifiers LOUD / STEALTH row (mirrors modifiers_subtabs.lua)
local SUBTAB_H = tweak_data.menu.pd2_medium_font_size + 12
local SUBTAB_H_PAD = 14
local SUBTAB_GAP = 24
local SUBTAB_PADDING = 10

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

local function split_loud_stealth(modifiers)
	local loud, stealth = {}, {}
	for _, mod in ipairs(modifiers) do
		if is_stealth_modifier(mod.id) then
			table.insert(stealth, mod)
		else
			table.insert(loud, mod)
		end
	end
	return loud, stealth
end

local function create_mod_subtab_btn(parent, text_str, x, active)
	local btn = parent:panel({ x = x, y = 0, h = SUBTAB_H, layer = 7 })
	local lbl = btn:text({
		name = "label",
		text = text_str,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = active and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3,
		layer = 8,
	})
	BlackMarketGui.make_fine_text(nil, lbl)
	local tw, th = lbl:w(), lbl:h()
	local pw = tw + SUBTAB_H_PAD * 2
	btn:set_w(pw)
	lbl:set_x((pw - tw) * 0.5)
	lbl:set_y((SUBTAB_H - th) * 0.5)
	btn:rect({
		name = "underline",
		h = 2,
		w = pw - 6,
		x = 3,
		y = SUBTAB_H - 3,
		color = tweak_data.screen_colors.button_stage_2,
		visible = active,
		layer = 9,
	})
	return btn, pw
end

local function set_mod_subtab_active(btn, active)
	if not btn or not alive(btn) then
		return
	end
	local lbl = btn:child("label")
	local ul = btn:child("underline")
	if lbl then
		lbl:set_color(active and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3)
	end
	if ul then
		ul:set_visible(active)
	end
end

local function setup_modifiers_subtabs(self, mp)
	if not CrimeSpreeModifierDetailsPage then
		return
	end
	CSR_FilterForUI = true
	local all_mods = managers.crime_spree:server_active_modifiers() or {}
	CSR_FilterForUI = false
	local loud_mods, stealth_mods = split_loud_stealth(all_mods)

	mp:clear()
	self._scroll = nil

	local tabs_row = mp:panel({ x = 0, y = 0, w = mp:w(), h = SUBTAB_H, layer = 10 })
	tabs_row:rect({
		name = "divider",
		h = 1,
		w = tabs_row:w(),
		y = SUBTAB_H - 1,
		color = Color(1, 0.25, 0.25, 0.25),
		layer = 6,
	})

	local loud_btn, loud_w = create_mod_subtab_btn(tabs_row, "LOUD", SUBTAB_PADDING, true)
	local stealth_btn = create_mod_subtab_btn(tabs_row, "STEALTH", SUBTAB_PADDING + loud_w + SUBTAB_GAP, false)

	local scroll_y = SUBTAB_H + SUBTAB_GAP
	local scroll_h = mp:h() - scroll_y

	local loud_cont = mp:panel({ x = 0, y = scroll_y, w = mp:w(), h = scroll_h })
	local stealth_cont = mp:panel({ x = 0, y = scroll_y, w = mp:w(), h = scroll_h })

	CrimeSpreeModifierDetailsPage.add_modifiers_panel(self, loud_cont, loud_mods, false)
	local loud_scroll = self._scroll

	CrimeSpreeModifierDetailsPage.add_modifiers_panel(self, stealth_cont, stealth_mods, false)
	local stealth_scroll = self._scroll

	stealth_cont:set_visible(false)
	self._scroll = loud_scroll

	self._csr_mod_subtab = "loud"
	self._csr_mod_loud_scroll = loud_scroll
	self._csr_mod_stealth_scroll = stealth_scroll
	self._csr_mod_loud_cont = loud_cont
	self._csr_mod_stealth_cont = stealth_cont
	self._csr_mod_loud_btn = loud_btn
	self._csr_mod_stealth_btn = stealth_btn
end

local function switch_mod_subtab(self, tab)
	if self._csr_mod_subtab == tab then
		return
	end
	self._csr_mod_subtab = tab
	local is_loud = tab == "loud"
	if self._csr_mod_loud_cont and alive(self._csr_mod_loud_cont) then
		self._csr_mod_loud_cont:set_visible(is_loud)
	end
	if self._csr_mod_stealth_cont and alive(self._csr_mod_stealth_cont) then
		self._csr_mod_stealth_cont:set_visible(not is_loud)
	end
	self._scroll = is_loud and self._csr_mod_loud_scroll or self._csr_mod_stealth_scroll
	set_mod_subtab_active(self._csr_mod_loud_btn, is_loud)
	set_mod_subtab_active(self._csr_mod_stealth_btn, not is_loud)
end

-- Re-implementation of the items_page cell-size calculation (independent copy
-- so briefing and in-game don't share internal state).
local function calc_cell_size(item_count, avail_w, avail_h, max_cell, min_cell)
	if item_count <= 0 then
		return max_cell
	end
	local cell = max_cell
	while cell > min_cell do
		local cols = math.max(1, math.floor(avail_w / cell))
		local rows = math.ceil(item_count / cols)
		if rows * cell <= avail_h then
			return cell
		end
		cell = cell - 2
	end
	return min_cell
end

local function render_grid(content, items, start_x, start_y, cell_size, positions, peer_id, area_w, force_single_col)
	local ICON_SCALE = _G.CSR_IconScale or {}
	local frame_size = cell_size + 2
	local DEFAULT_FRAME = 74
	local icon_size = math.floor(38 * (frame_size / DEFAULT_FRAME))
	local content_w = area_w or (content:w() - start_x)
	local icons_per_row
	if force_single_col then
		icons_per_row = 1
	else
		icons_per_row = math.max(1, math.floor(content_w / cell_size))
	end

	for i, item in ipairs(items) do
		local col = (i - 1) % icons_per_row
		local row = math.floor((i - 1) / icons_per_row)
		local x = start_x + col * cell_size
		local y = start_y + row * cell_size

		if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
			local fd = tweak_data.hud_icons[item.frame]
			content:bitmap({
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				w = frame_size,
				h = frame_size,
				x = x,
				y = y,
				color = item.color or Color.white,
				layer = 0,
			})
		end

		if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
			local id = tweak_data.hud_icons[item.icon]
			local this_size = icon_size * (ICON_SCALE[item.icon] or 1)
			local off = (frame_size - this_size) / 2
			content:bitmap({
				texture = id.texture,
				texture_rect = id.texture_rect,
				w = this_size,
				h = this_size,
				x = x + off,
				y = y + off,
				color = Color.white,
				layer = 2,
			})
		end

		if item.stacks and item.stacks >= 1 then
			local s = "x" .. tostring(item.stacks)
			local tx = x + frame_size - 30 - 4
			for dx = -1, 1 do
				for dy = -1, 1 do
					if not (dx == 0 and dy == 0) then
						content:text({
							text = s,
							font = tweak_data.menu.pd2_medium_font,
							font_size = 16,
							color = Color.black,
							x = tx + dx,
							y = y + dy,
							w = 30,
							layer = 4,
							align = "right",
							vertical = "top",
						})
					end
				end
			end
			content:text({
				text = s,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 16,
				color = Color.white,
				x = tx,
				y = y,
				w = 30,
				layer = 5,
				align = "right",
				vertical = "top",
			})
		end

		table.insert(positions, {
			x1 = x,
			y1 = y,
			x2 = x + frame_size,
			y2 = y + frame_size,
			item = item,
			peer_id = peer_id,
		})
	end

	local rows = math.ceil(#items / icons_per_row)
	return start_y + rows * cell_size
end

-- Split a flat items list into (regular, wildcards). Wildcards are tagged
-- via build_items_for_peer with is_wildcard=true.
local function split_wildcards(items)
	local regular, wildcards = {}, {}
	for _, item in ipairs(items) do
		if item.is_wildcard then
			table.insert(wildcards, item)
		else
			table.insert(regular, item)
		end
	end
	return regular, wildcards
end

-- Render the right-column wildcard slot. If `wildcards` is non-empty, draws
-- the owned wildcard (frame + icon, with hit detection so the tooltip works).
-- Otherwise draws a dim magenta hexagon as a reserved-but-empty placeholder.
-- Carry-1, so at most one icon ever shown.
local function render_wildcard_cell(content, wildcards, slot_x, slot_y, slot_w, slot_h, positions, peer_id)
	local frame_size = math.min(slot_w, slot_h)
	local x = slot_x + math.floor((slot_w - frame_size) / 2)
	local y = slot_y + math.floor((slot_h - frame_size) / 2)

	if #wildcards == 0 then
		if tweak_data.hud_icons and tweak_data.hud_icons.csr_frame then
			local fd = tweak_data.hud_icons.csr_frame
			content:bitmap({
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				w = frame_size,
				h = frame_size,
				x = x,
				y = y,
				color = WILDCARD_PLACEHOLDER_COLOR,
				layer = 0,
			})
		end
		return
	end

	local item = wildcards[1]
	local icon_size = math.floor(frame_size * WILDCARD_ICON_FRAME_RATIO)
	local ICON_SCALE = _G.CSR_IconScale or {}

	if positions then
		table.insert(positions, {
			x1 = x,
			y1 = y,
			x2 = x + frame_size,
			y2 = y + frame_size,
			item = item,
			peer_id = peer_id,
		})
	end

	if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
		local fd = tweak_data.hud_icons[item.frame]
		content:bitmap({
			texture = fd.texture,
			texture_rect = fd.texture_rect,
			w = frame_size,
			h = frame_size,
			x = x,
			y = y,
			color = item.color or Color.white,
			layer = 0,
		})
	end

	if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
		local id = tweak_data.hud_icons[item.icon]
		local sz = icon_size * (ICON_SCALE[item.icon] or 1)
		local off = (frame_size - sz) / 2
		content:bitmap({
			texture = id.texture,
			texture_rect = id.texture_rect,
			w = sz,
			h = sz,
			x = x + off,
			y = y + off,
			color = Color.white,
			layer = 2,
		})
	end
end

local function populate_items_panel(self, items_panel)
	items_panel:clear()
	self._csr_item_positions = {}

	if not _G.CSR_BuildItemsForPeer or not _G.CSR_PlayerItems then
		items_panel:text({
			text = "Items unavailable.",
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 10,
			y = 10,
		})
		return
	end

	-- Debug toggle: render the items tab as if 4 players are present.
	local fake_4 = _G.CSR_DEBUG_FAKE_4_PLAYERS == true
	local peer_ids = {}
	if fake_4 then
		peer_ids = { 1, 2, 3, 4 }
	else
		for pid, _ in pairs(_G.CSR_PlayerItems) do
			table.insert(peer_ids, pid)
		end
		table.sort(peer_ids)
	end

	local in_mp = fake_4 or (_G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer())
	local local_peer_id = CSR_LocalPeerId and CSR_LocalPeerId() or 1

	-- Singleplayer: just render local items
	if not in_mp then
		local items = CSR_BuildItemsForPeer(local_peer_id)
		local regular, wildcards = split_wildcards(items)

		-- Use the same per-section formula as the MP path so the wildcard slot
		-- has the same physical size in SP and MP.
		local section_gap = 6
		local section_h = math.floor((items_panel:h() - 3 * section_gap) / 4)
		local wildcard_slot_size = math.floor(section_h * WILDCARD_SLOT_RATIO)
		local main_w = items_panel:w()
			- 20
			- WILDCARD_MAIN_GRID_LEFT_PAD
			- wildcard_slot_size
			- WILDCARD_SLOT_GAP
			- WILDCARD_SLOT_RIGHT_PAD
		local grid_x = 10 + WILDCARD_MAIN_GRID_LEFT_PAD
		local slot_x = grid_x + main_w + WILDCARD_SLOT_GAP

		if #regular > 0 then
			local cell = calc_cell_size(#regular, main_w, items_panel:h() - 10, 72, 24)
			render_grid(items_panel, regular, grid_x, 10, cell, self._csr_item_positions, local_peer_id, main_w)
		elseif #wildcards == 0 then
			items_panel:text({
				text = managers.localization:text("menu_csr_items_placeholder"),
				font = tweak_data.menu.pd2_medium_font,
				font_size = 20,
				color = Color(0.5, 0.5, 0.5),
				x = 10,
				y = 10,
			})
		end

		-- Square wildcard cell, vertically centered in the panel — mirrors
		-- briefing items_page.lua SP layout.
		local slot_y = math.floor((items_panel:h() - wildcard_slot_size) / 2)
		render_wildcard_cell(
			items_panel,
			wildcards,
			slot_x,
			slot_y,
			wildcard_slot_size,
			wildcard_slot_size,
			self._csr_item_positions,
			local_peer_id
		)
		return
	end

	-- Multiplayer: section per peer with header
	local any = fake_4
	for _, pid in ipairs(peer_ids) do
		local d = _G.CSR_PlayerItems[pid]
		if d and d.items and #d.items > 0 then
			any = true
			break
		end
	end
	if not any then
		items_panel:text({
			text = managers.localization:text("menu_csr_items_placeholder"),
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 10,
			y = 10,
		})
		return
	end

	local section_gap = 6
	local header_h = 20
	local total_h = items_panel:h()
	local section_h = math.floor((total_h - 3 * section_gap) / 4)
	local grid_h = section_h - header_h
	local wildcard_slot_size = math.floor(section_h * WILDCARD_SLOT_RATIO)
	local MIN_CELL = 20

	for idx, pid in ipairs(peer_ids) do
		local data = _G.CSR_PlayerItems[pid]
		if fake_4 and not data then
			data = { items = {}, name = "DEBUG Player " .. pid }
		end
		if data then
			local source_pid = (fake_4 and not _G.CSR_PlayerItems[pid]) and local_peer_id or pid
			local items = CSR_BuildItemsForPeer(source_pid)
			local section_y = (idx - 1) * (section_h + section_gap)

			if idx > 1 then
				items_panel:rect({
					x = 10,
					y = section_y - math.floor(section_gap / 2),
					w = items_panel:w() - 20,
					h = 1,
					color = Color(1, 0.4, 0.4, 0.4),
					layer = 1,
				})
			end

			local player_name
			local session = managers.network and managers.network:session()
			if session then
				local peer = (pid == local_peer_id) and session:local_peer() or session:peer(pid)
				player_name = peer and peer:name()
			end
			if not player_name or player_name == "" then
				player_name = (data.name and data.name ~= "") and data.name or ("Player " .. pid)
			end

			local peer_vec = tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[pid]
			local header_color = Color.white
			if peer_vec then
				local r, g, b = peer_vec.x, peer_vec.y, peer_vec.z
				local grey = (r + g + b) / 3
				local sat = 1.5
				header_color = Color(
					1,
					math.min(math.max(grey + (r - grey) * sat, 0), 1),
					math.min(math.max(grey + (g - grey) * sat, 0), 1),
					math.min(math.max(grey + (b - grey) * sat, 0), 1)
				)
			end

			items_panel:text({
				text = player_name,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 16,
				color = header_color,
				x = 10,
				y = section_y,
				layer = 1,
			})

			local grid_y = section_y + header_h

			-- Split wildcards out for the dedicated right-column slot.
			local regular, wildcards = split_wildcards(items)
			local main_w = items_panel:w()
				- 20
				- WILDCARD_MAIN_GRID_LEFT_PAD
				- wildcard_slot_size
				- WILDCARD_SLOT_GAP
				- WILDCARD_SLOT_RIGHT_PAD
			local grid_x = 10 + WILDCARD_MAIN_GRID_LEFT_PAD
			local slot_x = grid_x + main_w + WILDCARD_SLOT_GAP

			if #regular > 0 then
				local start_cell = math.min(72, grid_h)
				local cell = calc_cell_size(#regular, main_w, grid_h, start_cell, MIN_CELL)
				render_grid(items_panel, regular, grid_x, grid_y, cell, self._csr_item_positions, pid, main_w)
			elseif #wildcards == 0 then
				items_panel:text({
					text = "No items yet",
					font = tweak_data.menu.pd2_small_font,
					font_size = 14,
					color = Color(0.45, 0.45, 0.45),
					x = 10,
					y = grid_y,
					layer = 1,
				})
			end

			-- Wildcard cell is vertically centered against THIS player's
			-- item grid band (grid_y .. grid_y+grid_h), i.e. below the
			-- name header — not the section and not the whole panel.
			local slot_y = grid_y + math.floor((grid_h - wildcard_slot_size) / 2)
			render_wildcard_cell(
				items_panel,
				wildcards,
				slot_x,
				slot_y,
				wildcard_slot_size,
				wildcard_slot_size,
				self._csr_item_positions,
				pid
			)
		end
	end
end

local function set_tab(self, which)
	self._csr_active_tab = which
	-- Remember across pause-menu open/close so the user returns to the same tab
	_G.CSR_IngameLastTab = which
	if self._modifiers_panel and alive(self._modifiers_panel) then
		self._modifiers_panel:set_visible(which == "modifiers")
	end
	if self._csr_items_panel and alive(self._csr_items_panel) then
		self._csr_items_panel:set_visible(which == "items")
	end
	local active_color = tweak_data.screen_colors.button_stage_3 or Color.white
	local inactive_color = Color(0.7, 0.7, 0.7)
	if self._csr_tab_modifiers then
		self._csr_tab_modifiers:set_color(which == "modifiers" and active_color or inactive_color)
	end
	if self._csr_tab_items then
		self._csr_tab_items:set_color(which == "items" and active_color or inactive_color)
	end
	if self._csr_tooltip and alive(self._csr_tooltip) and which ~= "items" then
		self._csr_tooltip:set_visible(false)
	end
end

Hooks:PostHook(IngameContractGuiCrimeSpree, "init", "CSR_AddItemsTab", function(self, ws, node)
	if not self._panel or not alive(self._panel) then
		return
	end
	if not self._modifiers_panel then
		return
	end

	local text_panel = self._text_panel
	if not text_panel or not alive(text_panel) then
		return
	end

	-- Replace vanilla modifiers_title with two clickable tab labels.
	-- Vanilla title is already drawn; find and remove it if we can, otherwise
	-- just overlay our labels in the same spot.
	local mp = self._modifiers_panel
	local tab_y = mp:y() - 24

	local tab_items = text_panel:text({
		name = "csr_tab_items",
		text = utf8.to_upper(managers.localization:text("menu_csr_items")) .. ":",
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.button_stage_3 or Color.white,
		x = 0,
		y = tab_y,
		layer = 2,
	})
	local _, _, iw, ih = tab_items:text_rect()
	tab_items:set_size(iw, ih)

	local tab_modifiers = text_panel:text({
		name = "csr_tab_modifiers",
		text = utf8.to_upper(managers.localization:text("cn_crime_spree_modifiers")),
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color(0.7, 0.7, 0.7),
		x = iw + 20,
		y = tab_y,
		layer = 2,
	})
	local _, _, tw, th = tab_modifiers:text_rect()
	tab_modifiers:set_size(tw, th)

	-- Hide any vanilla modifiers_title text children that overlap our tabs
	for _, c in ipairs(text_panel:children()) do
		if c ~= tab_modifiers and c ~= tab_items and c.text and c.set_visible then
			local ok, s = pcall(function()
				return c:text()
			end)
			if
				ok
				and s
				and utf8.to_upper(s) == utf8.to_upper(managers.localization:text("cn_crime_spree_modifiers"))
			then
				c:set_visible(false)
			end
		end
	end

	self._csr_tab_modifiers = tab_modifiers
	self._csr_tab_items = tab_items

	-- Items panel sits where modifiers panel sits
	local items_panel = self._panel:panel({
		name = "csr_items_panel",
		x = mp:x(),
		y = mp:y(),
		w = mp:w(),
		h = mp:h(),
		visible = false,
	})
	self._csr_items_panel = items_panel

	populate_items_panel(self, items_panel)

	-- Tooltip on the top-level workspace panel so it can overflow
	self._csr_tooltip = self._panel:panel({
		name = "csr_items_tooltip",
		visible = false,
		layer = 100,
	})

	setup_modifiers_subtabs(self, mp)

	-- Restore whichever tab was active last time the pause menu was open.
	-- Defaults to "items" on the first open.
	local remembered = _G.CSR_IngameLastTab
	if remembered ~= "modifiers" and remembered ~= "items" then
		remembered = "items"
	end
	set_tab(self, remembered)
end)

local function hit_tab(tab_obj, x, y)
	if not tab_obj or not alive(tab_obj) then
		return false
	end
	return x >= tab_obj:world_x()
		and x <= tab_obj:world_x() + tab_obj:w()
		and y >= tab_obj:world_y()
		and y <= tab_obj:world_y() + tab_obj:h()
end

local function show_tooltip(self, item, anchor_x_world, anchor_y_world, peer_id)
	local tt = self._csr_tooltip
	if not tt or not alive(tt) then
		return
	end
	tt:clear()

	local w = 280
	local pad = 10

	local title = item.name
	local local_peer_id = CSR_LocalPeerId and CSR_LocalPeerId() or 1
	if peer_id and peer_id ~= local_peer_id then
		local session = managers.network and managers.network:session()
		local peer = session and session:peer(peer_id)
		local pname = peer and peer:name()
		if pname and pname ~= "" then
			title = pname .. ": " .. title
		end
	end

	local desc = tt:text({
		text = item.desc or "",
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		x = pad,
		y = pad + 25,
		w = w - pad * 2,
		wrap = true,
		word_wrap = true,
		layer = 2,
	})
	local _, _, _, dh = desc:text_rect()
	local h = pad + 25 + dh + pad

	-- Convert world anchor to _panel-local
	local px = anchor_x_world - self._panel:world_x() + 20
	local py = anchor_y_world - self._panel:world_y() + 10
	if px + w > self._panel:w() - 4 then
		px = self._panel:w() - w - 4
	end
	if py + h > self._panel:h() - 4 then
		py = self._panel:h() - h - 4
	end
	tt:set_shape(px, py, w, h)

	tt:rect({ color = Color.black, alpha = 0.9, layer = 0 })
	local bc = item.color or Color.white
	local bs = 2
	tt:rect({ x = 0, y = 0, w = w, h = bs, color = bc, alpha = 0.4, layer = 1 })
	tt:rect({ x = 0, y = h - bs, w = w, h = bs, color = bc, alpha = 0.4, layer = 1 })
	tt:rect({ x = 0, y = 0, w = bs, h = h, color = bc, alpha = 0.4, layer = 1 })
	tt:rect({ x = w - bs, y = 0, w = bs, h = h, color = bc, alpha = 0.4, layer = 1 })

	tt:text({
		text = title,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = item.color or Color.white,
		x = pad,
		y = pad,
		layer = 2,
	})

	tt:set_visible(true)
end

Hooks:PostHook(IngameContractGuiCrimeSpree, "mouse_pressed", "CSR_TabClick", function(self, button, x, y)
	if button ~= Idstring("0") then
		return
	end
	if not self._csr_tab_modifiers or not self._csr_tab_items then
		return
	end
	if hit_tab(self._csr_tab_modifiers, x, y) then
		set_tab(self, "modifiers")
	elseif hit_tab(self._csr_tab_items, x, y) then
		set_tab(self, "items")
		-- Refresh item data in case CSR_PlayerItems updated since init
		if self._csr_items_panel and alive(self._csr_items_panel) then
			populate_items_panel(self, self._csr_items_panel)
		end
	elseif self._csr_active_tab == "modifiers" and self._csr_mod_loud_btn then
		if alive(self._csr_mod_loud_btn) and self._csr_mod_loud_btn:inside(x, y) then
			switch_mod_subtab(self, "loud")
		elseif alive(self._csr_mod_stealth_btn) and self._csr_mod_stealth_btn:inside(x, y) then
			switch_mod_subtab(self, "stealth")
		end
	end
end)

Hooks:PostHook(IngameContractGuiCrimeSpree, "mouse_moved", "CSR_TabHover", function(self, o, x, y)
	if not self._csr_items_panel or not alive(self._csr_items_panel) then
		return
	end
	if self._csr_active_tab ~= "items" then
		if self._csr_tooltip and alive(self._csr_tooltip) and self._csr_tooltip:visible() then
			self._csr_tooltip:set_visible(false)
		end
		if self._csr_active_tab == "modifiers" and self._csr_mod_loud_btn then
			local loud_in = alive(self._csr_mod_loud_btn) and self._csr_mod_loud_btn:inside(x, y)
			local stealth_in = alive(self._csr_mod_stealth_btn) and self._csr_mod_stealth_btn:inside(x, y)
			if loud_in or stealth_in then
				return true, "link"
			end
		end
		return
	end

	local positions = self._csr_item_positions
	if not positions then
		return
	end
	local panel = self._csr_items_panel
	local wx = panel:world_x()
	local wy = panel:world_y()
	local lx = x - wx
	local ly = y - wy

	for _, pos in ipairs(positions) do
		if lx >= pos.x1 and lx <= pos.x2 and ly >= pos.y1 and ly <= pos.y2 then
			show_tooltip(self, pos.item, wx + pos.x2, wy + pos.y2, pos.peer_id)
			return
		end
	end
	if self._csr_tooltip and alive(self._csr_tooltip) and self._csr_tooltip:visible() then
		self._csr_tooltip:set_visible(false)
	end
end)

Hooks:PostHook(IngameContractGuiCrimeSpree, "close", "CSR_ClearItemsTab", function(self)
	self._csr_tab_modifiers = nil
	self._csr_tab_items = nil
	self._csr_items_panel = nil
	self._csr_tooltip = nil
	self._csr_item_positions = nil
	self._csr_active_tab = nil
	self._csr_mod_subtab = nil
	self._csr_mod_loud_scroll = nil
	self._csr_mod_stealth_scroll = nil
	self._csr_mod_loud_cont = nil
	self._csr_mod_stealth_cont = nil
	self._csr_mod_loud_btn = nil
	self._csr_mod_stealth_btn = nil
end)
