-- CSRMissionsMenuComponent — fork of vanilla CrimeSpreeMissionsMenuComponent with class renames + managers.csr backend.

CSRMissionsMenuComponent = CSRMissionsMenuComponent or class(MenuGuiComponentGeneric)
local padding = 10
local large_padding = 32
local size = 280
-- Gap between the foreground title bottom and the sidebar top.
local sidebar_title_gap = 16

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

	-- Title + sidebar are lobby-only; hide them on the end-screen surface.
	local pnode = node and node.parameters and node:parameters()
	self._is_lobby = pnode ~= nil and pnode.name == "crime_spree_lobby"

	self:_setup()

	-- On a controller the lobby has no d-pad focus map, so drive a virtual mouse pointer
	-- (exactly as CrimeNet does) to keep every widget reachable. The vanilla lobby node's own
	-- mouse highlight is suppressed via input_focus(). Balanced by hide_cursor() in close().
	CSR_ControllerNav.show_cursor(self)
end

function CSRMissionsMenuComponent:close()
	-- Drain subscriptions before panels die to avoid callbacks on destroyed panels.
	if self._csr_unsubs then
		for _, unsub in ipairs(self._csr_unsubs) do
			if type(unsub) == "function" then
				unsub()
			end
		end
		self._csr_unsubs = nil
	end
	-- Balance the controller cursor activated in init.
	CSR_ControllerNav.hide_cursor(self)
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

	-- Hoisted so sidebar height can be pinned to match the cards' bottom edge.
	local bottom = parent:bottom() - tweak_data.menu.pd2_large_font_size * 1.5 - 20

	-- Always called: sets self._title_bottom for the sidebar anchor; on end-screen
	-- the visible elements are hidden inside _create_title, preserving the geometry.
	self:_create_title()
	self:_create_sidebar(bottom)

	local w = (self.button_size.w + padding) * tweak_data.crime_spree.gui.missions_displayed - padding
	local h = self.button_size.h + self.button_size.title_h
	self._title_panel = self._panel:panel({})

	self._title_panel:set_w(w)
	self._title_panel:set_h(tweak_data.menu.pd2_medium_font_size)
	self._title_panel:set_right(parent:right())
	self._title_panel:set_bottom(bottom - h - 4)
	self:_create_status_bar(w)

	self._buttons_panel = self._panel:panel({})

	self._buttons_panel:set_w(w)
	self._buttons_panel:set_h(h)
	self._buttons_panel:set_right(parent:right())
	self._buttons_panel:set_bottom(bottom)

	-- Abstract anchors used by _create_feature_panels and borrowed by briefing_sidebar.lua.
	self._csr_fp_parent = self._panel
	self._csr_fp_right_anchor = self._buttons_panel

	self:_create_feature_panels()

	local default_index = nil

	if _G.CSR_DEBUG then
		local C = managers.csr
		local set = C:mission_set()
		local ids = {}
		for i = 1, 3 do
			ids[i] = set[i] and set[i].id or "nil"
		end
		csr_log(
			string.format(
				"[CSR][mpdbg] lobby build: is_guesting=%s current_mission()=%s set_ids={%s} (guest current_mission is NOT host-synced -> no highlight)",
				tostring(C.is_guesting and C:is_guesting()),
				tostring(C:current_mission()),
				table.concat(ids, ",")
			)
		)
	end

	for idx = 1, tweak_data.crime_spree.gui.missions_displayed do
		-- Skip nil slots: mission_set() can be shorter than missions_displayed.
		local data = managers.csr:mission_set()[idx]
		if data then
			local btn = CSRMissionButton:new(idx, self._buttons_panel, data)

			btn:set_callback(callback(self, self, "_select_mission", idx))
			table.insert(self._buttons, btn)

			-- Re-highlight the selected mission on rebuild (persists across sub-screen round-trips).
			if managers.csr:current_mission() == data.id then
				default_index = idx
			end
		end
	end

	if not managers.menu:is_pc_controller() then
		default_index = default_index or 1
	end

	if managers.csr:is_guesting() then
		-- Guest never picks: show the host's synced selection as a highlight, without mutating
		-- current_mission or broadcasting (_set_button_index_selected would do both).
		self:_csr_apply_host_selection(managers.csr:current_mission())
	elseif default_index then
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
	local _, _, _, fth = self._host_failed_text:text_rect()

	self._host_failed_text:set_h(fth)
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
	local _, _, _, fh = self._host_failed:text_rect()

	self._host_failed:set_h(fh)
	self._host_failed:set_bottom(self._host_failed_text:top())

	-- Forked vanilla CrimeSpreeButton for "Start the Heist".
	self._start_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size)

	self._start_button:set_button("BTN_START")
	self._start_button:set_text(managers.localization:to_upper_text("menu_cs_start"))
	self._start_button:set_callback(callback(self, self, "_start_pressed"))

	-- Shrink-wrap in every input mode: set_text already includes the controller
	-- button glyph in text_rect, and the default 35%-parent width leaves huge
	-- gaps between the horizontally-anchored action buttons on a controller.
	self._start_button:shrink_wrap_button()

	self._start_button:panel():set_right(self._buttons_panel:right())
	self._start_button:panel():set_bottom(parent:bottom() - padding)

	self._reroll_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size * 0.8)

	self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_reroll"))
	self._reroll_button:set_callback(callback(self, self, "_reroll_pressed"))

	self._reroll_button:shrink_wrap_button()

	self._reroll_button:panel():set_right(self._start_button:panel():left() - large_padding)
	self._reroll_button:panel():set_bottom(self._start_button:panel():bottom())

	self._action_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size * 0.8)

	self._action_button:panel():set_bottom(self._reroll_button:panel():bottom())
	self:_refresh_action_buttons()

	-- Black scrim behind the action buttons; layer 1 so it draws below the button panels (layer 1000).
	local actions_vpad = 6
	local start_panel = self._start_button:panel()
	self._actions_bg = self._panel:rect({
		layer = 1,
		color = Color.black,
		alpha = 0.4,
	})
	self._actions_bg:set_w(w)
	self._actions_bg:set_h(start_panel:h() + actions_vpad * 2)
	self._actions_bg:set_right(self._buttons_panel:right())
	self._actions_bg:set_bottom(start_panel:bottom() + actions_vpad)
	self:refresh()

	self:_csr_reopen_pinned_feature_panel()

	-- _setup may run more than once; drain prior subscriptions before re-registering.
	if self._csr_unsubs then
		for _, unsub in ipairs(self._csr_unsubs) do
			if type(unsub) == "function" then
				unsub()
			end
		end
	end
	self._csr_unsubs = {}
	local mgr = managers and managers.csr
	if mgr and mgr.on_item_added then
		table.insert(
			self._csr_unsubs,
			mgr:on_item_added(function()
				self:refresh_for_rank_change()
			end)
		)
	end

	-- End-screen surface: a freshly-unlocked modifier flashes the siren behind the Modifiers sidebar
	-- icon -- the first thing seen post-heist. One-shot consume; the lobby keeps only the blue tint.
	if not self._is_lobby then
		local consumed = mgr and mgr.consume_modifier_glow and mgr:consume_modifier_glow()
		csr_log( -- TEMP siren debug (raw log: csr_log is CSR_DEBUG-gated)
			"[CSR][siren] _setup consume: consumed="
				.. tostring(consumed)
				.. " sidebar="
				.. tostring(self._sidebar ~= nil)
		)
		if consumed and self._sidebar and self._sidebar.play_modifier_siren then
			self._sidebar:play_modifier_siren()
		end
	end
