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

-- Items feature-panel layout. Rarity palette includes contraband even though
-- contraband items are excluded from the SELECTION-WINDOW pool (U1 drop-rate
-- redesign cut them from random rolls): the items themselves still exist and
-- can reach a player's inventory through other paths (e.g. the shop when ported
-- back), so the inventory view needs the matching frame tint. Contraband
-- orange matches the logbook's RARITY_FRAMES.contraband (logbook_menu.lua:257).
local items_panel_rarity_colors = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}
-- items_panel_icon_size is misnamed historically -- it is the CELL size (used
-- for the grid step and hover hit-test). The visible icon and the visible frame
-- have their own sizes below; the frame deliberately overflows the cell so it
-- reads as a card that's "a bit bigger than the icon" (user spec).
local items_panel_icon_size = 64
local items_panel_frame_size = 72
local items_panel_icon_gap = 8
-- Absolute floor for the cell size (RoR2-style adaptive items grid -- see
-- csr_adaptive_grid). Each player's inventory must fit a FIXED quarter of the panel
-- height, so cells shrink from items_panel_icon_size down to this as the count
-- grows; an inventory too large to fit its quarter even at this size overflows
-- (the readability floor). Low enough that the full 31-type inventory still fits a
-- quarter at typical panel heights.
local items_panel_min_icon_size = 28
local items_panel_peer_header_h = 22
-- 4-direction 1px offsets for the stack-count outline: the badge is drawn in black
-- at these offsets under the white copy, so "xN" stays readable over any icon at
-- small cell sizes -- no background box, no font scaling (user choice). Diesel text
-- has no native stroke; this multi-draw is the standard outline technique.
local items_panel_badge_outline = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- Cap (px) on how far below the cell top the stack badge's box bottom sits. The raw
-- anchor is cell_top + glyph_inset + drop, but glyph_inset (the glyph's centring
-- margin) grows with the cell, which dragged the number too low on big icons. Cap it
-- so the number stays near the top-right corner at every size; small icons, whose
-- glyph_inset is already below the cap, are unaffected.
local items_panel_badge_top_inset = 9
local items_panel_padding = 16

-- Modifiers feature-panel sub-tab row (Loud / Stealth). The two buttons split
-- the panel width 50/50 (no gap -- a segmented control) and sit at the top; the
-- modifier icon grid renders below them. Icons are frameless and the grid has its
-- OWN size + gap rather than reusing the items metrics.
local modifiers_subtab_h = 28
local modifiers_subtab_gap = 6 -- small gap between the Loud / Stealth buttons
local modifiers_grid_top_gap = 16
-- Grid sizing (user spec 2026-05-24): the icon row is JUSTIFIED to span the same
-- width as the Loud/Stealth sub-tab row above it -- the first icon's left edge
-- lines up with the Loud button's left edge and the last icon's right edge with
-- the Stealth button's right edge (modifiers_side_margin_frac = 0 keeps it flush;
-- raise it to inset the grid). Icons sit at modifiers_icon_size and NEVER grow
-- past it -- they only SHRINK (down to modifiers_min_icon_size) when the rows
-- would overflow the panel height. The size is deliberately small so MORE than
-- four icons pack into a row; the horizontal gaps then stretch to fill the width.
-- To fit more per row, lower modifiers_icon_size.
local modifiers_icon_size = 52
local modifiers_min_icon_size = 40 -- icons shrink to this (never below) to fit the panel height
local modifiers_icon_gap = 12 -- MINIMUM horizontal gap (the justify step stretches it); also the vertical gap
local modifiers_side_margin_frac = 0 -- inset on EACH side; 0 = flush with the Loud/Stealth buttons

-- Modifiers panel list rows (replaces the old icon grid): a vertical ScrollablePanel
-- where each row is an icon on the left + name (top) and wrapped description (below)
-- to its right. Row height grows to fit the wrapped description.
local modifiers_row_icon_size = 48
local modifiers_row_text_gap = 12 -- icon right edge -> text column
local modifiers_row_gap = 12 -- vertical gap between rows
local modifiers_row_scrollbar_margin = 18 -- reserve the right edge for the scroll bar

-- Rewards feature-panel layout. Four compact rows (one per run-completion reward):
-- a vanilla loot-card thumbnail on the left + title/amount on the right. The card
-- keeps its 128x180 portrait aspect and fills the row height; the row height is
-- derived from the panel height (4 rows + gaps), capped so tall panels don't
-- balloon the cards. The whole block is centred vertically in the panel.
local rewards_panel_row_gap = 12
local rewards_panel_max_row_h = 96
local rewards_panel_card_aspect = 128 / 180 -- loot-card art is portrait (w/h)
local rewards_panel_text_gap = 12 -- card right edge -> title/amount column

-- One Loud/Stealth tab button at the given x/width. Rebuilt (not mutated) on
-- every repopulate, so `active` is baked in at build time -- no separate
-- set_active path needed. Returns the hit-test panel; the caller stores it for
-- mouse_moved/pressed.
local function csr_build_modifier_subtab(parent, text_str, x, y, w, active)
	local p = parent:panel({
		x = x,
		y = y,
		w = w,
		h = modifiers_subtab_h,
		layer = 10,
	})
	p:rect({
		name = "bg",
		color = active and tweak_data.screen_colors.button_stage_2 or Color.black,
		alpha = active and 0.5 or 0.4,
		layer = 0,
	})
	-- Frame discarded like the feature-panel borders (anonymous; panel-tree
	-- teardown removes it with its parent).
	BoxGuiObject:new(p:panel({ layer = 2 }), { sides = { 1, 1, 1, 1 } })
	p:text({
		name = "label",
		text = utf8.to_upper(text_str),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = active and Color.white or tweak_data.screen_colors.button_stage_3,
		align = "center",
		vertical = "center",
		w = p:w(),
		h = p:h(),
		layer = 3,
	})
	return p
end

-- Adaptive grid sizing for the items panel: each player's inventory must fit a
-- FIXED region (a quarter of the panel height), so the cells share one square size
-- that SHRINKS as the count grows until every row fits BOTH the available width
-- and height. Returns the largest such size (<= max_size, clamped at min_size as
-- the floor) and the per-row column count. A count too large to fit even at
-- min_size overflows -- min_size is the readability floor. The inter-cell `gap` is
-- fixed (the size adapts, not the gap); the caller left-aligns, so a full row spans
-- the width and a partial last row hugs the left. cell_size is floored for crisp
-- rendering. Mirrors csr_fit_grid's height-fit loop but stays left-aligned (no
-- justify-stretch) to preserve the items panel's look.
local function csr_adaptive_grid(count, avail_w, avail_h, max_size, min_size, gap)
	if count <= 0 then
		return max_size, 1
	end
	-- Columns of `size` cells that fit avail_w, capped at count (a partial set
	-- leaves no empty trailing columns); rows derived from that.
	local function layout_for(size)
		local per_row = math.max(1, math.min(count, math.floor((avail_w + gap) / (size + gap))))
		return per_row, math.ceil(count / per_row)
	end
	local size = max_size
	while size > min_size do
		local _, rows = layout_for(size)
		if rows * (size + gap) - gap <= avail_h then
			break
		end
		size = size - 2
	end
	size = math.floor(math.max(size, min_size))
	local per_row = layout_for(size)
	return size, per_row
end

