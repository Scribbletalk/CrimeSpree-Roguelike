-- Crime Spree Roguelike - Gage's Services Menu Component
-- Full-screen menu, modeled on CrimeSpreeLogbookMenuComponent.
-- Hosts internal tabs (Shop currently the only one; built for expansion).

log("[CSR GAGE] gage_services_menu.lua loaded; RequiredScript=" .. tostring(RequiredScript))
if not RequiredScript then
	return
end

CrimeSpreeGageServicesMenuComponent = CrimeSpreeGageServicesMenuComponent or class()
log("[CSR GAGE] CrimeSpreeGageServicesMenuComponent class defined")

-- Suppress underlying end-screen UI (crew stats / personal stats / mission-end buttons)
-- while the shop is open on top. Without this, those panels stay visible AND clickable
-- through the shop overlay because PD2's MenuComponentManager dispatches mouse events
-- to them BEFORE the shop component (StageEndScreenGui at line 1531; CrimeSpreeMissionEndOptions
-- via run_return_on_all_live_components iteration order, which runs before our component).
function CrimeSpreeGageServicesMenuComponent:_suppress_endscreen()
	local mc = managers.menu_component
	if not mc then
		return
	end

	local sg = mc._stage_endscreen_gui
	if sg then
		self._sg_was_enabled = sg._enabled
		if sg.hide then
			sg:hide() -- sets _enabled=false, fades alpha to 0.5; mouse_pressed/_moved early-return
		end
		if sg._panel and alive(sg._panel) then
			self._sg_panel_was_visible = sg._panel:visible()
			sg._panel:set_visible(false)
		end
		if sg._fullscreen_panel and alive(sg._fullscreen_panel) then
			self._sg_fs_panel_was_visible = sg._fullscreen_panel:visible()
			sg._fullscreen_panel:set_visible(false)
		end
	end

	local cme = mc._crime_spree_mission_end
	if cme then
		if cme._panel and alive(cme._panel) then
			self._cme_panel_was_visible = cme._panel:visible()
			cme._panel:set_visible(false)
		end
		if cme._fullscreen_panel and alive(cme._fullscreen_panel) then
			self._cme_fs_panel_was_visible = cme._fullscreen_panel:visible()
			cme._fullscreen_panel:set_visible(false)
		end
		-- Override instance methods (not class methods) to swallow input while shop is open.
		-- Restored on close by clearing the instance entries so calls fall back to the class.
		self._cme_instance = cme
		cme.mouse_pressed = function()
			return nil
		end
		cme.mouse_moved = function()
			return nil
		end
	end
end

function CrimeSpreeGageServicesMenuComponent:_restore_endscreen()
	local mc = managers.menu_component
	if not mc then
		return
	end

	local sg = mc._stage_endscreen_gui
	if sg then
		if self._sg_panel_was_visible ~= nil and sg._panel and alive(sg._panel) then
			sg._panel:set_visible(self._sg_panel_was_visible)
		end
		if self._sg_fs_panel_was_visible ~= nil and sg._fullscreen_panel and alive(sg._fullscreen_panel) then
			sg._fullscreen_panel:set_visible(self._sg_fs_panel_was_visible)
		end
		if self._sg_was_enabled and sg.show then
			sg:show()
		end
	end

	local cme = self._cme_instance
	if cme then
		if self._cme_panel_was_visible ~= nil and cme._panel and alive(cme._panel) then
			cme._panel:set_visible(self._cme_panel_was_visible)
		end
		if self._cme_fs_panel_was_visible ~= nil and cme._fullscreen_panel and alive(cme._fullscreen_panel) then
			cme._fullscreen_panel:set_visible(self._cme_fs_panel_was_visible)
		end
		-- Clear instance overrides so calls fall back to the class methods
		cme.mouse_pressed = nil
		cme.mouse_moved = nil
	end

	self._sg_was_enabled = nil
	self._sg_panel_was_visible = nil
	self._sg_fs_panel_was_visible = nil
	self._cme_instance = nil
	self._cme_panel_was_visible = nil
	self._cme_fs_panel_was_visible = nil
end

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
	self:_suppress_endscreen()

	-- Swap menu music to vanilla "lets_go_shopping_menu" track for the duration
	-- of the shop. close() restores whatever ambient track was playing (mainmenu
	-- jukebox, briefing music, end-screen music, etc).
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

	-- Panel background
	self._content_panel:rect({
		color = Color.black,
		alpha = 0.92,
		layer = -1,
	})

	-- Border
	BoxGuiObject:new(self._content_panel, {
		sides = { 2, 2, 2, 2 },
	})

	-- Title
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

	-- Close button (top-right corner)
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

	self:_create_tabs()
	self:_create_tab_panels()
	self:_switch_tab("shop")
end

