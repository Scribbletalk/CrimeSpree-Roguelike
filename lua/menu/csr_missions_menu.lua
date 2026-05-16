-- CSRMissionsMenuComponent — fork of vanilla CrimeSpreeMissionsMenuComponent.
--
-- Origin: pd2_source_code/lib/managers/menu/crimespreemissionsmenucomponent.lua (775 lines)
-- Strategy: byte-for-byte copy with class renames + backend swapped from
-- managers.crime_spree to managers.csr. Diesel UI primitives (WalletGuiObject,
-- BoxGuiObject, BlackMarketGui, tweak_data.*) are left intact — per
-- REFACTOR_PLAN we replace the vanilla-CS-Lua surface, not the engine surface.
--
-- Class renames:
--   CrimeSpreeMissionsMenuComponent -> CSRMissionsMenuComponent
--   CrimeSpreeMissionButton         -> CSRMissionButton
--
-- Backend swaps:
--   managers.crime_spree:server_missions()  -> managers.csr:mission_set()
--   managers.crime_spree:current_mission()  -> managers.csr:current_mission()
--   managers.crime_spree:select_mission(x)  -> managers.csr:select_mission(x)
--   managers.crime_spree:get_random_mission -> managers.csr:get_random_mission
--   managers.crime_spree:_is_host()         -> self:_is_host()
--
-- Dropped (vanilla-CS features outside the alpha mission-select scope):
--   show_crash_dialog / clear_crash_dialog  (vanilla CS crash recovery)
--   has_consumable_value / consumable_value (vanilla CS consumables)
--   send_crime_spree_mission_data           (MP sync — REFACTOR_PLAN §4.4, later slice)
--   server_has_failed                       (host-fail propagation — later slice)

CSRMissionsMenuComponent = CSRMissionsMenuComponent or class(MenuGuiComponentGeneric)
local padding = 10
local large_padding = 32
local size = 280
CSRMissionsMenuComponent.button_size = {
	w = size * 0.6666666666666666,
	h = size * 0.5 * 0.6666666666666666,
	title_h = tweak_data.menu.pd2_medium_font_size + 4,
}
CSRMissionsMenuComponent.menu_nodes = {
	start_menu = "crime_spree_lobby",
	mission_end_menu = "main",
}

function CSRMissionsMenuComponent:init(ws, fullscreen_ws, node)
	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()
	self._fullscreen_panel = self._fullscreen_ws:panel():panel({})

	if not Global.game_settings.is_playing then
		WalletGuiObject.set_wallet(self._ws:panel())
		WalletGuiObject.set_layer(30)
		WalletGuiObject.move_wallet(10, -10)
	end

	self._buttons = {}

	self:_setup()
end

function CSRMissionsMenuComponent:close()
	WalletGuiObject.close_wallet(self._ws:panel())
	self._ws:panel():remove(self._panel)
	self._fullscreen_ws:panel():remove(self._fullscreen_panel)
end

