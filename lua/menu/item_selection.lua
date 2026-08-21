-- CSRItemSelectionComponent — data-driven fork of CrimeSpreeModifiersMenuComponent.
-- Opened by the lobby reminder click; rarity frame baked in (no per-frame PostHook hack).

if not RequiredScript then
	return
end

local padding = 10
local COMP_ID = "item_selection"

-- Returns the current card set from the frozen offer at the head of the peer's pending_offers.
-- Re-opening the same owed pick always sees the same offer until pop_offer is called.
local function csr_loc(s)
	if s and managers.localization then
		return managers.localization:text(s)
	end
	return s
end

local function build_item_pool()
	local mgr = managers and managers.csr
	local defs = {}
	if mgr and mgr.peek_offer and mgr.local_peer_id then
		defs = mgr:peek_offer(mgr:local_peer_id()) or {}
	end

	local items = {}
	for _, def in ipairs(defs) do
		items[#items + 1] = {
			id = def.type,
			icon = def.icon or "dog_tags",
			icon_scale = def.icon_scale or 1,
			rarity = def.rarity or "common",
			name = csr_loc(def.name) or string.upper(tostring(def.type)),
			desc = _G.CSR.item_text(def.desc, def) or "",
		}
	end

	if #items == 0 then
		-- Fallback: no offer stored yet, or all types were orphaned by addon removal.
		items[1] = {
			id = "none",
			icon = "dog_tags",
			rarity = "common",
			name = managers.localization:text("csr_item_selection_none_name"),
			desc = managers.localization:text("csr_item_selection_none_desc"),
		}
	end

	return items
end

-- Rarity tint per card (contraband excluded from selection pool by design).
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	wildcard = Color(1, 1, 0.3, 0.8),
}
-- Frame drawn larger than the icon container so it reads as a border.
local FRAME_SCALE = 2.0

-- ===================================================================
-- CSRItemSelectionButton — one selectable item card.
-- ===================================================================
CSRItemSelectionButton = CSRItemSelectionButton or class(MenuGuiItem)
CSRItemSelectionButton._type = "CSRItemSelectionButton"
CSRItemSelectionButton.size = {
	w = 208,
	h = 298,
}

function CSRItemSelectionButton:init(parent, data)
	self._data = data
	self._links = {}
	self._panel = parent:panel({
		layer = 1000,
		w = CSRItemSelectionButton.size.w,
		h = CSRItemSelectionButton.size.h,
	})

	local top_padding = padding * 4
	-- Base icon size; final size = _image_size * _size_modifier (idle) or _image_size (hover).
	self._image_size = 96
	self._size_modifier = 0.8
	self._image = self._panel:panel({
		y = top_padding,
		w = self._image_size,
		h = self._image_size,
	})

	self._image:set_center_x(self._panel:w() * 0.5)

	self._image_pos = {
		x = self._image:center_x(),
		y = self._image:center_y(),
	}

	-- Rarity frame on the button panel (not clipped by the icon panel); tracked in update().
	local frame_base = self._image_size * self._size_modifier * FRAME_SCALE
	self._frame = self._panel:bitmap({
		name = "rarity_frame",
		layer = 5,
		w = frame_base,
		h = frame_base,
	})
	self._frame:set_center(self._image_pos.x, self._image_pos.y)

	-- icon_scale shrinks/grows the glyph without touching the rarity frame (which tracks the container).
	self._item_image = self._image:bitmap({
		blend_mode = "add",
		name = "icon",
		layer = 10,
	})
	-- Anchor the name below the largest (hover) frame extent so the rarity border never crosses it.
	-- update() grows the frame to _image_size * FRAME_SCALE on hover; clear that, not the idle size.
	local label_gap = 4
	local frame_bottom_max = self._image_pos.y + self._image_size * FRAME_SCALE / 2
	self._name = self._panel:text({
		vertical = "top",
		wrap = false,
		align = "center",
		text = "",
		x = padding,
		y = frame_bottom_max + label_gap,
		w = self._panel:w() - padding * 2,
		h = tweak_data.menu.pd2_small_font_size,
		font_size = tweak_data.menu.pd2_small_font_size,
		font = tweak_data.menu.pd2_small_font,
		color = tweak_data.screen_colors.text,
	})
	local desc_y = self._name:bottom() + label_gap
	self._desc = self._panel:text({
		vertical = "top",
		wrap = true,
		align = "center",
		wrap_word = true,
		text = "",
		x = padding,
		y = desc_y,
		w = self._panel:w() - padding * 2,
		h = self._panel:h() - desc_y - padding,
		font_size = tweak_data.menu.pd2_small_font_size,
		font = tweak_data.menu.pd2_small_font,
		color = tweak_data.screen_colors.text,
	})
	self._highlight = self._panel:rect({
		blend_mode = "add",
		alpha = 0.4,
		layer = 10,
		color = tweak_data.screen_colors.button_stage_3,
	})

	BoxGuiObject:new(self._panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})

	self._active_outline = BoxGuiObject:new(self._panel, {
		sides = {
			2,
			2,
			2,
			2,
		},
	})

	self._image:set_size(self._image_size * self._size_modifier, self._image_size * self._size_modifier)
	self._image:set_center(self._image_pos.x, self._image_pos.y)
	self:refresh()
	self:set_item(data)