end

-- Repaint rank-dependent surfaces (reminder, items panel, status bar). Driven by
-- on_item_added, MP host-state push, and the debug keybind.
function CSRMissionsMenuComponent:refresh_for_rank_change()
	if not alive(self._panel) then
		return
	end
	if self._refresh_unselected_items then
		self:_refresh_unselected_items()
	end
	if self._populate_items_panel then
		self:_populate_items_panel()
	end
	self:_refresh_rank_display()
end

-- Update the status-bar RANK text in place; safe to call before/after the panel exists.
function CSRMissionsMenuComponent:_refresh_rank_display()
	local t = self._status_rank_text
	if not (t and alive(t)) then
		return
	end
	local prefix = self._status_rank_prefix or ""
	local glyph = self._status_rank_glyph or ""
	local str = prefix .. tostring(managers.csr:host_rank()) .. " " .. glyph
	t:set_text(str)
	t:set_range_color(utf8.len(prefix), utf8.len(str), self._status_rank_highlight or Color(1, 1, 1, 0))
end

function CSRMissionsMenuComponent:_create_title()
	-- Branded header: crisp foreground on safe-ws + faded ghost on fullscreen-ws (vanilla contractboxgui style).
	local title = self._panel:text({
		vertical = "top",
		name = "title",
		align = "left",
		text = managers.localization:to_upper_text("csr_header_title"),
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})
	local _, _, w, h = title:text_rect()

	title:set_size(w, h)

	-- Anchor measurements used by the sidebar and the lobby-code widget.
	self._title_bottom = title:bottom()
	self._title_right = title:right()

	-- Hide on end-screen but keep geometry so the sidebar anchor stays valid.
	if not self._is_lobby then
		title:set_visible(false)
	end

	if MenuBackdropGUI then
		local ghost_h = 90
		local ghost_move_y = 9
		local bg_text = self._fullscreen_panel:text({
			name = "title",
			vertical = "top",
			h = ghost_h,
			alpha = 0.4,
			align = "left",
			layer = 1,
			text = managers.localization:to_upper_text("csr_header_title"),
			font_size = tweak_data.menu.pd2_massive_font_size,
			font = tweak_data.menu.pd2_massive_font,
			color = tweak_data.screen_colors.button_stage_3,
		})
		local x, y = managers.gui_data:safe_to_full_16_9(title:world_x(), title:world_center_y())

		bg_text:set_world_left(x)
		bg_text:set_world_center_y(y)
		bg_text:move(-13, ghost_move_y)

		if not self._is_lobby then
			bg_text:set_visible(false)
		end
	end

	-- Reposition lobby-code widget if it already exists; the PostHook handles the reverse order.
	self:_reposition_lobby_code()
end

-- Vanilla never repositions this widget for CSR; without this it sits at (0,80) top-left.
-- Lobby: right of the header. End-screen: top-right corner (title is hidden there).
function CSRMissionsMenuComponent:_reposition_lobby_code()
	local mcm = managers and managers.menu_component
	local code_gui = mcm and mcm._lobby_code_gui
	if not (code_gui and code_gui.panel) then
		return
	end
	local panel = code_gui:panel()
	if not (panel and alive(panel)) then
		return
	end
	if self._is_lobby then
		local gap = 24
		local x = (self._title_right or 0) + gap
		local header_h = self._title_bottom or 0
		local y = math.floor(header_h / 2 - (5 + tweak_data.menu.pd2_medium_font_size / 2))
		panel:set_position(x, y)
	else
		-- End-screen: top-right corner.
		panel:set_right(self._ws:panel():right())
		panel:set_y(10)
	end
end

function CSRMissionsMenuComponent:_create_sidebar(bottom)
	-- CrimeNet-style sidebar; spans from just below the title to the cards' bottom edge.
	local top = (self._title_bottom or 0) + sidebar_title_gap

	self._sidebar = CSRSidebar:new(self._panel, top, bottom, self)
end

-- Build the mutually-exclusive feature panels (items/modifiers/rewards/heister) that open
-- between the sidebar and the mission cards.
function CSRMissionsMenuComponent:_create_feature_panels()
	if not self._sidebar or not self._csr_fp_right_anchor or not self._csr_fp_parent then
		return
	end

	local sb = self._sidebar:panel()
	local left = sb:right() + padding
	local right = self._csr_fp_right_anchor:left() - padding
	local width = math.max(right - left, 0)
	local px, py, ph = left, sb:top(), sb:h()
	local parent_for_panels = self._csr_fp_parent

	local function build()
		local p = parent_for_panels:panel({
			layer = 100,
		})

		p:set_w(width)
		p:set_h(ph)
		p:set_x(px)
		p:set_y(py)

		local bg = p:panel({
			layer = -1,
		})

		bg:rect({
			alpha = 0.4,
			color = Color.black,
		})
		bg:bitmap({
			texture = "guis/textures/test_blur_df",
			name = "blur_bg",
			halign = "scale",
			layer = -1,
			render_template = "VertexColorTexturedBlur3D",
			valign = "scale",
			w = bg:w(),
			h = bg:h(),
		})

		BoxGuiObject:new(
			p:panel({
				layer = 100,
			}),
			{
				sides = {
					1,
					1,
					1,
					1,
				},
			}
		)

		p:set_visible(false)

		return p
	end

	self._feature_panels = {
		items = build(),
		modifiers = build(),
		rewards = build(),
		heister = build(),
		preferences = build(),
	}

	self:_populate_items_panel()
	self:_populate_modifiers_panel()
	self:_populate_rewards_panel()
	self:_populate_heister_panel()
	self:_populate_preferences_panel()
end

