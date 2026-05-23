-- CSRContractMenuComponent — fork of vanilla CrimeSpreeContractMenuComponent.
--
-- Origin: pd2_source_code/lib/managers/menu/crimespreecontractmenucomponent.lua (815 lines)
-- Strategy: byte-for-byte copy with class names renamed. All managers.crime_spree
-- and tweak_data.crime_spree references intentionally left intact for this slice
-- — they will be swapped to managers.csr / our own tweak data in a follow-up slice.
-- This file existing alone changes nothing player-visible; instantiation is wired
-- in a separate step (Slice 4).
--
-- Class renames:
--   CrimeSpreeContractMenuComponent          -> CSRContractMenuComponent
--   MenuCrimeNetCrimeSpreeContractInitiator  -> MenuCSRContractInitiator
--
-- Diverged from the byte-copy: the vanilla starting-level picker
-- (CrimeSpreeStartingLevelItem) + its continental-coin cost were removed per the
-- locked rebalance (a run always starts at rank 0). In their place the popup now
-- shows a vanilla-style difficulty selector (risk-icon bar + difficulty name +
-- clickable < > cycle arrows). The selector is component-side, NOT a node menu
-- item: the CS contract node returns input_focus=false (menurenderer.lua:350), so
-- node items are non-navigable here -- the same reason vanilla CS keeps its own
-- interactive controls in this component.

CSRContractMenuComponent = CSRContractMenuComponent or class(MenuGuiComponentGeneric)

function CSRContractMenuComponent:init(ws, fullscreen_ws, node)
	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()
	self._data = node:parameters().menu_component_data or {}
	self._buttons = {}
	self._hosting = not self._data.server or self._data.id == "crime_spree"

	self:_setup()
end

function CSRContractMenuComponent:close()
	if not managers.menu:is_pc_controller() then
		managers.menu:active_menu().input:activate_controller_mouse()
	end

	self._ws:panel():remove(self._panel)
	self._fullscreen_ws:panel():remove(self._fullscreen_panel)
end

function CSRContractMenuComponent:_is_host()
	return self._hosting
end

function CSRContractMenuComponent:_host_spree_level()
	return tonumber(self._data.crime_spree or 0)
end

