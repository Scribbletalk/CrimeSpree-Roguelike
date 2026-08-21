-- Shared controller focus/navigation helper for CSR menu components.
-- A component builds a list of focus targets and delegates its MCM
-- move_*/confirm_pressed methods here. Focus reuses each component's own
-- hover visual via the target's on_focus(bool) callback.

if _G.CSR_ControllerNav then
	return
end

CSR_ControllerNav = class()

-- Static: center of a Diesel panel in workspace coords (same basis mouse
-- hit-tests use). world_position() returns top-left; add half the size.
function CSR_ControllerNav.center_of(panel)
	local wx, wy = panel:world_position()
	return wx + panel:w() * 0.5, wy + panel:h() * 0.5
end

-- Show the controller virtual cursor for a menu component (no-op on keyboard/mouse). The
-- activation is ref-counted in MenuInput and flagged on the component, so hide_cursor only
-- balances what it activated. Pair show_cursor in a component's init with hide_cursor in close.
function CSR_ControllerNav.show_cursor(component)
	if managers.menu:is_pc_controller() then
		return
	end
	-- Idempotent: activate_controller_mouse is ref-counted, so a second show without an
	-- intervening hide (the briefing's show hook can fire repeatedly) would leak the count.
	if component._csr_controller_mouse then
		return
	end
	local menu = managers.menu:active_menu()
	if menu and menu.input then
		menu.input:activate_controller_mouse()
		-- Force the controller confirm/back/nav block in MenuInput:update to run while the
		-- cursor drives input. Without this, MenuInput only processes those inputs when the
		-- active menu is "input-hijacked", which depends on MenuComponentManager:input_focus()
		-- reaching THIS component -- but its earlier gui branches (briefing/endscreen, still
		-- alive over the lobby) can shadow us, leaving A/B dead. Vanilla does the same for every
		-- controller-mouse GUI (CrimeNet, inventory, preplanning).
		menu.input:set_force_input(true)
		component._csr_controller_mouse = true
		CSR_ControllerNav.install_nav_suppression()
	end
end

function CSR_ControllerNav.hide_cursor(component)
	if not component._csr_controller_mouse then
		return
	end
	local menu = managers.menu:active_menu()
	if menu and menu.input then
		menu.input:deactivate_controller_mouse()
		menu.input:set_force_input(false)
	end
	component._csr_controller_mouse = nil
end

-- Replay a full left click (press then release) at (x,y) on a menu component. A controller
-- confirm carries no cursor coordinates and the engine sends no ws mouse click on a gamepad,
-- so this reuses the component's own coordinate-based handlers. Some widgets act on press
-- (buttons), others on release (tabs), so fire both. Returns truthy if either handled it.
function CSR_ControllerNav.replay_click(component, x, y)
	-- A wildcard-bind capture window wants the raw A press for itself; replaying it as a click would
	-- land on the bind row and cancel the capture, making A unbindable.
	if _G.CSR_WildcardBind and CSR_WildcardBind.listening() then
		return true
	end
	local btn = Idstring("0")
	local handled = component:mouse_pressed(btn, x, y)
	if component.mouse_released then
		local released = component:mouse_released(component._panel, btn, x, y)
		handled = handled or released
	end
	return handled
end

-- Pop the current node from a CSR sub-node on a controller (logbook/black_market shop). Those nodes
-- have no back item, so controller B reaches only the component's back_pressed, never MenuInput:back.
-- We can't route through managers.menu:back(): the component forces input_focus()==true (to claim the
-- cursor and kill the vanilla node's phantom highlight), and MenuInput:back early-returns whenever
-- _input_hijacked()==true, which reads that same input_focus. So drive the logic directly -- this is
-- exactly what MenuInput:back does after its guard. The lobby logic has _accept_input==true, so the
-- queued action drains on the next tick (deferred pop also avoids a synchronous teardown mid-input).
function CSR_ControllerNav.navigate_back()
	-- Same for B: without this it pops the node and the lobby raises its quit-confirm dialog instead
	-- of the button being bound.
	if _G.CSR_WildcardBind and CSR_WildcardBind.listening() then
		return true
	end
	managers.menu_component:post_event("menu_back")
	local menu = managers.menu:active_menu()
	if menu and menu.logic then
		menu.logic:navigate_back(false, false)
	end
	return true
end

-- Suppress d-pad/stick node navigation (both axes) while a CSR virtual-cursor surface is the active
-- selector, so the cursor is the ONLY way to pick a widget/button. Covers the lobby (missions
-- component under crime_spree_lobby), the briefing (MenuComponentManager._mission_briefing_gui), the
-- post-heist endscreen (._stage_endscreen_gui) and the ESC pause panel (._ingame_contract_gui, which
-- only raises the cursor on CSR heists) -- all four dock CSR widgets the stick cannot
-- otherwise reach. Gated on the controller-mouse counter (only our show_cursor raises it on these
-- surfaces; item_selection zeroes it for its own discrete nav; vanilla cursor menus like CrimeNet
-- raise it but match none of the surfaces below, so their nav is untouched). The virtual cursor
-- rides the analog stick via MousePointerManager, not these bools, so neutering them leaves cursor
-- movement and hover+A confirm intact. Installed lazily: MenuInput is not loaded when this file
-- (hooked on MenuComponentManager) first runs.
local function csr_suppress_cursor_nav(input)
	if (input._controller_mouse_active_counter or 0) <= 0 then
		return false
	end
	local mc = managers.menu_component
	if mc then
		if mc._mission_briefing_gui and mc._mission_briefing_gui._enabled then
			return true
		end
		if mc._stage_endscreen_gui and mc._stage_endscreen_gui._enabled then
			return true
		end
		-- Pause panel: the flag is only set while OUR cursor is up (CSR heists), so vanilla
		-- pause menus keep their stick navigation.
		if mc._ingame_contract_gui and mc._ingame_contract_gui._csr_controller_mouse then
			return true
		end
	end
	local menu = managers.menu:active_menu()
	local logic = menu and menu.logic
	return logic ~= nil and logic:selected_node() ~= nil and logic:selected_node_name() == "crime_spree_lobby"
end

-- True when the cursor is over a selectable vanilla node button. Mirrors the hit-test in
-- MenuInput:mouse_moved so our position-aware input_focus yields to the node ONLY while the cursor is
-- actually on one of its buttons -- keeping controller A position-accurate (empty space, or our own
-- widgets, never activates a stale node selection). Same node_gui/row_item API the engine uses there.
function CSR_ControllerNav.cursor_over_node_item(x, y)
	local menu = managers.menu:active_menu()
	local node_gui = menu and menu.renderer and menu.renderer:active_node_gui()
	if not node_gui or node_gui.CUSTOM_MOUSE_INPUT or not node_gui.row_items then
		return false
	end
	local logic = menu.logic
	local inside_parent = node_gui:item_panel_parent():inside(x, y)
	for _, row_item in pairs(node_gui.row_items) do
		local over = false
		if row_item.item and row_item.item:parameters().pd2_corner then
			over = row_item.gui_text and row_item.gui_text:inside(x, y)
		elseif inside_parent and row_item.gui_panel then
			over = row_item.gui_panel:inside(x, y)
		end
		if over then
			local item = logic and logic:get_item(row_item.name)
			if item and not item.no_mouse_select then
				return true
			end
		end
	end
	return false
end

function CSR_ControllerNav.install_nav_suppression()
	if CSR_ControllerNav._nav_patched or not _G.MenuInput then
		return
	end
	CSR_ControllerNav._nav_patched = true

	local orig_up = MenuInput.menu_up_input_bool
	function MenuInput:menu_up_input_bool(...)
		if csr_suppress_cursor_nav(self) then
			return false
		end
		return orig_up(self, ...)
	end

	local orig_down = MenuInput.menu_down_input_bool
	function MenuInput:menu_down_input_bool(...)
		if csr_suppress_cursor_nav(self) then
			return false
		end
		return orig_down(self, ...)
	end

	-- Briefing (asset move) and endscreen (tab switch) also carry horizontal stick nav; neuter it
	-- too so the cursor is the sole selector. Bumper paging (previous_page/next_page) is a separate
	-- input and stays live.
	local orig_left = MenuInput.menu_left_input_bool
	function MenuInput:menu_left_input_bool(...)
		if csr_suppress_cursor_nav(self) then
			return false
		end
		return orig_left(self, ...)
	end

	local orig_right = MenuInput.menu_right_input_bool
	function MenuInput:menu_right_input_bool(...)
		if csr_suppress_cursor_nav(self) then
			return false
		end
		return orig_right(self, ...)
	end
end

-- ============================================================
-- Controller cursor -- magnet on stick release, d-pad list scrolling
-- ============================================================

-- While a stick is held the cursor is free; the frame it centres, the cursor glides to the middle
-- of the nearest thing that is clickable RIGHT NOW. Each CSR surface lists those through
-- csr_magnet_targets(out); vanilla node buttons are added here so RESUME/OPTIONS pull too.
-- Radius scales with the pointer workspace so it means the same at any resolution, and stays small:
-- a wide reach turns free aiming into snapping between buttons.
local MAGNET_RADIUS_FRACTION = 0.03
local MAGNET_DEADZONE = 0.12
-- Exponential approach per second. Kept gentle on purpose: the pull should read as the cursor
-- settling onto what it was already next to, not as the menu grabbing it.
local MAGNET_GLIDE_SPEED = 6
local MAGNET_ARRIVED = 1.5

local magnet_x, magnet_y = nil, nil
local magnet_stick_held = false
local magnet_targets = {}

-- Both sticks steer: menu_move is the left one (menuinput.lua:924 reads it), look the right. A
-- connection this wrapper does not carry is skipped -- get_input_axis logs an error for those.
local STICK_AXES = { "menu_move", "look" }

function CSR_ControllerNav.stick_axis(ctrl)
	if not (ctrl and ctrl.get_input_axis) then
		return 0, 0
	end
	local map = ctrl.get_connection_map and ctrl:get_connection_map()
	local x, y = 0, 0
	for _, name in ipairs(STICK_AXES) do
		if not map or map[name] then
			local axis = ctrl:get_input_axis(name)
			if axis then
				x = x + axis.x
				y = y + axis.y
			end
		end
	end

	return math.clamp(x, -1, 1), math.clamp(y, -1, 1)
end

-- Targets are plain gui objects; a hidden or dead one is dropped here so callers can stay terse.
function CSR_ControllerNav.add_target(out, obj)
	if obj and alive(obj) and obj:visible() then
		table.insert(out, obj)
	end
end

-- CSRSidebar rows (lobby and briefing share the class): collapsed hides everything but the toggle,
-- and accepts_interaction() is what its own mouse_moved gates hover on.
function CSR_ControllerNav.add_sidebar_targets(out, sidebar)
	if not (sidebar and sidebar._buttons) then
		return
	end
	for _, btn in ipairs(sidebar._buttons) do
		local live = (btn == sidebar._toggle or not sidebar._collapsed)
			and (not btn.accepts_interaction or btn:accepts_interaction())
		if live and btn.panel then
			CSR_ControllerNav.add_target(out, btn:panel())
		end
	end
end

-- Feature panels (Items / Modifiers / Preferences) are built by the same borrowed helpers on every
-- surface that has them, so their clickables collect identically everywhere.
function CSR_ControllerNav.add_feature_panel_targets(out, component)
	local panels = component._feature_panels
	if not panels then
		return
	end
	local prefs = panels.preferences
	if prefs and alive(prefs) and prefs:visible() and component._preferences_buttons then
		for _, btn in ipairs(component._preferences_buttons) do
			CSR_ControllerNav.add_target(out, btn.panel)
		end
	end
	local mods = panels.modifiers
	if mods and alive(mods) and mods:visible() and component._modifiers_subtab_buttons then
		for _, btn in pairs(component._modifiers_subtab_buttons) do
			CSR_ControllerNav.add_target(out, btn.panel)
		end
	end
end

-- Vanilla node buttons, hit-tested the way MenuInput:mouse_moved does.
local function add_node_targets(out)
	local menu = managers.menu:active_menu()
	local node_gui = menu and menu.renderer and menu.renderer:active_node_gui()
	if not node_gui or node_gui.CUSTOM_MOUSE_INPUT or not node_gui.row_items then
		return
	end
	local logic = menu.logic
	for _, row_item in pairs(node_gui.row_items) do
		local item = logic and row_item.name and logic:get_item(row_item.name)
		if item and not item.no_mouse_select then
			if row_item.item and row_item.item:parameters().pd2_corner then
				CSR_ControllerNav.add_target(out, row_item.gui_text)
			else
				CSR_ControllerNav.add_target(out, row_item.gui_panel)
			end
		end
	end
end

-- Held-d-pad scroll rate for the Modifiers list, in canvas pixels per second. Vanilla's wheel step
-- (SCROLL_SPEED 28 * dt * 200, scrollablepanel.lua:331) is a per-notch impulse, far too fast to
-- repeat every frame.
local PAD_SCROLL_SPEED = 400

-- D-pad scrolls the Modifiers list on every surface that carries it (lobby, briefing, pause panel --
-- all three build it from the same borrowed helper). Both sticks are the cursor and the list has no
-- other pad input; menu_up/menu_down are the d-pad connections, and our nav suppression already stops
-- the node logic from consuming them here.
-- Vanilla repeats an arrow press only from ScrollablePanel:mouse_moved while its own _pressing_arrow
-- flag is set (scrollablepanel.lua:483), and a controller confirm is replayed as press+release inside
-- one frame, so the flag never survives long enough to scroll anything. Hold A over an arrow and
-- scroll it here instead. Child names are the engine's (scrollablepanel.lua:515-520).
local SCROLL_ARROWS = { scroll_up_indicator_arrow = 1, scroll_down_indicator_arrow = -1 }

local function pad_scroll_arrows(scroll, ctrl, mp, dt)
	if not ctrl:get_input_bool("confirm") then
		return false
	end
	local panel = scroll:panel()
	if not alive(panel) then
		return false
	end
	-- Arrows are hit-tested in the same safe-rect space the components use.
	local x, y = mp:convert_mouse_pos(mp:world_position())
	for name, dir in pairs(SCROLL_ARROWS) do
		local arrow = panel:child(name)
		if alive(arrow) and arrow:inside(x, y) then
			scroll:perform_scroll(PAD_SCROLL_SPEED * dt, dir)

			return true
		end
	end

	return false
end

-- Dragging the scroll bar with A. Vanilla's own grab flag is useless here: replay_click sends
-- mouse_pressed and mouse_released in the same frame, so _grabbed_scroll_bar is cleared again before
-- any mouse_moved can act on it (a trace showed our grab standing while vanilla's read false frame
-- after frame). So keep the drag entirely on our side -- remember the cursor y from frame to frame
-- and feed the delta to the same scroll_with_bar the mouse drag uses -- and hold vanilla's flag down
-- so a stray press cannot start a second drag on top of ours.
local pad_grabbed_scroll = nil
local pad_drag_y = 0

local function pad_release_scroll_bar()
	pad_grabbed_scroll = nil
end

local function pad_drag_scroll_bar(scroll, ctrl, mp)
	if not ctrl:get_input_bool("confirm") then
		pad_release_scroll_bar()

		return false
	end
	local x, y = mp:convert_mouse_pos(mp:world_position())
	if pad_grabbed_scroll ~= scroll then
		local bar = scroll._scroll_bar
		if not (alive(bar) and bar:visible() and bar:inside(x, y)) then
			return false
		end
		pad_grabbed_scroll = scroll
		pad_drag_y = y

		return true
	end
	scroll._grabbed_scroll_bar = false
	if y ~= pad_drag_y then
		-- (new cursor y, previous cursor y) -- the exact call ScrollablePanel:mouse_moved makes.
		scroll:scroll_with_bar(y, pad_drag_y)
		pad_drag_y = y
	end

	return true
end

-- Returns true when A is doing something to the list, so the caller leaves the cursor alone.
local function pad_scroll_modifiers(component, ctrl, mp, dt)
	local scroll = component._modifiers_scroll
	if not (scroll and component._modifiers_scroll_visible and component:_modifiers_scroll_visible()) then
		pad_release_scroll_bar()

		return false
	end
	if pad_drag_scroll_bar(scroll, ctrl, mp) then
		return true
	end
	if pad_scroll_arrows(scroll, ctrl, mp, dt) then
		return true
	end
	local dir = 0
	if ctrl:get_input_bool("menu_up") then
		dir = 1
	elseif ctrl:get_input_bool("menu_down") then
		dir = -1
	end
	if dir ~= 0 then
		scroll:perform_scroll(PAD_SCROLL_SPEED * dt, dir)
	end

	return false
end

-- The CSR surface currently holding the virtual cursor, or nil.
local function magnet_component()
	local mc = managers.menu_component
	if not mc or _G._csr_item_selection then
		return nil
	end
	local guis = {
		mc._crime_spree_missions,
		mc._ingame_contract_gui,
		mc._mission_briefing_gui,
		mc._stage_endscreen_gui,
	}
	for _, gui in pairs(guis) do
		if gui and gui._csr_controller_mouse then
			return gui
		end
	end

	return nil
end

-- Distance from the cursor to the object's rectangle, not its centre: a long row should not lose to
-- a small button just because its middle is further away. Returns nil when out of reach.
local function target_score(obj, x, y, radius)
	local ox, oy = obj:world_position()
	local ow, oh = obj:w(), obj:h()
	local cx = math.clamp(x, ox, ox + ow)
	local cy = math.clamp(y, oy, oy + oh)
	local dx, dy = x - cx, y - cy
	local dist = math.sqrt(dx * dx + dy * dy)
	if dist > radius then
		return nil
	end

	return dist, ox + ow * 0.5, oy + oh * 0.5
end

local function magnet_pick(component, mp)
	for i = #magnet_targets, 1, -1 do
		magnet_targets[i] = nil
	end
	if component.csr_magnet_targets then
		component:csr_magnet_targets(magnet_targets)
	end
	add_node_targets(magnet_targets)
	if #magnet_targets == 0 then
		return nil
	end
	-- Components hit-test in safe-rect coordinates (MenuInput converts once, menuinput.lua:169), and
	-- their panels live in that space; the pointer itself is in full-rect coordinates.
	local x, y = mp:convert_mouse_pos(mp:world_position())
	-- Radius in the same safe-rect units the distance is measured in (gui_data:scaled_size is what
	-- vanilla lays menus out against, menupauserenderer.lua:52).
	local scaled = managers.gui_data and managers.gui_data:scaled_size()
	local radius = ((scaled and scaled.height) or 720) * MAGNET_RADIUS_FRACTION
	local best_dist, best_x, best_y
	for _, obj in ipairs(magnet_targets) do
		if alive(obj) then
			local dist, tx, ty = target_score(obj, x, y, radius)
			if dist and (not best_dist or dist < best_dist) then
				best_dist, best_x, best_y = dist, tx, ty
			end
		end
	end
	if not best_dist then
		return nil
	end

	return managers.gui_data:safe_to_full(best_x, best_y)
end

local pad_update_t = nil

local function pad_update(t, dt)
	local component = magnet_component()
	if not component then
		magnet_x, magnet_y = nil, nil
		magnet_stick_held = false
		pad_release_scroll_bar()
		return
	end
	-- Two of the hooks below can fire in the same frame (an MP pause keeps the game running); the
	-- glide and the scroll both advance by dt, so run them once.
	if t == pad_update_t then
		return
	end
	pad_update_t = t
	local menu = managers.menu:active_menu()
	local ctrl = menu and menu.input and menu.input._controller
	local mp = managers.mouse_pointer
	if not (ctrl and mp and mp.mouse) then
		return
	end
	dt = dt or 0
	if pad_scroll_modifiers(component, ctrl, mp, dt) then
		-- Holding A on the bar or an arrow: a magnet glide here would drag the cursor off it.
		magnet_x, magnet_y = nil, nil

		return
	end
	local ax, ay = CSR_ControllerNav.stick_axis(ctrl)
	if math.abs(ax) > MAGNET_DEADZONE or math.abs(ay) > MAGNET_DEADZONE then
		-- Steering again cancels a glide in progress, so the magnet never fights the player.
		magnet_stick_held = true
		magnet_x, magnet_y = nil, nil
		return
	end
	if magnet_stick_held then
		magnet_stick_held = false
		magnet_x, magnet_y = magnet_pick(component, mp)
	end
	if not magnet_x then
		return
	end
	local mouse = mp:mouse()
	if not mouse then
		magnet_x, magnet_y = nil, nil
		return
	end
	local x, y = mouse:world_position()
	if math.abs(magnet_x - x) < MAGNET_ARRIVED and math.abs(magnet_y - y) < MAGNET_ARRIVED then
		mp:set_mouse_world_position(magnet_x, magnet_y)
		magnet_x, magnet_y = nil, nil
		return
	end
	local f = math.min(dt * MAGNET_GLIDE_SPEED, 1)
	mp:set_mouse_world_position(x + (magnet_x - x) * f, y + (magnet_y - y) * f)
end

if Hooks then
	-- Menu state for the lobby/briefing/endscreen, both game-state updates for the ESC panel (SP
	-- pause runs the paused one, MP keeps the game running).
	Hooks:Add("MenuUpdate", "CSR_ControllerNav_Magnet_Menu", pad_update)
	Hooks:Add("GameSetupUpdate", "CSR_ControllerNav_Magnet_Game", pad_update)
	Hooks:Add("GameSetupPausedUpdate", "CSR_ControllerNav_Magnet_Paused", pad_update)
end

function CSR_ControllerNav:init()
	self._targets = {}
	self._focus_id = nil
end

function CSR_ControllerNav:_find(id)
	for _, t in ipairs(self._targets) do
		if t.id == id then
			return t
		end
	end
	return nil
end

function CSR_ControllerNav:_set_focus(id)
	if self._focus_id == id then
		return
	end
	local prev = self:_find(self._focus_id)
	if prev and prev.on_focus then
		prev.on_focus(false)
	end
	self._focus_id = id
	local cur = self:_find(id)
	if cur and cur.on_focus then
		cur.on_focus(true)
	end
end

-- Rebuild the target set. Keep focus on the same id when it still exists.
function CSR_ControllerNav:set_targets(targets)
	local keep = self._focus_id
	self._targets = targets or {}
	local present = false
	for _, t in ipairs(self._targets) do
		if t.id == keep then
			present = true
			break
		end
	end
	if not present then
		self._focus_id = nil
	end
end

function CSR_ControllerNav:focus_id()
	return self._focus_id
end

function CSR_ControllerNav:set_focus(id)
	self:_set_focus(id)
end

function CSR_ControllerNav:clear()
	self:_set_focus(nil)
end

-- Score a candidate center for a move in dir from origin (ox,oy).
-- Candidate must lie in the pressed half-plane; perpendicular offset is
-- penalised so the widget most "in line" with the direction wins.
-- Returns nil when the candidate is not in the pressed direction.
local function score(dir, ox, oy, cx, cy)
	local dx, dy = cx - ox, cy - oy
	if dir == "left" then
		if dx >= -1 then
			return nil
		end
		return -dx + math.abs(dy) * 2
	elseif dir == "right" then
		if dx <= 1 then
			return nil
		end
		return dx + math.abs(dy) * 2
	elseif dir == "up" then
		if dy >= -1 then
			return nil
		end
		return -dy + math.abs(dx) * 2
	elseif dir == "down" then
		if dy <= 1 then
			return nil
		end
		return dy + math.abs(dx) * 2
	end
	return nil
end

function CSR_ControllerNav:move(dir)
	if #self._targets == 0 then
		return false
	end
	local cur = self:_find(self._focus_id)
	if not cur then
		self:_set_focus(self._targets[1].id)
		return true
	end
	local best, best_score
	for _, t in ipairs(self._targets) do
		if t.id ~= cur.id then
			local s = score(dir, cur.cx, cur.cy, t.cx, t.cy)
			if s and (not best_score or s < best_score) then
				best, best_score = t, s
			end
		end
	end
	if best then
		self:_set_focus(best.id)
		return true
	end
	return false
end

function CSR_ControllerNav:confirm()
	local cur = self:_find(self._focus_id)
	if cur and cur.on_confirm then
		cur.on_confirm()
		return true
	end
	return false
end