function CSRMissionsMenuComponent:toggle_feature_panel(key)
	if not self._feature_panels then
		return
	end

	local target = self._feature_panels[key]

	if not target or not alive(target) then
		return
	end

	local show = not target:visible()

	self:hide_feature_panels()
	target:set_visible(show)

	-- Global (not _G): lobby and briefing live in different Lua states, so _G
	-- would be nil by the time briefing reads it.
	Global._csr_pinned_feature = show and key or nil
	csr_log(
		"[CSR][pinned-tab] toggle: key="
			.. tostring(key)
			.. " show="
			.. tostring(show)
			.. " -> slot="
			.. tostring(Global._csr_pinned_feature)
	)

	if self._sidebar and self._sidebar.set_active_feature then
		self._sidebar:set_active_feature(show and key or nil)
	end

	-- Rebuild on toggle-on so the panel reflects any changes since it was last opened.
	if show and key == "items" then
		self:_populate_items_panel()
	elseif show and key == "modifiers" then
		self:_populate_modifiers_panel()
	elseif show and key == "rewards" then
		self:_populate_rewards_panel()
	elseif show and key == "heister" then
		self:_populate_heister_panel()
	elseif show and key == "preferences" then
		self:_populate_preferences_panel()
	end
end

-- Re-apply the pinned tab after build/show without flipping the Global slot.
-- Borrowed by briefing_sidebar.lua so both surfaces share the same logic.
function CSRMissionsMenuComponent:_csr_reopen_pinned_feature_panel()
	local pinned = Global and Global._csr_pinned_feature
	if not pinned then
		return
	end
	if not self._sidebar then
		return
	end
	if not self._feature_panels then
		return
	end
	local target = self._feature_panels[pinned]
	if not target or not alive(target) then
		return
	end
	if target:visible() then
		return
	end

	self:hide_feature_panels()
	target:set_visible(true)
	if self._sidebar.set_active_feature then
		self._sidebar:set_active_feature(pinned)
	end
	if pinned == "items" and self._populate_items_panel then
		self:_populate_items_panel()
	elseif pinned == "modifiers" and self._populate_modifiers_panel then
		self:_populate_modifiers_panel()
	elseif pinned == "heister" and self._populate_heister_panel then
		self:_populate_heister_panel()
	end
end

-- Hide every feature panel; also called on sidebar collapse.
function CSRMissionsMenuComponent:hide_feature_panels()
	if not self._feature_panels then
		return
	end

	for _, p in pairs(self._feature_panels) do
		if alive(p) then
			p:set_visible(false)
		end
	end

	-- Drop any lingering tooltip; one clear covers both mutually-exclusive panels.
	self:_clear_items_tooltip()
	self._items_hover_target = nil
	self._modifiers_hover_target = nil

	if self._sidebar and self._sidebar.set_active_feature then
		self._sidebar:set_active_feature(nil)
	end
end

function CSRMissionsMenuComponent:_create_status_bar(w)
	-- Header row above the cards: MISSIONS COMPLETED (left) | RANK (center) | DIFFICULTY (right).
	-- Dynamic values highlighted yellow via set_range_color; 4-arg Color (alpha is first arg).
	local highlight = Color(1, 1, 1, 0)
	local cs_glyph = utf8.char(0xE018) -- Crime Spree glyph U+E018

	-- While guesting show the HOST's count; nil falls back to own.
	local missions_prefix = managers.localization:to_upper_text("csr_lobby_missions_completed") .. ": "
	local missions_done = (managers.csr.mp_host_missions_completed and managers.csr:mp_host_missions_completed())
		or managers.csr:missions_completed()
	local missions_str = missions_prefix .. tostring(missions_done)
	local missions_text = self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		align = "left",
		halign = "left",
		valign = "bottom",
		text = missions_str,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	missions_text:set_range_color(utf8.len(missions_prefix), utf8.len(missions_str), highlight)

	local rank_prefix = managers.localization:to_upper_text("csr_lobby_rank") .. ": "
	local rank_str = rank_prefix .. tostring(managers.csr:host_rank()) .. " " .. cs_glyph
	local rank_text = self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		align = "center",
		halign = "center",
		valign = "bottom",
		text = rank_str,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	rank_text:set_range_color(utf8.len(rank_prefix), utf8.len(rank_str), highlight)

	-- Cached for in-place update by _refresh_rank_display.
	self._status_rank_text = rank_text
	self._status_rank_prefix = rank_prefix
	self._status_rank_glyph = cs_glyph
	self._status_rank_highlight = highlight

	-- While guesting show the HOST's difficulty; nil falls back to own.
	local diff_id = (managers.csr.mp_host_difficulty and managers.csr:mp_host_difficulty()) or managers.csr:difficulty()
	local diff_name_id = tweak_data.difficulty_name_ids[diff_id]
	local diff_text = diff_name_id and managers.localization:to_upper_text(diff_name_id) or tostring(diff_id)

	local diff_prefix = managers.localization:to_upper_text("csr_lobby_difficulty") .. ": "
	local diff_full = diff_prefix .. diff_text
	local diff_label = self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		align = "right",
		halign = "right",
		valign = "bottom",
		text = diff_full,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	diff_label:set_range_color(utf8.len(diff_prefix), utf8.len(diff_full), highlight)

	-- Clickable item-pick reminder, right-aligned above the status row; dim yellow, brightens on hover.
	self._unselected_color_dim = Color(1, 0.85, 0.78, 0)
	self._unselected_color_bright = Color(1, 1, 1, 0)

	self._unselected_panel = self._panel:panel({
		layer = 51,
	})
	-- Backing plate is a self._panel sibling (not a child of the hit-panel) so it can span
	-- the full mission-row width independently. Layer 1 keeps it under the layer-51 hit-panel.
	self._unselected_bg = self._panel:rect({
		layer = 1,
		color = Color(1, 1, 1, 0),
		alpha = 0.1,
	})
	self._unselected_items = self._unselected_panel:text({
		layer = 52,
		text = "",
		color = self._unselected_color_dim,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size * 1.2,
	})

	self:_refresh_unselected_items(true)
end

-- Picks owed = host_rank minus rank-sourced items owned (shop purchases excluded via rank_item_count).
function CSRMissionsMenuComponent:_unselected_item_count()
	if not managers.csr then
		return 0
	end

	local host_rank = managers.csr:host_rank() or 0
	local peer_id = managers.csr:local_peer_id()
	local owned = managers.csr:rank_item_count(peer_id)

	return math.max(0, host_rank - owned)
end

-- Refresh the reminder text and size; `allowed == false` force-hides it (host-fail).
function CSRMissionsMenuComponent:_refresh_unselected_items(allowed)
	if not self._unselected_panel or not alive(self._unselected_panel) then
		return
	end

	local count = self:_unselected_item_count()
	self._unselected_items:set_text(managers.localization:to_upper_text("csr_lobby_unselected_items", {
		count = count,
	}))

	BlackMarketGui.make_fine_text(nil, self._unselected_items)

	local pad_x, pad_y = 8, 3
	local tw, th = self._unselected_items:w(), self._unselected_items:h()
	self._unselected_items:set_position(pad_x, pad_y)
	self._unselected_panel:set_size(tw + pad_x * 2, th + pad_y * 2)
	self._unselected_panel:set_right(self._title_panel:right())
	-- Sit clearly ABOVE the status row (one medium line of clearance), not
	-- hugging it. Re-applied every refresh so a re-snug keeps the gap.
	self._unselected_panel:set_bottom(self._title_panel:top() - tweak_data.menu.pd2_medium_font_size)

	self._unselected_bg:set_w(self._title_panel:w())
	self._unselected_bg:set_h(th)
	self._unselected_bg:set_right(self._title_panel:right())
	self._unselected_bg:set_center_y(self._unselected_panel:center_y())

	self._unselected_items:set_color(self._unselected_color_dim)
	self._unselected_items_hover = false

	self._unselected_visible = allowed ~= false and count > 0
	self._unselected_panel:set_visible(self._unselected_visible)
	-- Sibling panel, not a child — must be toggled separately.
	self._unselected_bg:set_visible(self._unselected_visible)