end

function CSRItemSelectionButton:set_item(data)
	self._data = data

	self._panel:set_visible(self._data ~= nil)

	if not self._data then
		return
	end

	local texture, rect = _G.CSR.icon_data(self._data.icon)

	self._item_image:set_image(texture)
	self._item_image:set_texture_rect(unpack(rect))
	self._icon_scale = self._data.icon_scale or 1
	self:_size_icon(self._image:w())
	self._name:set_text(self._data.name or "")
	self._desc:set_text(self._data.desc or "")

	local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")
	self._frame:set_image(frame_tex)
	self._frame:set_texture_rect(unpack(frame_rect))
	self._frame:set_color(RARITY_COLORS[self._data.rarity] or Color.white)
	self._frame:set_visible(true)
end

function CSRItemSelectionButton:_size_icon(container_size)
	if not self._item_image then
		return
	end
	local glyph = container_size * (self._icon_scale or 1)
	self._item_image:set_size(glyph, glyph)
	self._item_image:set_center(container_size * 0.5, container_size * 0.5)
end

function CSRItemSelectionButton:refresh()
	self._highlight:set_visible(self:is_selected() or self:is_active())
	self._active_outline:set_visible(self:is_active())
end

function CSRItemSelectionButton:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRItemSelectionButton:data()
	return self._data
end

function CSRItemSelectionButton:callback()
	return self._callback
end

function CSRItemSelectionButton:set_callback(clbk)
	self._callback = clbk
end

function CSRItemSelectionButton:get_link(dir)
	return self._links[dir]
end

function CSRItemSelectionButton:set_link(dir, item)
	self._links[dir] = item
end

function CSRItemSelectionButton:set_x(...)
	self._panel:set_x(...)
end

function CSRItemSelectionButton:set_y(...)
	self._panel:set_y(...)
end

function CSRItemSelectionButton:update(t, dt)
	local desired_size = self._image_size * ((self:is_selected() or self:is_active()) and 1 or 0.8)
	local s = self:smoothstep(self._image:w(), desired_size, 500 * dt, 100)

	self._image:set_size(s, s)
	self._image:set_center_x(self._image_pos.x)
	self._image:set_center_y(self._image_pos.y)

	self:_size_icon(s)

	if self._frame then
		local fs = s * FRAME_SCALE
		self._frame:set_size(fs, fs)
		self._frame:set_center(self._image_pos.x, self._image_pos.y)
	end
end

function CSRItemSelectionButton:smoothstep(a, b, step, n)
	local v = step / n
	v = 1 - (1 - v) * (1 - v)
	local x = a * (1 - v) + b * v

	return x
end

-- ===================================================================
-- CSRItemSelectionActionButton — FINALIZE / BACK text buttons.
-- ===================================================================
CSRItemSelectionActionButton = CSRItemSelectionActionButton or class(MenuGuiItem)
CSRItemSelectionActionButton._type = "CSRItemSelectionActionButton"

function CSRItemSelectionActionButton:init(parent, font, font_size)
	self._w = 0.35
	self._color = tweak_data.screen_colors.button_stage_3
	self._selected_color = tweak_data.screen_colors.button_stage_2
	self._links = {}
	self._panel = parent:panel({
		layer = 1000,
		x = parent:w() * (1 - self._w) - padding,
		w = parent:w() * self._w,
		h = font_size or tweak_data.menu.pd2_medium_font_size,
	})

	self._panel:set_bottom(parent:h())

	self._text = self._panel:text({
		y = 0,
		blend_mode = "add",
		align = "right",
		text = "",
		halign = "right",
		x = 0,
		layer = 1,
		color = self._color,
		font = font or tweak_data.menu.pd2_medium_font,
		font_size = font_size or tweak_data.menu.pd2_medium_font_size,
	})
	self._highlight = self._panel:rect({
		blend_mode = "add",
		alpha = 0.2,
		valign = "scale",
		halign = "scale",
		layer = 10,
		color = self._color,
	})

	self:refresh()
end

function CSRItemSelectionActionButton:refresh()
	self._highlight:set_visible(self:is_selected())
	self._highlight:set_color(self:is_selected() and self._selected_color or self._color)
	self._text:set_color(self:is_selected() and self._selected_color or self._color)
end

function CSRItemSelectionActionButton:panel()
	return self._panel