function CSRContractMenuComponent:_setup()
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

	if not managers.menu:is_pc_controller() then
		managers.menu:active_menu().input:deactivate_controller_mouse()
		self:_setup_controller_input()
	end

	local font_size = tweak_data.menu.pd2_small_font_size
	local font = tweak_data.menu.pd2_small_font
	local risk_color = tweak_data.screen_colors.risk
	local padding = tweak_data.gui.crime_net.contract_gui.padding
	local width = tweak_data.gui.crime_net.contract_gui.width
	local height = tweak_data.gui.crime_net.contract_gui.height
	local text_w = tweak_data.gui.crime_net.contract_gui.text_width
	local text_h = math.round(height * 0.4)

	self._fullscreen_panel:rect({
		alpha = 0.75,
		layer = 0,
		color = Color.black,
	})

	local blur = self._fullscreen_panel:bitmap({
		texture = "guis/textures/test_blur_df",
		render_template = "VertexColorTexturedBlur3D",
		layer = 1,
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

	-- Header is always the plain title. The old "...Level $level$" variant (with
	-- its risk-colored level number) was removed per user request, so the
	-- show_level branch, the rank lookup, and the range-color highlight all went
	-- with it -- there is no level number to substitute or color anymore.
	self._contact_text_header = self._panel:text({
		vertical = "top",
		align = "left",
		layer = 1,
		text = managers.localization:to_upper_text("header_title"),
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})
	local x, y, w, h = self._contact_text_header:text_rect()

	self._contact_text_header:set_size(width, h)
	self._contact_text_header:set_center_x(self._panel:w() * 0.5)

	self._contract_panel = self._panel:panel({
		layer = 1,
		h = height,
		w = width,
		x = self._contact_text_header:x(),
		y = self._contact_text_header:bottom(),
	})

	self._contract_panel:set_center_y(self._panel:h() * 0.5)
	self._contact_text_header:set_bottom(self._contract_panel:top())

	if self._contact_text_header:y() < 0 then
		local y_offset = -self._contact_text_header:y()

		self._contact_text_header:move(0, y_offset)
		self._contract_panel:move(0, y_offset)
	end

	BoxGuiObject:new(self._contract_panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})

	self._desc_text = self._contract_panel:text({
		vertical = "top",
		wrap = true,
		align = "left",
		wrap_word = true,
		text = managers.localization:text("cn_crime_spree_brief"),
		w = text_w,
		h = text_h,
		font_size = font_size,
		font = font,
		color = tweak_data.screen_colors.text,
		x = padding,
		y = padding,
	})
	local _, _, _, h = self._desc_text:text_rect()
	local scale = 1

	if text_h < h then
		scale = text_h / (h - font_size)
	end

	self._desc_text:set_font_size(font_size * scale)
	CrimeNetGui.make_color_text(self, self._desc_text, tweak_data.screen_colors.important_1)

	if managers.crime_spree:in_progress() then
		self:_setup_continue_crime_spree(text_w, text_h)
	else
		self:_setup_new_crime_spree(text_w, text_h)
	end
end

function CSRContractMenuComponent:_setup_new_crime_spree(text_w, text_h)
	local padding = tweak_data.gui.crime_net.contract_gui.padding

	-- Difficulty risk-skull preview, on the LEFT just under the Crime Spree
	-- description (inside the contract description box). The < > selector itself is
	-- a MenuItemMultiChoice in the GAME SETTINGS box (contract_difficulty.lua);
	-- this row only shades risk skulls to match. Risk shading mirrors vanilla
	-- CrimeNetContractGui (active when i <= id - 1). (The vanilla starting-level
	-- picker + its coin cost were cut per the locked rebalance: run starts rank 0.)
	local label = self._contract_panel:text({
		layer = 1,
		vertical = "top",
		align = "left",
		text = managers.localization:to_upper_text("contract_difficulty"),
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		color = tweak_data.screen_colors.text,
	})

	BlackMarketGui.make_fine_text(self, label)

	self._difficulty_panel = self._contract_panel:panel({
		layer = 1,
		w = text_w,
		h = 48,
	})

	-- risk_pd (i==1) is the no-risk baseline and is not drawn; each higher tier
	-- lights up once the chosen difficulty reaches it. SKIP_OVERKILL_290 hides the
	-- two top tiers where the platform disables them, exactly as vanilla.
	local risks = {
		"risk_pd",
		"risk_swat",
		"risk_fbi",
		"risk_death_squad",
		"risk_easy_wish",
	}

	if not Global.SKIP_OVERKILL_290 then
		table.insert(risks, "risk_murder_squad")
		table.insert(risks, "risk_sm_wish")
	end

	self._risk_icons = {}
	local rx = 0

	for i, name in ipairs(risks) do
		if i ~= 1 then
			local texture, rect = tweak_data.hud_icons:get_icon_data(name)
			local icon = self._difficulty_panel:bitmap({
				texture = texture,
				texture_rect = rect,
				y = 0,
				x = rx,
			})

			rx = rx + icon:w() + 2
			self._risk_icons[i] = icon
		end
	end

	-- Stack just under the description, left-aligned: label on top, skulls below.
	label:set_left(padding)
	label:set_top(self._desc_text:bottom() + padding)
	self._difficulty_panel:set_left(padding)
	self._difficulty_panel:set_top(label:bottom())

	-- Current-run status line, just under the difficulty skulls. is_active() is the
	-- CSR run flag flipped by start_run / end_run (game_manager.lua), so this
	-- reads "active" once a run is in flight and "none" before one starts. Read
	-- once at setup -- the run state can't change while this contract menu is open.
	local spree_active = managers.csr and managers.csr:is_active()
	local spree_status = managers.localization:text(spree_active and "current_spree_active" or "current_spree_none")
	local spree_line = self._contract_panel:text({
		layer = 1,
		vertical = "top",
		align = "left",
		text = managers.localization:to_upper_text("current_spree", { status = spree_status }),
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		color = tweak_data.screen_colors.text,
	})

	BlackMarketGui.make_fine_text(self, spree_line)
	spree_line:set_left(padding)
	spree_line:set_top(self._difficulty_panel:bottom() + padding)

	-- Highlight just the status word (the tail after "CURRENT SPREE: "): ACTIVE in
	-- crime_spree yellow, NONE in a dimmed white. The status sits at the end of the
	-- line, so its 0-based start = full length minus status length (set_range_color
	-- is start-inclusive / end-exclusive -- vanilla, hudmissionbriefing.lua:560).
	-- status_len uses the lowercase loc value, whose codepoint count matches the
	-- uppercased render for these ASCII words.
	local full_len = utf8.len(spree_line:text())
	local status_len = utf8.len(spree_status)
	local status_color = spree_active and tweak_data.screen_colors.crime_spree_risk or Color.white:with_alpha(0.6)
	spree_line:set_range_color(full_len - status_len, full_len, status_color)

	self:set_difficulty_id(self:_current_difficulty_id())
end

-- Current difficulty as a tweak_data.difficulties index (2..8 are selectable).
function CSRContractMenuComponent:_current_difficulty_id()
	local diff = managers.csr and managers.csr:difficulty() or tweak_data.crime_spree.base_difficulty
	return tweak_data:difficulty_to_index(diff) or tweak_data.crime_spree.base_difficulty_index
end

-- Refresh the risk-skull shading for a tweak_data.difficulties index. Called once
-- on setup and again by change_csr_contract_difficulty when the player cycles the
-- node's difficulty multichoice. Mirrors vanilla CrimeNetContractGui:set_difficulty_id
-- (active when i <= id - 1).
function CSRContractMenuComponent:set_difficulty_id(difficulty_id)
	if not self._risk_icons then
		return
	end

	for i, icon in pairs(self._risk_icons) do
		local active = i <= difficulty_id - 1

		icon:set_color(active and tweak_data.screen_colors.risk or Color.white)
		icon:set_alpha(active and 1 or 0.25)
	end
end

function CSRContractMenuComponent:_setup_continue_crime_spree(text_w, text_h)
	if self:_is_host() then
		self:_setup_continue_host(text_w, text_h)
	else
		self:_setup_continue_client(text_w, text_h)
	end
end

function CSRContractMenuComponent:_setup_continue_host(text_w, text_h)
	local padding = tweak_data.gui.crime_net.contract_gui.padding
	local modifiers = managers.crime_spree:active_modifiers()
	local next_modifiers_h = tweak_data.menu.pd2_small_font_size * 2
	local line_h = tweak_data.menu.pd2_small_font_size * 1.5
	local table_split = 0.125
	self._modifiers_panel = self._contract_panel:panel({
		x = padding,
		y = self._desc_text:bottom() + padding + tweak_data.menu.pd2_medium_font_size,
		w = text_w,
		h = self._contract_panel:h() - text_h - padding * 3 - tweak_data.menu.pd2_medium_font_size,
	})

	CrimeSpreeModifierDetailsPage.add_modifiers_panel(
		self,
		self._modifiers_panel,
		managers.crime_spree:active_modifiers(),
		false
	)

	local text = self._contract_panel:text({
		vertical = "top",
		wrap = true,
		align = "left",
		wrap_word = true,
		text = managers.localization:to_upper_text("cn_crime_spree_modifiers"),
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		color = tweak_data.screen_colors.text,
	})

	BlackMarketGui.make_fine_text(self, text)
	text:set_bottom(self._modifiers_panel:top())
	text:set_left(self._modifiers_panel:left())

	if #modifiers == 0 then
		local panel = self._scroll:canvas():panel({
			y = line_h,
			h = line_h,
		})

		panel:text({
			halign = "left",
			vertical = "center",
			align = "left",
			layer = 1,
			alpha = 0.8,
			y = 5,
			valign = "center",
			text = managers.localization:text("cn_crime_spree_no_modifiers"),
			x = padding + panel:w() * table_split,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			w = panel:w() * (1 - table_split),
			h = tweak_data.menu.pd2_small_font_size,
			color = Color.white,
		})
	end

	self._scroll:update_canvas_size()
end

function CSRContractMenuComponent:_setup_continue_client(text_w, text_h)
	local padding = tweak_data.gui.crime_net.contract_gui.padding
	self._info_panel = self._contract_panel:panel({
		x = padding,
		y = self._desc_text:bottom() + padding + tweak_data.menu.pd2_medium_font_size,
		w = text_w,
		h = self._contract_panel:h() - text_h - padding * 3 - tweak_data.menu.pd2_medium_font_size,
	})
	local text = self._contract_panel:text({
		vertical = "top",
		wrap = true,
		align = "left",
		wrap_word = true,
		text = managers.localization:to_upper_text("menu_cs_in_progress"),
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		color = tweak_data.screen_colors.text,
	})

	BlackMarketGui.make_fine_text(self, text)
	text:set_bottom(self._info_panel:top())
	text:set_left(self._info_panel:left())

	local desc = self._info_panel:text({
		vertical = "top",
		wrap = true,
		align = "left",
		wrap_word = true,
		x = 0,
		text = managers.localization:text("menu_cs_in_progress_desc"),
		w = text_w,
		h = text_h,
		font_size = tweak_data.menu.pd2_small_font_size,
		font = tweak_data.menu.pd2_small_font,
		color = tweak_data.screen_colors.text,
		y = padding,
	})

	BlackMarketGui.make_fine_text(self, desc)

	local level_desc_text, level_desc_col = nil
	local level_higher = self:_host_spree_level() < managers.crime_spree:spree_level()
	local level_lower = managers.crime_spree:spree_level() < self:_host_spree_level()

	if level_higher then
		level_desc_text = "menu_cs_in_progress_desc_higher"
		level_desc_col = tweak_data.screen_colors.important_1
	elseif level_lower then
		level_desc_text = "menu_cs_in_progress_desc_lower"
		level_desc_col = tweak_data.screen_colors.heat_warm_color
	end

	if level_desc_text then
		local level_warning = self._info_panel:text({
			vertical = "top",
			wrap = true,
			align = "left",
			wrap_word = true,
			x = 0,
			text = managers.localization:text(level_desc_text),
			w = text_w,
			h = text_h,
			font_size = tweak_data.menu.pd2_small_font_size,
			font = tweak_data.menu.pd2_small_font,
			color = level_desc_col,
			y = padding,
		})

		BlackMarketGui.make_fine_text(self, level_warning)
		level_warning:set_top(desc:bottom() + padding)
	end
end

function CSRContractMenuComponent:mouse_moved(o, x, y)
	local used, pointer = nil

	for idx, btn in ipairs(self._buttons) do
		btn:set_selected(btn:inside(x, y))

		if btn:is_selected() then
			pointer = "link"
			used = true
		end
	end

	return used, pointer
end

function CSRContractMenuComponent:mouse_pressed(o, button, x, y)
	for idx, btn in ipairs(self._buttons) do
		if btn:is_selected() and btn:callback() then
			btn:callback()()

			return true
		end
	end
end

function CSRContractMenuComponent:mouse_wheel_up(x, y)
	if alive(self._scroll) then
		self._scroll:scroll(x, y, 1)
	end
end

function CSRContractMenuComponent:mouse_wheel_down(x, y)
	if alive(self._scroll) then
		self._scroll:scroll(x, y, -1)
	end
end

function CSRContractMenuComponent:special_btn_pressed(button)
	-- Difficulty is selected via the node's difficulty MenuItemMultiChoice
	-- (contract_difficulty.lua), so this popup no longer consumes the
	-- modify/voice special buttons.
end

function CSRContractMenuComponent:_setup_controller_input()
	self._gui = {
		_left_axis_vector = Vector3(),
		_right_axis_vector = Vector3(),
	}

	self._ws:connect_controller(managers.menu:active_menu().input:get_controller(), true)
	self._panel:axis_move(callback(self, self, "_axis_move"))
end

function CSRContractMenuComponent:_axis_move(o, axis_name, axis_vector, controller)
	if axis_name == Idstring("left") then
		mvector3.set(self._gui._left_axis_vector, axis_vector)
	elseif axis_name == Idstring("right") then
		mvector3.set(self._gui._right_axis_vector, axis_vector)
	end
end

function CSRContractMenuComponent:update(t, dt)
	if
		not managers.menu:is_pc_controller()
		and self._gui
		and self._gui._right_axis_vector
		and alive(self._scroll)
		and not mvector3.is_zero(self._gui._right_axis_vector)
	then
		local x = mvector3.x(self._gui._right_axis_vector)
		local y = mvector3.y(self._gui._right_axis_vector)

		self._scroll:perform_scroll(ScrollablePanel.SCROLL_SPEED * dt * 24, y)
	end
end

MenuCSRContractInitiator = MenuCSRContractInitiator or class()

function MenuCSRContractInitiator:modify_node(original_node, data)
	local node = deep_clone(original_node)

	if Global.game_settings.single_player then
		node:item("toggle_ai"):set_value(Global.game_settings.team_ai and Global.game_settings.team_ai_option or 0)
	elseif data.smart_matchmaking then
		-- Nothing
	elseif data.id == "crime_spree" then
		node:item("lobby_kicking_option"):set_value(Global.game_settings.kick_option)
		node:item("lobby_permission"):set_value(Global.game_settings.permission)
		node:item("lobby_reputation_permission"):set_value(Global.game_settings.reputation_permission)
		node:item("lobby_drop_in_option"):set_value(Global.game_settings.drop_in_option)
		node:item("toggle_ai"):set_value(Global.game_settings.team_ai and Global.game_settings.team_ai_option or 0)
		node:item("toggle_auto_kick"):set_value(Global.game_settings.auto_kick and "on" or "off")
		node:item("toggle_allow_modded_players"):set_value(Global.game_settings.allow_modded_players and "on" or "off")

		if tweak_data.quickplay.stealth_levels[data.job_id] then
			local job_plan_item = node:item("lobby_job_plan")
			local stealth_option = nil

			for _, option in ipairs(job_plan_item:options()) do
				if option:value() == 2 then
					stealth_option = option

					break
				end
			end

			job_plan_item:clear_options()
			job_plan_item:add_option(stealth_option)
		end
	end

	node:item("accept_contract"):set_enabled(managers.crime_spree:unlocked())

	if data and data.back_callback then
		table.insert(node:parameters().back_callback, data.back_callback)
	end

	node:parameters().menu_component_data = data

	return node
end

log("[CSR] contract_menu.lua loaded (Slice 2 fork)")
