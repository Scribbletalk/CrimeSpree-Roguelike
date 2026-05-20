-- CSRItemSelectionComponent — fork of vanilla CrimeSpreeModifiersMenuComponent.
--
-- Origin: pd2_source_code/lib/managers/menu/crimespreemodifiersmenucomponent.lua
-- Strategy: byte-for-byte copy with class renames + the backend decoupled from
-- managers.crime_spree. Vanilla read the offered items from
-- managers.crime_spree:get_loud_modifiers() and the description from
-- :make_modifier_description(); that backend is not ported in 6.3, so the
-- component is now DATA-DRIVEN — :new() takes a plain item list and each entry
-- carries its own id / icon / rarity / name / desc. The selection-pool and
-- "when does this open" logic is intentionally NOT wired yet (user scope:
-- "just the window, opened by a debug key").
--
-- Class renames:
--   CrimeSpreeModifiersMenuComponent -> CSRItemSelectionComponent
--   CrimeSpreeModifierButton         -> CSRItemSelectionButton
--   CrimeSpreeButton                 -> CSRItemSelectionActionButton
--
-- Folded in: the rarity frame that the pre-refactor mod added via
-- PreHook/PostHook on CrimeSpreeModifierButton:update (item_frames_in_selection.lua).
-- Owning the fork removes the "restore vanilla icon size each frame so
-- smoothstep does not compound" hack — the frame is just sized off the icon
-- inside our own update().
--
-- Trigger: lobby "unselected items" reminder click (csr_missions_menu.lua
-- `_on_unselected_items_clicked`). The reminder is rank-vs-owned-gated
-- (visible only when host_rank > total_item_count), so it enforces "one pick
-- per rank earned" -- and the click passes the gap as the pick quota
-- (CSR_OpenItemSelection(num_to_select)), which the component then chews
-- through one pick at a time via _advance_pick before closing.

if not RequiredScript then
	return
end

local padding = 10
local COMP_ID = "csr_item_selection"

-- Build the item-card data set for one round of the selection window.
--
-- Registry-driven: one card per item registered through CSR.register_item
-- (CSR's own + any addon's). Reads name/desc/icon/rarity straight off the
-- registered def as literal strings -- deliberately NOT via loc keys, so this
-- path never touches the partially-ported legacy csr_localization.lua
-- generator. The selection POOL (which weighted subset rolls per popup) lands
-- with CSRGameManager:roll_item_pool; for now it lists everything registered,
-- so :_advance_pick rebuilds the same set each step (consistent, just not yet
-- randomised). Defined at file scope (not local to a method) so :_setup AND
-- :_advance_pick both reach it -- both call it once per card refresh.
local function build_item_pool()
	local items = {}
	local mgr = managers and managers.csr
	local reg = (mgr and mgr.registered_items and mgr:registered_items()) or {}

	for _, def in ipairs(reg) do
		items[#items + 1] = {
			id = def.type,
			icon = def.icon or "csr_dog_tags",
			rarity = def.rarity or "common",
			name = def.name or string.upper(tostring(def.type)),
			desc = def.desc or "",
		}
	end

	if #items == 0 then
		-- Opened before any item registered (or none exist): keep the window
		-- readable as "nothing yet" instead of an empty/broken layout.
		items[1] = {
			id = "csr_none",
			icon = "csr_dog_tags",
			rarity = "common",
			name = "NO ITEMS",
			desc = "No items are registered yet.",
		}
	end

	return items
end

-- Generic rarity frame (single texture, tinted per rarity at draw time) — same
-- mapping the pre-refactor selection overlay used, minus contraband: contraband
-- items no longer appear in the item selection (user, 6.3 drop-rate redesign).
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	wildcard = Color(1, 1, 0.3, 0.8),
}
-- Frame is drawn larger than the icon so it reads as a border around it.
-- Applied to the icon's ACTUAL (0.8-modified) size in BOTH init and update so
-- there is no size jump on the first update tick.
local FRAME_SCALE = 2.0

