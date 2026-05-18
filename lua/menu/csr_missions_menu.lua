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
-- Vertical gap between the measured bottom of the foreground title text and the
-- top of the sidebar. Single visual tunable: raise it to push the sidebar down,
-- lower it to pull the sidebar up toward the header. Kept small — the massive
-- ghost behind the title is alpha 0.4 and its visible glyphs sit well above its
-- 90px box, so a modest clearance avoids overlap without wasting space.
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

	-- The component now builds on BOTH the crime_spree_lobby node AND the
	-- mission_end_menu "main" node (csr_missions_wiring.lua fix #3). The
	-- branded "Crime Spree Roguelike" title and the left sidebar are
	-- LOBBY-ONLY chrome — on the end screen they must not render (user
	-- report 2026-05-18). node-name is the deterministic boundary, the same
	-- signal csr_missions_wiring.lua gates the build on.
	local pnode = node and node.parameters and node:parameters()
	self._is_lobby = pnode ~= nil and pnode.name == "crime_spree_lobby"

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

	-- Mission cards' bottom edge (applied below via self._buttons_panel:set_bottom).
	-- Hoisted so the sidebar can be built with its height pinned to it — the
	-- sidebar sits at y=0, so h == bottom makes its bottom line up with the cards.
	local bottom = parent:bottom() - tweak_data.menu.pd2_large_font_size * 1.5

	-- _create_title() is called UNCONDITIONALLY: it sets self._title_bottom,
	-- and _create_sidebar anchors its top to that
	-- (top = self._title_bottom + sidebar_title_gap). Skipping the title would
	-- make _title_bottom nil -> top collapses to sidebar_title_gap -> the
	-- sidebar shifts UP and grows taller (user report 2026-05-18 — NOT
	-- requested). The title is lobby-only chrome, so on the end screen its
	-- visible elements are hidden INSIDE _create_title instead: the geometry
	-- (self._title_bottom) is preserved, only the text is not drawn. Sidebar
	-- stays byte-identical to the lobby.
	self:_create_title()
	self:_create_sidebar(bottom)

	local w = (self.button_size.w + padding) * tweak_data.crime_spree.gui.missions_displayed - padding
	local h = self.button_size.h + self.button_size.title_h
	self._title_panel = self._panel:panel({})

	self._title_panel:set_w(w)
	self._title_panel:set_h(tweak_data.menu.pd2_medium_font_size)
	self._title_panel:set_right(parent:right())
	self._title_panel:set_bottom(bottom - h - 4)
	-- The header row's text is built entirely by _create_status_bar: spree RANK
	-- on the left (replacing the old static "SELECT NEXT HEIST" label) and the
	-- DIFFICULTY on the right, both on this single line above the cards.
	self:_create_status_bar(w)

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

	-- Slice B context button, LEFT of Reroll. Same CSRStartButton widget as
	-- Reroll. Its label + callback (and the Start/Reroll failed-lock) are set
	-- by _refresh_action_buttons(), called here and from refresh() so the
	-- failed state re-applies whenever the panel rebuilds.
	self._action_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size * 0.8)

	self._action_button:panel():set_bottom(self._reroll_button:panel():bottom())
	self:_refresh_action_buttons()

	-- Black scrim behind the Start / Reroll buttons. Spans the full 3-card
	-- mission-row width (same `w` and right edge as self._buttons_panel above)
	-- so it reads as a backing plate aligned with the cards. Created after the
	-- buttons so it can measure them, but pinned to layer 1 -- well below the
	-- CSRStartButton panels (layer 1000, see CSRStartButton:init) -- so Diesel's
	-- per-layer child sort draws it underneath regardless of insertion order.
	-- color + alpha (not a 3-arg Color, Rule #6): same rect idiom CSRStartButton
	-- uses for its highlight. Child of self._panel, so vanilla close() cleans it
	-- up. Start/Reroll are never toggled in refresh(), so neither is this.
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
end

function CSRMissionsMenuComponent:_create_title()
	-- Top-left branded header in the vanilla lobby "crew page" style
	-- (contractboxgui.lua:8-84, the PLANNING-PHASE-looking title): a crisp
	-- pd2_large_font foreground on the safe workspace plus a huge faded blue
	-- pd2_massive_font ghost on the fullscreen workspace, coordinate-mapped with
	-- safe_to_full_16_9 so the ghost lines up without being clipped by the safe
	-- area. Copied 1:1 from vanilla; only the text (csr_header_title, registered
	-- in csr_contract_wiring.lua) and component panels differ. We route the lobby
	-- box to CrimeSpreeContractBoxGui (which draws no crewpage header), so this
	-- corner is free and there is no double-up with vanilla. MenuBackdropGUI.
	-- animate_bg_text is intentionally NOT called: it is a verified no-op
	-- (pd2_menubackdrop_animate_bg_text_noop) -- the ghost is static in vanilla.
	-- Children of self._panel / self._fullscreen_panel, both removed in close().
	local title = self._panel:text({
		vertical = "top",
		name = "csr_title",
		align = "left",
		text = managers.localization:to_upper_text("csr_header_title"),
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})
	local _, _, w, h = title:text_rect()

	title:set_size(w, h)

	-- Measured bottom of the solid foreground title, in self._panel (safe)
	-- coords. The sidebar starts at this + sidebar_title_gap. We anchor to the
	-- measured text (not modelled ghost-box geometry): the ghost is alpha 0.4
	-- and top-aligned in an oversized box, so its visible glyphs end only a
	-- little below the foreground — a small gap clears both.
	self._title_bottom = title:bottom()

	-- End screen: the measurement above is kept (the sidebar anchors to it),
	-- but the branded title itself is lobby-only chrome and must not render
	-- here (user report 2026-05-18). Hide rather than skip so geometry holds.
	if not self._is_lobby then
		title:set_visible(false)
	end

	if MenuBackdropGUI then
		local ghost_h = 90
		local ghost_move_y = 9
		local bg_text = self._fullscreen_panel:text({
			name = "csr_title",
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

		-- End screen: hide the faded ghost too (lobby-only chrome).
		if not self._is_lobby then
			bg_text:set_visible(false)
		end
	end
end

function CSRMissionsMenuComponent:_create_sidebar(bottom)
	-- CrimeNet-style left sidebar, forked from CrimeNetSidebarGui /
	-- CrimeNetSidebarItem (crimenetsidebargui.lua). Visual recipe copied 1:1
	-- (256-wide panel, 0.4 black + test_blur_df backdrop, BoxGui border, icon +
	-- underscored-uppercase label rows). The collapse/expand, glow, pulse,
	-- attention/separator subclasses and controller snap are intentionally
	-- dropped — user asked for "just the panel" for now. Buttons are
	-- placeholders with no callbacks; behaviour wired in a later pass.
	-- Child of self._panel so the existing close() (removes self._panel) cleans
	-- it up. CSR-only by construction: this component is built only for the
	-- crime_spree_lobby node. The panel spans [top, bottom]: `top` clears the
	-- title (measured foreground bottom + sidebar_title_gap) so the sidebar
	-- never overlaps the header text or its faint ghost; `bottom` is the
	-- mission cards' bottom edge so the two line up.
	local top = (self._title_bottom or 0) + sidebar_title_gap

	self._sidebar = CSRSidebar:new(self._panel, top, bottom)
end

function CSRMissionsMenuComponent:_create_status_bar(w)
	-- The header row directly above the mission cards (it replaces the old
	-- static "SELECT NEXT HEIST" label) shows three values on one line:
	--   MISSIONS COMPLETED (left)  |  RANK (center)  |  DIFFICULTY (right)
	-- All three are parented to self._title_panel with vertical/valign "bottom"
	-- so the baselines line up, and all follow the single self._title_panel
	-- visibility toggle in refresh(). RANK uses align "center" so it floats
	-- between the left/right anchored labels. Backend reads go through
	-- managers.csr (the refactor's single source of truth).
	-- Difficulty is mapped id -> loc via vanilla tweak_data.difficulty_name_ids
	-- (NOT "menu_difficulty_"..id -- engine ids like "overkill" don't match that
	-- pattern: that id localizes to "Very Hard", not "Overkill"). Child of
	-- self._panel, so the existing close() (removes self._panel) cleans it up.
	--
	-- Yellow highlight for the dynamic values only (rank number + Crime Spree
	-- glyph, and the difficulty name) -- the static "RANK"/"DIFFICULTY:" labels
	-- stay white. 4-arg Color per Rule #6 (3-arg Color drops blue). Applied as
	-- a sub-string recolor via set_range_color, the same vanilla-proven pattern
	-- used for the mission-card risk text further down this file.
	local highlight = Color(1, 1, 1, 0)
	-- U+E018: the Crime Spree glyph (same codepoint csr_localization.lua emits
	-- as the raw bytes \xEE\x80\x98); utf8.char keeps it consistent with the
	-- existing utf8.char(0xE012) usage there.
	local cs_glyph = utf8.char(0xE018)

	-- Left anchor: how many heists were completed in the current run. Reads the
	-- dedicated managers.csr:missions_completed() counter (NOT rank -- the two
	-- are distinct concepts; see csr_game_manager.lua default_state comment).
	local missions_prefix = managers.localization:to_upper_text("csr_lobby_missions_completed") .. ": "
	local missions_str = missions_prefix .. tostring(managers.csr:missions_completed())
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

	-- Center anchor: spree RANK, floating between the left/right labels.
	local rank_prefix = managers.localization:to_upper_text("csr_lobby_rank") .. ": "
	local rank_str = rank_prefix .. tostring(managers.csr:rank()) .. " " .. cs_glyph
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

	local diff_id = managers.csr:difficulty()
	local diff_name_id = tweak_data.difficulty_name_ids[diff_id]
	local diff_text = diff_name_id and managers.localization:to_upper_text(diff_name_id) or tostring(diff_id)

	-- Right-aligned on the same self._title_panel line as the rank text;
	-- vertical/valign "bottom" matches the rank text so the baselines align.
	-- refresh() toggles self._title_panel visibility, so this child follows it.
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

-- A failed run (lobby only) locks mission select / Start until the player
-- resolves it via the paid Continue or End Spree. has_failed() is a persisted
-- managers.csr flag set by csr_mission_lifecycle on a lost heist.
function CSRMissionsMenuComponent:_is_locked()
	return self._is_lobby and managers.csr and managers.csr:has_failed() == true
end

-- Thin wrappers to the backend-swapped contract callbacks (same pattern as
-- _start_pressed -> csr_start_game). end_csr/return_to_csr_lobby/csr_continue
-- now act on managers.csr (Slice B backend swap).
function CSRMissionsMenuComponent:_action_end_spree()
	MenuCallbackHandler:end_csr()
end

function CSRMissionsMenuComponent:_action_return_to_lobby()
	log("[CSR] _action_return_to_lobby: button pressed (is_lobby=" .. tostring(self._is_lobby) .. ")")
	MenuCallbackHandler:return_to_csr_lobby()
end

function CSRMissionsMenuComponent:_action_continue()
	MenuCallbackHandler:csr_continue()
end

-- Sets the context button (left of Reroll) + the Start/Reroll failed-lock.
-- Called at build and from refresh() so the failed state always re-applies.
function CSRMissionsMenuComponent:_refresh_action_buttons()
	local locked = self:_is_locked()

	if self._action_button then
		-- Loc: csr_end_spree / csr_return_to_lobby follow the csr_* convention
		-- (CSR-owned wording, like csr_lobby_rank). menu_cs_continue is the
		-- existing vanilla key (crimespreemissionendoptions.lua:80).
		if self._is_lobby then
			self._action_button:set_text(managers.localization:to_upper_text("csr_end_spree"))
			self._action_button:set_callback(callback(self, self, "_action_end_spree"))
		else
			self._action_button:set_text(managers.localization:to_upper_text("csr_return_to_lobby"))
			self._action_button:set_callback(callback(self, self, "_action_return_to_lobby"))
		end

		if managers.menu:is_pc_controller() then
			self._action_button:shrink_wrap_button()
		end

		self._action_button:panel():set_right(self._reroll_button:panel():left() - large_padding)
		self._action_button:panel():set_bottom(self._reroll_button:panel():bottom())
	end

	if self._start_button then
		-- Failed: Start hidden (cannot launch a heist on a failed run).
		self._start_button:panel():set_visible(not locked)
	end

	if self._reroll_button then
		if locked then
			self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_continue"))
			self._reroll_button:set_callback(callback(self, self, "_action_continue"))
		else
			self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_reroll"))
			self._reroll_button:set_callback(callback(self, self, "_reroll_pressed"))
		end

		if managers.menu:is_pc_controller() then
			self._reroll_button:shrink_wrap_button()
		end
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

function CSRMissionsMenuComponent:_set_button_index_selected(idx, selected)
	if not idx then
		return false
	end

	-- Failed run is locked: no mission can be selected until Continue (pay)
	-- or End Spree. The cards stay visible but inert.
	if selected and self:_is_locked() then
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
	-- Rank + difficulty are both children of self._title_panel, so this single
	-- toggle covers the whole header row.
	self._title_panel:set_visible(not hide)

	-- Re-apply the context button + failed-lock every refresh so returning to
	-- a FAILED lobby comes up locked (Start hidden, Reroll -> Continue).
	self:_refresh_action_buttons()
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

	if self._sidebar then
		self._sidebar:update(t, dt)
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

	if self._action_button then
		self._action_button:set_selected(self._action_button:inside(x, y))

		if self._action_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if self._sidebar then
		local s_used, s_pointer = self._sidebar:mouse_moved(x, y)

		if s_used then
			pointer = s_pointer
			used = true
		end
	end

	return used, pointer
end

-- NOTE: MenuComponentManager dispatches this via
-- run_return_on_all_live_components("mouse_pressed", button, x, y)
-- (menucomponentmanager.lua:1693) — i.e. the component is called as
-- mouse_pressed(self, button, x, y), only THREE args. Vanilla declares
-- (o, button, x, y) and gets away with it because its body only calls
-- confirm_pressed() and never reads the (shifted) coords. Our sidebar branch
-- needs real x,y, so we must use the correct 3-arg signature here.
function CSRMissionsMenuComponent:mouse_pressed(button, x, y)
	-- Sidebar click uses real cursor coords (confirm_pressed has none). With
	-- placeholder buttons (no callbacks) this returns nil and falls through, so
	-- card/start/reroll handling is unchanged until sidebar callbacks land.
	if self._sidebar and self._sidebar:mouse_pressed(x, y) then
		return true
	end

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

	if self._action_button and self._action_button:is_selected() and self._action_button:callback() then
		self._action_button:callback()()

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
	-- Vanilla passes mission_data.add here -- the per-mission rank increment
	-- from vanilla CS tweak_data, which varies by mission length/difficulty.
	-- The CSR rebalance makes every completed heist worth a FLAT rank amount
	-- (rank_per_heist), so the card must advertise that same flat value, not
	-- the vanilla per-mission number. This is the exact value the player
	-- actually receives -- csr_mission_lifecycle.lua awards
	-- managers.csr:constant("rank_per_heist") on a successful heist with the
	-- identical `or 1` fallback, so the card and the payout never disagree.
	local inc_text = managers.localization:text("menu_cs_lobby_mission_inc", {
		inc = managers.csr:constant("rank_per_heist") or 1,
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

-- CSRSidebar / CSRSidebarItem — fork of vanilla CrimeNetSidebarGui /
-- CrimeNetSidebarItem (pd2_source_code/lib/managers/menu/crimenetsidebargui.lua).
-- Visual recipe copied 1:1: 256-wide panel pinned to the workspace left edge,
-- 0.4 black rect + test_blur_df backdrop on a layer -1 sub-panel, BoxGui border,
-- and per-row icon + underscored-uppercase label with a 0.66 black highlight bg.
-- Deliberately NOT forked (user wants "just the panel"): collapse/expand state,
-- glow, pulse colour, controller mouse-snap, the tweak_data.gui.crime_net.sidebar
-- data drive, and the Attention/Separator/Safehouse/etc. item subclasses. Items
-- here are a static placeholder list with no callbacks; behaviour is a later
-- pass. Pure Diesel UI — no managers.crime_spree / managers.csr reads; CSR-only
-- scoping is guaranteed by the owning component (built only for crime_spree_lobby).
CSRSidebar = CSRSidebar or class()
CSRSidebar._type = "CSRSidebar"
CSRSidebar.WIDTH = 160 -- vanilla CrimeNet sidebar is 256; CSR uses a narrower panel
-- CSR feature rows, in the order the user requested. icon ids are real vanilla
-- hud_icons used by the live CrimeNet sidebar (guitweakdata.lua:1840+) so they
-- resolve through tweak_data.hud_icons:get_icon_data — they are PLACEHOLDERS
-- only (final art TBD). Callbacks are wired per-row as features get ported;
-- rows without one are inert until then.
local function csr_open_logbook()
	-- Reuse the ported open-node callback (lua/menu/logbook_button.lua), which
	-- wraps managers.menu:open_node("csr_logbook_screen"). Resolved at click
	-- time, so load order with the logbook scripts doesn't matter.
	local has_cb = MenuCallbackHandler ~= nil and MenuCallbackHandler.CSR_OpenLogbook ~= nil
	log("[CSR Logbook] sidebar Logbook clicked; CSR_OpenLogbook present=" .. tostring(has_cb))

	if has_cb then
		MenuCallbackHandler:CSR_OpenLogbook()
	end
end

CSRSidebar.ITEMS = {
	{ text = "Items", icon = "sidebar_basics" },
	{ text = "Modifiers", icon = "sidebar_mutators" },
	{ text = "Rewards", icon = "sidebar_broker" },
	{ separator = true },
	{ text = "Gage Services", icon = "sidebar_gage" },
	{ separator = true },
	{ text = "Logbook", icon = "sidebar_codex", callback = csr_open_logbook },
}

function CSRSidebar:init(parent, top, bottom)
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

	local next_position = padding
	local item_margin = 2

	for _, item in ipairs(CSRSidebar.ITEMS) do
		local btn

		if item.separator then
			btn = CSRSidebarSeparator:new(self._panel, {
				position = next_position,
			})
		else
			btn = CSRSidebarItem:new(self._panel, {
				position = next_position,
				text = item.text,
				icon = item.icon,
				callback = item.callback,
			})
		end

		next_position = next_position + btn:panel():height() + item_margin

		table.insert(self._buttons, btn)
	end

	self._border = BoxGuiObject:new(
		self._panel:panel({
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
end

function CSRSidebar:panel()
	return self._panel
end

function CSRSidebar:mouse_moved(x, y)
	local used, pointer = false, nil

	for _, btn in ipairs(self._buttons) do
		if btn:accepts_interaction() then
			local inside = btn:inside(x, y)

			btn:set_highlight(inside, true)

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
		if btn:accepts_interaction() and btn:inside(x, y) and btn:callback() then
			btn:callback()()

			return true
		end
	end
end

function CSRSidebar:update(t, dt)
	for _, btn in ipairs(self._buttons) do
		btn:update(t, dt)
	end
end

-- CSRSidebarSeparator — fork of vanilla CrimeNetSidebarSeparator
-- (crimenetsidebargui.lua:457-491), 1:1 minus the collapse width-swap (we have
-- no collapse). A non-interactive 10px row with the vanilla dotted divider
-- texture. Texture path verified present in extracted assets
-- (guis/dlcs/sju/textures/pd2/crimenet_menu_dots_df.texture).
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

	local texture, rect = tweak_data.hud_icons:get_icon_data(parameters.icon)

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

function CSRSidebarItem:set_highlight(enabled, force_update)
	if self._highlight ~= enabled or force_update then
		self._text:set_visible(true)
		self._bg:set_visible(enabled)
		self._text:set_color(enabled and Color.white or tweak_data.screen_colors.button_stage_2)
		self._icon:set_color(enabled and Color.white or tweak_data.screen_colors.button_stage_2)
		self._bg:set_color(Color.black)

		self._highlight = enabled
	end
end

function CSRSidebarItem:set_text(text)
	-- Vanilla quirk preserved 1:1 (CrimeNetSidebarItem:set_text): upper-case and
	-- spaces -> underscores. Keeps the look identical to the CrimeNet sidebar.
	text = utf8.to_upper(text)
	text = text:gsub(" ", "_")

	self._text:set_text(text)
end

function CSRSidebarItem:update(t, dt) end

log("[CSR] csr_missions_menu.lua loaded (Slice 8 fork + start button)")
