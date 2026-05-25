-- Crime Spree Roguelike - Gage's Services Menu Component.
-- Full-screen menu node (940x600 centered panel), modelled on the U1 logbook
-- component (logbook_menu.lua) — same node+component+open_node lifecycle. Hosts
-- internal tabs (Shop is currently the only one; built for expansion) and a
-- title + close button. The shop page content lives in black_market_shop_page.lua.
--
-- U1 port note: the pre-refactor version also suppressed the end-screen UI when
-- opened over the victory screen. That's dropped here — the U1 shop opens from
-- the lobby sidebar (like the logbook), not the end screen. Re-add a
-- _suppress_endscreen pass (see the logbook component) if/when the shop becomes
-- reachable from the end screen.

if not RequiredScript then
	return
end

CrimeSpreeBlackMarketMenuComponent = CrimeSpreeBlackMarketMenuComponent or class()

function CrimeSpreeBlackMarketMenuComponent:init(ws, fullscreen_ws, node)
	if not ws or not fullscreen_ws then
		return
	end
	if not managers or not managers.menu then
		return
	end

	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._node = node
	self._init_layer = ws:panel():layer()

	self._tab_buttons = {}
	self._tab_panels = {}
	self._current_tab = nil
	self._last_hovered_id = nil

	self:_setup()

	-- Swap menu music to the vanilla "lets_go_shopping_menu" track for the
	-- duration of the shop; close() restores whatever was playing before.
	self._prev_music_event = Global and Global.music_manager and Global.music_manager.current_event or nil
	pcall(function()
		if managers and managers.music and managers.music.post_event then
			managers.music:post_event("stop_all_music")
			managers.music:post_event("lets_go_shopping_menu")
		end
	end)
end

function CrimeSpreeBlackMarketMenuComponent:_setup()
	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = parent:panel({
		name = "csr_black_market_panel",
		layer = self._init_layer + 10,
	})

	local panel_w = 940
	-- Height matches the vanilla weapon-select grid (BlackMarketGui): a fraction of
	-- the workspace, so it scales with resolution instead of a fixed number.
	-- GRID_H_MUL = (6.9 or 6.95)/8; the -70 mirrors BlackMarketGui's grid_size offset.
	local grid_h_mul = (NOT_WIN_32 and 6.9 or 6.95) / 8
	local panel_h = math.floor((self._panel:h() - 70) * grid_h_mul)

	self._content_panel = self._panel:panel({
		name = "csr_black_market_content",
		w = panel_w,
		h = panel_h,
		layer = 10,
	})
	self._content_panel:set_center_x(self._panel:w() / 2)
	self._content_panel:set_center_y(self._panel:h() / 2)

	-- Panel background + border.
	self._content_panel:rect({
		color = Color.black,
		alpha = 0.92,
		layer = -1,
	})
	BoxGuiObject:new(self._content_panel, {
		sides = { 2, 2, 2, 2 },
	})

	-- Branded header OUTSIDE the content box, in the lobby "CRIME SPREE ROGUELIKE"
	-- style: a crisp pd2_large foreground over a huge faded-blue pd2_massive ghost.
	-- Both layers live on the OUTER panel (not the box) and anchor just above the
	-- box's top-left, so the ghost spills over the backdrop like the lobby title.
	-- Ghost on a low layer (behind the box) so its lower half is masked by the box.
	local header_label = managers.localization:text("csr_black_market_title")
	local header_ghost = self._panel:text({
		name = "csr_header_ghost",
		vertical = "top",
		align = "left",
		alpha = 0.4,
		h = 90,
		text = header_label,
		font = tweak_data.menu.pd2_massive_font,
		font_size = tweak_data.menu.pd2_massive_font_size,
		color = tweak_data.screen_colors.button_stage_3,
		layer = 5,
	})
	local header = self._panel:text({
		name = "csr_header",
		vertical = "top",
		align = "left",
		text = header_label,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = tweak_data.screen_colors.text,
		layer = 60,
	})
	local _, _, header_w, header_h = header:text_rect()
	header:set_size(header_w, header_h)
	-- Same spot as the lobby title: (0,0) of the (safe-workspace) outer panel, i.e.
	-- the safe-area top-left corner. These menus share the lobby's safe self._ws, so
	-- the lobby's implicit (0,0) maps here 1:1.
	header:set_left(0)
	header:set_top(0)
	header_ghost:set_world_left(header:world_left())
	header_ghost:set_world_center_y(header:world_center_y())
	header_ghost:move(-13, 9)

	-- PD2-style BACK button at the workspace bottom-right (replaces the old top-right
	-- close X). Same action -- managers.menu:back() -- the X had. Mirrors vanilla
	-- BlackMarketGui's back_button (blackmarketgui.lua:2573): pd2_large, button_stage_3,
	-- flush bottom-right of the outer panel, symmetric with the top-left header.
	self._back_button = self._panel:text({
		name = "csr_back_button",
		vertical = "bottom",
		align = "right",
		text = utf8.to_upper(managers.localization:text("menu_back")),
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = tweak_data.screen_colors.button_stage_3,
		layer = 60,
	})
	local _, _, back_w, back_h = self._back_button:text_rect()
	self._back_button:set_size(back_w, back_h)
	self._back_button:set_right(self._panel:w())
	self._back_button:set_bottom(self._panel:h())

	-- Single shop "tab": the lone SHOP button was redundant, so no tab bar is
	-- drawn. _tab_definitions still drives _create_tab_panels / _switch_tab, and
	-- the (empty) _tab_buttons table keeps the mouse/colour loops as harmless no-ops.
	self._tab_definitions = {
		{ id = "shop", label_key = "csr_black_market_tab_shop" },
	}
	self:_create_tab_panels()
	self:_switch_tab("shop")