-- ===================================================================
-- CSRItemSelectionButton — one selectable item card.
-- Fork of CrimeSpreeModifierButton with the rarity frame baked in and the
-- icon/description sourced from the data table instead of managers.crime_spree.
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

	-- Vertical gap above the icon (top of card to top of icon panel).
	local top_padding = padding * 4
	-- Vertical gap between icon-panel bottom and the description text. Kept
	-- separate from top_padding so we can push the text further down without
	-- moving the icon (item descriptions are short -- ~one line -- so the icon
	-- already sits where it should and only the text needs more breathing room).
	local desc_top_gap = padding * 6
	-- Base icon size. Final on-screen size is _image_size * _size_modifier (idle)
	-- or _image_size (hover/selected, per update()); the rarity frame and update
	-- smoothstep both derive from this single value, so one knob controls all.
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

	-- Rarity frame BEHIND the icon (layer 5 < icon layer 10). Lives on the
	-- 208x298 button panel, not the icon panel, so it is not clipped. Sized
	-- and centred every frame in update() to track the icon's smoothstep.
	local frame_base = self._image_size * self._size_modifier * FRAME_SCALE
	self._frame = self._panel:bitmap({
		name = "csr_rarity_frame",
		layer = 5,
		w = frame_base,
		h = frame_base,
	})
	self._frame:set_center(self._image_pos.x, self._image_pos.y)

	self._item_image = self._image:bitmap({
		blend_mode = "add",
		name = "icon",
		valign = "grow",
		halign = "grow",
		layer = 10,
	})
	self._desc = self._panel:text({
		vertical = "top",
		wrap = true,
		align = "center",
		wrap_word = true,
		text = "",
		x = padding,
		y = self._image:bottom() + desc_top_gap,
		w = self._panel:w() - padding * 2,
		h = self._panel:h() - self._image:bottom() - desc_top_gap - padding,
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

	-- Resolve icon: a "/" in the value means a full DB-mounted texture path
	-- (an addon shipping its own .dds via DB:create_entry); otherwise it is a
	-- short hud_icons id (CSR's built-in items). The direct-path branch assumes
	-- 128x128 since hud_icons records carry that rect for every CSR icon; an
	-- addon needing a different rect would warrant promoting `icon` to a table.
	local texture, rect
	if type(self._data.icon) == "string" and self._data.icon:find("/", 1, true) then
		texture, rect = self._data.icon, { 0, 0, 128, 128 }
	else
		texture, rect = tweak_data.hud_icons:get_icon_data(self._data.icon)
	end

	self._item_image:set_image(texture)
	self._item_image:set_texture_rect(unpack(rect))
	self._desc:set_text(self._data.desc or "")

	-- Rarity frame: tint per the item's rarity (white = common).
	local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")
	self._frame:set_image(frame_tex)
	self._frame:set_texture_rect(unpack(frame_rect))
	self._frame:set_color(RARITY_COLORS[self._data.rarity] or Color.white)
	self._frame:set_visible(true)
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

	-- Frame tracks the icon's animated size at an independent scale so the
	-- border thickness stays proportional as the card grows/shrinks.
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
-- CSRItemSelectionActionButton — the FINALIZE / BACK text buttons.
-- Verbatim fork of CrimeSpreeButton (no behavioural change).
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
-- CSRItemSelectionComponent — the centred modal popup.
-- Fork of CrimeSpreeModifiersMenuComponent; :new() takes (ws, fullscreen_ws,
-- items) where `items` is an array of { id, icon, rarity, name, desc }.
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
	-- Pick budget: how many items the player is entitled to grab in this open.
	-- Quota source is the caller (lobby reminder passes host_rank - owned; debug
	-- keybind passes nil -> defaults to 1). _current_num counts picks IN PROGRESS
	-- (1 = the pick currently shown), so the header reads "1 / N" on open.
	self._num_to_select = math.max(1, num_to_select or 1)
	self._current_num = 1

	self:_setup()
end

function CSRItemSelectionComponent:close()
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
		text = managers.localization:to_upper_text("menu_cs_select_modifier"),
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})
	local _, _, _, h = self._text_header:text_rect()

	self._text_header:set_size(self._panel:w(), h)
	self._text_header:set_left(self._panel:left())
	self._text_header:set_bottom(self._panel:top())

	-- Pick counter (right-aligned, top-right of the popup, opposite the title).
	-- Shown only when more than one pick is queued -- a 1-of-1 reads as noise.
	-- _current_num / _num_to_select are set in :init(); the actual text is
	-- written via _update_counter_text so the call site (here AND _advance_pick)
	-- can stay one-liner.
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
		-- Track item buttons separately so _advance_pick can rebuild only this
		-- subset between picks without disturbing the action buttons below.
		table.insert(self._item_buttons, btn)
	end

	if managers.menu:is_pc_controller() then
		local finalize_btn = CSRItemSelectionActionButton:new(self._button_panel)

		finalize_btn:set_text(managers.localization:to_upper_text("menu_cs_select_modifier"))
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
			.. managers.localization:to_upper_text("menu_cs_select_modifier")
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

-- Grant the picked item to the local peer, then close. Local-only: the count
-- model store (`managers.csr` peer_items) is not yet MP-synced (design open
-- item O4) -- the host doesn't yet broadcast a grant, the client doesn't yet
-- listen. When that slice lands, this is the point that should also fire a
-- network message.
--
-- Pick-cap gate: handled OUTSIDE this function via the lobby reminder. The
-- reminder is the production trigger and is rank-vs-owned-gated (only visible
-- while host_rank > total_item_count), so add_item is naturally bounded to the
-- "one pick per rank earned" budget on that path. The debug keybind bypasses
-- the gate -- intentional, dev-only escape hatch. Selection-pool weighting
-- (60/24/4/12 per rarity) is still parked separately.
function CSRItemSelectionComponent:_on_finalize_item()
	if not self._picked_item then
		managers.menu:post_event("menu_error")

		return
	end

	local data = self._picked_item:data() or {}
	local item_type = data.id
	local mgr = managers and managers.csr

	if mgr and mgr.add_item and mgr.local_peer_id and item_type then
		local pid = mgr:local_peer_id()
		mgr:add_item(pid, item_type)

		-- Refresh the two lobby surfaces that read peer_items state so they
		-- repaint immediately (otherwise they only repaint on the next refresh
		-- trigger -- which for an already-open items feature panel means the
		-- user has to close + reopen it to see the new x2 badge):
		--   1. unselected-items reminder (rank-vs-owned counter above DIFFICULTY)
		--   2. items feature panel content (per-peer icon grid)
		-- Component lookup is nil-safe: missing == popup opened from outside the
		-- lobby (debug keybind path), no surface to refresh, no-op rather than
		-- crash.
		--
		-- TODO future cleanup: register both refresh paths as on_item_added
		-- callbacks on managers.csr so any add_item caller drives the repaint
		-- automatically. Direct call is fine while there's only one grant site.
		local mcm = managers and managers.menu_component
		local lobby = mcm and mcm._crime_spree_missions
		if lobby and lobby._refresh_unselected_items then
			lobby:_refresh_unselected_items()
		end
		if lobby and lobby._populate_items_panel then
			lobby:_populate_items_panel()
		end
	else
		log(
			"[CSR][warn] item selection finalize: cannot grant (missing manager / add_item / type) "
				.. "type="
				.. tostring(item_type)
		)
	end

	managers.menu_component:post_event("item_buy")

	-- Multi-pick: if the player is still owed more picks, reroll the cards in
	-- place and stay open; otherwise close. _advance_pick handles both branches
	-- (it sets _wants_close on the last pick), and the close itself is deferred
	-- via _wants_close for the same reason _on_back is -- see _on_back / update.
	self:_advance_pick()
end

-- Top-right "X / Y" counter. Shown only when the quota is > 1; a 1-of-1 pick
-- reads as noise and matches the prior debug-window behaviour. Safe to call
-- before _setup wires the header (no-op) so :init ordering is forgiving.
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

-- Advance to the next pick OR close if the quota is spent.
--
-- Called from _on_finalize_item after the item is granted. If picks remain we
-- rebuild ONLY self._items_panel's children (the item cards) -- the action
-- buttons, header, blur, and modal-focus registration are untouched so the
-- window stays visually live (no close/reopen flicker) and the live-component
-- snapshot in CSR_OpenItemSelection stays valid.
--
-- self._buttons is reassembled as item buttons + action buttons in the same
-- order :_setup produced, so mouse_moved / mouse_pressed / update keep their
-- existing semantics (item buttons first -> action buttons second).
function CSRItemSelectionComponent:_advance_pick()
	if self._current_num >= self._num_to_select then
		self._wants_close = true
		return
	end

	self._current_num = self._current_num + 1
	self:_update_counter_text()

	-- Tear down previous item cards. The panels live under _items_panel so
	-- removing them there cleans up the bitmap/text children automatically;
	-- no need to walk each button's internal panel tree.
	for _, btn in ipairs(self._item_buttons or {}) do
		if btn._panel and alive(btn._panel) then
			self._items_panel:remove(btn._panel)
		end
	end
	self._item_buttons = {}
	self._picked_item = nil
	self._selected_item = nil

	-- Fresh roll. build_item_pool is the current pool source -- when the
	-- weighted selection pool lands (CSRGameManager:roll_item_pool), swap this
	-- single call for the production roller; the rest of this function still
	-- works unchanged.
	self._items = build_item_pool()
	local count = math.max(#self._items, 1)

	for i = 1, count do
		local item = self._items[i]
		local btn = CSRItemSelectionButton:new(self._items_panel, item)
		btn:set_x((CSRItemSelectionButton.size.w + padding) * (i - 1))
		btn:set_y(0)
		btn:set_callback(callback(self, self, "_on_select_item", btn))
		table.insert(self._item_buttons, btn)
	end

	-- Rebuild self._buttons = item buttons + action buttons. Order matches
	-- :_setup so dispatch iteration sees the same shape it did at open time.
	self._buttons = {}
	for _, b in ipairs(self._item_buttons) do
		table.insert(self._buttons, b)
	end
	for _, b in ipairs(self._action_buttons or {}) do
		table.insert(self._buttons, b)
	end

	-- Relink keyboard / controller navigation. The action buttons (finalize,
	-- back) are stable across rolls -- only the item buttons' left/right/down
	-- links need re-pointing.
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

	-- Controller path: _setup ends with _move_selection("up") to seed a focused
	-- card. Mirror that here so the next pick starts highlighted on the
	-- (rebuilt) first card -- otherwise gamepad nav reads as "no focus" until
	-- the player flicks the stick.
	if not managers.menu:is_pc_controller() and self._move_selection then
		self:_move_selection("up")
	end
end

function CSRItemSelectionComponent:_on_back()
	-- Do NOT close here. _on_back runs from the popup's mouse_pressed, which is
	-- itself called from MenuComponentManager:run_return_on_all_live_components
	-- while it ipairs-iterates _alive_components. Calling CSR_CloseItemSelection
	-- now would unregister_component (table.remove + table.sort on that live
	-- list) and node_gui:set_visible (renderer stencil/bg re-apply) mid-dispatch,
	-- corrupting mouse routing so the lobby component never gets clicks again
	-- (user report: "after Back none of the CSR buttons can be clicked").
	-- Defer to update(), which runs outside the input/renderer call stack —
	-- the same pattern the pre-refactor briefing_select_item.lua used (it
	-- closed its popup from an update PostHook, never from an input handler).
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

-- Claim modal input focus. MenuComponentManager:input_focus() ends with
-- run_return_on_all_live_components("input_focus") and returns the first
-- non-nil; we are registered at priority -100 so we are hit first. With this
-- truthy, MenuInput:mouse_moved (menuinput.lua:203) and :mouse_pressed (:503)
-- BOTH skip the active node_gui's row-item hover/click handling — so the
-- hidden vanilla buttons (Inventory / Options / Back) can no longer be
-- clicked or highlighted — while the component-manager dispatch that feeds
-- THIS popup's own mouse_moved/mouse_pressed is left untouched (that path is
-- not gated by input_focus). The component is only registered while the popup
-- is open, so focus is released automatically on close.
function CSRItemSelectionComponent:input_focus()
	return true
end

-- Effectively modal via the dark/blur backdrop, but input is consumed ONLY
-- while the cursor is over the popup itself. Consuming unconditionally would
-- be unsafe: this is a debug toggle with no node lifecycle, so an ESC out of
-- the lobby leaves the component registered (only the keybind closes it) — an
-- "always true" handler would then lock ALL menu mouse input on the next
-- screen until the keybind is pressed again. Scoping to self._panel keeps an
-- orphaned popup harmless. Registered at priority -100 so it still sees input
-- before crime_spree_missions when both are live.
function CSRItemSelectionComponent:mouse_moved(o, x, y)
	if not managers.menu:is_pc_controller() or not alive(self._panel) then
		return
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

-- NOTE: MenuComponentManager dispatches this via
-- run_return_on_all_live_components("mouse_pressed", button, x, y)
-- (menucomponentmanager.lua:1693) — THREE args, no leading `o`. Same shape
-- CSRMissionsMenuComponent:mouse_pressed uses.
function CSRItemSelectionComponent:mouse_pressed(button, x, y)
	for idx, btn in ipairs(self._buttons) do
		if btn._panel:visible() and btn:is_selected() and btn:callback() then
			btn:callback()()

			return true
		end
	end

	-- Swallow clicks that land on the popup body (but not selectable) so they
	-- don't punch through to the lobby; let clicks outside fall through.
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
-- Registers at priority -100 so the modal sees mouse input before the
-- lobby's crime_spree_missions component (priority 0). The pool builder
-- (build_item_pool) lives at file scope -- see top of the file.
-- ===================================================================

-- Hide / restore everything behind the popup.
--
-- The popup is an OVERLAY on the crime_spree_lobby node — there is no menu-node
-- switch (vanilla CS opened its modifiers menu as its own node, so the menu
-- system swapped the whole screen for free; we don't). Two separate layers
-- keep drawing on top of our dark/blur backdrop unless we hide them ourselves:
--
--  1. The forked lobby panel (CSRMissionsMenuComponent — cards, sidebar,
--     branded title, missions/rank counters, Start/Reroll). It is a
--     managers.menu_component component → hide its _panel / _fullscreen_panel.
--     Same pattern the pre-refactor briefing_select_item.lua used.
--  2. The vanilla menu NODE list (Inventory / Options / Back / etc.). That is
--     rendered by the menu renderer, NOT a menu_component. The active node gui
--     is renderer:selected_node() (top of _node_gui_stack,
--     coremenurenderer.lua:248) and MenuNodeGui:set_visible (menunodegui.lua:1791)
--     toggles it (and re-applies stencil/bg on show — vanilla's own restore).
--
-- We restore ONLY what we hid, and only if we hid it, so an open from a screen
-- with no lobby panel / node can't wrongly force something visible.
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

	-- Restore the pre-popup live-component order (see open snapshot comment).
	-- Rebuild deterministically: original components in their original order
	-- (minus ours), then any registered while the popup was up (minus ours).
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

	log("[CSR] item selection window closed")
end

function _G.CSR_OpenItemSelection(num_to_select)
	local mcm = managers and managers.menu_component
	if not mcm then
		log("[CSR] item selection: managers.menu_component not ready")
		return
	end

	local ws = mcm._ws
	local fullscreen_ws = mcm._fullscreen_ws
	if not ws or not fullscreen_ws then
		log("[CSR] item selection: menu workspaces not ready")
		return
	end

	-- num_to_select: how many picks this open is entitled to. Lobby reminder
	-- passes host_rank - owned (the rank-vs-owned gap); the debug keybind
	-- passes nil (defaults to 1 inside :init so the dev path stays one-shot).
	local ok, comp = pcall(
		CSRItemSelectionComponent.new,
		CSRItemSelectionComponent,
		ws,
		fullscreen_ws,
		build_item_pool(),
		num_to_select
	)
	if not ok or not comp then
		log("[CSR] item selection: failed to create component: " .. tostring(comp))
		return
	end

	-- Snapshot the live-component ORDER before we register. register_component
	-- runs table.sort(_alive_components, a.priority < b.priority); Lua's sort is
	-- NOT stable, so inserting our entry reshuffles the existing equal-priority
	-- (p=0) components (lobby_code / crime_spree_missions / socialhub) and
	-- unregister never re-sorts -> the lobby's crime_spree_missions can end up
	-- behind a component whose mouse_pressed returns non-nil, starving it
	-- forever (the "after close, CSR buttons dead" bug). We restore this exact
	-- order on close.
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
	log("[CSR] item selection window opened")
end

log("[CSR] csr_item_selection.lua loaded (forked selection window)")