-- Justified grid sizing (used by the Modifiers panel). Icons sit at `max_size`
-- and NEVER grow past it; they only SHRINK (down to `min_size`) when the rows
-- would overflow `avail_h` -- a smaller size fits more per row, so fewer rows.
-- Columns pack into the inner width (avail_w minus `margin_frac` on each side) and
-- are capped at `count`. The row is JUSTIFIED across that inner width: the first
-- icon hugs the left edge and the last icon of a full row hugs the right edge,
-- with the horizontal step stretched to absorb the slack -- so the grid spans the
-- same width as the Loud/Stealth sub-tab row above it (user spec 2026-05-24). With
-- margin_frac 0 that left edge is the panel padding (= the Loud button's left) and
-- the right edge is the Stealth button's right. A partial last row left-aligns in
-- the justified columns; the vertical step stays a fixed `size + gap` (set by the
-- caller). Returns (cell_size, cols, start_x, step_x).
local function csr_fit_grid(count, avail_w, avail_h, margin_frac, max_size, min_size, gap)
	if count <= 0 then
		return max_size, 1, 0, 0
	end
	-- Inner width icons span; cols is capped at `count` so a partial set leaves no
	-- empty trailing columns (it justifies across however many icons there are).
	local inner_w = avail_w * (1 - margin_frac * 2)
	local function cols_for(size)
		return math.max(1, math.min(count, math.floor((inner_w + gap) / (size + gap))))
	end
	local size = max_size
	while size > min_size do
		local rows = math.ceil(count / cols_for(size))
		if rows * (size + gap) - gap <= avail_h then
			break
		end
		size = size - 2
	end
	if size < min_size then
		size = min_size
	end
	size = math.floor(size)
	local cols = cols_for(size)
	local start_x = math.floor(avail_w * margin_frac)
	-- Stretch the column step so the first icon sits at start_x and the last full-
	-- row icon's right edge lands at start_x + inner_w. A single column has no step
	-- (the lone icon sits at the left edge).
	local step_x = cols > 1 and math.floor((inner_w - size) / (cols - 1)) or 0
	return size, cols, start_x, step_x
end

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
	-- mission_end_menu "main" node (missions_wiring.lua fix #3). The
	-- branded "Crime Spree Roguelike" title and the left sidebar are
	-- LOBBY-ONLY chrome — on the end screen they must not render (user
	-- report 2026-05-18). node-name is the deterministic boundary, the same
	-- signal missions_wiring.lua gates the build on.
	local pnode = node and node.parameters and node:parameters()
	self._is_lobby = pnode ~= nil and pnode.name == "crime_spree_lobby"

	self:_setup()
end

function CSRMissionsMenuComponent:close()
	-- Drop our CSRGameManager subscriptions before the panels die: an active
	-- callback against destroyed panels would crash on the next add_item.
	-- Each entry is the unsubscribe closure returned by mgr:on_item_added().
	if self._csr_unsubs then
		for _, unsub in ipairs(self._csr_unsubs) do
			if type(unsub) == "function" then
				unsub()
			end
		end
		self._csr_unsubs = nil
	end
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

	-- Abstract anchor fields so the feature-panel helpers below can be method-
	-- borrowed by MissionBriefingGui (see briefing_sidebar.lua). The
	-- briefing screen has different concrete panels for the same conceptual
	-- roles; the helpers read these abstract names so both screens share one
	-- implementation:
	--   _csr_fp_parent       -- panel where feature panels + tooltip are parented
	--                           (lobby: full-ws self._panel; briefing: ws_panel)
	--   _csr_fp_right_anchor -- panel whose :left() is the right boundary of the
	--                           feature panel's allotted rect (lobby:
	--                           _buttons_panel; briefing: vanilla self._panel,
	--                           which is the right-half briefing column).
	self._csr_fp_parent = self._panel
	self._csr_fp_right_anchor = self._buttons_panel

	-- Built here (not in _create_sidebar) because it measures BOTH the sidebar
	-- and the now-positioned mission-cards panel for its left/right bounds.
	self:_create_feature_panels()

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

			-- Re-highlight the still-selected mission on rebuild. The pick
			-- survives sub-screen round-trips (Inventory/Options) and is only
			-- cleared on a genuine lobby exit -- managers.csr:select_mission(false)
			-- in the CSR_ClearMissionOnLeaveLobby PostHook on the vanilla
			-- _dialog_leave_lobby_yes (contract_callbacks.lua).
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

	-- Restore the pinned feature panel (if any) AFTER everything is built --
	-- the helper short-circuits when self._sidebar is absent (end-screen surface),
	-- so this is safe on every CSRMissionsMenuComponent build site.
	self:_csr_reopen_pinned_feature_panel()

	-- Subscribe to CSRGameManager.on_item_added so the unselected-items reminder
	-- and the items feature panel repaint themselves whenever ANY grant site
	-- (selection-window finalize, future rank-up auto-grant, scrapper payoff)
	-- calls add_item. The unsubscribe handles live in self._csr_unsubs and are
	-- drained in close() so destroyed panels never get touched by a stale
	-- callback. alive(self._panel) guards the body for the race where a
	-- callback fires after close() but before the unsub closure runs (close
	-- order is deterministic today but cheap to harden).
	--
	-- _setup() may be called more than once on the same instance (the
	-- alive(self._panel) guard at the top of _setup handles a reset path); in
	-- that case any prior subscription is no longer valid (its closure points
	-- at the now-replaced panels). Drain first, then re-register.
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
		local function refresh_lobby_surfaces()
			if not alive(self._panel) then
				return
			end
			if self._refresh_unselected_items then
				self:_refresh_unselected_items()
			end
			if self._populate_items_panel then
				self:_populate_items_panel()
			end
		end
		table.insert(self._csr_unsubs, mgr:on_item_added(refresh_lobby_surfaces))
	end
end

function CSRMissionsMenuComponent:_create_title()
	-- Top-left branded header in the vanilla lobby "crew page" style
	-- (contractboxgui.lua:8-84, the PLANNING-PHASE-looking title): a crisp
	-- pd2_large_font foreground on the safe workspace plus a huge faded blue
	-- pd2_massive_font ghost on the fullscreen workspace, coordinate-mapped with
	-- safe_to_full_16_9 so the ghost lines up without being clipped by the safe
	-- area. Copied 1:1 from vanilla; only the text (csr_header_title, registered
	-- in contract_wiring.lua) and component panels differ. We route the lobby
	-- box to CrimeSpreeContractBoxGui (which draws no crewpage header), so this
	-- corner is free and there is no double-up with vanilla. MenuBackdropGUI.
	-- animate_bg_text is intentionally NOT called: it is a verified no-op
	-- (pd2_menubackdrop_animate_bg_text_noop) -- the ghost is static in vanilla.
	-- Children of self._panel / self._fullscreen_panel, both removed in close().
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

	-- Pass self as owner so the sidebar's Items row can toggle the
	-- component-owned Items panel (geometry spans sidebar -> mission cards).
	self._sidebar = CSRSidebar:new(self._panel, top, bottom, self)
end

-- Feature panels: rectangular panels that open to the RIGHT of the sidebar
-- when its Items / Modifiers / Rewards row is clicked. All three share the
-- EXACT same region -- height == the sidebar's height, spanning the empty gap
-- with a symmetric `padding` margin on both sides (from the sidebar and from
-- the leftmost mission card -- user spec 2026-05-19). Built once here (hidden),
-- toggled by visibility; lifetime is tied to self._panel, which the existing
-- close() removes, so no extra teardown is needed (same ownership model as the
-- sidebar). Visual recipe is the sidebar's 1:1 (0.4 black rect + test_blur_df
-- backdrop + BoxGui frame); content is a later pass, exactly how the sidebar
-- itself started as "just the panel".
--
-- Requires self._sidebar (built in _create_sidebar above) and
-- self._buttons_panel (built in _setup before this is called) to measure the
-- left/right bounds; both are children of self._panel, so all coordinates are
-- in the same space.
function CSRMissionsMenuComponent:_create_feature_panels()
	if not self._sidebar or not self._csr_fp_right_anchor or not self._csr_fp_parent then
		return
	end

	local sb = self._sidebar:panel()
	-- Symmetric `padding` gap on BOTH sides: from the sidebar on the left and
	-- from the leftmost mission card on the right (user refinement 2026-05-19 --
	-- flush-to-card was too wide).
	local left = sb:right() + padding
	local right = self._csr_fp_right_anchor:left() - padding
	local width = math.max(right - left, 0)
	local px, py, ph = left, sb:top(), sb:h()
	local parent_for_panels = self._csr_fp_parent

	-- One panel per content category, all built identically and pinned to the
	-- same rect (they are mutually exclusive -- see toggle_feature_panel).
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

		-- Frame discarded like the sidebar's own border (anonymous, never
		-- referenced again); the panel-tree teardown removes it.
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
	}

	-- Initial population so the panels have content the first time the sidebar
	-- opens them. Re-populated on every toggle-on for MP-sync arrival (item
	-- counts can change while the lobby is up once the sync slice lands).
	self:_populate_items_panel()
	self:_populate_modifiers_panel()
	self:_populate_rewards_panel()
	self:_populate_heister_panel()
end

-- Mutually exclusive: the three panels occupy the SAME rect, so showing one
-- hides the others; clicking the already-open row closes it (toggle off).
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

	-- Persist the player's pinned tab across surface transitions (lobby <->
	-- briefing) and across sub-screen blanking (Inventory etc., which call
	-- hide_feature_panels via the briefing hide hook). MUST be Global.*,
	-- NOT _G.*: lobby (menu_main) and briefing (ingame_waiting_for_players)
	-- live in different Lua states with a full reinit between them, so a
	-- _G flag set in the lobby would be nil by the time briefing reads it
	-- (see pd2_g_vs_global_cross_lua_state). Global survives the reinit.
	-- Closing the panel (toggle-off) drops the slot so the next surface
	-- stays closed -- a deliberate close-on-this-surface = closed everywhere.
	-- hide_feature_panels does NOT touch the slot (sub-screen blanking /
	-- sidebar collapse should not look like a user-driven close).
	Global._csr_pinned_feature = show and key or nil
	log(
		"[CSR][pinned-tab] toggle: key="
			.. tostring(key)
			.. " show="
			.. tostring(show)
			.. " -> slot="
			.. tostring(Global._csr_pinned_feature)
	)

	-- Mirror the open/closed state onto the sidebar so the active row's persistent
	-- highlight tracks the visible panel (nil on toggle-off clears it).
	if self._sidebar and self._sidebar.set_active_feature then
		self._sidebar:set_active_feature(show and key or nil)
	end

	if show and key == "items" then
		-- Rebuild on toggle-on so newly granted items or peer joins are reflected
		-- without needing to leave/re-enter the lobby. Cheap (≤ 28 items × N peers).
		self:_populate_items_panel()
	elseif show and key == "modifiers" then
		-- Rebuild on toggle-on so a rank gained since the last build is reflected
		-- without leaving the lobby. Cheap (≤ pool size icons).
		self:_populate_modifiers_panel()
	elseif show and key == "rewards" then
		-- Rebuild on toggle-on so the projected payout tracks the live rank /
		-- difficulty / skill loadout without leaving the lobby. Cheap (4 rows).
		self:_populate_rewards_panel()
	elseif show and key == "heister" then
		-- Rebuild on toggle-on so a loadout / skill change since the last build is
		-- reflected without leaving the lobby. Cheap (a handful of stat rows).
		self:_populate_heister_panel()
	end
end

-- Re-apply the pinned feature panel (Global._csr_pinned_feature) on this
-- surface. Called after build (_setup for lobby / _csr_build_sidebar for
-- briefing) and on briefing show() so closing+reopening the briefing -- or
-- transitioning lobby <-> briefing -- restores whatever tab the player had
-- open. No-op when no slot is pinned, when the sidebar wasn't built (e.g.
-- end-screen surface, where _is_lobby=false skips sidebar but
-- _create_feature_panels still runs and we DO NOT want stray panels appearing
-- without a way to dismiss), or when the target panel is missing. Bypasses
-- toggle_feature_panel to avoid flipping the slot: a programmatic re-open is
-- not a user-toggle.
--
-- Borrowed by MissionBriefingGui via METHODS_TO_BORROW in briefing_sidebar.lua
-- so both surfaces share the same logic.
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
	-- self._sidebar verified non-nil above; light up the restored row so a freshly
	-- built / re-shown surface matches the pinned tab state.
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

-- Hide every feature panel. Also driven by the sidebar's Hide Sidebar collapse
-- (the panel is component-owned, not sidebar chrome, so CSRSidebar:set_collapsed
-- asks the owner to hide it -- user spec 2026-05-19).
function CSRMissionsMenuComponent:hide_feature_panels()
	if not self._feature_panels then
		return
	end

	for _, p in pairs(self._feature_panels) do
		if alive(p) then
			p:set_visible(false)
		end
	end

	-- A hidden panel cannot be hovered; drop any active tooltip so it does not
	-- linger on top of the sidebar / mission cards. The items + modifiers panels
	-- share one tooltip slot (mutually exclusive), so one clear covers both.
	self:_clear_items_tooltip()
	self._items_hover_target = nil
	self._modifiers_hover_target = nil

	-- Single choke point for "all panels closed": clear the active-row highlight.
	-- Covers sidebar collapse and sub-screen blanking (where the pinned slot
	-- persists but no panel is visible); toggle / reopen re-set it right after
	-- when they bring a panel back up. Guarded for the end-screen surface, which
	-- builds feature panels without a sidebar.
	if self._sidebar and self._sidebar.set_active_feature then
		self._sidebar:set_active_feature(nil)
	end
end