end

function CSRItemSelectionActionButton:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRItemSelectionActionButton:callback()
	return self._callback
end

function CSRItemSelectionActionButton:set_callback(clbk)
	self._callback = clbk
end

function CSRItemSelectionActionButton:set_button(btn)
	self._btn = btn
end

function CSRItemSelectionActionButton:set_text(text)
	local prefix = not managers.menu:is_pc_controller()
			and self._btn
			and managers.localization:get_default_macro(self._btn)
		or ""

	self._text:set_text(prefix .. text)
end

function CSRItemSelectionActionButton:get_link(dir)
	return self._links[dir]
end

function CSRItemSelectionActionButton:set_link(dir, item)
	self._links[dir] = item
end

function CSRItemSelectionActionButton:update(t, dt) end

function CSRItemSelectionActionButton:shrink_wrap_button(w_padding, h_padding)
	local _, _, w, h = self._text:text_rect()

	self._panel:set_size(w + (w_padding or 0), h + (h_padding or 0))
end

-- ===================================================================
-- CSRItemSelectionComponent — centred modal popup.
-- ===================================================================
CSRItemSelectionComponent = CSRItemSelectionComponent or class(MenuGuiComponentGeneric)

function CSRItemSelectionComponent:init(ws, fullscreen_ws, items, num_to_select)
	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()
	self._items = items or {}
	self._buttons = {}
	self._item_buttons = {}
	self._action_buttons = {}
	self._num_to_select = math.max(1, num_to_select or 1)
	self._current_num = 1

	self:_setup()

	-- This screen navigates with the d-pad/stick (move_up/down + confirm_pressed), so hide
	-- the lobby's virtual cursor while it is open. Ref-counted; restored in close().
	local menu = managers.menu:active_menu()
	if menu and menu.input and not managers.menu:is_pc_controller() then
		menu.input:deactivate_controller_mouse()
		self._csr_controller_mouse_off = true
	end
end

function CSRItemSelectionComponent:close()
	-- Restore the virtual cursor suppressed in init (balances the ref count).
	if self._csr_controller_mouse_off then
		local menu = managers.menu:active_menu()
		if menu and menu.input then
			menu.input:activate_controller_mouse()
		end
		self._csr_controller_mouse_off = nil
	end
	if self._owned_strip then
		self._owned_strip:destroy()
		self._owned_strip = nil
	end
	self._ws:panel():remove(self._panel)
	self._ws:panel():remove(self._text_header)
	self._ws:panel():remove(self._number_header)
	self._fullscreen_ws:panel():remove(self._fullscreen_panel)
end

