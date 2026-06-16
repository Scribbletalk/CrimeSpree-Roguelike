-- Gage's Services full-screen menu component. Shop page content lives in black_market_shop_page.lua.

if not RequiredScript then
	return
end

CrimeSpreeBlackMarketMenuComponent = CrimeSpreeBlackMarketMenuComponent or class()

-- Hide the briefing's heist-NAME title while Gage's Services is open so it doesn't bleed through
-- behind the top-left BLACK MARKET header. Two separate elements carry the name:
--   (1) MissionBriefingGui._panel  -- small description-tab title.
--   (2) HUDMissionBriefing layers  -- the prominent "CONTACT: JOBNAME" title (solid on
--       _foreground_layer_one + faded ghost on _background_layer_three), both named "job_text".
-- Vanilla MissionBriefingGui:hide() only dims to alpha 0.5, and the HUD title isn't touched at
-- all -- so the name stays readable. No-op when no briefing is present.
function CrimeSpreeBlackMarketMenuComponent:_suppress_briefing()
	local mbg = managers.menu_component and managers.menu_component._mission_briefing_gui
	if mbg and mbg._panel and alive(mbg._panel) then
		self._mbg = mbg
		self._mbg_panel_was_visible = mbg._panel:visible()
		mbg._panel:set_visible(false)
	end

	local hud = managers.hud and managers.hud._hud_mission_briefing
	if hud then
		local fg = hud._foreground_layer_one
		local bg = hud._background_layer_three
		self._mb_job_text_fg = fg and alive(fg) and fg:child("job_text") or nil
		self._mb_job_text_bg = bg and alive(bg) and bg:child("job_text") or nil
		if self._mb_job_text_fg then
			self._mb_job_text_fg:set_visible(false)
		end
		if self._mb_job_text_bg then
			self._mb_job_text_bg:set_visible(false)
		end
	end
end

function CrimeSpreeBlackMarketMenuComponent:_restore_briefing()
	local mbg = self._mbg
	if mbg and self._mbg_panel_was_visible ~= nil and mbg._panel and alive(mbg._panel) then
		mbg._panel:set_visible(self._mbg_panel_was_visible)
	end
	if self._mb_job_text_fg and alive(self._mb_job_text_fg) then
		self._mb_job_text_fg:set_visible(true)
	end
	if self._mb_job_text_bg and alive(self._mb_job_text_bg) then
		self._mb_job_text_bg:set_visible(true)
	end
	self._mbg = nil
	self._mbg_panel_was_visible = nil
	self._mb_job_text_fg = nil
	self._mb_job_text_bg = nil
end

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
	self:_suppress_briefing()

	-- Swap to shopping music; close() restores it.
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
	-- Height mirrors BlackMarketGui's grid_size formula so it scales with resolution.
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

	self._content_panel:rect({
		color = Color.black,
		alpha = 0.92,
		layer = -1,
	})
	BoxGuiObject:new(self._content_panel, {
		sides = { 2, 2, 2, 2 },
	})

	-- pd2_large foreground + faded pd2_massive ghost on the outer panel, matching lobby title style.
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
	header:set_left(0)
	header:set_top(0)
	self._header = header -- exposed so the shop page can align its owned-items strip
	header_ghost:set_world_left(header:world_left())
	header_ghost:set_world_center_y(header:world_center_y())
	header_ghost:move(-13, 9)

	-- BACK button flush bottom-right, mirroring vanilla BlackMarketGui layout.
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

	-- No tab bar drawn (single tab); _tab_buttons stays empty so hover/click loops are no-ops.
	self._tab_definitions = {
		{ id = "shop", label_key = "csr_black_market_tab_shop" },
	}
	self:_create_tab_panels()
	self:_switch_tab("shop")
end

function CrimeSpreeBlackMarketMenuComponent:_create_tab_panels()
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

	if tab_id == "shop" and not self._shop_populated then
		if CrimeSpreeBlackMarketShopPage then
			self._shop_page = CrimeSpreeBlackMarketShopPage:new(self._tab_panels["shop"], self)
		end
		self._shop_populated = true
	end
end

function CrimeSpreeBlackMarketMenuComponent:close()
	-- Nil the global before panel removal to prevent callers from touching a dead Diesel object.
	if _G.CSR_BlackMarketShopPageInstance == self._shop_page then
		_G.CSR_BlackMarketShopPageInstance = nil
	end
	self:_restore_briefing()
	if self._panel and alive(self._panel) and self._ws then
		self._ws:panel():remove(self._panel)
	end
	pcall(function()
		if managers and managers.music and managers.music.post_event then
			-- After a heist the captured pre-shop event is "music_uno_fade_reset": on_mission_end
			-- overwrites Global.current_event with a fade-reset that names no track, so it can't be
			-- replayed. Fall back to the result track recorded at mission end, then to menu music.
			local prev = self._prev_music_event
			if prev == "music_uno_fade_reset" and _G.CSR_post_mission_music then
				prev = _G.CSR_post_mission_music
			end
			if _G.CSR_DEBUG then
				csr_log("[CSR][music] BM close restore: " .. tostring(prev))
			end
			managers.music:post_event("stop_all_music")
			if
				prev
				and prev ~= "stop_all_music"
				and prev ~= "lets_go_shopping_menu"
				and prev ~= "music_uno_fade_reset"
			then
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

	if self._back_button and alive(self._back_button) and self._back_button:inside(x, y) then
		managers.menu_component:post_event("menu_back")
		managers.menu:back()
		return true
	end

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
