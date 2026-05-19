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
-- Trigger: DEBUG ONLY. _G.CSR_ToggleItemSelectionDebug() (bound to a keybind)
-- registers/unregisters the component on managers.menu_component. No lobby
-- button, and deliberately NOT placed where "Start the heist" lives.

if not RequiredScript then
	return
end

local padding = 10
local COMP_ID = "csr_item_selection_debug"

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
local FRAME_SCALE = 1.6

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

	local top_padding = padding * 2
	self._image_size = 128
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

	self._modifier_image = self._image:bitmap({
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
		y = self._image:bottom() + top_padding,
		w = self._panel:w() - padding * 2,
		h = self._panel:h() - self._image:bottom() - top_padding - padding,
		font_size = tweak_data.menu.pd2_tiny_font_size,
		font = tweak_data.menu.pd2_tiny_font,
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
	self:set_modifier(data)
end

function CSRItemSelectionButton:set_modifier(data)
	self._data = data

	self._panel:set_visible(self._data ~= nil)

	if not self._data then
		return
	end

	local texture, rect = tweak_data.hud_icons:get_icon_data(self._data.icon)

	self._modifier_image:set_image(texture)
	self._modifier_image:set_texture_rect(unpack(rect))
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

function CSRItemSelectionComponent:init(ws, fullscreen_ws, items)
	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()
	self._items = items or {}
	self._buttons = {}

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

	local modifier_h = CSRItemSelectionButton.size.h
	local btn_size = tweak_data.menu.pd2_large_font_size

	self._panel:set_w((CSRItemSelectionButton.size.w + padding) * count + padding)
	self._panel:set_h(modifier_h + btn_size + padding * 3)
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

	-- Debug shell: a single pick, so the "X / Y" counter stays blank (vanilla
	-- only shows it when more than one selection is pending).
	self._current_num = 1
	self._num_to_select = 1
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

	self._modifiers_panel = self._panel:panel({
		x = padding,
		y = padding,
		w = self._panel:w() - padding * 2,
		h = modifier_h,
	})
	self._button_panel = self._panel:panel({
		x = padding,
		y = self._modifiers_panel:bottom() + padding,
		w = self._panel:w() - padding * 2,
		h = btn_size,
	})

	for i = 1, count do
		local item = items[i]
		local btn = CSRItemSelectionButton:new(self._modifiers_panel, item)

		btn:set_x((CSRItemSelectionButton.size.w + padding) * (i - 1))
		btn:set_y(0)
		btn:set_callback(callback(self, self, "_on_select_modifier", btn))
		table.insert(self._buttons, btn)
	end

	if managers.menu:is_pc_controller() then
		local finalize_btn = CSRItemSelectionActionButton:new(self._button_panel)

		finalize_btn:set_text(managers.localization:to_upper_text("menu_cs_select_modifier"))
		finalize_btn:set_callback(callback(self, self, "_on_finalize_modifier"))
		finalize_btn:shrink_wrap_button(0, 0)
		table.insert(self._buttons, finalize_btn)

		local back_btn = CSRItemSelectionActionButton:new(self._button_panel)

		back_btn:set_text(managers.localization:to_upper_text("menu_back"))
		back_btn:set_callback(callback(self, self, "_on_back"))
		back_btn:shrink_wrap_button(0, 0)
		table.insert(self._buttons, back_btn)
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

function CSRItemSelectionComponent:_on_select_modifier(item)
	if self._selected_modifier then
		self._selected_modifier:set_active(false)
	end

	self._selected_modifier = item

	if self._selected_modifier then
		self._selected_modifier:set_active(true)

		if managers.menu:is_pc_controller() then
			managers.menu_component:post_event("menu_enter")
		else
			self:_on_finalize_modifier()
		end
	end
end

-- Debug shell: the selection pool / granting logic is intentionally not wired
-- (user scope). Finalize just logs the chosen item and closes the popup so the
-- whole window can be exercised end-to-end without a backend.
function CSRItemSelectionComponent:_on_finalize_modifier()
	if not self._selected_modifier then
		managers.menu:post_event("menu_error")

		return
	end

	local data = self._selected_modifier:data() or {}
	log(
		"[CSR][debug] item selection: would pick id="
			.. tostring(data.id)
			.. " rarity="
			.. tostring(data.rarity)
			.. " (granting logic not wired yet)"
	)
	managers.menu_component:post_event("item_buy")

	-- Deferred: see _on_back / update for why this must not close synchronously.
	self._wants_close = true
end

function CSRItemSelectionComponent:_on_back()
	-- Do NOT close here. _on_back runs from the popup's mouse_pressed, which is
	-- itself called from MenuComponentManager:run_return_on_all_live_components
	-- while it ipairs-iterates _alive_components. Calling CSR_CloseItemSelectionDebug
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
		if _G.CSR_CloseItemSelectionDebug then
			CSR_CloseItemSelectionDebug()
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
-- Debug open/close. Bound to a keybind (csr_debug_item_selection.lua).
-- Registers at priority -100 so the modal sees mouse input before the
-- lobby's crime_spree_missions component (priority 0).
-- ===================================================================

-- Builds the debug card set: the only registered 6.3 item is Dog Tags
-- (managers.csr._registry), shown x3. Description is derived from the live
-- balance constant (no hardcoded number, no logbook {color} markup).
local function build_debug_items()
	local bonus = 0.10
	if managers.csr and managers.csr.constant then
		bonus = managers.csr:constant("dog_tags_hp_bonus") or bonus
	end
	local desc = string.format("Increases maximum health by %g%% (+%g%% per stack, linear).", bonus * 100, bonus * 100)

	local items = {}
	for i = 1, 3 do
		items[i] = {
			id = "player_health_boost_" .. i,
			icon = "csr_dog_tags",
			rarity = "common",
			name = "DOG TAGS",
			desc = desc,
		}
	end
	return items
end

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

function _G.CSR_CloseItemSelectionDebug()
	local mcm = managers and managers.menu_component
	if not mcm then
		return
	end

	mcm:unregister_component(COMP_ID)

	if _G._csr_item_selection_debug then
		pcall(function()
			_G._csr_item_selection_debug:close()
		end)
		_G._csr_item_selection_debug = nil
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

	log("[CSR][debug] item selection window closed")
end

function _G.CSR_OpenItemSelectionDebug()
	local mcm = managers and managers.menu_component
	if not mcm then
		log("[CSR][debug] item selection: managers.menu_component not ready")
		return
	end

	local ws = mcm._ws
	local fullscreen_ws = mcm._fullscreen_ws
	if not ws or not fullscreen_ws then
		log("[CSR][debug] item selection: menu workspaces not ready")
		return
	end

	local ok, comp =
		pcall(CSRItemSelectionComponent.new, CSRItemSelectionComponent, ws, fullscreen_ws, build_debug_items())
	if not ok or not comp then
		log("[CSR][debug] item selection: failed to create component: " .. tostring(comp))
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
	_G._csr_item_selection_debug = comp
	csr_hide_lobby_chrome()
	log("[CSR][debug] item selection window opened")
end

function _G.CSR_ToggleItemSelectionDebug()
	if _G._csr_item_selection_debug then
		CSR_CloseItemSelectionDebug()
	else
		CSR_OpenItemSelectionDebug()
	end
end

log("[CSR] csr_item_selection.lua loaded (forked selection window + debug toggle)")