function CSRItemSelectionComponent:_setup()
	local items = self._items
	local count = math.max(#items, 1)
	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = self._ws:panel():panel({
		layer = 51,
	})
	self._fullscreen_panel = self._fullscreen_ws:panel():panel({
		layer = 50,
	})

	self._fullscreen_panel:rect({
		alpha = 0.75,
		layer = 0,
		color = Color.black,
	})

	local blur = self._fullscreen_panel:bitmap({
		texture = "guis/textures/test_blur_df",
		render_template = "VertexColorTexturedBlur3D",
		w = self._fullscreen_ws:panel():w(),
		h = self._fullscreen_ws:panel():h(),
	})

	local function func(o)
		local start_blur = 0

		over(0.6, function(p)
			o:set_alpha(math.lerp(start_blur, 1, p))
		end)
	end

	blur:animate(func)

	local item_h = CSRItemSelectionButton.size.h
	local btn_size = tweak_data.menu.pd2_large_font_size

	self._panel:set_w((CSRItemSelectionButton.size.w + padding) * count + padding)
	self._panel:set_h(item_h + btn_size + padding * 3)
	self._panel:set_center_x(parent:center_x())
	self._panel:set_center_y(parent:center_y())
	self._panel:rect({
		alpha = 0.4,
		layer = -1,
		color = Color.black,
	})

	self._text_header = self._ws:panel():text({
		vertical = "top",
		align = "left",
		layer = 51,
		text = managers.localization:to_upper_text("csr_menu_select_item"),
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})
	local _, _, _, h = self._text_header:text_rect()

	self._text_header:set_size(self._panel:w(), h)
	self._text_header:set_left(self._panel:left())
	self._text_header:set_bottom(self._panel:top())

	-- Pick counter (top-right, opposite title); hidden for 1-of-1 to reduce noise.
	self._number_header = self._ws:panel():text({
		vertical = "top",
		align = "right",
		layer = 51,
		text = "",
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})

	self._number_header:set_size(self._panel:w(), h)
	self._number_header:set_left(self._panel:left())
	self._number_header:set_bottom(self._panel:top())
	self:_update_counter_text()

	-- Owned-items strip lives on the headers' workspace so it sits above the popup.
	if CSROwnedItemsStrip then
		local title_top = (self._text_header and alive(self._text_header) and self._text_header:top())
			or self._panel:top()
		self._owned_strip = CSROwnedItemsStrip:new({
			parent = self._ws:panel(),
			tooltip_parent = self._ws:panel(),
			width = self._panel:w(),
			layer = 51,
			max_height = math.max(64, title_top - 12),
			align = "left",
			anchor = function(panel)
				panel:set_center_x(self._panel:center_x())
				panel:set_bottom(title_top - padding)
			end,
		})
		self._owned_strip:rebuild()
	end

	self._items_panel = self._panel:panel({
		x = padding,
		y = padding,
		w = self._panel:w() - padding * 2,
		h = item_h,
	})
	self._button_panel = self._panel:panel({
		x = padding,
		y = self._items_panel:bottom() + padding,
		w = self._panel:w() - padding * 2,
		h = btn_size,
	})

	for i = 1, count do
		local item = items[i]
		local btn = CSRItemSelectionButton:new(self._items_panel, item)

		btn:set_x((CSRItemSelectionButton.size.w + padding) * (i - 1))
		btn:set_y(0)
		btn:set_callback(callback(self, self, "_on_select_item", btn))
		table.insert(self._buttons, btn)
		table.insert(self._item_buttons, btn)
	end

	if managers.menu:is_pc_controller() then
		local finalize_btn = CSRItemSelectionActionButton:new(self._button_panel)

		finalize_btn:set_text(managers.localization:to_upper_text("csr_menu_select_item"))
		finalize_btn:set_callback(callback(self, self, "_on_finalize_item"))
		finalize_btn:shrink_wrap_button(0, 0)
		table.insert(self._buttons, finalize_btn)
		table.insert(self._action_buttons, finalize_btn)

		local back_btn = CSRItemSelectionActionButton:new(self._button_panel)

		back_btn:set_text(managers.localization:to_upper_text("menu_back"))
		back_btn:set_callback(callback(self, self, "_on_back"))
		back_btn:shrink_wrap_button(0, 0)
		table.insert(self._buttons, back_btn)
		table.insert(self._action_buttons, back_btn)
		back_btn:panel():set_right(self._button_panel:w() - padding * 2)
		finalize_btn:panel():set_right(back_btn:panel():left() - padding * 3)

		for i = 1, count do
			local btn = self._buttons[i]

			if i > 1 then
				btn:set_link("left", self._buttons[i - 1])
			end

			if i < count then
				btn:set_link("right", self._buttons[i + 1])
			end

			btn:set_link("down", finalize_btn)
		end

		finalize_btn:set_link("up", self._buttons[1])
		finalize_btn:set_link("right", back_btn)
		back_btn:set_link("up", self._buttons[1])
		back_btn:set_link("left", finalize_btn)
	else
		self._legend_text = self._button_panel:text({
			halign = "right",
			vertical = "bottom",
			layer = 1,
			blend_mode = "add",
			align = "right",
			text = "",
			y = 0,
			x = 0,
			valign = "bottom",
			color = tweak_data.screen_colors.text,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
		})
		local legend_string = managers.localization:get_default_macro("BTN_ACCEPT")
			.. " "
			.. managers.localization:to_upper_text("csr_menu_select_item")
			.. "  |  "
			.. managers.localization:to_upper_text("menu_legend_back")

		self._legend_text:set_text(legend_string)

		for i = 1, count do
			local btn = self._buttons[i]

			if i > 1 then
				btn:set_link("left", self._buttons[i - 1])
			end

			if i < count then
				btn:set_link("right", self._buttons[i + 1])
			end
		end

		self:_move_selection("up")
	end

	BoxGuiObject:new(self._panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})
end

function CSRItemSelectionComponent:_on_select_item(item)
	if self._picked_item then
		self._picked_item:set_active(false)
	end

	self._picked_item = item

	if self._picked_item then
		self._picked_item:set_active(true)

		if managers.menu:is_pc_controller() then
			managers.menu_component:post_event("menu_enter")
		else
			self:_on_finalize_item()
		end
	end
end

function CSRItemSelectionComponent:_on_finalize_item()
	if not self._picked_item then
		managers.menu:post_event("menu_error")

		return
	end

	local data = self._picked_item:data() or {}
	local item_type = data.id
	local mgr = managers and managers.csr

	-- Wildcards are carry-1: replacing an already-held wildcard needs confirmation first.
	if data.rarity == "wildcard" and mgr and mgr.held_wildcard and mgr.local_peer_id then
		local held = mgr:held_wildcard(mgr:local_peer_id())
		if held and held ~= item_type then
			self:_confirm_wildcard_replace(held, data, mgr)
			return
		end
	end

	self:_grant_picked(item_type, mgr)
end