function CSRMissionsMenuComponent:_setup()
	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = parent:panel({
		layer = self._init_layer,
	})
	local w = (self.button_size.w + padding) * tweak_data.crime_spree.gui.missions_displayed - padding
	local h = self.button_size.h + self.button_size.title_h
	local bottom = parent:bottom() - tweak_data.menu.pd2_large_font_size * 1.5
	self._title_panel = self._panel:panel({})

	self._title_panel:set_w(w)
	self._title_panel:set_h(tweak_data.menu.pd2_medium_font_size)
	self._title_panel:set_right(parent:right())
	self._title_panel:set_bottom(bottom - h - 4)
	self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		word_wrap = true,
		wrap = true,
		align = "left",
		halign = "left",
		valign = "bottom",
		text = managers.localization:to_upper_text("menu_cs_select_next_heist"),
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	self._buttons_panel = self._panel:panel({})

	self._buttons_panel:set_w(w)
	self._buttons_panel:set_h(h)
	self._buttons_panel:set_right(parent:right())
	self._buttons_panel:set_bottom(bottom)

	local default_index = nil

	for idx = 1, tweak_data.crime_spree.gui.missions_displayed do
		-- Hardening (intentional deviation from the vanilla fork): vanilla
		-- guaranteed server_missions() was always populated; ours can be short
		-- if a tier resolved empty. Skip unrenderable slots instead of building
		-- a card with nil .add/.level (crash_report_2026_05_16_19_45).
		local data = managers.csr:mission_set()[idx]
		if data then
			local btn = CSRMissionButton:new(idx, self._buttons_panel, data)

			btn:set_callback(callback(self, self, "_select_mission", idx))
			table.insert(self._buttons, btn)

			if managers.csr:current_mission() == data.id then
				default_index = idx
			end
		end
	end

	if not managers.menu:is_pc_controller() then
		default_index = default_index or 1
	end

	if default_index then
		self:_set_button_index_selected(default_index, true)
	end

	self._host_failed_text = self._buttons_panel:text({
		halign = "right",
		vertical = "bottom",
		layer = 51,
		wrap = true,
		align = "right",
		word_wrap = true,
		y = 0,
		x = 0,
		valign = "bottom",
		text = managers.localization:text("menu_cs_host_failed_text"),
		color = Color.white,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
	})
	local _, _, _, h = self._host_failed_text:text_rect()

	self._host_failed_text:set_h(h)
	self._host_failed_text:set_bottom(self._buttons_panel:h())

	self._host_failed = self._buttons_panel:text({
		halign = "right",
		vertical = "bottom",
		layer = 51,
		wrap = true,
		align = "right",
		word_wrap = true,
		y = 0,
		x = 0,
		valign = "bottom",
		text = managers.localization:to_upper_text("menu_cs_host_failed"),
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})
	local _, _, _, h = self._host_failed:text_rect()

	self._host_failed:set_h(h)
	self._host_failed:set_bottom(self._host_failed_text:top())

	-- Forked vanilla CS "Start the Heist" button. Vanilla surfaced this as the
	-- crime_spree_lobby node's `spree_start` menu item; it is not showing in the
	-- forked flow. We rebuild it with the exact widget + params vanilla uses in
	-- crimespreemissionendoptions.lua for its menu_cs_start option: CrimeSpreeButton
	-- (forked as CSRStartButton) with pd2_large_font + shrink_wrap_button, then
	-- right-aligned. Child of self._panel so vanilla close() cleans it up.
	self._start_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size)

	self._start_button:set_button("BTN_START")
	self._start_button:set_text(managers.localization:to_upper_text("menu_cs_start"))
	self._start_button:set_callback(callback(self, self, "_start_pressed"))

	if managers.menu:is_pc_controller() then
		self._start_button:shrink_wrap_button()
	end

	self._start_button:panel():set_right(self._buttons_panel:right())
	self._start_button:panel():set_bottom(parent:bottom() - padding)
	self._start_bg_text = self:_add_bg_text(self._start_button, managers.localization:to_upper_text("menu_cs_start"))

	-- Forked vanilla CS "Reroll" button. Same widget as start (vanilla builds
	-- both corner buttons from one CrimeSpreeButton class in
	-- crimespreemissionendoptions.lua); the reroll/second corner uses
	-- pd2_large_font_size * 0.8 and sits to the LEFT of start with a
	-- large_padding gap (set_right(start:left() - large_padding)).
	self._reroll_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size * 0.8)

	self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_reroll"))
	self._reroll_button:set_callback(callback(self, self, "_reroll_pressed"))

	if managers.menu:is_pc_controller() then
		self._reroll_button:shrink_wrap_button()
	end

	self._reroll_button:panel():set_right(self._start_button:panel():left() - large_padding)
	self._reroll_button:panel():set_bottom(self._start_button:panel():bottom())
	self._reroll_bg_text = self:_add_bg_text(self._reroll_button, managers.localization:to_upper_text("menu_cs_reroll"))
	self:refresh()
end