end

function CrimeSpreeBlackMarketMenuComponent:_create_tab_panels()
	-- Title now lives OUTSIDE the box, so content starts near the top (was y=60 to
	-- clear the in-box title) and reclaims that strip. Bottom margin 20px.
	local panel_w = self._content_panel:w() - 40
	local panel_x = 20
	local panel_y = 10
	local panel_h = self._content_panel:h() - panel_y - 20

	for _, def in ipairs(self._tab_definitions) do
		self._tab_panels[def.id] = self._content_panel:panel({
			name = "csr_tab_" .. def.id,
			x = panel_x,
			y = panel_y,
			w = panel_w,
			h = panel_h,
			layer = 8,
			visible = false,
		})
	end
end

function CrimeSpreeBlackMarketMenuComponent:_switch_tab(tab_id)
	self._current_tab = tab_id

	-- Tab button colours: selected = gold bg / black text; others = dim.
	for id, button in pairs(self._tab_buttons) do
		if id == tab_id then
			button.bg:set_color(Color(1, 0.85, 0.7, 0.2))
			button.text:set_color(Color.black)
		else
			button.bg:set_color(Color(1, 0.15, 0.15, 0.15))
			button.text:set_color(Color(1, 0.5, 0.5, 0.5))
		end
	end

	for id, panel in pairs(self._tab_panels) do
		panel:set_visible(id == tab_id)
	end

	-- Lazy-populate the shop page on first switch to the tab.
	if tab_id == "shop" and not self._shop_populated then
		if CrimeSpreeBlackMarketShopPage then
			self._shop_page = CrimeSpreeBlackMarketShopPage:new(self._tab_panels["shop"], self)
		end
		self._shop_populated = true
	end
end

function CrimeSpreeBlackMarketMenuComponent:close()
	-- Clear the live-instance global before destroying the panel so external
	-- callers don't refresh a dead Diesel object (C++ access violation).
	if _G.CSR_BlackMarketShopPageInstance == self._shop_page then
		_G.CSR_BlackMarketShopPageInstance = nil
	end
	if self._panel and alive(self._panel) and self._ws then
		self._ws:panel():remove(self._panel)
	end
	-- Restore whatever ambient music was playing before the shop opened.
	pcall(function()
		if managers and managers.music and managers.music.post_event then
			managers.music:post_event("stop_all_music")
			local prev = self._prev_music_event
			if prev and prev ~= "stop_all_music" and prev ~= "lets_go_shopping_menu" then
				managers.music:post_event(prev)
			elseif managers.music.jukebox_menu_track then
				managers.music:post_event(managers.music:jukebox_menu_track("mainmenu"))
			end
		end
	end)
end

function CrimeSpreeBlackMarketMenuComponent:input_focus()
	return 1
end

function CrimeSpreeBlackMarketMenuComponent:mouse_moved(o, x, y)
	if not self._content_panel then
		return false
	end

	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Back button hover (bottom-right): brighten on hover, dim otherwise.
	if self._back_button and alive(self._back_button) then
		if self._back_button:inside(x, y) then
			self._back_button:set_color(tweak_data.screen_colors.button_stage_2)
			if self._last_hovered_id ~= "back_btn" then
				self._last_hovered_id = "back_btn"
				managers.menu_component:post_event("highlight")
			end
			return true, "link"
		else
			self._back_button:set_color(tweak_data.screen_colors.button_stage_3)
		end
	end

	-- Tab bar hover.
	for tab_id, button in pairs(self._tab_buttons) do
		if
			local_x >= button.x
			and local_x <= button.x + button.w
			and local_y >= button.y
			and local_y <= button.y + button.h
		then
			if self._last_hovered_id ~= "tab_" .. tab_id then
				self._last_hovered_id = "tab_" .. tab_id
				managers.menu_component:post_event("highlight")
			end
			return true, "link"
		end
	end

	self._last_hovered_id = nil

	-- Delegate to the active tab's page.
	if self._shop_page and self._current_tab == "shop" and self._shop_page.mouse_moved then
		return self._shop_page:mouse_moved(o, x, y)
	end

	return false, "arrow"
end

function CrimeSpreeBlackMarketMenuComponent:mouse_pressed(button, x, y)
	if not self._content_panel then
		return
	end

	-- Ignore right clicks.
	if button == Idstring("1") then
		return
	end

	-- Back button click (bottom-right).
	if self._back_button and alive(self._back_button) and self._back_button:inside(x, y) then
		managers.menu_component:post_event("menu_back")
		managers.menu:back()
		return true
	end

	-- Delegate to the active tab's page.
	if self._shop_page and self._current_tab == "shop" and self._shop_page.mouse_pressed then
		return self._shop_page:mouse_pressed(button, x, y)
	end

	return false
end

function CrimeSpreeBlackMarketMenuComponent:mouse_released(o, button, x, y)
	if not self._content_panel then
		return false
	end

	if button == Idstring("1") then
		return false
	end

	if not x or not y then
		if managers.mouse_pointer then
			x, y = managers.mouse_pointer:world_position()
		end
	end

	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Tab bar click switches the active tab.
	for tab_id, button_data in pairs(self._tab_buttons) do
		if
			local_x >= button_data.x
			and local_x <= button_data.x + button_data.w
			and local_y >= button_data.y
			and local_y <= button_data.y + button_data.h
		then
			managers.menu_component:post_event("menu_enter")
			self:_switch_tab(tab_id)
			return true
		end
	end

	return false
end

function CrimeSpreeBlackMarketMenuComponent:mouse_wheel_up(x, y)
	return true
end

function CrimeSpreeBlackMarketMenuComponent:mouse_wheel_down(x, y)
	return true
end