-- Grant the picked item, broadcast for MP, then advance to the next pick (or flag close).
function CSRItemSelectionComponent:_grant_picked(item_type, mgr)
	if mgr and mgr.add_item and mgr.local_peer_id and item_type then
		local pid = mgr:local_peer_id()
		-- A wildcard pick while one is already held is net-zero on the item count (carry-1 swap
		-- or re-pick), so the owed-pick quota wouldn't advance. Flag it before add_item mutates state.
		local def = mgr.item_def and mgr:item_def(item_type)
		local net_zero = def and def.rarity == "wildcard" and mgr.held_wildcard and mgr:held_wildcard(pid) ~= nil
		-- Credit the net-zero (wildcard swap/re-pick) BEFORE add_item: add_item fires on_item_added,
		-- which drives the lobby/briefing reminder refresh. If the credit lands after that, the
		-- reminder recomputes owed without it and lingers at the pre-pick count → a stale click then
		-- opens a window with nothing owed (synthetic "NO ITEMS" card).
		if net_zero and mgr.note_net_zero_rank_pick then
			mgr:note_net_zero_rank_pick(pid)
		end
		mgr:add_item(pid, item_type)
		-- pop_offer discards the whole 3-card set; the unchosen cards never carry over.
		if mgr.pop_offer then
			mgr:pop_offer(pid)
		end
	else
		csr_log(
			"[CSR][warn] item selection finalize: cannot grant (missing manager / add_item / type) "
				.. "type="
				.. tostring(item_type)
		)
	end

	-- MP: broadcast so every peer's items panel reflects the pick (no-op in SP).
	if _G.CSR_MP and _G.CSR_MP.broadcast_own_items then
		_G.CSR_MP.broadcast_own_items()
	end

	managers.menu_component:post_event("item_buy")

	self:_advance_pick()
end

-- Confirm swapping the held wildcard for the newly-picked one. On cancel the pick stays highlighted
-- so the player can choose differently; on confirm add_item performs the carry-1 swap.
function CSRItemSelectionComponent:_confirm_wildcard_replace(held_type, new_data, mgr)
	local old_def = mgr.item_def and mgr:item_def(held_type)
	local old_name = (old_def and old_def.name and csr_loc(old_def.name)) or string.upper(tostring(held_type))
	local new_name = new_data.name or string.upper(tostring(new_data.id))
	local new_type = new_data.id

	local dialog_data = {
		title = csr_loc("csr_wildcard_replace_title"),
		text = managers.localization:text("csr_wildcard_replace_text", { OLD = old_name, NEW = new_name }),
		id = "csr_wildcard_replace",
	}
	local yes_button = {
		text = csr_loc("dialog_yes"),
		callback_func = function()
			self:_grant_picked(new_type, mgr)
		end,
	}
	local no_button = {
		text = csr_loc("dialog_no"),
		cancel_button = true,
	}
	dialog_data.button_list = { yes_button, no_button }
	managers.system_menu:show(dialog_data)
end

function CSRItemSelectionComponent:_update_counter_text()
	if not self._number_header or not alive(self._number_header) then
		return
	end
	if self._num_to_select and self._num_to_select > 1 then
		self._number_header:set_text(tostring(self._current_num) .. " / " .. tostring(self._num_to_select))
	else
		self._number_header:set_text("")
	end
end