end

-- Open the item-selection window. CSR_OpenItemSelection is NOT idempotent — guard on
-- _csr_item_selection so a double-click doesn't corrupt the component-order snapshot.
function CSRMissionsMenuComponent:_on_unselected_items_clicked()
	managers.menu_component:post_event("menu_enter")

	if _G.CSR_OpenItemSelection and not _G._csr_item_selection then
		_G.CSR_OpenItemSelection(self:_unselected_item_count())
	end
end

function CSRMissionsMenuComponent:_start_pressed()
	-- Defer to update(): csr_start_game() tears down the active menu, but on a controller
	-- MenuInput:update() indexes active_menu():disable_input() right after confirm_pressed()
	-- returns. Starting synchronously leaves that a nil index (crash menuinput.lua:843). One
	-- frame later the menu is still alive for MenuInput to finish its frame.
	self._csr_pending_start = true
end

function CSRMissionsMenuComponent:_reroll_pressed()
	MenuCallbackHandler:csr_reroll()
end

-- has_failed() is a persisted flag set on heist loss; locks both the lobby and end-screen
-- until Continue or End Spree is chosen.
function CSRMissionsMenuComponent:_is_locked()
	return managers.csr and managers.csr:has_failed() == true
end

function CSRMissionsMenuComponent:_action_end_spree()
	MenuCallbackHandler:end_csr()
end

function CSRMissionsMenuComponent:_action_return_to_lobby()
	MenuCallbackHandler:return_to_csr_lobby()
end

function CSRMissionsMenuComponent:_action_continue()
	MenuCallbackHandler:csr_continue()
end

-- Sets the context button (left of Reroll) + the Start/Reroll failed-lock.
-- Called at build and from refresh() so the failed state always re-applies.
function CSRMissionsMenuComponent:_refresh_action_buttons()
	local locked = self:_is_locked()
	-- Guest sees no bottom-row actions; pure visibility hide (confirm_pressed already guards on _is_host).
	local client = not self:_is_host()

	if self._start_button then
		self._start_button:panel():set_visible(not locked and not client)
	end

	-- Reroll is positioned BEFORE the action button so End Spree can anchor to its final left edge.
	if self._reroll_button then
		if locked then
			self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_continue"))
			self._reroll_button:set_callback(callback(self, self, "_action_continue"))
		else
			self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_reroll"))
			self._reroll_button:set_callback(callback(self, self, "_reroll_pressed"))
		end

		self._reroll_button:shrink_wrap_button()

		-- When locked, Start is hidden and Reroll becomes "Continue Crime Spree": right-align it to
		-- the panel edge (where Start sat) instead of leaving it floating left of the hidden Start.
		if locked then
			self._reroll_button:panel():set_right(self._buttons_panel:right())
		else
			self._reroll_button:panel():set_right(self._start_button:panel():left() - large_padding)
		end
		self._reroll_button:panel():set_bottom(self._start_button:panel():bottom())
		self._reroll_button:panel():set_visible(not client)
	end

	if self._action_button then
		if self._is_lobby then
			self._action_button:set_text(managers.localization:to_upper_text("csr_end_spree"))
			self._action_button:set_callback(callback(self, self, "_action_end_spree"))
		else
			self._action_button:set_text(managers.localization:to_upper_text("csr_return_to_lobby"))
			self._action_button:set_callback(callback(self, self, "_action_return_to_lobby"))
		end

		self._action_button:shrink_wrap_button()

		self._action_button:panel():set_right(self._reroll_button:panel():left() - large_padding)
		self._action_button:panel():set_bottom(self._reroll_button:panel():bottom())
		self._action_button:panel():set_visible(not client)
	end

	-- Scrim hidden for guests too; exists only after the first _refresh_action_buttons during build.
	if self._actions_bg and alive(self._actions_bg) then
		self._actions_bg:set_visible(not client)
	end
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

-- Guest-only: reflect the host's selected mission as a card highlight, WITHOUT calling
-- select_mission (which mutates current_mission + broadcasts). nil clears all highlights.
function CSRMissionsMenuComponent:_csr_apply_host_selection(host_mission_id)
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" then
			local sel = host_mission_id ~= nil and btn:mission_id() == host_mission_id
			btn:set_selected(sel)
			btn:set_active(sel)
			if sel then
				self._selected_button = idx
			end
		end
	end
end

function CSRMissionsMenuComponent:_set_button_index_selected(idx, selected)
	if not idx then
		return false
	end

	if selected and self:_is_locked() then
		return false
	end

	self._selected_button = idx
	local btn = self._buttons[idx]

	if btn then
		btn:set_selected(selected)
		btn:set_active(selected)

		-- Only push the pick on select; clear on deselect so a reroll leaves current_mission nil.
		-- (Vanilla called select_mission unconditionally, re-selecting the pre-reroll mission.)
		if selected then
			managers.csr:select_mission(btn:mission_id())
		else
			managers.csr:select_mission(false)
		end

		if selected and self:_is_host() then
			managers.menu_component:post_event("menu_enter")
		end
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
	local hide = false -- host-fail propagation deferred

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
	self:_refresh_unselected_items(not hide)
	self:_refresh_action_buttons()
end

function CSRMissionsMenuComponent.get_height()
	return CSRMissionsMenuComponent.button_size.h
		+ CSRMissionsMenuComponent.button_size.title_h
		+ tweak_data.menu.pd2_medium_font_size
end

function CSRMissionsMenuComponent:update(t, dt)
	-- Run a deferred heist start one frame after the controller confirm (see _start_pressed).
	if self._csr_pending_start then
		self._csr_pending_start = nil
		MenuCallbackHandler:csr_start_game()

		return
	end

	local randomizing = self:is_randomizing()

	for idx, btn in ipairs(self._buttons) do
		btn:update(t, dt)
	end

	if self._sidebar then
		self._sidebar:update(t, dt)
	end

	if not managers.menu:is_pc_controller() and randomizing and not self:is_randomizing() then
		self:_select_mission(1)
	end
end