function CSRMissionsMenuComponent:_add_bg_text(btn, label)
	-- Big faded ghost text behind a corner button, copied 1:1 from vanilla's
	-- per-corner-item recipe (menunodegui.lua:545-560). Parented to self._panel
	-- (not the shrink-wrapped button panel) so the massive font isn't clipped;
	-- a lower layer than the button (1000) keeps the sharp button text on top.
	-- MenuBackdropGUI.animate_bg_text is intentionally NOT called: in vanilla it
	-- defines an unused closure and never animates, so it is a no-op.
	local bg_text = self._panel:text({
		vertical = "bottom",
		h = 90,
		alpha = 0.4,
		align = "right",
		rotation = 360,
		layer = 1,
		text = label,
		font_size = tweak_data.menu.pd2_massive_font_size,
		font = tweak_data.menu.pd2_massive_font,
		color = tweak_data.screen_colors.button_stage_3,
	})

	bg_text:set_right(btn:panel():right())
	bg_text:set_center_y(btn:panel():center_y())
	bg_text:move(13, -9)

	return bg_text
end

function CSRMissionsMenuComponent:_start_pressed()
	-- Mirrors vanilla CrimeSpreeMissionEndOptions:perform_start, but routed
	-- through our forked callback. csr_start_game already guards on
	-- managers.csr:current_mission() == nil with a menu_error post.
	MenuCallbackHandler:csr_start_game()
end

function CSRMissionsMenuComponent:_reroll_pressed()
	-- Mirrors vanilla CrimeSpreeMissionEndOptions:perform_reroll. csr_reroll
	-- already guards on is_randomizing() (menu_error) and drives our component's
	-- randomize_crimespree(); it is the free-reroll fork (no continental coins).
	MenuCallbackHandler:csr_reroll()
end

function CSRMissionsMenuComponent:update_mission(btn_idx)
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and (btn_idx == nil or btn:index() == btn_idx) then
			btn:update_mission(managers.csr:mission_set()[btn:index()])
		end
	end
end

function CSRMissionsMenuComponent:randomize_crimespree(btn_idx)
	managers.csr:select_mission(false)
	self:_select_mission(0)

	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and (btn_idx == nil or btn:index() == btn_idx) then
			btn:randomize(managers.csr:mission_set()[btn:index()])
		end
	end
end

function CSRMissionsMenuComponent:is_randomizing()
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and btn:is_randomizing() then
			return true
		end
	end

	return false
end

function CSRMissionsMenuComponent:selection_index()
	return self._selected_button or 0
end

function CSRMissionsMenuComponent:move_selection(dir)
	if not self:_is_host() then
		return false
	end

	self:_set_button_index_selected(self._selected_button, false)

	self._selected_button = self:selection_index() + dir

	if self._selected_button > #self._buttons then
		self._selected_button = 1
	elseif self._selected_button < 1 then
		self._selected_button = #self._buttons
	end

	self:_set_button_index_selected(self._selected_button, true)
end

function CSRMissionsMenuComponent:_select_mission(idx)
	if self._selected_button ~= idx then
		self:_set_button_index_selected(self._selected_button, false)
	end

	self._selected_button = idx

	self:_set_button_index_selected(idx, true)
end

function CSRMissionsMenuComponent:_set_button_index_selected(idx, selected)
	if not idx then
		return false
	end

	self._selected_button = idx
	local btn = self._buttons[idx]

	if btn then
		btn:set_selected(selected)
		btn:set_active(selected)
		managers.csr:select_mission(btn:mission_id())

		if self:_is_host() then
			managers.menu_component:post_event("menu_enter")
		end

		-- MP mission-data sync deferred to a later slice (REFACTOR_PLAN §4.4).
	end
end

function CSRMissionsMenuComponent:get_selected_index()
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and btn:is_active() then
			return btn:index()
		end
	end
end

function CSRMissionsMenuComponent:_is_host()
	return Network:is_server() or Global.game_settings.single_player
end

function CSRMissionsMenuComponent:refresh()
	-- Host-fail propagation is a later MP slice; nothing is hidden in alpha.
	local hide = false

	for idx, btn in ipairs(self._buttons) do
		if hide then
			btn:panel():hide()
		else
			btn:panel():show()
		end
	end

	self._host_failed_text:set_visible(hide)
	self._host_failed:set_visible(hide)
	self._title_panel:set_visible(not hide)