-- Advance to the next pick, or set _wants_close if the quota is spent.
-- Rebuilds only the item cards; action buttons and modal registration stay live.
function CSRItemSelectionComponent:_advance_pick()
	if self._current_num >= self._num_to_select then
		self._wants_close = true
		return
	end

	self._current_num = self._current_num + 1
	self:_update_counter_text()

	for _, btn in ipairs(self._item_buttons or {}) do
		if btn._panel and alive(btn._panel) then
			self._items_panel:remove(btn._panel)
		end
	end
	self._item_buttons = {}
	self._picked_item = nil
	self._selected_item = nil

	self._items = build_item_pool()

	-- No real offer left (quota already satisfied): close rather than render the synthetic
	-- "NO ITEMS" placeholder as a fake selectable pick. Old item buttons were already removed
	-- above, so drop them from _buttons too — a stray mouse event before update() closes would
	-- otherwise iterate dead panels.
	if not (self._items[1] and self._items[1].id ~= "none") then
		self._buttons = {}
		for _, b in ipairs(self._action_buttons or {}) do
			table.insert(self._buttons, b)
		end
		self._wants_close = true
		return
	end

	local count = math.max(#self._items, 1)

	for i = 1, count do
		local item = self._items[i]
		local btn = CSRItemSelectionButton:new(self._items_panel, item)
		btn:set_x((CSRItemSelectionButton.size.w + padding) * (i - 1))
		btn:set_y(0)
		btn:set_callback(callback(self, self, "_on_select_item", btn))
		table.insert(self._item_buttons, btn)
	end

	-- Rebuild self._buttons = item buttons + action buttons (same order as :_setup).
	self._buttons = {}
	for _, b in ipairs(self._item_buttons) do
		table.insert(self._buttons, b)
	end
	for _, b in ipairs(self._action_buttons or {}) do
		table.insert(self._buttons, b)
	end

	local finalize_btn = self._action_buttons and self._action_buttons[1]
	local back_btn = self._action_buttons and self._action_buttons[2]
	for i = 1, count do
		local btn = self._item_buttons[i]
		btn:set_link("left", i > 1 and self._item_buttons[i - 1] or nil)
		btn:set_link("right", i < count and self._item_buttons[i + 1] or nil)
		if finalize_btn then
			btn:set_link("down", finalize_btn)
		end
	end
	if finalize_btn and self._item_buttons[1] then
		finalize_btn:set_link("up", self._item_buttons[1])
	end
	if back_btn and self._item_buttons[1] then
		back_btn:set_link("up", self._item_buttons[1])
	end

	-- Seed controller focus on the first card of the new set (mirrors :_setup).
	if not managers.menu:is_pc_controller() and self._move_selection then
		self:_move_selection("up")
	end

	if self._owned_strip then
		self._owned_strip:rebuild()
	end
end

function CSRItemSelectionComponent:_on_back()
	-- Post "menu_exit" here only; quota-spent auto-close uses item_buy SFX instead.
	if managers.menu_component then
		managers.menu_component:post_event("menu_exit")
	end

	-- Defer close to update() — closing mid-dispatch corrupts MCM's _alive_components iteration.
	self._wants_close = true
end

function CSRItemSelectionComponent:update(t, dt)
	if self._wants_close then
		self._wants_close = nil
		if _G.CSR_CloseItemSelection then
			CSR_CloseItemSelection()
		end
		return
	end

	for idx, btn in ipairs(self._buttons) do
		if btn._panel:visible() then
			btn:update(t, dt)
		end
	end
end

function CSRItemSelectionComponent:confirm_pressed()
	if self._selected_item and self._selected_item:callback() then
		self._selected_item:callback()()

		return true
	end

	return true
end

-- Returning truthy here blocks vanilla node-gui hover/click while the popup is open.
function CSRItemSelectionComponent:input_focus()
	return true
end

-- Only consumes input over self._panel — scoped so an orphaned popup can't lock all menu input.
function CSRItemSelectionComponent:mouse_moved(o, x, y)
	if not managers.menu:is_pc_controller() or not alive(self._panel) then
		return
	end

	if self._owned_strip then
		self._owned_strip:mouse_moved(x, y)
	end

	local inside = self._panel:inside(x, y)
	local pointer = inside and "arrow" or nil
	self._selected_item = nil

	for idx, btn in ipairs(self._buttons) do
		if btn._panel:visible() then
			btn:set_selected(btn:inside(x, y))

			if btn:is_selected() then
				self._selected_item = btn
				pointer = "link"
			end
		end
	end

	return inside and true or nil, pointer
end

function CSRItemSelectionComponent:mouse_pressed(button, x, y)
	for idx, btn in ipairs(self._buttons) do
		if btn._panel:visible() and btn:is_selected() and btn:callback() then
			btn:callback()()

			return true
		end
	end

	-- Swallow unhandled clicks inside the popup so they don't punch through to the lobby.
	if alive(self._panel) and self._panel:inside(x, y) then
		return true
	end
end

function CSRItemSelectionComponent:_move_selection(dir)
	if not self._selected_item then
		self._selected_item = self._buttons[1]

		self._selected_item:set_selected(true)
	else
		local new_item = self._selected_item:get_link(dir)

		if new_item and new_item._panel:visible() then
			self._selected_item:set_selected(false)
			new_item:set_selected(true)

			self._selected_item = new_item
		end

		if self._selected_item and not self._selected_item._panel:visible() then
			self._selected_item:set_selected(false)

			self._selected_item = self._buttons[1]

			self._selected_item:set_selected(true)
		end
	end
end

function CSRItemSelectionComponent:move_up()
	self:_move_selection("up")
end

function CSRItemSelectionComponent:move_down()
	self:_move_selection("down")
end

function CSRItemSelectionComponent:move_left()
	self:_move_selection("left")
end

function CSRItemSelectionComponent:move_right()
	self:_move_selection("right")
end

-- ===================================================================
-- Open/close lifecycle for the selection window.
-- Registered at priority -100 so the modal sees mouse before crime_spree_missions.
-- ===================================================================

-- Overlay approach: no menu-node switch, so lobby chrome must be hidden manually.
-- Hides CSRMissionsMenuComponent panels + active node gui + lobby-code widget.
local function csr_active_node_gui()
	local am = managers and managers.menu and managers.menu:active_menu()
	local renderer = am and am.renderer
	if renderer and renderer.selected_node then
		return renderer:selected_node()
	end
	return nil
end

local function csr_hide_lobby_chrome()
	local hidden = {}

	local mcm = managers and managers.menu_component
	local comp = mcm and mcm._crime_spree_missions
	if comp then
		if comp._panel and alive(comp._panel) then
			comp._panel:set_visible(false)
		end
		if comp._fullscreen_panel and alive(comp._fullscreen_panel) then
			comp._fullscreen_panel:set_visible(false)
		end
		hidden.comp = comp
	end

	local node_gui = csr_active_node_gui()
	if node_gui and node_gui.set_visible then
		node_gui:set_visible(false)
		hidden.node_gui = node_gui
	end

	-- Lobby-code widget draws above the blur backdrop (layer 100), so hide it too.
	local code_gui = mcm and mcm._lobby_code_gui
	if code_gui and code_gui.panel then
		local cp = code_gui:panel()
		if cp and alive(cp) and cp:visible() then
			cp:set_visible(false)
			hidden.lobby_code = code_gui
		end
	end

	_G._csr_item_selection_hidden = hidden
end

local function csr_restore_lobby_chrome()
	local hidden = _G._csr_item_selection_hidden
	_G._csr_item_selection_hidden = nil
	if not hidden then
		return
	end

	local comp = hidden.comp
	if comp then
		if comp._panel and alive(comp._panel) then
			comp._panel:set_visible(true)
		end
		if comp._fullscreen_panel and alive(comp._fullscreen_panel) then
			comp._fullscreen_panel:set_visible(true)
		end
	end

	if hidden.node_gui and hidden.node_gui.set_visible then
		hidden.node_gui:set_visible(true)
	end

	if hidden.lobby_code and hidden.lobby_code.panel then
		local cp = hidden.lobby_code:panel()
		if cp and alive(cp) then
			cp:set_visible(true)
		end
	end
end

-- Repaint the live lobby reminder against current pick state. on_item_added refreshes the
-- component that registered it, but the visible lobby comp is repainted only by its own refresh,
-- which the open/close paths otherwise skip -- a wildcard swap leaves the item count unchanged,
-- so without this the reminder lingers at its pre-pick count.
local function csr_refresh_lobby_reminder(mcm)
	local lobby_comp = mcm and mcm._crime_spree_missions
	if lobby_comp and lobby_comp.refresh_for_rank_change then
		lobby_comp:refresh_for_rank_change()
	end
end

function _G.CSR_CloseItemSelection()
	local mcm = managers and managers.menu_component
	if not mcm then
		return
	end

	mcm:unregister_component(COMP_ID)

	if _G._csr_item_selection then
		pcall(function()
			_G._csr_item_selection:close()
		end)
		_G._csr_item_selection = nil
	end

	csr_restore_lobby_chrome()

	-- A wildcard swap leaves the item count unchanged, so the close path must repaint the
	-- lobby reminder itself or it lingers at its pre-pick count after the window closes.
	csr_refresh_lobby_reminder(mcm)

	-- Restore _alive_components order from snapshot (see CSR_OpenItemSelection).
	local snap = _G._csr_alive_snapshot
	_G._csr_alive_snapshot = nil
	if snap and mcm._alive_components then
		local present = {}
		for _, cd in ipairs(mcm._alive_components) do
			present[cd] = true
		end
		local rebuilt = {}
		for _, cd in ipairs(snap) do
			if present[cd] and cd.id ~= COMP_ID then
				rebuilt[#rebuilt + 1] = cd
				present[cd] = nil
			end
		end
		for _, cd in ipairs(mcm._alive_components) do
			if present[cd] and cd.id ~= COMP_ID then
				rebuilt[#rebuilt + 1] = cd
			end
		end
		mcm._alive_components = rebuilt
	end

	csr_log("[CSR] item selection window closed")
end

function _G.CSR_OpenItemSelection(num_to_select)
	local mcm = managers and managers.menu_component
	if not mcm then
		csr_log("[CSR] item selection: managers.menu_component not ready")
		return
	end

	local ws = mcm._ws
	local fullscreen_ws = mcm._fullscreen_ws
	if not ws or not fullscreen_ws then
		csr_log("[CSR] item selection: menu workspaces not ready")
		return
	end

	-- Install ESC gates lazily on first open. MenuInput / MenuManager may be nil at file-scope load
	-- time (this file hooks menucomponentmanager, which can load BEFORE menuinput/menumanager), so a
	-- file-scope install would silently no-op. By open time every menu class is loaded. ESC over the
	-- modal must be neutralised at TWO independent entry points, both keyed on _csr_item_selection:
	--   1. MenuInput:back / force_back -> navigate_back pops the underlying screen to the previous
	--      menu. Swallow it (force_back bypasses the _back_disabled guard, so wrap it too).
	--   2. MenuManager:toggle_menu_state -> opens menu_pause over the window. Swallow it.
	-- The window itself still closes via the MCM:back_pressed wrap.
	if not _G._CSR_ITEMSEL_INPUT_GATES then
		_G._CSR_ITEMSEL_INPUT_GATES = true

		if MenuInput then
			local orig_back = MenuInput.back
			function MenuInput:back(...)
				if _G._csr_item_selection then
					return
				end
				return orig_back(self, ...)
			end
			local orig_force_back = MenuInput.force_back
			function MenuInput:force_back(...)
				if _G._csr_item_selection then
					return
				end
				return orig_force_back(self, ...)
			end
		end

		if MenuManager then
			local orig_toggle = MenuManager.toggle_menu_state
			function MenuManager:toggle_menu_state(...)
				if _G._csr_item_selection then
					return
				end
				return orig_toggle(self, ...)
			end
		end
	end

	-- Pre-generate N offers before building the first card set; ensure_offers is
	-- idempotent, so re-opening the same owed pick always shows the same cards.
	local mgr = managers and managers.csr
	if mgr and mgr.ensure_offers and mgr.local_peer_id then
		mgr:ensure_offers(mgr:local_peer_id(), num_to_select or 1)
	end

	-- A stale reminder (e.g. left visible after a wildcard swap consumed the pick) can ask to open
	-- with nothing actually owed. Bail instead of presenting a synthetic "NO ITEMS" card, and repaint
	-- the lobby reminder so it drops to its true count.
	local pool = build_item_pool()
	local has_real_offer = pool[1] and pool[1].id ~= "none"
	if (tonumber(num_to_select) or 0) <= 0 or not has_real_offer then
		csr_refresh_lobby_reminder(mcm)
		csr_log("[CSR] item selection: nothing owed / no offer — open suppressed")
		return
	end

	local ok, comp =
		pcall(CSRItemSelectionComponent.new, CSRItemSelectionComponent, ws, fullscreen_ws, pool, num_to_select)
	if not ok or not comp then
		log("[CSR] item selection: failed to create component: " .. tostring(comp))
		return
	end

	-- Snapshot _alive_components order before register (Lua sort is unstable; restore on close
	-- to prevent crime_spree_missions getting starved by a higher-priority component).
	do
		local snap = {}
		for i, cd in ipairs(mcm._alive_components or {}) do
			snap[i] = cd
		end
		_G._csr_alive_snapshot = snap
	end

	mcm:register_component(COMP_ID, comp, -100)
	_G._csr_item_selection = comp
	csr_hide_lobby_chrome()
	csr_log("[CSR] item selection window opened")
end

-- Mask as the active crime_spree_modifiers component so CrimeSpreeContractBoxGui:can_take_input()
-- blocks peer-panel clicks through the modal.
if MenuComponentManager and not _G._CSR_ITEMSEL_INPUT_GATE then
	_G._CSR_ITEMSEL_INPUT_GATE = true
	Hooks:PostHook(MenuComponentManager, "crime_spree_modifiers", "CSR_ItemSelInputGate", function(self)
		if _G._csr_item_selection then
			return _G._csr_item_selection
		end
	end)
end

-- ESC closes the modal via renderer:back_pressed -> MCM:back_pressed. Consume it here so the
-- component's Back button and the ESC key share one close path. _on_back defers the actual
-- close to update() (closing mid-dispatch corrupts MCM's _alive_components iteration).
if MenuComponentManager and not _G._CSR_ITEMSEL_BACK_GATE then
	_G._CSR_ITEMSEL_BACK_GATE = true
	local orig_back_pressed = MenuComponentManager.back_pressed
	function MenuComponentManager:back_pressed(...)
		if _G._csr_item_selection then
			if _G._csr_item_selection._on_back then
				_G._csr_item_selection:_on_back()
			end
			return true
		end
		return orig_back_pressed(self, ...)
	end
end

-- Block the pause menu while the modal is open. MenuManager:toggle_menu_state opens menu_pause
-- unless managers.menu_component:input_focus() == true. This wrap is on MCM (the class this file
-- hooks, so it installs reliably regardless of load order). MenuInput/MenuManager gates that are
-- NOT guaranteed loaded here are installed lazily on open instead (see CSR_OpenItemSelection).
if MenuComponentManager and not _G._CSR_ITEMSEL_FOCUS_GATE then
	_G._CSR_ITEMSEL_FOCUS_GATE = true
	local orig_input_focus = MenuComponentManager.input_focus
	function MenuComponentManager:input_focus(...)
		if _G._csr_item_selection then
			return true
		end
		return orig_input_focus(self, ...)
	end
end

csr_log("[CSR] item_selection.lua loaded (forked selection window)")