function CrimeSpreeGageServicesMenuComponent:_create_tabs()
	-- Tab definitions: add entries here to expand to more tabs later.
	self._tab_definitions = {
		{ id = "shop", label_key = "csr_gage_services_tab_shop" },
	}

	local panel_w = self._content_panel:w()
	local margin_left = 20
	local margin_right = 20
	local tab_spacing = 10
	local tab_height = 30
	local start_y = 60

	local tabs = self._tab_definitions
	local available_width = panel_w - margin_left - margin_right - (tab_spacing * (#tabs - 1))
	local tab_width = available_width / #tabs

	for i, tab_data in ipairs(tabs) do
		local x = margin_left + (i - 1) * (tab_width + tab_spacing)

		local tab_bg = self._content_panel:rect({
			name = "tab_bg_" .. tab_data.id,
			color = Color(0.2, 0.2, 0.2),
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 5,
		})

		local tab_text = self._content_panel:text({
			name = "tab_text_" .. tab_data.id,
			text = managers.localization:text(tab_data.label_key),
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			align = "center",
			vertical = "center",
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 6,
		})

		self._tab_buttons[tab_data.id] = {
			bg = tab_bg,
			text = tab_text,
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
		}
	end

	-- Divider line below the tab bar
	self._content_panel:rect({
		name = "tabs_divider",
		color = Color(0.4, 0.4, 0.4),
		x = margin_left,
		y = start_y + tab_height + 5,
		w = panel_w - margin_left - margin_right,
		h = 2,
		layer = 5,
	})
end

function CrimeSpreeGageServicesMenuComponent:_create_tab_panels()
	local panel_w = self._content_panel:w() - 40
	local panel_h = self._content_panel:h() - 120
	local panel_x = 20
	local panel_y = 100

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

	-- Update tab button colours
	for id, button in pairs(self._tab_buttons) do
		if id == tab_id then
			button.bg:set_color(Color(0.85, 0.7, 0.2))
			button.text:set_color(Color.black)
		else
			button.bg:set_color(Color(0.15, 0.15, 0.15))
			button.text:set_color(Color(0.5, 0.5, 0.5))
		end
	end

	-- Show/hide tab content panels
	for id, panel in pairs(self._tab_panels) do
		panel:set_visible(id == tab_id)
	end

	-- Lazy-populate the shop page on first switch to the tab
	if tab_id == "shop" and not self._shop_populated then
		if CrimeSpreeGageServicesShopPage then
			self._shop_page = CrimeSpreeGageServicesShopPage:new(self._tab_panels["shop"], self)
		end
		self._shop_populated = true
	end
end

function CrimeSpreeGageServicesMenuComponent:back_pressed()
	managers.menu:back()
end

function CrimeSpreeGageServicesMenuComponent:close()
	self:_restore_endscreen()
	-- Clear the live-instance global before destroying the panel so external
	-- callers (debug menu, sync code) don't try to refresh a dead Diesel object
	-- via _token_text:set_text and trigger a C++ access violation.
	if _G.CSR_GageServicesShopPageInstance == self._shop_page then
		_G.CSR_GageServicesShopPageInstance = nil
	end
	if self._panel and alive(self._panel) and self._ws then
		self._ws:panel():remove(self._panel)
	end
	-- Restore whatever ambient music was playing before the shop opened
	-- (mainmenu jukebox, briefing track, end-screen track, ...).
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

	-- Close button hover
	if self._close_btn_panel and alive(self._close_btn_panel) and self._close_btn_panel:inside(x, y) then
		if self._last_hovered_id ~= "close_btn" then
			self._last_hovered_id = "close_btn"
			managers.menu_component:post_event("highlight")
		end
		return true, "link"
	end

	-- Tab bar hover
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

	-- Delegate to the active tab's page
	if self._shop_page and self._current_tab == "shop" and self._shop_page.mouse_moved then
		return self._shop_page:mouse_moved(o, x, y)
	end

	return false, "arrow"
end

function CrimeSpreeGageServicesMenuComponent:mouse_pressed(button, x, y)
	if not self._content_panel then
		return
	end

	-- Ignore right clicks
	if button == Idstring("1") then
		return
	end

	-- Close button click
	if self._close_btn_panel and alive(self._close_btn_panel) and self._close_btn_panel:inside(x, y) then
		managers.menu_component:post_event("menu_back")
		managers.menu:back()
		return true
	end

	-- Delegate to the active tab's page
	if self._shop_page and self._current_tab == "shop" and self._shop_page.mouse_pressed then
		return self._shop_page:mouse_pressed(button, x, y)
	end

	return false
end

function CrimeSpreeGageServicesMenuComponent:mouse_released(o, button, x, y)
	if not self._content_panel then
		return false
	end

	-- Ignore right clicks
	if button == Idstring("1") then
		return false
	end

	-- Fall back to mouse_pointer if coordinates were not passed
	if not x or not y then
		if managers.mouse_pointer then
			x, y = managers.mouse_pointer:world_position()
		end
	end

	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Tab bar click switches the active tab
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