end

function CSRMissionsMenuComponent.get_height()
	return CSRMissionsMenuComponent.button_size.h
		+ CSRMissionsMenuComponent.button_size.title_h
		+ tweak_data.menu.pd2_medium_font_size
end

function CSRMissionsMenuComponent:update(t, dt)
	local randomizing = self:is_randomizing()

	for idx, btn in ipairs(self._buttons) do
		btn:update(t, dt)
	end

	if not managers.menu:is_pc_controller() and randomizing and not self:is_randomizing() then
		self:_select_mission(1)
	end
end

function CSRMissionsMenuComponent:mouse_moved(o, x, y)
	if not self:_is_host() or not managers.menu:is_pc_controller() then
		return
	end

	local used, pointer = nil

	for idx, btn in ipairs(self._buttons) do
		btn:set_selected(btn:inside(x, y))

		if btn:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if self._start_button then
		self._start_button:set_selected(self._start_button:inside(x, y))

		if self._start_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if self._reroll_button then
		self._reroll_button:set_selected(self._reroll_button:inside(x, y))

		if self._reroll_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	return used, pointer
end

function CSRMissionsMenuComponent:mouse_pressed(o, button, x, y)
	return self:confirm_pressed()
end

function CSRMissionsMenuComponent:confirm_pressed()
	if not self:_is_host() then
		return nil
	end

	for idx, btn in ipairs(self._buttons) do
		if btn:is_selected() and btn:callback() then
			btn:callback()()

			return true
		end
	end

	if self._start_button and self._start_button:is_selected() and self._start_button:callback() then
		self._start_button:callback()()

		return true
	end

	if self._reroll_button and self._reroll_button:is_selected() and self._reroll_button:callback() then
		self._reroll_button:callback()()

		return true
	end
end

function CSRMissionsMenuComponent:dummy_trigger()
	return self:confirm_pressed()
end

function CSRMissionsMenuComponent:move_left()
	self:move_selection(-1)
end

function CSRMissionsMenuComponent:move_right()
	self:move_selection(1)
end

function CSRMissionsMenuComponent:input_focus() end

CSRMissionButton = CSRMissionButton or class(MenuGuiItem)
CSRMissionButton._type = "CSRMissionButton"
CSRMissionButton.RandomState = {
	Cleanup = 5,
	Rollback = 3,
	Done = 4,
	Slow = 2,
	Spin = 1,
}