function CSRMissionsMenuComponent:mouse_moved(o, x, y)
	-- No is_pc_controller gate: this must run for the real mouse (pc) AND the
	-- controller-driven virtual cursor, so hover-select works on a gamepad too.

	-- Remember the cursor position so a controller confirm can replay a click here (the
	-- gamepad confirm button carries no coordinates of its own). See confirm_pressed.
	self._csr_last_x, self._csr_last_y = x, y

	-- When a sub-screen covers the cards (self._csr_overlay_active), the sidebar + open feature
	-- panel stay interactive, but card/button hover is suppressed by folding it into `host` (cards
	-- and Start/Reroll/Action all gate on host). The unselected reminder is guarded separately.
	local host = self:_is_host() and not self._csr_overlay_active
	-- Failed-lock: Start is hidden AND must be unhoverable/unclickable while Continue is shown.
	local locked = self:_is_locked()
	local used, pointer = nil, nil

	if self._sidebar then
		local s_used, s_pointer = self._sidebar:mouse_moved(x, y)

		if s_used then
			used = true
			pointer = s_pointer or pointer
		end
	end

	-- Bound card hover to the cards' own container to prevent flicker from overlapping widgets.
	local cards_area = self._buttons_panel and alive(self._buttons_panel) and self._buttons_panel:inside(x, y)

	for idx, btn in ipairs(self._buttons) do
		btn:set_selected(host and cards_area and btn:inside(x, y) or false)

		if btn:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if host and self._start_button then
		-- Locked run (Continue shown): never let the hidden Start hover/select, so it can't be clicked.
		self._start_button:set_selected(not locked and self._start_button:inside(x, y))

		if self._start_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if host and self._reroll_button then
		self._reroll_button:set_selected(self._reroll_button:inside(x, y))

		if self._reroll_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if host and self._action_button then
		self._action_button:set_selected(self._action_button:inside(x, y))

		if self._action_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	local was_unselected_hover = self._unselected_items_hover == true
	self._unselected_items_hover = not self._csr_overlay_active
		and self._unselected_visible == true
		and self._unselected_panel ~= nil
		and alive(self._unselected_panel)
		and self._unselected_panel:inside(x, y)

	if self._unselected_items_hover then
		pointer = "link"
		used = true

		-- Hover SFX only on the false->true transition, not every mouse_moved.
		if not was_unselected_hover then
			managers.menu:post_event("highlight")
		end
	end

	if self._unselected_visible and alive(self._unselected_panel) then
		self._unselected_items:set_color(
			self._unselected_items_hover and self._unselected_color_bright or self._unselected_color_dim
		)
	end

	if self:_items_panel_mouse_moved(x, y) then
		pointer = "link"
		used = true
	end

	if self:_modifiers_panel_mouse_moved(x, y) then
		pointer = "link"
		used = true
	end

	if self:_preferences_panel_mouse_moved(x, y) then
		pointer = "link"
		used = true
	end

	-- Track whether the cursor sits on one of our widgets. input_focus() reads this so the hidden
	-- vanilla lobby node stays interactive when the cursor is off our UI (over its own buttons).
	self._csr_cursor_over_widget = used and true or false
	-- Off our widgets, note whether the cursor is directly over a vanilla node button. input_focus
	-- yields to the node ONLY there, so controller A activates a button just when the cursor is on it
	-- (over empty space we keep focus and A stays inert). Skip the hit-test while over our own UI.
	self._csr_over_vanilla_button = not used and CSR_ControllerNav.cursor_over_node_item(x, y) or false

	return used, pointer
end

-- 3-arg signature required: MenuComponentManager dispatches as (button, x, y) not (o, button, x, y).
function CSRMissionsMenuComponent:mouse_pressed(button, x, y)
	-- Sidebar + open feature panel stay clickable even while a sub-screen covers the cards.
	if self._sidebar and self._sidebar:mouse_pressed(x, y) then
		return true
	end

	if self:_modifiers_panel_mouse_pressed(x, y) then
		return true
	end

	if self:_preferences_panel_mouse_pressed(x, y) then
		return true
	end

	if self:_modifiers_scroll_visible() and self._modifiers_scroll:mouse_pressed(button, x, y) then
		return true
	end

	-- Cards/buttons are hidden under the sub-screen: don't act on clicks over them.
	if self._csr_overlay_active then
		return false
	end

	return self:confirm_pressed()
end

-- Wheel + release routing for the Modifiers scroll; mouse_released always feeds
-- the scroll so a grabbed bar releases even if the cursor left mid-drag.
function CSRMissionsMenuComponent:mouse_wheel_up(x, y)
	if self:_modifiers_scroll_visible() then
		return self._modifiers_scroll:scroll(x, y, 1)
	end
end

function CSRMissionsMenuComponent:mouse_wheel_down(x, y)
	if self:_modifiers_scroll_visible() then
		return self._modifiers_scroll:scroll(x, y, -1)
	end
end

-- MenuComponentManager dispatches mouse_released to live components as (o, button, x, y) -- the
-- panel object comes first, unlike mouse_pressed(button, x, y). Match it so x/y line up.
function CSRMissionsMenuComponent:mouse_released(o, button, x, y)
	if self:_preferences_panel_mouse_released(button, x, y) then
		return true
	end
	if self._modifiers_scroll then
		return self._modifiers_scroll:mouse_released(button, x, y)
	end
end

function CSRMissionsMenuComponent:confirm_pressed()
	-- On a gamepad the engine raises no ws mouse click, so a controller confirm (A) replays a
	-- left click at the virtual cursor's last position (stored by mouse_moved). Reusing the whole
	-- mouse_pressed hit-test makes every widget reachable through one path -- sidebar, Modifiers
	-- Loud/Stealth, Preferences, the Black Market reminder, mission cards. The reentrancy guard
	-- stops the mouse_pressed -> confirm_pressed tail call from recursing.
	if self._csr_controller_mouse and self._csr_last_x and not self._csr_in_confirm then
		self._csr_in_confirm = true
		local handled = CSR_ControllerNav.replay_click(self, self._csr_last_x, self._csr_last_y)
		self._csr_in_confirm = nil

		return handled
	end

	-- Item-pick reminder is the one control guests may click; checked before the host guard.
	if self._unselected_items_hover then
		self:_on_unselected_items_clicked()

		return true
	end

	if not self:_is_host() then
		return nil
	end

	for idx, btn in ipairs(self._buttons) do
		if btn:is_selected() and btn:callback() then
			btn:callback()()

			return true
		end
	end

	if
		self._start_button
		and not self:_is_locked()
		and self._start_button:is_selected()
		and self._start_button:callback()
	then
		self._start_button:callback()()

		return true
	end

	if self._reroll_button and self._reroll_button:is_selected() and self._reroll_button:callback() then
		self._reroll_button:callback()()

		return true
	end

	if self._action_button and self._action_button:is_selected() and self._action_button:callback() then
		self._action_button:callback()()

		return true
	end
end

