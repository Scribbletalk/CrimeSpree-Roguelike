-- Crime Spree Roguelike - Gage's Services Menu Component.
-- Full-screen menu node (940x600 centered panel), modelled on the U1 logbook
-- component (logbook_menu.lua) — same node+component+open_node lifecycle. Hosts
-- internal tabs (Shop is currently the only one; built for expansion) and a
-- title + close button. The shop page content lives in gage_services_shop_page.lua.
--
-- U1 port note: the pre-refactor version also suppressed the end-screen UI when
-- opened over the victory screen. That's dropped here — the U1 shop opens from
-- the lobby sidebar (like the logbook), not the end screen. Re-add a
-- _suppress_endscreen pass (see the logbook component) if/when the shop becomes
-- reachable from the end screen.

if not RequiredScript then
	return
end

CrimeSpreeGageServicesMenuComponent = CrimeSpreeGageServicesMenuComponent or class()

function CrimeSpreeGageServicesMenuComponent:init(ws, fullscreen_ws, node)
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

function CrimeSpreeGageServicesMenuComponent:_setup()
	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = parent:panel({
		name = "csr_gage_services_panel",
		layer = self._init_layer + 10,
	})

	local panel_w = 940
	local panel_h = 600

	self._content_panel = self._panel:panel({
		name = "csr_gage_services_content",
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

	-- Title (top-left).
	self._content_panel:text({
		name = "title",
		text = managers.localization:text("csr_gage_services_title"),
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = Color.white,
		x = 20,
		y = 10,
		layer = 10,
	})

	-- Close button (top-right corner).
	local close_icon_size = 20
	local close_hitbox = 24
	local btn_padding = 8
	self._close_btn_panel = self._content_panel:panel({
		name = "close_btn",
		w = close_hitbox,
		h = close_hitbox,
		layer = 10,
	})
	self._close_btn_panel:set_right(panel_w - btn_padding)
	self._close_btn_panel:set_y(btn_padding)
	local close_offset = math.round((close_hitbox - close_icon_size) / 2)
	self._close_btn_panel:bitmap({
		texture = "guis/textures/pd2/crime_spree/csr_btn_close",
		w = close_icon_size,
		h = close_icon_size,
		x = close_offset,
		y = close_offset,
		blend_mode = "add",
		color = tweak_data.screen_colors.text,
	})

	-- Single shop "tab": the lone SHOP button was redundant, so no tab bar is
	-- drawn. _tab_definitions still drives _create_tab_panels / _switch_tab, and
	-- the (empty) _tab_buttons table keeps the mouse/colour loops as harmless no-ops.
	self._tab_definitions = {
		{ id = "shop", label_key = "csr_gage_services_tab_shop" },
	}
	self:_create_tab_panels()
	self:_switch_tab("shop")
end

function CrimeSpreeGageServicesMenuComponent:_create_tab_panels()
	-- Content sits just below the title now that the tab bar is gone (was y=100
	-- to clear the bar; the shop page needs >=480px and gets 520 here).
	local panel_w = self._content_panel:w() - 40
	local panel_h = self._content_panel:h() - 80
	local panel_x = 20
	local panel_y = 60

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

function CrimeSpreeGageServicesMenuComponent:_switch_tab(tab_id)
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
		if CrimeSpreeGageServicesShopPage then
			self._shop_page = CrimeSpreeGageServicesShopPage:new(self._tab_panels["shop"], self)
		end
		self._shop_populated = true
	end
end

function CrimeSpreeGageServicesMenuComponent:close()
	-- Clear the live-instance global before destroying the panel so external
	-- callers don't refresh a dead Diesel object (C++ access violation).
	if _G.CSR_GageServicesShopPageInstance == self._shop_page then
		_G.CSR_GageServicesShopPageInstance = nil
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

function CrimeSpreeGageServicesMenuComponent:input_focus()
	return 1
end

function CrimeSpreeGageServicesMenuComponent:mouse_moved(o, x, y)
	if not self._content_panel then
		return false
	end

	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Close button hover.
	if self._close_btn_panel and alive(self._close_btn_panel) and self._close_btn_panel:inside(x, y) then
		if self._last_hovered_id ~= "close_btn" then
			self._last_hovered_id = "close_btn"
			managers.menu_component:post_event("highlight")
		end
		return true, "link"
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

function CrimeSpreeGageServicesMenuComponent:mouse_pressed(button, x, y)
	if not self._content_panel then
		return
	end

	-- Ignore right clicks.
	if button == Idstring("1") then
		return
	end

	-- Close button click.
	if self._close_btn_panel and alive(self._close_btn_panel) and self._close_btn_panel:inside(x, y) then
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

function CrimeSpreeGageServicesMenuComponent:mouse_released(o, button, x, y)
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

function CrimeSpreeGageServicesMenuComponent:mouse_wheel_up(x, y)
	return true
end

function CrimeSpreeGageServicesMenuComponent:mouse_wheel_down(x, y)
	return true
end