-- Resolve a per-peer accent color (4-arg Color form, per Critical Rule #6).
-- tweak_data.peer_vector_colors is the same source vanilla teammate contours and
-- chat use, so the panel color-codes match what the player already associates
-- with each peer everywhere else in the UI.
function CSRMissionsMenuComponent:_items_panel_peer_color(peer_id)
	local v = tweak_data and tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[peer_id]
	if v then
		return Color(1, v.x, v.y, v.z)
	end
	return Color.white
end

-- Deterministic peer order: local peer first (always present, never duplicated),
-- then remote peers ascending by id. Used as the per-peer section order in the
-- items panel so adding/removing a teammate does not jumble existing sections.
function CSRMissionsMenuComponent:_collect_peers_for_items_panel(local_pid)
	local out = {}
	local seen = {}

	local nm = managers and managers.network
	local session = nm and nm.session and nm:session()

	local local_peer = session and session.local_peer and session:local_peer()
	if local_peer then
		local lid = local_peer:id()
		out[1] = {
			id = lid,
			name = (local_peer.name and local_peer:name()) or "Player",
			color = self:_items_panel_peer_color(lid),
		}
		seen[lid] = true
	else
		out[1] = {
			id = local_pid,
			name = "Player",
			color = self:_items_panel_peer_color(local_pid),
		}
		seen[local_pid] = true
	end

	if session and session.peers then
		local peers = session:peers() or {}
		local remote = {}
		for pid, peer in pairs(peers) do
			if not seen[pid] then
				remote[#remote + 1] = {
					id = pid,
					name = (peer.name and peer:name()) or ("Peer " .. tostring(pid)),
					color = self:_items_panel_peer_color(pid),
				}
			end
		end
		table.sort(remote, function(a, b)
			return a.id < b.id
		end)
		for _, p in ipairs(remote) do
			out[#out + 1] = p
		end
	end

	return out
end

-- Build / rebuild the items feature-panel content from the live manager state.
-- Idempotent: prior content panel is torn down first, hit-target list reset.
-- MP-shaped from day one (per-peer cycle); other peers render empty until the
-- count-model sync slice lands (design O4) -- the UI then just starts showing
-- their items with no code change.
function CSRMissionsMenuComponent:_populate_items_panel()
	if not self._feature_panels or not alive(self._feature_panels.items) then
		return
	end
	local panel = self._feature_panels.items

	if self._items_content and alive(self._items_content) then
		panel:remove(self._items_content)
	end
	self._items_content = nil
	self._items_hit_targets = {}
	self:_clear_items_tooltip()
	self._items_hover_target = nil

	local content = panel:panel({
		layer = 5,
	})
	self._items_content = content

	local mgr = managers and managers.csr
	if not mgr or not mgr.registered_items then
		return
	end

	local by_type = {}
	for _, def in ipairs(mgr:registered_items()) do
		by_type[def.type] = def
	end

	local local_pid = mgr:local_peer_id()
	local peers_list = self:_collect_peers_for_items_panel(local_pid)

	-- No section title: the sidebar row "Items" already labels the panel; an in-
	-- panel "ITEMS" header was visual duplication. Per-peer color-strip headers
	-- carry the structure on their own.
	local section_w = panel:w() - items_panel_padding * 2
	-- Each player's inventory occupies a FIXED quarter of the panel height, so the
	-- layout is stable for up to 4 players and a peer's grid never grows past its
	-- slot -- it shrinks to fit (like the Modifiers/Rewards panels). In SP the single
	-- peer fills the top quarter; the lower three are reserved for teammates.
	local section_h = math.floor(panel:h() / 4)

	for index, peer_info in ipairs(peers_list) do
		local pid = peer_info.id
		local pcolor = peer_info.color
		local section_top = (index - 1) * section_h

		local header = content:panel({
			x = items_panel_padding,
			y = section_top + items_panel_padding,
			w = section_w,
			h = items_panel_peer_header_h,
		})

		header:rect({
			name = "peer_color_strip",
			color = pcolor,
			w = 4,
			h = header:h(),
		})
		header:text({
			name = "peer_name",
			-- Local peer is identifiable by their color strip (matches chat /
			-- teammate contour color); no "(you)" suffix needed.
			text = peer_info.name,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = pcolor,
			x = 12,
			y = 0,
			w = header:w() - 12,
			h = header:h(),
			vertical = "center",
		})

		local counts = mgr:player_items(pid) or {}
		local items_list = {}
		for item_type, count in pairs(counts) do
			local def = by_type[item_type]
			if def and count > 0 then
				items_list[#items_list + 1] = { def = def, count = count }
			end
		end

		if #items_list > 0 then
			table.sort(items_list, function(a, b)
				if (a.def.rarity or "") ~= (b.def.rarity or "") then
					return (a.def.rarity or "") < (b.def.rarity or "")
				end
				return (a.def.type or "") < (b.def.type or "")
			end)

			-- Grid sits below the header and fills the REST of this peer's quarter.
			-- 10px breathing room under the (vertical-centered, ~24px-glyph) 22px
			-- header before the icons. csr_adaptive_grid is height-aware: it shrinks
			-- the shared square cell (from items_panel_icon_size down to the min)
			-- until every row fits grid_h, so the inventory stays inside its quarter.
			-- Left-aligned, fixed gap; the rarity frame, glyph and badge all scale
			-- with the cell size.
			local grid_y = section_top + items_panel_padding + items_panel_peer_header_h + 10
			local grid_h = section_top + section_h - grid_y - items_panel_padding
			local cell_size, per_row = csr_adaptive_grid(
				#items_list,
				section_w,
				grid_h,
				items_panel_icon_size,
				items_panel_min_icon_size,
				items_panel_icon_gap
			)
			local step = cell_size + items_panel_icon_gap
			-- Frame keeps its 72/64 over-cell ratio so it still overflows the cell
			-- symmetrically at any size.
			local frame_size = math.floor(cell_size * items_panel_frame_size / items_panel_icon_size)
			local frame_overflow = (frame_size - cell_size) / 2
			local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")

			for i, entry in ipairs(items_list) do
				local col = (i - 1) % per_row
				local row = math.floor((i - 1) / per_row)
				local ix = items_panel_padding + col * step
				local iy = grid_y + row * step

				-- Frame is a SIBLING of the cell on `content`, not a child, so its
				-- 72x72 footprint can overflow the 64x64 cell by 4px each side --
				-- giving the frame a bigger visible read than the icon while
				-- keeping the cell as the precise hit-test footprint. Layer 5 here
				-- + cell layer 10 below puts the icon above the frame even though
				-- the frame extends past the cell bounds (no clipping).
				local frame_bmp = content:bitmap({
					name = "rarity_frame",
					texture = frame_tex,
					texture_rect = frame_rect,
					x = ix - frame_overflow,
					y = iy - frame_overflow,
					w = frame_size,
					h = frame_size,
					layer = 5,
				})
				frame_bmp:set_color(items_panel_rarity_colors[entry.def.rarity] or Color.white)

				local cell = content:panel({
					x = ix,
					y = iy,
					w = cell_size,
					h = cell_size,
					layer = 10,
				})

				-- Resolve icon: a "/" means a full DB-mounted texture path (addon
				-- shipping its own .dds via DB:create_entry); otherwise a short
				-- hud_icons id (CSR's built-in items). Direct-path branch
				-- assumes 128x128 -- promote `icon` to a table if an addon
				-- needs a different rect.
				local icon_tex, icon_rect
				local raw_icon = entry.def.icon or "dog_tags"
				if type(raw_icon) == "string" and raw_icon:find("/", 1, true) then
					icon_tex, icon_rect = raw_icon, { 0, 0, 128, 128 }
				else
					icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(raw_icon)
				end
				-- Glyph fills 56.25% of the cell (the legacy 36px-in-64px ratio),
				-- times the optional per-item icon_scale, centred in the cell.
				local glyph = math.floor(cell_size * (1 - 28 / items_panel_icon_size) * (entry.def.icon_scale or 1))
				local glyph_inset = math.floor((cell_size - glyph) / 2)
				cell:bitmap({
					name = "item_icon",
					texture = icon_tex,
					texture_rect = icon_rect,
					x = glyph_inset,
					y = glyph_inset,
					w = glyph,
					h = glyph,
					layer = 10,
				})

				-- Stack badge: white "xN" with a thin black outline (readable over any
				-- icon; no background box, no font scaling -- user choice). Anchored by
				-- its BOTTOM-LEFT to the glyph's TOP-RIGHT corner (align left + vertical
				-- bottom), so the number sits at the glyph corner and extends UP + RIGHT,
				-- always clear of the centred glyph. As the cell shrinks the glyph (and
				-- its corner) shrink too, so the fixed-size number automatically rides
				-- further up-right OUT of the icon instead of overlapping it. Shown
				-- unconditionally (incl. x1) so the inventory reads as a stack-count
				-- view. SIBLINGS of the cell on `content` (cell panels clip children in
				-- Diesel); w/h is just a generous container -- only the glyphs render,
				-- left/bottom-aligned at (badge_x, badge_y + h). Layers 19/20 put the
				-- outline (19) under the white glyph (20), both above frame (5)/cell (10).
				local badge = {
					name = "stack_badge",
					text = "x" .. tostring(entry.count),
					font = tweak_data.menu.pd2_small_font,
					font_size = tweak_data.menu.pd2_small_font_size,
					align = "left",
					vertical = "bottom",
					w = items_panel_icon_size,
					h = items_panel_icon_size,
				}
				-- Box left = glyph right edge; box bottom (badge_y + h) sits a little below
				-- the cell top so the number rides the top-right corner. The vertical
				-- offset is min(glyph_inset, cap) + drop: the glyph_inset term tracks the
				-- corner on small icons but is capped so big icons (with a wide centring
				-- margin) don't drag the number low. drop is a fraction of the NUMBER's own
				-- (fixed) height, so the corner overlap reads the same at every size.
				local badge_x = ix + glyph_inset + glyph
				local badge_drop = math.floor(tweak_data.menu.pd2_small_font_size * 0.2)
				local badge_inset = math.min(glyph_inset, items_panel_badge_top_inset)
				local badge_y = (iy + badge_inset + badge_drop) - items_panel_icon_size
				-- Black outline copies first (under), then the white glyph on top. The
				-- params table is reused -- panel:text() reads it at call time and does
				-- not retain it, so mutating between calls is safe.
				badge.color = Color.black
				badge.layer = 19
				for _, off in ipairs(items_panel_badge_outline) do
					badge.x, badge.y = badge_x + off[1], badge_y + off[2]
					content:text(badge)
				end
				badge.color = Color.white
				badge.layer = 20
				badge.x, badge.y = badge_x, badge_y
				content:text(badge)

				self._items_hit_targets[#self._items_hit_targets + 1] = {
					panel = cell,
					def = entry.def,
					count = entry.count,
				}
			end
		end
	end
end

-- Edge-triggered hover for the items grid. mouse_moved is event-driven (not a
-- per-frame path), so the linear walk over hit targets is fine; the targets
-- list is small (28 items × N peers in the worst case).
function CSRMissionsMenuComponent:_items_panel_mouse_moved(x, y)
	local panel = self._feature_panels and self._feature_panels.items
	if not panel or not alive(panel) or not panel:visible() then
		if self._items_hover_target ~= nil then
			self._items_hover_target = nil
			self:_clear_items_tooltip()
		end
		return false
	end
	if not self._items_hit_targets or #self._items_hit_targets == 0 then
		return false
	end

	local hovered = nil
	for _, target in ipairs(self._items_hit_targets) do
		if alive(target.panel) and target.panel:inside(x, y) then
			hovered = target
			break
		end
	end

	if hovered ~= self._items_hover_target then
		self._items_hover_target = hovered
		self:_clear_items_tooltip()
		if hovered then
			-- No "highlight" hover SFX: items are passive inventory entries,
			-- not selectable controls, and per-cell hover audio in a dense grid
			-- would chatter as the cursor crosses cells (user spec 2026-05-20).
			self:_show_items_tooltip(hovered)
		end
	end

	return hovered ~= nil
end

function CSRMissionsMenuComponent:_clear_items_tooltip()
	-- Tooltip parent must match where _show_items_tooltip created it (abstract
	-- _csr_fp_parent, set in _setup): on the briefing screen the tooltip lives
	-- on the saferect workspace panel, not on self._panel. Lobby's
	-- _csr_fp_parent == self._panel so this is a no-behavior-change rewrite
	-- there.
	local parent = self._csr_fp_parent or self._panel
	if self._items_tooltip and alive(self._items_tooltip) and parent and alive(parent) then
		parent:remove(self._items_tooltip)
	end
	self._items_tooltip = nil
end

-- Tooltip anchored to the hovered icon (not the cursor). Floats above the items
-- panel on self._panel layer 200 so it overlaps the sidebar / cards cleanly.
-- Clamped to self._panel bounds so an icon near the panel edge does not push
-- the tooltip off-screen.
function CSRMissionsMenuComponent:_show_items_tooltip(target)
	if not target or not alive(target.panel) then
		return
	end
	local def = target.def
	local pad = 6
	local tip_w = 200
	local name_h = tweak_data.menu.pd2_small_font_size + 2

	-- Tooltip is parented and clamped to the abstract feature-panels parent
	-- (set in _setup as _csr_fp_parent). Lobby keeps the historical behavior
	-- (_csr_fp_parent == self._panel); the briefing screen sets it to the
	-- saferect ws_panel so the tooltip can clamp against the full saferect.
	local fp_parent = self._csr_fp_parent or self._panel

	-- Build at placeholder height so we can host the text nodes for measurement.
	-- BoxGuiObject and the bg rect are added AFTER the final resize -- BoxGui
	-- bakes its corner/edge sprite positions at construction time, so creating
	-- it pre-resize leaves the corners stranded at the placeholder dimensions
	-- (the visible artefact the user reported as "weird corners").
	local tip = fp_parent:panel({
		layer = 200,
		w = tip_w,
		h = 200,
	})
	self._items_tooltip = tip

	local name_color = items_panel_rarity_colors[def.rarity] or Color.white
	-- Resolve display text. Items pass loc KEYS in def.name/def.desc (resolved
	-- per language here). Modifiers pass PRE-RESOLVED literals in def.name_text/
	-- def.desc_text (the combined "Title\nBody" loc string is split before it
	-- reaches us). Prefer the pre-resolved field when present: feeding an already
	-- localized literal back through :text() does NOT echo it -- the engine
	-- returns an "ERROR ..." placeholder for an unknown key, which is exactly the
	-- doubled-"ERROR" the modifier tooltip showed.
	local resolved_name = def.name_text
		or (def.name and managers.localization and managers.localization:text(def.name))
		or ""
	local resolved_desc = def.desc_text
		or (def.desc and managers.localization and managers.localization:text(def.desc))
		or ""
	local name_text = tip:text({
		name = "tooltip_name",
		text = resolved_name,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = name_color,
		x = pad,
		y = pad,
		w = tip_w - pad * 2,
		h = name_h,
		layer = 5,
	})

	-- Desc wraps within tip_w-2*pad; measured h tracks however many lines the
	-- text actually needs, so a one-word desc isn't padded with blank space.
	local desc_text = tip:text({
		name = "tooltip_desc",
		text = resolved_desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		x = pad,
		y = pad + name_h + 2,
		w = tip_w - pad * 2,
		h = 160,
		wrap = true,
		wrap_word = true,
		layer = 5,
	})
	local _, _, _, dh = desc_text:text_rect()
	desc_text:set_h(dh)

	-- Final size, THEN chrome: BoxGui captures the panel's w/h at construction.
	local tip_h = pad + name_h + 2 + dh + pad
	tip:set_h(tip_h)

	tip:rect({
		name = "tooltip_bg",
		color = Color.black,
		alpha = 0.9,
		layer = 0,
		w = tip_w,
		h = tip_h,
	})
	BoxGuiObject:new(tip, {
		sides = { 1, 1, 1, 1 },
	})

	local cell_x, cell_y = target.panel:world_position()
	local panel_x, panel_y = fp_parent:world_position()
	local local_x = cell_x - panel_x
	local local_y = cell_y - panel_y

	local tx = local_x + items_panel_icon_size + 6
	if tx + tip_w > fp_parent:w() then
		tx = local_x - tip_w - 6
	end
	if tx < 0 then
		tx = 0
	end

	local ty = local_y
	if ty + tip_h > fp_parent:h() then
		ty = fp_parent:h() - tip_h - 4
	end
	if ty < 0 then
		ty = 0
	end

	tip:set_position(tx, ty)
end

-- Build / rebuild the Modifiers feature-panel content: a Loud / Stealth sub-tab row
-- at the top and, below it, a vertical scroll list of the modifiers active for the
-- chosen sub-tab. Each row is an icon (left) + name (top) + wrapped description
-- (below) -- the description is inline now, so there is no hover tooltip anymore.
-- Idempotent: prior content (and the ScrollablePanel inside it) is removed first.
-- Borrowed by MissionBriefingGui (briefing_sidebar.lua METHODS_TO_BORROW) so both
-- surfaces share it; mouse routing lives in mouse_wheel_up/down + mouse_released +
-- the modifiers branches of mouse_moved/mouse_pressed (lobby) and the briefing's own
-- input wraps (wheel only -- the briefing never receives mouse_released).
function CSRMissionsMenuComponent:_populate_modifiers_panel()
	if not self._feature_panels or not alive(self._feature_panels.modifiers) then
		return
	end
	local panel = self._feature_panels.modifiers

	if self._modifiers_content and alive(self._modifiers_content) then
		panel:remove(self._modifiers_content)
	end
	self._modifiers_content = nil
	self._modifiers_subtab_buttons = nil
	-- The scroll lived inside the content panel just removed; drop the stale ref so
	-- the mouse handlers can't poke a dead panel between repopulates.
	self._modifiers_scroll = nil
	self._modifiers_hit_targets = {}
	self:_clear_items_tooltip()
	self._modifiers_hover_target = nil

	-- Default to Loud; persisted on the instance across repopulates.
	self._modifiers_subtab = self._modifiers_subtab == "stealth" and "stealth" or "loud"
	local is_stealth = self._modifiers_subtab == "stealth"

	local content = panel:panel({
		layer = 5,
	})
	self._modifiers_content = content

	-- Sub-tab row: the two buttons split the content width with a small gap between
	-- them -- together they still span the full panel width.
	local pad = items_panel_padding
	local section_w = panel:w() - pad * 2
	local btn_w = math.floor((section_w - modifiers_subtab_gap) / 2)
	local b_loud = csr_build_modifier_subtab(content, "Loud", pad, pad, btn_w, not is_stealth)
	-- Stealth takes the remainder so odd-pixel widths still tile flush to the gap.
	local b_stealth = csr_build_modifier_subtab(
		content,
		"Stealth",
		pad + btn_w + modifiers_subtab_gap,
		pad,
		section_w - btn_w - modifiers_subtab_gap,
		is_stealth
	)
	self._modifiers_subtab_buttons = {
		loud = { panel = b_loud },
		stealth = { panel = b_stealth },
	}

	-- Loud-only ambient header: the per-rank enemy HP/damage scaling (continuous in
	-- rank, separate from the unlockable modifiers listed below). Reads the percent
	-- from managers.csr:enemy_scaling so the shown number can't drift from what
	-- apply_modifiers applies. Fixed on `content` (NOT in the scroll canvas) so it
	-- stays pinned at the very top; the scroll list is pushed down by header_h.
	-- Hidden at 0% (rank 0). HP% == DMG% today, so one number covers both.
	local header_h = 0
	if not is_stealth then
		local smgr = managers and managers.csr
		local hp_pct = 0
		if smgr and smgr.enemy_scaling then
			hp_pct = (smgr:enemy_scaling()) or 0
		end
		if hp_pct > 0 then
			-- White sentence, yellow number + "%" (the mod's accent, same highlight
			-- the status bar uses). set_range_color recolors the trailing value
			-- substring -- the vanilla-proven pattern from _create_status_bar.
			local prefix = "Enemy's base health and damage increased by "
			local full = prefix .. math.floor(hp_pct) .. "%"
			local header = content:text({
				name = "enemy_scaling_header",
				text = full,
				font = tweak_data.menu.pd2_small_font,
				font_size = tweak_data.menu.pd2_small_font_size,
				color = tweak_data.screen_colors.text,
				x = pad,
				y = pad + modifiers_subtab_h + modifiers_grid_top_gap,
				w = section_w,
				h = tweak_data.menu.pd2_small_font_size,
				wrap = true,
				word_wrap = true,
				layer = 10,
			})
			header:set_range_color(utf8.len(prefix), utf8.len(full), Color(1, 1, 1, 0))
			local _, _, _, lh = header:text_rect()
			header:set_h(lh)
			header_h = lh + modifiers_grid_top_gap
		end
	end

	-- Scroll list below the sub-tabs (engine ScrollablePanel: draggable bar + wheel,
	-- canvas clipped to the viewport). Content goes on :canvas(); update_canvas_size
	-- recomputes the scroll height from the rows after they are laid out. list_top
	-- includes header_h so the loud ambient header (when shown) sits above the list.
	local list_top = pad + modifiers_subtab_h + modifiers_grid_top_gap + header_h
	local list_h = math.max(0, panel:h() - list_top - pad)
	local scroll = ScrollablePanel:new(content, "csr_modifiers_scroll", {
		x = pad,
		y = list_top,
		w = section_w,
		h = list_h,
		padding = 0,
		layer = 10,
	})
	self._modifiers_scroll = scroll
	local canvas = scroll:canvas()

	local mgr = managers and managers.csr
	local list = (mgr and mgr.active_modifiers and mgr:active_modifiers(self._modifiers_subtab)) or {}
	if #list == 0 then
		-- Empty (rank 0, or this category's pool already exhausted): sub-tabs stand
		-- alone, empty scroll. No filler text -- matches the items panel convention.
		scroll:update_canvas_size()
		return
	end

	-- Newest-unlocked modifier first (user spec 2026-05-24): active_modifiers returns
	-- the unlock sequence oldest-first (entry i unlocked at rank i), so reversing it
	-- floats the modifier gained at the current rank to the TOP. Reversed in the VIEW
	-- only -- active_modifiers' "rank R is a prefix-superset of R+1" contract (relied
	-- on by apply_modifiers) stays intact. The list is a fresh per-call table, so the
	-- in-place reverse mutates nothing shared.
	for i = 1, math.floor(#list / 2) do
		list[i], list[#list - i + 1] = list[#list - i + 1], list[i]
	end

	-- Text column reserves a right margin for the scroll bar so a wrapped line never
	-- runs under it.
	local text_x = modifiers_row_icon_size + modifiers_row_text_gap
	local text_w = math.max(40, canvas:w() - text_x - modifiers_row_scrollbar_margin)
	local row_y = 0

	for _, entry in ipairs(list) do
		-- Combined "Title\nBody" loc string -> name (top) + description (wrapped).
		local full = (entry.loc and managers.localization and managers.localization:text(entry.loc)) or ""
		local title, body = full, ""
		local nl = full:find("\n", 1, true)
		if nl then
			title = full:sub(1, nl - 1)
			body = full:sub(nl + 1)
		end

		-- One panel per row, sized to the taller of the icon and the text block
		-- after the wrapped description is measured.
		local row = canvas:panel({
			x = 0,
			y = row_y,
			w = canvas:w(),
			h = modifiers_row_icon_size,
		})

		-- Icon (left). get_icon_data returns (texture, rect) and is nil-safe.
		local icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(entry.icon or "csr_dog_tags")
		row:bitmap({
			name = "mod_icon",
			texture = icon_tex,
			texture_rect = icon_rect,
			x = 0,
			y = 0,
			w = modifiers_row_icon_size,
			h = modifiers_row_icon_size,
			layer = 1,
		})

		-- Name (top of the text column), measured + resized to its own line height.
		local name_text = row:text({
			name = "mod_name",
			text = title,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = tweak_data.screen_colors.text,
			x = text_x,
			y = 0,
			w = text_w,
			h = tweak_data.menu.pd2_medium_font_size,
			layer = 1,
		})
		local _, _, _, name_h = name_text:text_rect()
		name_text:set_h(name_h)

		-- Description (below the name, wrapped); measured h tracks the line count.
		local desc_text = row:text({
			name = "mod_desc",
			text = body,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color.white:with_alpha(0.7),
			x = text_x,
			y = name_h,
			w = text_w,
			h = 200,
			wrap = true,
			wrap_word = true,
			layer = 1,
		})
		local _, _, _, desc_h = desc_text:text_rect()
		desc_text:set_h(desc_h)

		local row_h = math.max(modifiers_row_icon_size, name_h + desc_h)
		row:set_h(row_h)

		row_y = row_y + row_h + modifiers_row_gap
	end

	scroll:update_canvas_size()
end

-- Build / rebuild the Rewards feature-panel: the four run-completion rewards
-- (cash, XP, Continental Coins, Loot Cards) as compact rows -- a vanilla loot-card
-- thumbnail on the left + title/amount on the right. The amounts are the PROJECTED
-- run-end payout at the current rank + difficulty: CSR pays out FROM RANK at the
-- end of a spree (not per heist), so the panel answers "what do I get if I end the
-- spree now?". Formulas + per-rank tables are locked in
-- project_csr_reward_system_design.
--
-- Read-only and local-state-only (rank is the run's; the skill/infamy XP mults are
-- THIS player's), so MP-safe with no packet. A client whose rank hasn't synced yet
-- just shows its local value -- same deferred-sync caveat as the items panel.
function CSRMissionsMenuComponent:_populate_rewards_panel()
	if not self._feature_panels or not alive(self._feature_panels.rewards) then
		return
	end
	local panel = self._feature_panels.rewards

	if self._rewards_content and alive(self._rewards_content) then
		panel:remove(self._rewards_content)
	end
	self._rewards_content = nil

	local content = panel:panel({
		layer = 5,
	})
	self._rewards_content = content

	-- Projected run-end payout from the single source of truth (managers.csr:
	-- projected_rewards -- the SAME numeric table End Spree awards). cash_string
	-- prefixes the locale cash sign ("$"); experience_string is the bare grouped
	-- number (we add the "+"). pcall-isolated -- a display must never crash the lobby.
	local mgr = managers and managers.csr
	local r = (mgr and mgr.projected_rewards and mgr:projected_rewards()) or {}
	local cash_str, xp_str = "$0", "0"
	pcall(function()
		cash_str = managers.experience:cash_string(r.cash or 0)
	end)
	pcall(function()
		xp_str = managers.experience:experience_string(r.experience or 0)
	end)

	local rows = {
		{ icon = "upcard_cash", title = "CASH", value = cash_str },
		{ icon = "upcard_xp", title = "EXPERIENCE", value = "+" .. xp_str },
		{ icon = "upcard_coins", title = "CONTINENTAL COINS", value = tostring(r.continental_coins or 0) },
		{ icon = "upcard_random", title = "LOOT CARDS", value = tostring(r.loot_drop or 0) },
	}

	-- Row height fits 4 rows + 3 gaps into the panel, capped so tall panels keep
	-- sane card sizes; the resulting block is centred vertically.
	local pad = items_panel_padding
	local avail_h = panel:h() - pad * 2
	local row_h = math.min(rewards_panel_max_row_h, math.floor((avail_h - rewards_panel_row_gap * 3) / 4))
	row_h = math.max(row_h, tweak_data.menu.pd2_medium_font_size + tweak_data.menu.pd2_small_font_size)
	local card_w = math.floor(row_h * rewards_panel_card_aspect)
	local block_h = row_h * 4 + rewards_panel_row_gap * 3
	local start_y = pad + math.max(0, math.floor((avail_h - block_h) / 2))
	local text_x = pad + card_w + rewards_panel_text_gap
	local text_w = math.max(0, panel:w() - pad - text_x)

	for i, r in ipairs(rows) do
		local ry = start_y + (i - 1) * (row_h + rewards_panel_row_gap)

		-- Loot-card thumbnail (vanilla atlas; get_icon_data returns texture + rect,
		-- nil-safe). Fills the row height at the portrait aspect.
		local tex, rect = tweak_data.hud_icons:get_icon_data(r.icon)
		content:bitmap({
			name = "reward_card",
			texture = tex,
			texture_rect = rect,
			x = pad,
			y = ry,
			w = card_w,
			h = row_h,
			layer = 10,
		})

		-- Title (dim) above the amount (white), the pair vertically centred against
		-- the card so a short row still reads as a unit.
		local title_h = tweak_data.menu.pd2_small_font_size
		local amount_h = tweak_data.menu.pd2_medium_font_size
		local tb_y = ry + math.floor((row_h - (title_h + amount_h)) / 2)

		content:text({
			name = "reward_title",
			text = r.title,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color.white:with_alpha(0.6),
			x = text_x,
			y = tb_y,
			w = text_w,
			h = title_h,
			vertical = "center",
			layer = 10,
		})
		content:text({
			name = "reward_amount",
			text = r.value,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = tweak_data.screen_colors.text,
			x = text_x,
			y = tb_y + title_h,
			w = text_w,
			h = amount_h,
			vertical = "center",
			layer = 10,
		})
	end
end

-- Player combat characteristics for the Heister feature panel.
--
-- Computed with the SAME formulas the vanilla inventory screen uses for its
-- player-stats table (PlayerInventoryGui:_get_armor_stats in pd2_source). They
-- reflect the player's CURRENT loadout (equipped armor + skills) but NOT the CSR
-- item buffs: item numbers are hidden by design, so this "standard" table shows
-- the player's normal PD2 values. Folding the CSR item contributions into these
-- totals is a later pass (the row layout below does not change for it).
--
-- pcall-isolated at two levels (loadout lookup + each stat): a stat read must
-- never crash the lobby / briefing. On any failure a row falls back to the bare
-- base constant, so the table always renders.
local function csr_round1(n)
	-- format_round's non-integer branch (pd2 playerinventorygui): one decimal,
	-- trailing zeros stripped ("230.0" -> "230", "4.5" -> "4.5").
	return (string.format("%.1f", n):gsub("%.?0+$", ""))
end

-- TOTAL (base + skill) for one stat, line-for-line from the matching branch of
-- _get_armor_stats. `name` = equipped armor id, `upgrade_level` its tier.
local function csr_heister_stat_value(stat_name, name, upgrade_level, detection_risk, mult)
	local player = managers.player
	if stat_name == "health" then
		local base = (tweak_data.player.damage.HEALTH_INIT + player:health_skill_addend()) * mult
		return base * player:health_skill_multiplier()
	elseif stat_name == "armor" then
		local base = (tweak_data.player.damage.ARMOR_INIT + player:body_armor_value("armor", upgrade_level)) * mult
		return (base + player:body_armor_skill_addend(name) * mult) * player:body_armor_skill_multiplier(name)
	elseif stat_name == "movement" then
		local base = tweak_data.player.movement_state.standard.movement.speed.STANDARD_MAX / 100 * mult
		return base * player:movement_speed_multiplier(false, false, upgrade_level, 1)
	elseif stat_name == "dodge" then
		return player:body_armor_value("dodge", upgrade_level) * 100
			+ player:skill_dodge_chance(false, false, false, name, detection_risk) * 100
	elseif stat_name == "stamina" then
		local base = tweak_data.player.movement_state.stamina.STAMINA_INIT
		return base * player:body_armor_value("stamina", upgrade_level) * player:stamina_multiplier()
	end
	return 0
end

local function csr_collect_heister_stats()
	local mult = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local pd = tweak_data.player

	-- Equipped armor id + tier + detection risk (head of _get_armor_stats). Guarded:
	-- outside an active loadout these reads can throw.
	local name, upgrade_level, detection_risk = nil, 0, 0
	pcall(function()
		name = managers.blackmarket:equipped_armor()
		local tw = name and tweak_data.blackmarket.armors[name]
		upgrade_level = (tw and tw.upgrade_level) or 0
		local dr = managers.blackmarket:get_suspicion_offset_from_custom_data(
			{ armors = name },
			pd.SUSPICION_OFFSET_LERP or 0.75
		)
		detection_risk = math.round(dr * 100)
	end)

	-- Ordered combat characteristics. `fallback` = bare base constant shown if the
	-- live read errors; `pct` rows append "%". Loc keys are vanilla (bm_menu_*).
	local defs = {
		{ key = "health", loc = "bm_menu_health", pct = false, fallback = (pd.damage.HEALTH_INIT or 0) * mult },
		{ key = "armor", loc = "bm_menu_armor", pct = false, fallback = (pd.damage.ARMOR_INIT or 0) * mult },
		{
			key = "movement",
			loc = "bm_menu_movement",
			pct = false,
			fallback = (pd.movement_state.standard.movement.speed.STANDARD_MAX or 0) / 100 * mult,
		},
		{ key = "dodge", loc = "bm_menu_dodge", pct = true, fallback = 0 },
		{
			key = "stamina",
			loc = "bm_menu_stamina",
			pct = false,
			fallback = pd.movement_state.stamina.STAMINA_INIT or 0,
		},
	}

	local out = {}
	for _, d in ipairs(defs) do
		local ok, v = pcall(csr_heister_stat_value, d.key, name, upgrade_level, detection_risk, mult)
		if not ok or type(v) ~= "number" then
			v = d.fallback
		end
		v = math.max(v, 0)
		out[#out + 1] = {
			label = managers.localization:to_upper_text(d.loc),
			value = d.pct and (math.round(v) .. "%") or csr_round1(v),
		}
	end
	return out
end

-- Build / rebuild the Heister feature-panel content: a two-column table of the
-- player's combat characteristics (name left, value right) with a zebra band on
-- alternating rows for readability. Idempotent (prior content torn down first).
-- Borrowed by MissionBriefingGui (briefing_sidebar.lua METHODS_TO_BORROW) so both
-- the lobby and the briefing share it.
function CSRMissionsMenuComponent:_populate_heister_panel()
	if not self._feature_panels or not alive(self._feature_panels.heister) then
		return
	end
	local panel = self._feature_panels.heister

	if self._heister_content and alive(self._heister_content) then
		panel:remove(self._heister_content)
	end
	self._heister_content = nil

	local content = panel:panel({
		layer = 5,
	})
	self._heister_content = content

	local stats = csr_collect_heister_stats()
	local pad = items_panel_padding
	local row_h = tweak_data.menu.pd2_medium_font_size + 8
	local row_gap = 4
	-- Yellow value highlight (4-arg Color per Rule #6), same accent the status bar
	-- uses for its dynamic rank / difficulty values.
	local highlight = Color(1, 1, 1, 0)
	local y = pad

	for i, s in ipairs(stats) do
		local row = content:panel({
			x = pad,
			y = y,
			w = panel:w() - pad * 2,
			h = row_h,
			layer = 5,
		})

		-- Zebra band on alternating rows (the same 0.4-black the vanilla inventory
		-- stats table uses).
		if i % 2 == 1 then
			row:rect({
				color = Color.black:with_alpha(0.4),
				layer = 0,
			})
		end

		row:text({
			name = "stat_name",
			text = s.label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			x = 8,
			w = row:w() - 16,
			h = row:h(),
			align = "left",
			vertical = "center",
			layer = 2,
		})
		row:text({
			name = "stat_value",
			text = s.value,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = highlight,
			x = 8,
			w = row:w() - 16,
			h = row:h(),
			align = "right",
			vertical = "center",
			layer = 2,
		})

		y = y + row_h + row_gap
	end
end

-- True when the Modifiers scroll list exists AND its panel is visible. Gates the
-- scroll mouse routing so wheel / grab events do nothing while another tab is up.
-- Borrowed by the briefing so its input wrap can gate the same way.
function CSRMissionsMenuComponent:_modifiers_scroll_visible()
	local panel = self._feature_panels and self._feature_panels.modifiers
	return self._modifiers_scroll ~= nil and panel ~= nil and alive(panel) and panel:visible()
end

-- Hover for the Modifiers panel: scroll bar (hover / drag cursor) + sub-tab link
-- cursor. The description is inline in each row now, so there is no icon tooltip.
-- Returns true when the cursor is over the scroll bar or a sub-tab so the caller can
-- flip the pointer to "link". Shared by the lobby + the briefing.
function CSRMissionsMenuComponent:_modifiers_panel_mouse_moved(x, y)
	local panel = self._feature_panels and self._feature_panels.modifiers
	if not panel or not alive(panel) or not panel:visible() then
		return false
	end

	-- Scroll bar hover / drag. Drag is only ever active on the lobby (which grabs
	-- the bar in mouse_pressed); the briefing never grabs, so this is hover-only
	-- there. ScrollablePanel:mouse_moved returns (used, pointer).
	if self._modifiers_scroll then
		local used = self._modifiers_scroll:mouse_moved(nil, x, y)
		if used then
			return true
		end
	end

	-- Sub-tab hover -> link cursor.
	if self._modifiers_subtab_buttons then
		for _, b in pairs(self._modifiers_subtab_buttons) do
			if b.panel and alive(b.panel) and b.panel:inside(x, y) then
				return true
			end
		end
	end

	return false
end

-- Click handling for the Modifiers sub-tabs. Returns true if a sub-tab was hit
-- (switching repopulates the grid). Called from the lobby's mouse_pressed and
-- the briefing input wrap. Posts the same click SFX the sidebar / cards use.
function CSRMissionsMenuComponent:_modifiers_panel_mouse_pressed(x, y)
	local panel = self._feature_panels and self._feature_panels.modifiers
	if not panel or not alive(panel) or not panel:visible() then
		return false
	end
	if not self._modifiers_subtab_buttons then
		return false
	end
	for key, b in pairs(self._modifiers_subtab_buttons) do
		if b.panel and alive(b.panel) and b.panel:inside(x, y) then
			if self._modifiers_subtab ~= key then
				self._modifiers_subtab = key
				managers.menu_component:post_event("menu_enter")
				self:_populate_modifiers_panel()
			end
			return true
		end
	end
	return false
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
	-- U+E018: the Crime Spree glyph (same codepoint localization.lua emits
	-- as the raw bytes \xEE\x80\x98); utf8.char keeps it consistent with the
	-- existing utf8.char(0xE012) usage there.
	local cs_glyph = utf8.char(0xE018)

	-- Left anchor: how many heists were completed in the current run. Reads the
	-- dedicated managers.csr:missions_completed() counter (NOT rank -- the two
	-- are distinct concepts; see game_manager.lua default_state comment).
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

	-- Notification line ABOVE the status row, right-aligned over DIFFICULTY:
	-- a yellow, clickable reminder that the player still owes roguelike item
	-- picks. The hit target is a snug panel (not the w-wide title row) so only
	-- the words react -- this file hit-tests panels everywhere (sidebar, cards),
	-- never raw text objects, so we follow that convention. Child of
	-- self._panel, so the existing close() (removes self._panel) cleans it up.
	-- Same yellow as the rank/difficulty highlight above for visual coherence
	-- (4-arg Color per Rule #6; this is a=1 r=1 g=1 b=0 == yellow).
	-- Default (left/top) align: the text is snugged to its glyphs by
	-- make_fine_text in _refresh_unselected_items and pinned to (0,0), then the
	-- hit-panel is sized to it and right-anchored over DIFFICULTY. Right edge
	-- stays put as the digit count changes (panel grows leftward).
	-- Two-state yellow: dim by default, full bright on hover (mouse_moved
	-- swaps these). Bright == the rank/difficulty highlight yellow above for
	-- coherence; dim is the same hue scaled down. 4-arg Color per Rule #6
	-- (a=1, r, g, b=0 == yellow).
	self._unselected_color_dim = Color(1, 0.85, 0.78, 0)
	self._unselected_color_bright = Color(1, 1, 1, 0)

	self._unselected_panel = self._panel:panel({
		layer = 51,
	})
	-- Near-transparent yellow backing plate, same rect idiom as self._actions_bg
	-- (color sets RGB, the alpha field sets the final translucency -- Rule #6:
	-- this is 4-arg a=1 r=1 g=1 b=0 == yellow, not a 3-arg Color). Child of
	-- self._panel (NOT the snug hit-panel): it spans the whole mission row
	-- while the hit-panel stays snug around the words, so it needs its own
	-- visibility toggle. Layer 1 so Diesel's per-layer sort draws it under the
	-- layer-51 hit-panel (and its layer-52 text). Sized in _refresh_unselected_items.
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

	-- Populate text, snug the hit-panel, and apply pending>0 visibility. The
	-- host-fail hide in refresh() can still override this (passed as `allowed`).
	self:_refresh_unselected_items(true)
end

-- How many roguelike item picks the player still owes. The entitlement is the
-- HOST's spree rank (user spec); subtract what the local player already owns.
-- Items bought with Gage tokens must NOT count toward the rank quota ("это на
-- будущее"): tokens/shop are not ported in U1 so every owned item is currently
-- a rank item -- when the token slice lands, filter token-sourced items out of
-- the `owned` count right here.
function CSRMissionsMenuComponent:_unselected_item_count()
	if not managers.csr then
		return 0
	end

	local host_rank = managers.csr:host_rank() or 0
	local peer_id = managers.csr:local_peer_id()
	-- total_item_count = sum of stacks across all owned types (the count model
	-- replaced the id-list, so #player_items would be wrong on the map).
	local owned = managers.csr:total_item_count(peer_id)

	return math.max(0, host_rank - owned)
end

-- Refresh the notification's text + size + visibility. `allowed == false`
-- force-hides it (host-fail state), otherwise it shows only when the player
-- actually owes picks. Called from _create_status_bar (initial) and refresh()
-- (event-driven, never per-frame), so the table alloc in :text{} is fine.
function CSRMissionsMenuComponent:_refresh_unselected_items(allowed)
	if not self._unselected_panel or not alive(self._unselected_panel) then
		return
	end

	local count = self:_unselected_item_count()
	-- to_upper_text (not text): all-caps, same as the csr_lobby_rank/difficulty
	-- labels on the status row below. It takes the macro table too (vanilla
	-- uses to_upper_text("menu_cs_level", { ... }) the same way).
	self._unselected_items:set_text(managers.localization:to_upper_text("csr_lobby_unselected_items", {
		count = count,
	}))

	-- Snug the text to its glyphs with the canonical PD2 helper
	-- (blackmarketgui.lua:2416 -- set_size + ROUNDED set_position; the original
	-- of this fork uses the same call in CrimeSpreeMissionButton:update_button_text).
	-- Doing the resize by hand without the position re-pin left the glyphs
	-- drawn outside the moved panel: panel hoverable, text invisible. Then pin
	-- the text to (0,0) and wrap the hit-panel exactly around it so only the
	-- words are clickable, right-anchored over DIFFICULTY.
	BlackMarketGui.make_fine_text(nil, self._unselected_items)

	-- Padded backing plate (vanilla-button feel): the snug text sits inside a
	-- slightly larger panel so the yellow plate has breathing room, and the
	-- click/hover area equals the visible plate. bg fills the panel; both grow
	-- leftward since the right edge is pinned over DIFFICULTY.
	local pad_x, pad_y = 8, 3
	local tw, th = self._unselected_items:w(), self._unselected_items:h()
	self._unselected_items:set_position(pad_x, pad_y)
	self._unselected_panel:set_size(tw + pad_x * 2, th + pad_y * 2)
	self._unselected_panel:set_right(self._title_panel:right())
	-- Sit clearly ABOVE the status row (one medium line of clearance), not
	-- hugging it. Re-applied every refresh so a re-snug keeps the gap.
	self._unselected_panel:set_bottom(self._title_panel:top() - tweak_data.menu.pd2_medium_font_size)

	-- Backing plate: height == the TEXT glyph height (th), not the padded hit
	-- panel; width spans the whole mission row -- from the left edge of the
	-- leftmost card to the right edge over DIFFICULTY. self._title_panel shares
	-- w and right edge with self._buttons_panel (the cards), so right-anchoring
	-- at title_panel:right() with w == title_panel:w() lands exactly there.
	-- Vertically centred on the hit panel (the text is centred in it), so the
	-- th-tall plate sits flush behind the glyphs.
	self._unselected_bg:set_w(self._title_panel:w())
	self._unselected_bg:set_h(th)
	self._unselected_bg:set_right(self._title_panel:right())
	self._unselected_bg:set_center_y(self._unselected_panel:center_y())

	-- Reset to the dim base colour on (re)build; mouse_moved brightens it on
	-- hover. Stale hover can't persist a bright colour through a refresh.
	self._unselected_items:set_color(self._unselected_color_dim)
	self._unselected_items_hover = false

	self._unselected_visible = allowed ~= false and count > 0
	self._unselected_panel:set_visible(self._unselected_visible)
	-- bg is a sibling under self._panel, not a child of the hit panel, so the
	-- panel's set_visible above does NOT cover it -- toggle it on the same flag.
	self._unselected_bg:set_visible(self._unselected_visible)
end

-- Open the forked item-selection window (item_selection.lua). That file
-- owns the register/hide-chrome lifecycle and exposes _G.CSR_OpenItemSelection;
-- _G._csr_item_selection is its own "is it open" flag, which we reuse as
-- the guard. CSR_OpenItemSelection is NOT idempotent -- a second call
-- re-registers the component and overwrites its live-component-order snapshot
-- (the "after close, CSR buttons dead" bug it documents), so only open when
-- nothing is open yet. Nil-guarded: the window file is menu-loaded, but stay
-- defensive in case load order/strip changes. The pool is still the debug set
-- until CSRGameManager:roll_item_pool lands; this wires the trigger now.
function CSRMissionsMenuComponent:_on_unselected_items_clicked()
	-- Click SFX, same event the mission cards / sidebar post on activation
	-- (managers.menu_component:post_event("menu_enter"), see _set_button_index_selected).
	managers.menu_component:post_event("menu_enter")

	if _G.CSR_OpenItemSelection and not _G._csr_item_selection then
		-- Pass the current rank-vs-owned gap as the pick quota. The window stays
		-- open and re-rolls between picks until quota is spent (see
		-- item_selection.lua:_advance_pick). Recomputed at click time so a
		-- reroll/refresh that landed since the last reminder repaint is honoured.
		_G.CSR_OpenItemSelection(self:_unselected_item_count())
	end
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

		-- Diverges DELIBERATELY from vanilla crimespreemissionsmenucomponent.lua
		-- (which calls select_mission(btn:mission_id()) unconditionally). In the
		-- CSR fork csr_start_game reads managers.csr:current_mission() directly,
		-- and reroll/_select_mission(0) deselects the old card AFTER
		-- reroll_mission_set() already nil'd current_mission. The vanilla
		-- unconditional call re-selects the old (still-attached) mission_data on
		-- that deselect, so Start launched the pre-reroll heist. Push the pick
		-- into the manager only when actually selecting; clear it on deselect so
		-- a reroll (and a genuine deselect) leaves current_mission nil.
		if selected then
			managers.csr:select_mission(btn:mission_id())
		else
			managers.csr:select_mission(false)
		end

		if selected and self:_is_host() then
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

	-- The reminder is a sibling of self._title_panel (own snug panel, not a
	-- child of the row), so it needs its own toggle. Re-evaluates the pending
	-- count every refresh -- the pick total can change across sub-screen
	-- round-trips -- and stays hidden while the host-fail screen is up.
	self:_refresh_unselected_items(not hide)

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

	-- The sidebar is a child object of THIS component but is geometrically
	-- disjoint from the mission cards: the sidebar column and
	-- self._buttons_panel never overlap (verified from runtime bounds
	-- 2026-05-19 -- sidebar x:[0,160], cards x:[618,1198]). So the sidebar
	-- needs NO coupling with the card-hover logic: forward the cursor to it
	-- purely for its own button highlight / hover-sound and let it report
	-- whether it consumed the cursor. The card loop below is independently
	-- bounded to self._buttons_panel, so a cursor over the sidebar simply
	-- yields cards_area=false and no card reacts. Removing the previous
	-- "over_sidebar" early-return (which force-cleared every card's
	-- set_selected and juggled the pointer) eliminated the entire
	-- collapse->expand flicker class -- the two were only ever coupled by
	-- that band-aid.
	if self._sidebar then
		local s_used, s_pointer = self._sidebar:mouse_moved(x, y)

		if s_used then
			used = true
			pointer = s_pointer or pointer
		end
	end

	-- Bound mission-card hover to the cards' OWN container. A card is only
	-- hover-selected when the cursor is inside self._buttons_panel AND inside
	-- that card. Without the container check, any widget drawn over the card
	-- area on a higher layer (the social-hub notification toast, lobby code,
	-- future overlays) makes the card behind it flicker as the cursor moves,
	-- because mouse_moved otherwise hit-tests cards across the whole screen
	-- (user report 2026-05-19, generalises the sidebar fix above).
	local cards_area = self._buttons_panel and alive(self._buttons_panel) and self._buttons_panel:inside(x, y)

	for idx, btn in ipairs(self._buttons) do
		btn:set_selected(cards_area and btn:inside(x, y) or false)

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

	-- Unselected-items reminder: link cursor on hover, mirroring the buttons
	-- above. self._unselected_visible already folds in the pending>0 + host-fail
	-- gating, so an invisible reminder can never be hovered. (Hover/click are
	-- only reached for host/SP -- mouse_moved early-returns for non-host, same
	-- as mission selection; full per-client behaviour is a later slice.)
	local was_unselected_hover = self._unselected_items_hover == true
	self._unselected_items_hover = self._unselected_visible == true
		and self._unselected_panel ~= nil
		and alive(self._unselected_panel)
		and self._unselected_panel:inside(x, y)

	if self._unselected_items_hover then
		pointer = "link"
		used = true

		-- Hover SFX once on the false->true transition (NOT every mouse_moved
		-- while inside) -- the exact gate vanilla CrimeNetSidebarItem:set_highlight
		-- uses. "highlight" is the vanilla menu hover event
		-- (crimenetsidebargui.lua:604; also CSRSidebarItem:set_highlight here).
		if not was_unselected_hover then
			managers.menu:post_event("highlight")
		end
	end

	-- Brighten on hover, dim otherwise (mirrors the buttons' set_selected here;
	-- mouse_moved is event-driven, not a per-frame path, so set_color is cheap).
	if self._unselected_visible and alive(self._unselected_panel) then
		self._unselected_items:set_color(
			self._unselected_items_hover and self._unselected_color_bright or self._unselected_color_dim
		)
	end

	-- Items feature panel hover -> tooltip + edge-gated highlight SFX. Returns
	-- true when an item icon is under the cursor so the pointer flips to "link"
	-- (mirroring the unselected-items reminder + mission cards). Hidden-panel
	-- case is handled inside the method (drops any stale tooltip).
	if self:_items_panel_mouse_moved(x, y) then
		pointer = "link"
		used = true
	end

	-- Modifiers feature panel hover -> tooltip (icons) + link cursor (sub-tabs),
	-- same contract as the items panel above. Hidden-panel case handled inside.
	if self:_modifiers_panel_mouse_moved(x, y) then
		pointer = "link"
		used = true
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

	-- Modifiers sub-tab click (Loud / Stealth). Checked after the sidebar (which
	-- owns the rows that open the panel) and before card/start handling. No-op
	-- unless the panel is open and the click landed on a tab.
	if self:_modifiers_panel_mouse_pressed(x, y) then
		return true
	end

	-- Modifiers scroll-bar grab (lobby only; the briefing has no mouse_released so
	-- its scroll is wheel-only). Checked after the sub-tabs (which sit above the
	-- list) so a tab click is never stolen by the bar.
	if self:_modifiers_scroll_visible() and self._modifiers_scroll:mouse_pressed(button, x, y) then
		return true
	end

	return self:confirm_pressed()
end

-- Mouse-wheel + release routing for the Modifiers scroll list (lobby). The menu
-- framework dispatches these to every live component (menucomponentmanager.lua
-- run_return_on_all_live_components), so they only need to act when our scroll is
-- the visible tab. mouse_released always feeds the scroll so a grabbed bar releases
-- even if the cursor left the panel mid-drag.
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

function CSRMissionsMenuComponent:mouse_released(button, x, y)
	if self._modifiers_scroll then
		return self._modifiers_scroll:mouse_released(button, x, y)
	end
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

	if self._unselected_items_hover then
		self:_on_unselected_items_clicked()

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
	-- Fork divergence from vanilla CrimeSpreeMissionButton:refresh (which keys
	-- _bg purely on is_selected): vanilla CS auto-launches the heist the instant
	-- a mission is picked, so a chosen card is never left on screen to hover
	-- away from. CSR keeps the chosen mission card persistent in the lobby, so
	-- with vanilla's rule the chosen card's _bg pulses every time the cursor
	-- enters/leaves it (set_selected toggles via the hover loop while is_active
	-- stays true -- runtime-confirmed 2026-05-19). Gate _bg on is_active too so
	-- the chosen card holds its selected look regardless of hover; the other
	-- three lines already depend on is_active and were always stable.
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
	-- Per-mission rank gain, scaled by the LENGTH category shown by the clock
	-- glyph above (short = 1, medium = 2, long = 3). Uses managers.csr:rank_for_
	-- mission -- the SAME function mission_lifecycle.lua awards on completion, so
	-- the card advertises exactly what the player receives. (Vanilla passed
	-- mission_data.add directly; CSR maps that add-category to 1/2/3.)
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
	-- wraps managers.menu:open_node("logbook_screen"). Resolved at click
	-- time, so load order with the logbook scripts doesn't matter.
	local has_cb = MenuCallbackHandler ~= nil and MenuCallbackHandler.CSR_OpenLogbook ~= nil
	log("[CSR Logbook] sidebar Logbook clicked; CSR_OpenLogbook present=" .. tostring(has_cb))

	if has_cb then
		MenuCallbackHandler:CSR_OpenLogbook()
	end
end

-- Opens the full-screen Gage Services (Black Market) screen. Mirrors
-- csr_open_logbook: routes through MenuCallbackHandler:CSR_OpenBlackMarket
-- (black_market_button.lua) -> managers.menu:open_node("black_market_screen").
-- Resolved at click time, so load order with the shop scripts doesn't matter;
-- the arg-less closure ignores the owner the sidebar passes it.
local function csr_open_shop()
	if MenuCallbackHandler and MenuCallbackHandler.CSR_OpenBlackMarket then
		MenuCallbackHandler:CSR_OpenBlackMarket()
	end
end

-- Sidebar row callbacks are invoked as btn:callback()(owner) where owner is the
-- CSRMissionsMenuComponent (CSRSidebar:mouse_pressed passes self._owner). The
-- feature panels are component-owned (they span from the sidebar to the mission
-- cards, geometry the sidebar itself doesn't know), so each row forwards to the
-- owner with its category key. The factory returns a stateless module-level
-- closure (captures only the constant key, no instance state -- safe to share
-- across instances). nil/method-guarded so a missing owner is inert.
local function csr_feature_toggle(key)
	return function(owner)
		if owner and owner.toggle_feature_panel then
			owner:toggle_feature_panel(key)
		end
	end
end

-- Resolve the selected character's DEFAULT (signature) mask icon as a direct DB
-- texture path for the Heister sidebar row -- NOT the equipped mask. Passing the
-- "character_locked" pseudo-id makes BlackMarketTweakData:get_mask_icon swap in
-- tweak_data.blackmarket.masks.character_locked[character] (dallas->"dallas",
-- wolf->"wolf", ...); the character defaults to get_preferred_character() (the one
-- selected in the menu). Used as a FUNCTION icon (see the build loop in
-- CSRSidebar:init) so it resolves at build time, not at file load when the static
-- ITEMS table is evaluated. pcall-guarded AND DB:has-verified: on any failure
-- (no character resolved, missing/unloaded texture) it falls back to the generic
-- mask hud icon so the row never renders a magenta missing-texture block.
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

CSRSidebar.ITEMS = {
	-- Divider between the always-visible Hide/Show toggle (built before this
	-- list, pinned to the top) and the content rows. Built in the same loop, so
	-- it joins self._buttons and is hidden/non-interactive on collapse like the
	-- other separators — no special-casing needed.
	{ separator = true },
	-- Player combat characteristics (HP / armor / speed / dodge / stamina). Sits at
	-- the top of the content rows with its own separator (user spec). icon is a
	-- function: the selected character's DEFAULT mask texture, resolved at sidebar-
	-- build time (falls back to the generic mask hud icon -- see csr_character_mask_icon).
	{ text = "Heister", icon = csr_character_mask_icon, key = "heister", callback = csr_feature_toggle("heister") },
	{ separator = true },
	-- key tags the row with its feature-panel id so CSRSidebar:set_active_feature
	-- can light up whichever row owns the currently-visible panel.
	{ text = "Items", icon = "sidebar_basics", key = "items", callback = csr_feature_toggle("items") },
	{ text = "Modifiers", icon = "sidebar_mutators", key = "modifiers", callback = csr_feature_toggle("modifiers") },
	{ text = "Rewards", icon = "sidebar_broker", key = "rewards", callback = csr_feature_toggle("rewards") },
	{ separator = true },
	{ text = "Black Market", icon = "sidebar_gage", callback = csr_open_shop },
	{ separator = true },
	{ text = "Logbook", icon = "sidebar_codex", callback = csr_open_logbook },
}

function CSRSidebar:init(parent, top, bottom, owner)
	-- owner = the CSRMissionsMenuComponent. Stored so row callbacks can act on
	-- component-owned UI (e.g. the Items panel) via btn:callback()(self._owner).
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

	-- Always-visible collapse toggle, pinned to the top of the sidebar. It is
	-- deliberately NOT part of the collapsible content (set_collapsed never
	-- touches it), so it stays on screen as a "SHOW_SIDEBAR" affordance once the
	-- rest is hidden. Same CSRSidebarItem widget + vanilla "sidebar_expand" icon
	-- (hudiconstweakdata.lua — the exact icon the live CrimeNet sidebar uses for
	-- its collapse control) as every other row. CSRSidebarItem callbacks are
	-- invoked as btn:callback()(owner) in mouse_pressed; this arg-less closure
	-- ignores the owner and just forwards to self:toggle_collapsed().
	self._toggle = CSRSidebarItem:new(self._panel, {
		position = padding,
		text = "Hide Sidebar",
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
			-- icon may be a FUNCTION (resolved here, at build time, so it can track
			-- live state like the equipped mask) or a static string (hud id / path).
			local icon = item.icon
			if type(icon) == "function" then
				icon = icon()
			end
			btn = CSRSidebarItem:new(self._panel, {
				position = next_position,
				text = item.text,
				icon = icon,
				callback = item.callback,
			})
			-- nil for rows without a feature panel (Black Market, Logbook); only
			-- the feature-panel content rows carry a key, so only they can light up.
			btn._feature_key = item.key
		end

		next_position = next_position + btn:panel():height() + item_margin

		table.insert(self._buttons, btn)
	end

	-- Stored (was an anonymous panel in vanilla) so set_collapsed can hide the
	-- frame along with the rest of the collapsible content.
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

-- Collapse toggle. The toggle button itself is always left visible/interactive;
-- only the backdrop, the rows, and the frame are hidden. inside() still returns
-- geometric hits on a set_visible(false) panel, so mouse_moved/mouse_pressed
-- gate the non-toggle rows on self._collapsed rather than on visibility.
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

	-- Collapsing also hides the component-owned feature panel (Items/Modifiers/
	-- Rewards) -- it is opened from a sidebar row, so it must not linger when the
	-- sidebar is hidden (user spec 2026-05-19). Expanding does NOT reopen it; the
	-- player re-clicks the row. owner/method-guarded (inert if absent).
	if self._collapsed and self._owner and self._owner.hide_feature_panels then
		self._owner:hide_feature_panels()
	end

	self._toggle:set_text(self._collapsed and "Show Sidebar" or "Hide Sidebar")
end

function CSRSidebar:panel()
	return self._panel
end

function CSRSidebar:mouse_moved(x, y)
	local used, pointer = false, nil

	for _, btn in ipairs(self._buttons) do
		-- While collapsed only the toggle is live (hidden rows still hit-test).
		if (btn == self._toggle or not self._collapsed) and btn:accepts_interaction() then
			local inside = btn:inside(x, y)

			-- No no_sound / force_update args (vanilla CrimeNetSidebarGui
			-- :mouse_moved calls set_highlight(true)/(false) bare): the change
			-- guard fires the hover sound once per transition, never per frame.
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
			-- Click feedback, posted centrally (vanilla scatters this into every
			-- clbk_*; one site here covers all rows + the toggle + future
			-- callbacks). Same event the mission cards / tabs use elsewhere in
			-- this file. Row callbacks must therefore NOT post their own click
			-- sound or it double-triggers.
			managers.menu_component:post_event("menu_enter")
			-- Pass the owning component so component-scoped rows (Items) can act
			-- on it; the arg-less closures (toggle / csr_open_logbook) ignore it.
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

-- Light up the row that owns the currently-open feature panel. `key` is the
-- feature id ("items"/"modifiers"/"rewards") or nil when none is open. Each
-- content row tagged its _feature_key at build time; the toggle button has none
-- (so it never lights) and separators lack set_selected entirely (skipped).
-- Idempotent via CSRSidebarItem:set_selected's change-guard, so callers can fire
-- it freely (e.g. hide_feature_panels clearing, then a toggle re-setting).
function CSRSidebar:set_active_feature(key)
	for _, btn in ipairs(self._buttons) do
		if btn.set_selected then
			btn:set_selected(btn._feature_key ~= nil and btn._feature_key == key)
		end
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

	-- Icon resolves two ways: a string containing "/" is a direct DB texture path
	-- (e.g. an equipped mask icon from BlackMarketManager:get_mask_icon) drawn whole
	-- with no rect, so any source resolution scales to fit; anything else is a
	-- hud_icons id resolved to (texture, rect). Mirrors the items feature panel's
	-- icon handling (see CSRMissionsMenuComponent:_populate_items_panel).
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

	-- Active-tab marker, orthogonal to hover. Set true by set_selected when this
	-- row's feature panel is the visible one (see CSRSidebar:set_active_feature).
	self._selected = false

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

-- Signature restored to vanilla CrimeNetSidebarItem:set_highlight 1:1
-- (enabled, no_sound, force_update). The block (and thus the hover "highlight"
-- sound) only runs on a real state change unless force_update is set; the init
-- call passes no_sound=true so building the sidebar is silent, exactly like
-- vanilla (crimenetsidebargui.lua:553/584-608). managers.menu:post_event
-- ("highlight") is the same hover event vanilla uses (verified line 604). The
-- look itself is computed in _apply_visual so hover (_highlight) and the
-- active-tab marker (_selected) compose into one consistent appearance.
function CSRSidebarItem:set_highlight(enabled, no_sound, force_update)
	if self._highlight ~= enabled or force_update then
		self._highlight = enabled
		self:_apply_visual()

		if not no_sound then
			managers.menu:post_event("highlight")
		end
	end
end

-- Persistent "active tab" marker, independent of hover. Driven by
-- CSRSidebar:set_active_feature when a feature panel (Items/Modifiers/Rewards)
-- opens or closes, so the row whose panel is visible stays lit even when the
-- cursor is elsewhere. Silent + change-guarded (a programmatic selection must
-- not fire the hover sound).
function CSRSidebarItem:set_selected(enabled)
	enabled = enabled and true or false
	if self._selected ~= enabled then
		self._selected = enabled
		self:_apply_visual()
	end
end

-- Compose the row's look from hover (_highlight) and active-tab (_selected).
-- Selected wins on the backdrop: a persistent PD2-blue tint, a touch brighter
-- while also hovered so the active row still acknowledges hover. A plain row
-- keeps the vanilla recipe -- black backdrop on hover only, cyan resting
-- text/icon. Color AND alpha are set explicitly every pass: in Diesel set_color
-- writes RGB only and leaves alpha as set at panel creation, so swapping between
-- the blue and black (0.66) backdrops needs the alpha re-applied each
-- time or the carried-over value bleeds across states.
function CSRSidebarItem:_apply_visual()
	self._text:set_visible(true)

	if self._selected then
		-- Deliberately faint: the active-tab marker should be barely noticeable
		-- (user spec), so the blue wash sits at a low alpha -- a touch stronger
		-- while also hovered since hover feedback is transient and expected.
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
	-- Vanilla quirk preserved 1:1 (CrimeNetSidebarItem:set_text): upper-case and
	-- spaces -> underscores. Keeps the look identical to the CrimeNet sidebar.
	text = utf8.to_upper(text)
	text = text:gsub(" ", "_")

	self._text:set_text(text)
end

function CSRSidebarItem:update(t, dt) end

log("[CSR] missions_menu.lua loaded (Slice 8 fork + start button)")