-- What the controller cursor may snap to on stick release. Same live-ness rules mouse_moved uses to
-- decide hover, so the magnet never pulls towards something a click would ignore.
function CSRMissionsMenuComponent:csr_magnet_targets(out)
	CSR_ControllerNav.add_sidebar_targets(out, self._sidebar)
	CSR_ControllerNav.add_feature_panel_targets(out, self)
	-- Reminder plates are clickable for guests too, so they go in above the host-only block.
	if self._unselected_visible and not self._csr_overlay_active then
		CSR_ControllerNav.add_target(out, self._unselected_panel)
	end
	CSR_ControllerNav.add_target(out, self._csr_bm_lobby_panel)
	if not self:_is_host() or self._csr_overlay_active then
		return
	end
	for _, btn in ipairs(self._buttons) do
		CSR_ControllerNav.add_target(out, btn:panel())
	end
	if self._start_button and not self:_is_locked() then
		CSR_ControllerNav.add_target(out, self._start_button:panel())
	end
	if self._reroll_button then
		CSR_ControllerNav.add_target(out, self._reroll_button:panel())
	end
	if self._action_button then
		CSR_ControllerNav.add_target(out, self._action_button:panel())
	end
end

-- START on a pad fires "Start the Heist" from anywhere in the lobby, so the cursor never has to
-- find the button. The button already draws the BTN_START glyph, and vanilla routes that pad button
-- through the menu_respec_tree_all connection (blackmarketgui.lua:3247, crimespreemenucomponent.lua:10);
-- MenuInput lists it in _give_special_buttons (menuinput.lua:862), so it reaches live components as
-- special_btn_pressed. Guards mirror the click path: host, unlocked, and no sub-screen or item-pick
-- modal over the lobby.
function CSRMissionsMenuComponent:special_btn_pressed(button)
	if button ~= Idstring("menu_respec_tree_all") then
		return
	end
	if self._csr_overlay_active or _G._csr_item_selection then
		return
	end
	if not self:_is_host() or self:_is_locked() then
		return
	end
	local panel = self._start_button and self._start_button:panel()
	if not (panel and alive(panel) and panel:visible()) then
		return
	end
	self:_start_pressed()

	return true
end

function CSRMissionsMenuComponent:back_pressed()
	if managers.menu:is_pc_controller() then
		return
	end

	-- Controller B (cancel) fires MenuInput:back via a controller trigger, but that early-returns while
	-- we hijack input (input_focus == true), so B only pops when the cursor sits on a vanilla node
	-- button (the one spot we do NOT hijack). Pop the node ourselves whenever we ARE hijacking so B
	-- works everywhere; over a node button we are not hijacked, so let MenuInput:back do it (this same
	-- flag drives input_focus, so exactly one of the two paths ever pops -- no double back).
	if not self._csr_over_vanilla_button then
		return CSR_ControllerNav.navigate_back()
	end
end

function CSRMissionsMenuComponent:dummy_trigger()
	return self:confirm_pressed()
end

-- On a controller the virtual cursor selects cards, so suppress discrete stick nav
-- here (it would jump card selection while the cursor is also moving). Keyboard on
-- pc keeps left/right card navigation.
function CSRMissionsMenuComponent:move_left()
	if not managers.menu:is_pc_controller() then
		return
	end

	return self:move_selection(-1)
end

function CSRMissionsMenuComponent:move_right()
	if not managers.menu:is_pc_controller() then
		return
	end

	return self:move_selection(1)
end

function CSRMissionsMenuComponent:input_focus()
	if managers.menu:is_pc_controller() then
		return
	end

	-- Controller: keep hard focus (hijack) everywhere EXCEPT directly over a vanilla lobby-node button.
	-- Over our widgets OR empty space -> true: MenuInput routes the cursor to us and, being hijacked,
	-- CoreMenuInput:update skips node-item confirm, so A can't fire a stale node selection. Only when
	-- the cursor is on a real node button do we return nil, letting MenuInput hit-test + activate it
	-- (menuinput mouse_moved gates on input_focus ~= true) -- so A works exactly when the cursor is on
	-- the button. _csr_over_vanilla_button is already false whenever _csr_cursor_over_widget is true.
	if self._csr_over_vanilla_button then
		return
	end
	return true