function CSRMissionButton:init(idx, parent, mission_data)
	self._idx = idx
	self._mission_data = mission_data
	self._panel = parent:panel({
		layer = 60,
		name = "mission_" .. tostring(self._mission_data.id),
		w = CSRMissionsMenuComponent.button_size.w,
		h = CSRMissionsMenuComponent.button_size.h + CSRMissionsMenuComponent.button_size.title_h,
		x = (CSRMissionsMenuComponent.button_size.w + padding) * (idx - 1),
	})
	self._image_panel = self._panel:panel({
		h = self._panel:h() - CSRMissionsMenuComponent.button_size.title_h,
	})
	self._mission_bg = self._image_panel:rect({
		layer = -2,
		color = Color.black,
	})
	local texture, rect = tweak_data.hud_icons:get_icon_data(mission_data.icon)

	if not texture or not DB:has(Idstring("texture"), texture) then
		texture = "guis/dlcs/cee/textures/pd2/crime_spree/missions_atlas"
		rect = {
			0,
			0,
			280,
			140,
		}
	end

	self._mission_image = self._image_panel:bitmap({
		blend_mode = "add",
		name = "mission_image",
		layer = 9,
		stream = true,
		texture = texture,
		texture_rect = rect,
		w = self._panel:w(),
		h = self._panel:h(),
	})
	local image_scanlines = self._image_panel:bitmap({
		texture = "guis/dlcs/chill/textures/pd2/rooms/safehouse_room_preview_effect",
		name = "scalines",
		layer = 11,
		wrap_mode = "wrap",
		texture_rect = {
			0,
			0,
			512,
			512,
		},
		w = self._panel:w(),
		h = self._panel:h(),
	})
	local h = tweak_data.menu.pd2_medium_font_size
	self._info_panel = self._panel:panel({
		layer = 50,
		h = h,
	})

	self._info_panel:set_top(padding * 0.5)

	local h = CSRMissionsMenuComponent.button_size.title_h
	local level_name_bg = self._panel:rect({
		y = self._panel:h() - h,
		h = h,
		color = Color(0.05, 0.05, 0.05),
	})
	self._highlight_name = self._panel:rect({
		layer = 1,
		y = self._panel:h() - h,
		h = h,
		color = tweak_data.screen_colors.button_stage_3,
	})
	self._level_text = self._panel:text({
		halign = "center",
		vertical = "center",
		layer = 51,
		align = "center",
		text = "",
		y = 0,
		x = 0,
		valign = "center",
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	BlackMarketGui.make_fine_text(self, self._level_text)
	self._level_text:set_center_x(self._panel:w() * 0.5)

	self._info_text = self._info_panel:text({
		halign = "center",
		vertical = "center",
		layer = 1,
		align = "center",
		text = "",
		y = 0,
		x = 0,
		valign = "center",
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	self:update_info_text(self._mission_data)

	self._bg = self._panel:rect({
		alpha = 0.4,
		layer = -1,
		color = Color.black,
	})
	self._highlight = self._panel:rect({
		blend_mode = "add",
		layer = -1,
		color = tweak_data.screen_colors.button_stage_3,
	})
	self._blur = self._panel:bitmap({
		texture = "guis/textures/test_blur_df",
		layer = -1,
		halign = "scale",
		alpha = 1,
		render_template = "VertexColorTexturedBlur3D",
		valign = "scale",
		w = self._panel:w(),
		h = self._panel:h(),
	})
	self._border_panel = self._panel:panel({
		layer = 20,
	})

	BoxGuiObject:new(self._border_panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})

	self._active_border = BoxGuiObject:new(self._border_panel, {
		sides = {
			2,
			2,
			2,
			2,
		},
	})

	self:update_button_text()
	self:refresh()
end

function CSRMissionButton:refresh()
	self._bg:set_visible(not self:is_selected())
	self._highlight:set_visible(self:is_active() or self:is_selected())
	self._highlight_name:set_visible(self:is_active() or self:is_selected())
	self._active_border:set_visible(self:is_active())
end

function CSRMissionButton:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRMissionButton:panel()
	return self._panel
end

function CSRMissionButton:index()
	return self._idx
end

function CSRMissionButton:callback()
	return self._callback
end

function CSRMissionButton:set_callback(clbk)
	self._callback = clbk
end

function CSRMissionButton:is_randomizing()
	return self._randomize ~= nil
end

function CSRMissionButton:update(t, dt)
	if self._randomize then
		if self._randomize.state == CSRMissionButton.RandomState.Spin then
			self._randomize.t = self._randomize.t - dt
			local speed = math.clamp(
				self._randomize.t * tweak_data.crime_spree.gui.spin_speed,
				unpack(tweak_data.crime_spree.gui.spin_speed_limit)
			)

			self:_move_random_texts(speed, dt)

			if self._randomize.t <= 0 then
				self._randomize.t = nil
				self._randomize.state = CSRMissionButton.RandomState.Slow
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Slow then
			local slow_time = {
				0.1,
				0.3,
			}
			local speed = tweak_data.crime_spree.gui.spin_speed_limit[1]

			if self._randomize.t then
				speed = speed * self._randomize.t / slow_time[2]
			end

			self:_move_random_texts(speed, dt)

			if not self._randomize.t and math.abs(self._level_text:y() - self:button_text_h()) < 2 then
				self._randomize.t = math.rand(unpack(slow_time))
			end

			if self._randomize.t then
				self._randomize.t = self._randomize.t - dt

				if self._randomize.t <= 0 then
					self._randomize.t = nil
					self._randomize.state = CSRMissionButton.RandomState.Rollback
				end
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Rollback then
			local speed = (self._level_text:y() - self:button_text_h()) * dt

			self:_move_random_texts(-200, dt)

			local dis = self._level_text:y() - self:button_text_h()

			if dis < 0.1 then
				self._randomize.state = CSRMissionButton.RandomState.Done
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Done then
			local fade_out_t = 0.5

			self:update_button_text()
			self:update_info_text()

			if not self._randomize.t then
				self._randomize.t = fade_out_t
			else
				self._randomize.t = self._randomize.t - dt

				for i, text in ipairs(self._random_texts) do
					if i > 1 then
						text:set_alpha(self._randomize.t / fade_out_t)
					end
				end

				self._info_panel:set_alpha(1 - self._randomize.t / fade_out_t)
				self._mission_image:set_alpha(1 - self._randomize.t / fade_out_t)
				self._mission_bg:set_alpha(1 - self._randomize.t / fade_out_t)

				if self._randomize.t <= 0 then
					self._randomize.state = CSRMissionButton.RandomState.Cleanup
				end
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Cleanup then
			self:_cleanup_random_texts()

			self._randomize = nil
		end
	end
end

function CSRMissionButton:randomize(mission_data)
	self._mission_data = mission_data
	self._randomize = {
		state = CSRMissionButton.RandomState.Spin,
		t = math.rand(unpack(tweak_data.crime_spree.gui.randomize_time)),
	}

	self._info_panel:set_alpha(0)
	self._mission_image:set_alpha(0)
	self._mission_bg:set_alpha(0)
	self:_create_random_texts()
end

function CSRMissionButton:update_mission(mission_data)
	self._mission_data = mission_data

	self:update_button_text(nil, mission_data)
	self:update_info_text(mission_data)
end

function CSRMissionButton:update_button_text(text, mission_data, dont_reset_pos)
	text = text or self._level_text
	mission_data = mission_data or self._mission_data
	local level_tweak = tweak_data.levels[mission_data.level.level_id] or {}

	text:set_text(managers.localization:to_upper_text(level_tweak.name_id))
	text:set_font_size(tweak_data.menu.pd2_small_font_size)

	local x, y, w, h = text:text_rect()

	if self._panel:w() <= w then
		text:set_font_size(tweak_data.menu.pd2_small_font_size * 0.8)
	end

	BlackMarketGui.make_fine_text(self, text)
	text:set_center_x(self._panel:w() * 0.5)

	if not dont_reset_pos then
		text:set_y(self:button_text_h())
	end
end

function CSRMissionButton:button_text_h()
	return self._panel:h() - tweak_data.menu.pd2_small_font_size - 4
end

function CSRMissionButton:update_info_text(mission_data)
	mission_data = mission_data or self._mission_data
	local text = ""
	local spacer = " "
	local category = self:_get_mission_category(mission_data)

	if category then
		local timer_text = managers.localization:get_default_macro("BTN_SPREE_" .. utf8.to_upper(category))
		text = text .. timer_text
	end

	local level_tweak = tweak_data.levels[mission_data.level.level_id]

	if level_tweak and level_tweak.ghost_bonus then
		local stealth_text = managers.localization:get_default_macro("BTN_SPREE_STEALTH")
		text = text .. spacer .. stealth_text
	end

	text = text .. spacer
	local len = utf8.len(text)
	local inc_text = managers.localization:text("menu_cs_lobby_mission_inc", {
		inc = mission_data.add,
	})
	text = text .. inc_text

	self._info_text:set_text(text)
	self._info_text:set_range_color(len, len + utf8.len(inc_text), tweak_data.screen_colors.crime_spree_risk)

	local texture, rect = tweak_data.hud_icons:get_icon_data(mission_data.icon)

	if not texture or not DB:has(Idstring("texture"), texture) then
		texture = "guis/dlcs/cee/textures/pd2/crime_spree/missions_atlas"
		rect = {
			0,
			0,
			280,
			140,
		}
	end

	self._mission_image:set_image(texture)

	if rect then
		self._mission_image:set_texture_rect(unpack(rect))
	end
end

function CSRMissionButton:_create_random_texts()
	self:_cleanup_random_texts()

	self._random_texts = {}

	table.insert(self._random_texts, self._level_text)

	for i = 1, 8 do
		local text = self._panel:text({
			halign = "center",
			vertical = "center",
			layer = 1,
			align = "center",
			text = "",
			y = 0,
			x = 0,
			valign = "center",
			color = Color.white,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
		})

		table.insert(self._random_texts, text)
		self:update_button_text(text, managers.csr:get_random_mission(), true)

		if i > 1 then
			text:set_bottom(self._random_texts[i]:top())
		else
			text:set_bottom(self._panel:top())
		end

		text:set_center_x(self._panel:w() * 0.5)
	end
end

function CSRMissionButton:_cleanup_random_texts()
	if self._random_texts then
		for i, text in ipairs(self._random_texts) do
			if i > 1 then
				self._panel:remove(text)
			end
		end

		self._random_texts = nil
	end
end

function CSRMissionButton:_move_random_texts(speed, dt)
	for i, text in ipairs(self._random_texts) do
		text:set_y(text:y() + speed * dt)

		if self._panel:h() < text:y() then
			local idx = (i - 1) % #self._random_texts

			if idx == 0 then
				idx = #self._random_texts or idx
			end

			text:set_bottom(self._random_texts[idx]:top())

			if i == 1 then
				self:update_button_text(nil, nil, true)
			else
				self:update_button_text(text, managers.csr:get_random_mission(), true)
			end
		end
	end
end

function CSRMissionButton:_get_mission_category(mission)
	if mission.add <= 5 then
		return "short"
	elseif mission.add <= 7 then
		return "medium"
	else
		return "long"
	end
end

function CSRMissionButton:mission_id()
	return (self._mission_data or {}).id
end

-- CSRStartButton — byte-for-byte fork of vanilla CrimeSpreeButton
-- (pd2_source_code/lib/managers/menu/crimespreemodifiersmenucomponent.lua:526-614).
-- This is the SAME widget vanilla CS uses for its "Start the Heist" option
-- (crimespreemissionendoptions.lua builds it with menu_cs_start + pd2_large_font
-- + shrink_wrap_button): a clean right-aligned large-font text button with a
-- faint add-blend highlight, NOT a boxed/blurred panel. Class rename only; the
-- widget is backend-agnostic (pure Diesel UI). The callback owner
-- (CSRMissionsMenuComponent:_start_pressed) routes to our forked csr_start_game.
CSRStartButton = CSRStartButton or class(MenuGuiItem)
CSRStartButton._type = "CSRStartButton"

function CSRStartButton:init(parent, font, font_size)
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

function CSRStartButton:refresh()
	self._highlight:set_visible(self:is_selected())
	self._highlight:set_color(self:is_selected() and self._selected_color or self._color)
	self._text:set_color(self:is_selected() and self._selected_color or self._color)
end

function CSRStartButton:panel()
	return self._panel
end

function CSRStartButton:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRStartButton:callback()
	return self._callback
end

function CSRStartButton:set_callback(clbk)
	self._callback = clbk
end

function CSRStartButton:set_button(btn)
	self._btn = btn
end

function CSRStartButton:set_text(text)
	local prefix = not managers.menu:is_pc_controller()
			and self._btn
			and managers.localization:get_default_macro(self._btn)
		or ""

	self._text:set_text(prefix .. text)
end

function CSRStartButton:get_link(dir)
	return self._links[dir]
end

function CSRStartButton:set_link(dir, item)
	self._links[dir] = item
end

function CSRStartButton:update(t, dt) end

function CSRStartButton:shrink_wrap_button(w_padding, h_padding)
	local _, _, w, h = self._text:text_rect()

	self._panel:set_size(w + (w_padding or 0), h + (h_padding or 0))
end

log("[CSR] csr_missions_menu.lua loaded (Slice 8 fork + start button)")