end

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

	local bh = CSRMissionsMenuComponent.button_size.title_h
	local level_name_bg = self._panel:rect({
		y = self._panel:h() - bh,
		h = bh,
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
	-- Also gate _bg on is_active: vanilla doesn't because it launches immediately, but CSR
	-- keeps the chosen card persistent, so without this it flickers on hover.
	self._bg:set_visible(not (self:is_selected() or self:is_active()))
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
	-- Rank gain shown on card; same function mission_lifecycle.lua uses on completion.
	local inc_text = managers.localization:text("menu_cs_lobby_mission_inc", {
		inc = managers.csr:rank_for_mission(mission_data.id),
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

-- CSRStartButton — fork of vanilla CrimeSpreeButton (class rename only; pure Diesel UI widget).
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

-- CSRSidebar / CSRSidebarItem — fork of vanilla CrimeNetSidebarGui (visual recipe 1:1; collapse/expand etc. dropped).
CSRSidebar = CSRSidebar or class()
CSRSidebar._type = "CSRSidebar"
CSRSidebar.WIDTH = 160 -- narrower than vanilla CrimeNet's 256
local function csr_open_logbook()
	local has_cb = MenuCallbackHandler ~= nil and MenuCallbackHandler.CSR_OpenLogbook ~= nil
	csr_log("[CSR Logbook] sidebar Logbook clicked; CSR_OpenLogbook present=" .. tostring(has_cb))

	if has_cb then
		MenuCallbackHandler:CSR_OpenLogbook()
	end
end

local function csr_open_shop()
	if MenuCallbackHandler and MenuCallbackHandler.CSR_OpenBlackMarket then
		MenuCallbackHandler:CSR_OpenBlackMarket()
	end
end

-- Row callbacks are invoked as btn:callback()(owner); forward to the component-owned panel.
local function csr_feature_toggle(key)
	return function(owner)
		if owner and owner.toggle_feature_panel then
			owner:toggle_feature_panel(key)
		end
	end
end

-- Resolve the selected character's default mask texture at build time; falls back to
-- the generic mask icon if the character or texture is missing.
local function csr_character_mask_icon()
	local ok, path = pcall(function()
		local bm = managers and managers.blackmarket
		if not bm then
			return nil
		end
		return bm:get_mask_icon("character_locked")
	end)
	if
		ok
		and type(path) == "string"
		and path ~= ""
		and DB
		and DB.has
		and DB:has(Idstring("texture"), Idstring(path))
	then
		return path
	end
	return "upcard_mask"
end

-- .text fields hold loc keys, not literals -- localized at render in CSRSidebar:_setup
-- (this table is file-scope, so managers.localization isn't available here yet).
CSRSidebar.ITEMS = {
	{ separator = true },
	{
		text = "csr_sidebar_heister",
		icon = csr_character_mask_icon,
		key = "heister",
		callback = csr_feature_toggle("heister"),
	},
	{ separator = true },
	{ text = "csr_sidebar_items", icon = "sidebar_casino", key = "items", callback = csr_feature_toggle("items") },
	{
		text = "csr_sidebar_modifiers",
		icon = "sidebar_mutators",
		key = "modifiers",
		callback = csr_feature_toggle("modifiers"),
	},
	{
		text = "csr_sidebar_rewards",
		icon = "sidebar_broker",
		key = "rewards",
		callback = csr_feature_toggle("rewards"),
	},
	{ separator = true },
	{ text = "csr_sidebar_black_market", icon = "sidebar_gage", callback = csr_open_shop },
	{ separator = true },
	{ text = "csr_sidebar_logbook", icon = "sidebar_codex", callback = csr_open_logbook },
	{ separator = true },
	{
		text = "csr_sidebar_preferences",
		icon = "sidebar_filters",
		key = "preferences",
		callback = csr_feature_toggle("preferences"),
	},
}

function CSRSidebar:init(parent, top, bottom, owner)
	self._owner = owner
	self._buttons = {}
	self._panel = parent:panel({
		w = CSRSidebar.WIDTH,
		y = top,
		h = bottom - top,
		layer = 100,
	})
	self._bg_panel = self._panel:panel({
		layer = -1,
	})

	self._bg_panel:rect({
		alpha = 0.4,
		color = Color.black,
	})
	self._bg_panel:bitmap({
		texture = "guis/textures/test_blur_df",
		name = "blur_bg",
		halign = "scale",
		layer = -1,
		render_template = "VertexColorTexturedBlur3D",
		valign = "scale",
		w = self._bg_panel:w(),
		h = self._bg_panel:h(),
	})

	self._collapsed = false

	local item_margin = 2

	-- Collapse toggle is never hidden by set_collapsed, staying visible as the "SHOW" affordance.
	self._toggle = CSRSidebarItem:new(self._panel, {
		position = padding,
		text = managers.localization:text("csr_sidebar_hide"),
		icon = "sidebar_expand",
		callback = function()
			self:toggle_collapsed()
		end,
	})

	table.insert(self._buttons, self._toggle)

	local next_position = padding + self._toggle:panel():height() + item_margin

	for _, item in ipairs(CSRSidebar.ITEMS) do
		local btn

		if item.separator then
			btn = CSRSidebarSeparator:new(self._panel, {
				position = next_position,
			})
		else
			-- icon may be a function (resolved at build time) or a static hud-id string.
			local icon = item.icon
			if type(icon) == "function" then
				icon = icon()
			end
			btn = CSRSidebarItem:new(self._panel, {
				position = next_position,
				text = managers.localization:text(item.text),
				icon = icon,
				callback = item.callback,
			})
			btn._feature_key = item.key -- nil for non-feature rows (Black Market, Logbook)
		end

		next_position = next_position + btn:panel():height() + item_margin

		table.insert(self._buttons, btn)
	end

	-- Stored so set_collapsed can hide the frame along with the other collapsible content.
	self._border_panel = self._panel:panel({
		layer = 100,
	})
	self._border = BoxGuiObject:new(self._border_panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})
end

-- inside() still hits invisible panels, so collapsed rows are gated on self._collapsed, not visibility.
function CSRSidebar:toggle_collapsed()
	self:set_collapsed(not self._collapsed)
end

function CSRSidebar:set_collapsed(collapsed)
	self._collapsed = collapsed and true or false

	if self._bg_panel then
		self._bg_panel:set_visible(not self._collapsed)
	end

	if self._border_panel then
		self._border_panel:set_visible(not self._collapsed)
	end

	for _, btn in ipairs(self._buttons) do
		if btn ~= self._toggle then
			btn:panel():set_visible(not self._collapsed)
		end
	end

	-- Hide the feature panel on collapse; expanding does NOT reopen it.
	if self._collapsed and self._owner and self._owner.hide_feature_panels then
		self._owner:hide_feature_panels()
	end

	self._toggle:set_text(managers.localization:text(self._collapsed and "csr_sidebar_show" or "csr_sidebar_hide"))
end

function CSRSidebar:panel()
	return self._panel
end

function CSRSidebar:mouse_moved(x, y)
	local used, pointer = false, nil

	for _, btn in ipairs(self._buttons) do
		-- While collapsed only the toggle row is live (hidden rows still hit-test geometrically).
		if (btn == self._toggle or not self._collapsed) and btn:accepts_interaction() then
			local inside = btn:inside(x, y)

			btn:set_highlight(inside)

			if inside then
				used = true
				pointer = "link"
			end
		end
	end

	return used, pointer
end

function CSRSidebar:mouse_pressed(x, y)
	for _, btn in ipairs(self._buttons) do
		-- While collapsed only the toggle is live (hidden rows still hit-test).
		if
			(btn == self._toggle or not self._collapsed)
			and btn:accepts_interaction()
			and btn:inside(x, y)
			and btn:callback()
		then
			managers.menu_component:post_event("menu_enter")
			btn:callback()(self._owner)

			return true
		end
	end
end

function CSRSidebar:update(t, dt)
	for _, btn in ipairs(self._buttons) do
		btn:update(t, dt)
	end
end

-- Light up the row whose feature panel is visible; nil clears all highlights.
function CSRSidebar:set_active_feature(key)
	for _, btn in ipairs(self._buttons) do
		if btn.set_selected then
			btn:set_selected(btn._feature_key ~= nil and btn._feature_key == key)
		end
	end
end

-- Flash the new-modifier siren behind the Modifiers row icon (end-screen post-heist cue).
function CSRSidebar:play_modifier_siren()
	for _, btn in ipairs(self._buttons) do
		if btn._feature_key == "modifiers" and btn.play_siren then
			csr_log("[CSR][siren] play_modifier_siren: modifiers button found, arming") -- TEMP siren debug
			btn:play_siren()
			return
		end
	end
	csr_log("[CSR][siren] play_modifier_siren: NO modifiers button found") -- TEMP siren debug
end

-- CSRSidebarSeparator — fork of vanilla CrimeNetSidebarSeparator; 10px non-interactive row.
CSRSidebarSeparator = CSRSidebarSeparator or class()
CSRSidebarSeparator._type = "CSRSidebarSeparator"

function CSRSidebarSeparator:init(parent_panel, parameters)
	self._panel = parent_panel:panel({
		h = 10,
		layer = 10,
		w = parent_panel:width() - padding * 2,
		x = padding,
		y = parameters.position,
	})

	local bitmap = self._panel:bitmap({
		texture = "guis/dlcs/sju/textures/pd2/crimenet_menu_dots_df",
		name = "separator",
		color = tweak_data.screen_colors.button_stage_3,
	})

	bitmap:set_center_y(self._panel:height() * 0.5)
end

function CSRSidebarSeparator:panel()
	return self._panel
end

function CSRSidebarSeparator:accepts_interaction()
	return false
end

function CSRSidebarSeparator:update(t, dt) end

-- Red/blue police siren flashed behind the Modifiers sidebar icon on the end screen when a new
-- modifier just unlocked. Vanilla raid colors; alpha driven from update() so it ticks reliably.
local sidebar_siren_duration = 3 -- seconds the strobe plays
local sidebar_siren_glow_size = 56 -- glow diameter behind the 24px icon
local sidebar_siren_red = Color(255, 255, 0, 0) / 255 -- a, r, g, b
local sidebar_siren_blue = Color(255, 0, 180, 255) / 255

CSRSidebarItem = CSRSidebarItem or class()
CSRSidebarItem._type = "CSRSidebarItem"

function CSRSidebarItem:init(panel, parameters)
	local font_size = math.ceil(tweak_data.menu.pd2_small_font_size)
	local icon_size = 24
	local panel_size = math.max(font_size, icon_size)
	self._callback = parameters.callback
	self._panel = panel:panel({
		halign = "scale",
		layer = 10,
		valign = "scale",
		w = panel:w() - padding * 2,
		h = panel_size,
		x = padding,
		y = parameters.position,
	})

	-- "/" in icon = direct DB texture path (no rect); otherwise a hud_icons id.
	local texture, rect
	local icon = parameters.icon
	if type(icon) == "string" and icon:find("/", 1, true) then
		texture, rect = icon, nil
	else
		texture, rect = tweak_data.hud_icons:get_icon_data(icon)
	end

	self._icon = self._panel:bitmap({
		name = "icon",
		blend_mode = "normal",
		layer = 1,
		texture = texture,
		texture_rect = rect,
		w = icon_size,
		h = icon_size,
	})
	self._text = self._panel:text({
		text = "",
		name = "title",
		valign = "scale",
		halign = "scale",
		blend_mode = "normal",
		y = 2,
		layer = 2,
		font = tweak_data.menu.pd2_medium_font,
		font_size = font_size,
		color = tweak_data.screen_colors.button_stage_3,
		x = icon_size + 4,
		h = font_size,
	})

	self:set_text(parameters.text or "")

	self._bg = self._panel:rect({
		blend_mode = "normal",
		layer = 1,
		halign = "scale",
		alpha = 0.66,
		valign = "scale",
		x = icon_size,
		color = Color.black,
	})

	self._selected = false -- active-tab marker, independent of hover

	self:set_highlight(false, true)
end

function CSRSidebarItem:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRSidebarItem:panel()
	return self._panel
end

function CSRSidebarItem:callback()
	return self._callback
end

function CSRSidebarItem:accepts_interaction()
	return true
end

-- Vanilla CrimeNetSidebarItem:set_highlight signature (enabled, no_sound, force_update).
function CSRSidebarItem:set_highlight(enabled, no_sound, force_update)
	if self._highlight ~= enabled or force_update then
		self._highlight = enabled
		self:_apply_visual()

		if not no_sound then
			managers.menu:post_event("highlight")
		end
	end
end

-- Persistent active-tab highlight; change-guarded and silent (must not fire the hover sound).
function CSRSidebarItem:set_selected(enabled)
	enabled = enabled and true or false
	if self._selected ~= enabled then
		self._selected = enabled
		self:_apply_visual()
	end
end

-- Compose look from hover + active-tab state. Always set color AND alpha: Diesel's
-- set_color writes RGB only, so alpha from a previous state bleeds across without the re-apply.
function CSRSidebarItem:_apply_visual()
	self._text:set_visible(true)

	if self._selected then
		self._bg:set_visible(true)
		self._bg:set_color(tweak_data.screen_colors.button_stage_2)
		self._bg:set_alpha(self._highlight and 0.22 or 0.1)
		self._text:set_color(Color.white)
		self._icon:set_color(Color.white)
	else
		local col = self._highlight and Color.white or tweak_data.screen_colors.button_stage_2
		self._bg:set_visible(self._highlight)
		self._bg:set_color(Color.black)
		self._bg:set_alpha(0.66)
		self._text:set_color(col)
		self._icon:set_color(col)
	end
end

function CSRSidebarItem:set_text(text)
	-- Vanilla CrimeNetSidebarItem:set_text: upper-case + spaces -> underscores.
	text = utf8.to_upper(text)
	text = text:gsub(" ", "_")

	self._text:set_text(text)
end

-- Arm a one-shot ~3s red/blue siren behind this row's icon. Lazily builds the two additive glow
-- bitmaps (layer 0, under the layer-1 icon), centered on the icon. update() drives the strobe.
function CSRSidebarItem:play_siren()
	if not alive(self._panel) or not alive(self._icon) then
		return
	end
	if not alive(self._siren_glow) then
		local cx, cy = self._icon:center()
		self._siren_glow = self._panel:panel({
			name = "csr_siren_glow",
			layer = 0,
			w = sidebar_siren_glow_size,
			h = sidebar_siren_glow_size,
		})
		self._siren_glow:set_center(cx, cy)
		local function add_glow(color)
			return self._siren_glow:bitmap({
				texture = "guis/textures/pd2/crimenet_marker_glow",
				blend_mode = "add",
				color = color,
				alpha = 0,
				w = self._siren_glow:w(),
				h = self._siren_glow:h(),
			})
		end
		self._siren_red = add_glow(sidebar_siren_red)
		self._siren_blue = add_glow(sidebar_siren_blue)
	end
	self._siren_t = 0
	self._siren_logged = nil -- TEMP siren debug
end

function CSRSidebarItem:update(t, dt)
	if not self._siren_t then
		return
	end
	if not alive(self._siren_red) or not alive(self._siren_blue) then
		self._siren_t = nil
		return
	end
	self._siren_t = self._siren_t + dt
	local tt = self._siren_t
	if tt >= sidebar_siren_duration then
		self._siren_t = nil
		if alive(self._siren_glow) then
			self._panel:remove(self._siren_glow)
		end
		self._siren_glow, self._siren_red, self._siren_blue = nil, nil, nil
		return
	end
	-- Out-of-phase red/blue strobe; quick fade over the last 0.6s so it trails off.
	local fade = math.min(1, (sidebar_siren_duration - tt) / 0.6)
	local red_a = math.abs(math.sin(tt * 8)) * 0.55 * fade
	local blue_a = math.abs(math.cos(tt * 8)) * 0.55 * fade
	self._siren_red:set_alpha(red_a)
	self._siren_blue:set_alpha(blue_a)
	if not self._siren_logged then -- TEMP siren debug
		self._siren_logged = true
		csr_log(
			"[CSR][siren] update ticking: tt="
				.. string.format("%.2f", tt)
				.. " red_a="
				.. string.format("%.2f", red_a)
				.. " blue_a="
				.. string.format("%.2f", blue_a)
				.. " panel_vis="
				.. tostring(alive(self._panel) and self._panel:visible())
		)
	end
end

csr_log("[CSR] missions_menu.lua loaded (Slice 8 fork + start button)")
