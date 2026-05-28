-- CSR mission-briefing sidebar + feature panels.
--
-- Reuses CSRSidebar (defined alongside CSRMissionsMenuComponent in
-- lua/menu/missions_menu.lua) so the briefing screen shows the same
-- left-side navigation column as the lobby. Vanilla MissionBriefingGui
-- builds its content panel right-anchored at safe_ws_w / 2 -- the entire
-- left half of the saferect is empty, which is exactly where the sidebar
-- and the Items / Modifiers / Rewards feature panels belong (visually
-- mirrors the lobby's "sidebar left, mission cards right" layout, except
-- here the right side is the briefing column).
--
-- Coord space: everything lives on `self._safe_workspace:panel()` for
-- the same reason the reminder does (see briefing_reminder_input.lua):
-- the briefing's mouse_moved/mouse_pressed callbacks receive coordinates
-- in saferect-local space, and rendering anywhere else creates a Y
-- mismatch between visible plate and click target.
--
-- This file is loaded AFTER briefing_reminder_input.lua per mod.txt
-- order, so OUR wrap of mouse_moved / mouse_pressed is the outer one.
-- Dispatch chain: sidebar wrap (this file) -> reminder wrap -> vanilla.
-- Same `_G._csr_item_selection` modal gate the reminder uses: while the
-- selection window is open, every briefing-side input falls through to
-- the live-components loop so the modal (priority -100) receives clicks.
--
-- No-leak: built only when the CSR-forked HUD briefing is live
-- (managers.hud._hud_mission_briefing._csr_progress_header is a field
-- only CSRMissionBriefing populates -- vanilla MissionBriefingGui in a
-- non-CSR session leaves it nil). Same gate the reminder uses, so the
-- two stay in lockstep: either both build or neither does.
--
-- Owner = self (the MissionBriefingGui). The lobby sidebar passes its
-- CSRMissionsMenuComponent so the Items / Modifiers / Rewards rows can
-- toggle component-owned feature panels via owner:toggle_feature_panel().
-- We do the same thing: MissionBriefingGui method-borrows those helpers
-- from CSRMissionsMenuComponent so the briefing has a working
-- toggle_feature_panel / hide_feature_panels / _populate_items_panel /
-- ... pipeline. The borrowed methods read abstract anchor fields
-- (_csr_fp_parent / _csr_fp_right_anchor) set in _csr_build_sidebar; lobby
-- sets the same fields in CSRMissionsMenuComponent:_setup. The functions
-- are byte-for-byte the same; only the concrete panels behind the
-- abstract names differ.

if not RequiredScript then
	return
end

-- CSR-heist signal, identical to briefing_wiring.lua's: the temporary
-- "crime_spree" job is active and vanilla Crime Spree is NOT. Previously this
-- keyed off the HUD briefing's _csr_progress_header, but that couples the sidebar
-- to the HUD-briefing FORK routing -- which fails for an MP guest, because its
-- current_job becomes "crime_spree" by network sync only AFTER
-- setup_mission_briefing_hud already built the (vanilla) HUD briefing, so the
-- guest got no header AND therefore no sidebar. By _csr_build_sidebar time
-- (MissionBriefingGui:init PostHook) the job sync HAS landed (the init PreHook
-- crash-guard proves current_job == "crime_spree" here), so gating on the job
-- directly builds the sidebar for the guest regardless of HUD-briefing routing.
local function csr_briefing_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

-- Method-borrowing list. Each name is a method on CSRMissionsMenuComponent;
-- we copy them onto MissionBriefingGui so the briefing instance can drive
-- the same feature-panel pipeline (toggle / populate / tooltip) the lobby
-- uses. Borrowing is done lazily (first time _csr_build_sidebar runs) so
-- this file doesn't depend on missions_menu.lua's hook having already
-- fired at load time -- both hook on different vanilla scripts and order
-- between them isn't guaranteed.
local METHODS_TO_BORROW = {
	"_create_feature_panels",
	"toggle_feature_panel",
	"hide_feature_panels",
	"_csr_reopen_pinned_feature_panel",
	"_populate_items_panel",
	"_collect_peers_for_items_panel",
	"_items_panel_peer_color",
	"_clear_items_tooltip",
	"_show_items_tooltip",
	"_items_panel_mouse_moved",
	"_populate_modifiers_panel",
	"_modifiers_panel_mouse_moved",
	"_modifiers_panel_mouse_pressed",
	-- Gate for the modifiers scroll list's wheel routing (briefing wheel handling
	-- in this file's mouse_pressed wrap calls it).
	"_modifiers_scroll_visible",
	-- _create_feature_panels + toggle_feature_panel both call this, so the
	-- briefing must borrow it too or those calls hit a nil method.
	"_populate_rewards_panel",
	-- Heister combat-stats panel: same reason as rewards -- _create_feature_panels
	-- and toggle_feature_panel both call it.
	"_populate_heister_panel",
}

local function ensure_methods_borrowed()
	if MissionBriefingGui._csr_methods_borrowed then
		return true
	end
	if not CSRMissionsMenuComponent then
		return false
	end
	for _, name in ipairs(METHODS_TO_BORROW) do
		MissionBriefingGui[name] = CSRMissionsMenuComponent[name]
	end
	MissionBriefingGui._csr_methods_borrowed = true
	return true
end

if MissionBriefingGui and not _G._CSR_BRIEFING_SIDEBAR_HOOKED then
	_G._CSR_BRIEFING_SIDEBAR_HOOKED = true

	function MissionBriefingGui:_csr_build_sidebar()
		if self._sidebar then
			return
		end
		if not csr_briefing_active() then
			return
		end
		local ws_panel = self._safe_workspace and self._safe_workspace:panel()
		if not ws_panel or not alive(ws_panel) then
			return
		end
		if not CSRSidebar then
			return
		end
		if not ensure_methods_borrowed() then
			return
		end

		-- Vertical span mirrors the LOBBY sidebar's so the two screens read
		-- as the same column at the same size (user spec: briefing height
		-- ~= lobby height). Lobby anchors its top to the measured bottom
		-- of its "Crime Spree Roguelike" pd2_large_font title plus a 16
		-- gap (missions_menu.lua: top = _title_bottom + sidebar_title_gap,
		-- _title_bottom = title:bottom() = pd2_large_font_size since the
		-- title is at panel-y=0 with vertical="top"). Reproducing that
		-- arithmetic directly here -- pd2_large_font_size + 16 -- gives
		-- the SAME absolute y, even though the briefing screen has no
		-- visible title on the left half (saferect left half is empty,
		-- so sitting at lobby-top y is clear). Bottom is identical to
		-- lobby (parent:bottom() - pd2_large_font_size * 1.5) so the
		-- visible height matches end-to-end.
		local top = tweak_data.menu.pd2_large_font_size + 16
		local bottom = ws_panel:h() - tweak_data.menu.pd2_large_font_size * 1.5

		-- Pass self as owner so the Items / Modifiers / Rewards row
		-- callbacks (csr_feature_toggle("items") etc.) can call
		-- owner:toggle_feature_panel(key).
		self._sidebar = CSRSidebar:new(ws_panel, top, bottom, self)

		-- Abstract anchor fields read by the borrowed feature-panel
		-- helpers (see missions_menu.lua _setup for the lobby pair):
		--   _csr_fp_parent       -- where feature panels + tooltip live
		--                           (briefing: the saferect ws_panel, so
		--                           feature panels share the sidebar's
		--                           coord space and can sit beside it)
		--   _csr_fp_right_anchor -- panel whose :left() bounds the feature
		--                           panel's rect on the right (briefing:
		--                           vanilla self._panel, the right-half
		--                           briefing content column; sidebar to its
		--                           left, briefing UI to its right, feature
		--                           panel fills the gap between them)
		self._csr_fp_parent = ws_panel
		self._csr_fp_right_anchor = self._panel

		-- Build the three feature panels (Items / Modifiers / Rewards).
		-- The helper is a no-op without _sidebar + _csr_fp_right_anchor +
		-- _csr_fp_parent, all of which we just set. After this returns
		-- self._feature_panels = { items, modifiers, rewards }, all hidden,
		-- ready for toggle_feature_panel() to flip them on.
		if self._create_feature_panels then
			self:_create_feature_panels()
		end

		-- Restore the pinned feature panel (set by the player on the lobby or
		-- a previous briefing) so the same tab opens automatically here. The
		-- helper short-circuits when no slot is pinned, so this is a no-op
		-- for the first-ever briefing of the session.
		if self._csr_reopen_pinned_feature_panel then
			self:_csr_reopen_pinned_feature_panel()
		end

		-- Subscribe to CSRGameManager item-added events so the items panel
		-- repaints itself in place when the player picks an item from the
		-- briefing-side reminder (the reminder repaint is owned by
		-- briefing_reminder_input.lua's own subscription). Guarded with
		-- _csr_sidebar_unsub so a build/show idempotent re-entry doesn't
		-- stack subscriptions. _populate_items_panel short-circuits when
		-- self._feature_panels.items is nil/dead, so it's safe to call
		-- unconditionally on every add_item.
		local mgr = managers and managers.csr
		if not self._csr_sidebar_unsub and mgr and mgr.on_item_added then
			self._csr_sidebar_unsub = mgr:on_item_added(function()
				if self._populate_items_panel then
					self:_populate_items_panel()
				end
			end)
		end
	end

	function MissionBriefingGui:_csr_remove_sidebar()
		-- Drop the items-panel refresh subscription before destroying the
		-- panels it draws into. Stale callback against destroyed panels =
		-- next add_item crashes.
		if self._csr_sidebar_unsub then
			self._csr_sidebar_unsub()
			self._csr_sidebar_unsub = nil
		end
		-- Feature panels first: they live on _csr_fp_parent (ws_panel), not
		-- on self._panel which vanilla MissionBriefingGui:close removes for
		-- us. Without this they would leak across briefing open/close
		-- cycles inside one menu session.
		if self._feature_panels then
			local fp_parent = self._csr_fp_parent
			for _, p in pairs(self._feature_panels) do
				if p and alive(p) and fp_parent and alive(fp_parent) then
					fp_parent:remove(p)
				end
			end
			self._feature_panels = nil
		end
		-- Tooltip is a sibling on the same parent; clear it explicitly so it
		-- doesn't outlive the icons that drove it.
		if self._clear_items_tooltip then
			self:_clear_items_tooltip()
		end
		self._items_hit_targets = nil
		self._items_hover_target = nil
		self._items_content = nil
		self._modifiers_hit_targets = nil
		self._modifiers_hover_target = nil
		self._modifiers_content = nil
		self._modifiers_subtab_buttons = nil
		self._heister_content = nil

		if self._sidebar then
			local p = self._sidebar:panel()
			local ws_panel = self._safe_workspace and self._safe_workspace:panel()
			if p and alive(p) and ws_panel and alive(ws_panel) then
				ws_panel:remove(p)
			end
			self._sidebar = nil
		end
		self._csr_fp_parent = nil
		self._csr_fp_right_anchor = nil
	end

	-- Crash guard (MP client). Vanilla MissionBriefingGui:init indexes
	-- managers.job:current_level_data().name_id. A CSR client never runs
	-- select_mission (host-only), so although its current_job IS the synced
	-- "crime_spree" temp job, the crime_spree narrative chain (local tweak_data,
	-- NOT network-synced) is still the empty {} default -> current_stage_data()
	-- returns {} -> current_level_id() nil -> current_level_data() nil -> the init
	-- nil-crash (crash_report_2026_05_26_17_30). The host never hits this
	-- (select_mission set its chain). Re-derive the chain from the loading level
	-- right BEFORE init builds (PreHook), exactly as the host's CSRGameManager init
	-- does -- but now timed when Global.game_settings.level_id is guaranteed present.
	-- Pure guard: a no-op whenever current_level_data already resolves (host + every
	-- vanilla heist), and only acts under the crime_spree job (no vanilla leak).
	Hooks:PreHook(MissionBriefingGui, "init", "CSR_BriefingEnsureChain", function(self)
		if not managers or not managers.job or not managers.csr then
			return
		end
		if managers.job:current_level_data() then
			return
		end
		if managers.job:current_job_id() == "crime_spree" and managers.csr._setup_temporary_job then
			managers.csr:_setup_temporary_job()
			csr_log("[CSR] briefing: re-derived empty crime_spree chain before init (MP client)")
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "init", "CSR_BriefingSidebarInit", function(self)
		self:_csr_build_sidebar()

		-- MP: the briefing's items panel needs every peer's items, but a guest's
		-- _remote_peer_items are runtime-only and were wiped by the menu->game state
		-- transition (and the lobby's request doesn't carry over). Re-sync now, exactly
		-- like missions_wiring.lua does for the lobby: announce our own, and (as a
		-- client) pull the host's roster -- CSR_MP.refresh_items_panel repaints THIS
		-- briefing panel as each peer's data arrives. Gated on self._sidebar so it only
		-- fires for a real CSR briefing (where _csr_build_sidebar actually built).
		if self._sidebar and _G.CSR_MP and _G.CSR_MP.is_multiplayer and _G.CSR_MP.is_multiplayer() then
			_G.CSR_MP.broadcast_own_items()
			if _G.CSR_MP.is_client and _G.CSR_MP.is_client() then
				_G.CSR_MP.request_all_items()
				-- Also PULL host-state here. A guest that joined the host MID-HEIST
				-- (JOINED_GAME / drop-in) never hit the lobby on_enter_lobby ping AND
				-- IngameWaitingForPlayersState:at_enter may not fire its guest pull, so
				-- host-state (rank/seed) is never acquired -> is_guesting() stays false ->
				-- the guest wrongly runs its OWN rank + OWN solo-run items. This briefing
				-- hook DID fire (it requested items above), so it's a reliable point where
				-- the session is is_client-ready. request_host_state self-gates to clients.
				if _G.CSR_MP.request_host_state then
					_G.CSR_MP.request_host_state()
				end
			end
		end
	end)

	-- show/hide cover the case where MissionBriefingGui is built once
	-- and re-shown across sub-screen round-trips (Inventory, Skill Tree,
	-- etc.) without re-running init. Visibility tracks the briefing's
	-- own show/hide so the sidebar + feature panels don't bleed onto
	-- sub-screens.
	Hooks:PostHook(MissionBriefingGui, "show", "CSR_BriefingSidebarShow", function(self)
		if self._csr_build_sidebar then
			self:_csr_build_sidebar()
		end
		if self._sidebar then
			local p = self._sidebar:panel()
			if p and alive(p) then
				p:set_visible(true)
			end
		end
		-- Re-apply the pinned feature tab so closing+reopening the briefing
		-- (e.g. round-trip through Inventory or Skill Tree sub-screens) keeps
		-- whatever was open. The hide hook below force-hides every panel so
		-- they don't bleed onto sub-screens; show() restores them. Body is
		-- a no-op when no slot is pinned (player has nothing open) -- the
		-- prior "feature panels stay HIDDEN on show" rule is preserved in
		-- that case.
		if self._csr_reopen_pinned_feature_panel then
			self:_csr_reopen_pinned_feature_panel()
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "hide", "CSR_BriefingSidebarHide", function(self)
		if self._sidebar then
			local p = self._sidebar:panel()
			if p and alive(p) then
				p:set_visible(false)
			end
		end
		-- Force-hide any open feature panel + tooltip so they don't show
		-- through to the sub-screen on top of us.
		if self.hide_feature_panels then
			self:hide_feature_panels()
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "close", "CSR_BriefingSidebarClose", function(self)
		self:_csr_remove_sidebar()
	end)

	-- Input wraps. Critical Rule #1 exception (return-value hooks) per
	-- feedback_rule1_return_value_exception -- PostHook can't carry the
	-- (used, pointer) tuple mouse_moved returns or the `used` flag
	-- mouse_pressed returns. _G guard stops hot-reload from compounding
	-- wraps.
	--
	-- Dispatch priority (descending): items-panel tooltip hover ->
	-- sidebar row hover -> inner wrap (reminder + vanilla). Tooltip needs
	-- to run BEFORE the sidebar dispatch only so its return value flags
	-- "used" when over an icon (preventing the reminder hover swap),
	-- but the items panel is always rendered to the RIGHT of the sidebar
	-- so the two regions never actually overlap -- order is defensive.
	local orig_mouse_moved = MissionBriefingGui.mouse_moved
	if orig_mouse_moved then
		function MissionBriefingGui:mouse_moved(x, y)
			-- Suppress every CSR surface while EITHER the modal selection window
			-- is open OR the briefing is disabled (self._enabled is false
			-- whenever a sub-screen node -- preplanning / loadout / skill tree --
			-- sits on top of us; vanilla gates ALL of its own mouse_moved /
			-- mouse_pressed on the same flag). MenuComponentManager keeps feeding
			-- us events because the gui only goes nil on close(), so without this
			-- the sidebar still hit-tests its rows under the sub-screen
			-- ("invisible but clickable" -- :inside() tests geometry regardless
			-- of visibility). Clear sticky hover (-9999,-9999 = "send pointer far
			-- away": every inside() returns false) and fall through to vanilla,
			-- which itself bails on not self._enabled.
			if _G._csr_item_selection or not self._enabled then
				if self._sidebar and self._sidebar.mouse_moved then
					self._sidebar:mouse_moved(-9999, -9999)
				end
				if self._items_panel_mouse_moved then
					self:_items_panel_mouse_moved(-9999, -9999)
				end
				if self._modifiers_panel_mouse_moved then
					self:_modifiers_panel_mouse_moved(-9999, -9999)
				end
				return orig_mouse_moved(self, x, y)
			end

			-- Items panel hover (tooltip) -- only meaningful if the items
			-- feature panel is currently visible. The helper returns
			-- early-false otherwise, so it's cheap to call unconditionally.
			if self._items_panel_mouse_moved then
				local items_used = self:_items_panel_mouse_moved(x, y)
				if items_used then
					return true, "link"
				end
			end

			-- Modifiers panel hover (tooltip + sub-tab cursor). Same contract as
			-- the items panel above; mutually exclusive, so only one is visible.
			if self._modifiers_panel_mouse_moved then
				local mods_used = self:_modifiers_panel_mouse_moved(x, y)
				if mods_used then
					return true, "link"
				end
			end

			local sb = self._sidebar
			if sb and sb.mouse_moved then
				local used, pointer = sb:mouse_moved(x, y)
				if used then
					return used, pointer
				end
			end
			return orig_mouse_moved(self, x, y)
		end
	end

	local orig_mouse_pressed = MissionBriefingGui.mouse_pressed
	if orig_mouse_pressed then
		function MissionBriefingGui:mouse_pressed(button, x, y)
			-- Modal selection window open OR briefing disabled (preplanning /
			-- loadout / skill tree sub-screen on top -- vanilla gates input on
			-- self._enabled the same way): the sidebar + wheel + sub-tab handling
			-- must NOT run. Fall through to the inner wrap (reminder -> vanilla);
			-- vanilla returns early on not self._enabled, so nothing is consumed.
			if _G._csr_item_selection or not self._enabled then
				return orig_mouse_pressed(self, button, x, y)
			end
			-- The briefing receives mouse-wheel as a mouse_pressed with a wheel
			-- button (MenuComponentManager:mouse_pressed dispatches the briefing gui
			-- unconditionally, before its own wheel branch). Route it to the
			-- modifiers scroll list and consume -- BEFORE the sub-tab check so a
			-- scroll over a tab can't toggle it. The briefing has no mouse_released,
			-- so the bar can't be dragged here; wheel is the only scroll input.
			if button == Idstring("mouse wheel up") or button == Idstring("mouse wheel down") then
				if self._modifiers_scroll and self._modifiers_scroll_visible and self:_modifiers_scroll_visible() then
					local dir = button == Idstring("mouse wheel up") and 1 or -1
					if self._modifiers_scroll:scroll(x, y, dir) then
						return true
					end
				end
				return orig_mouse_pressed(self, button, x, y)
			end
			local sb = self._sidebar
			if sb and sb.mouse_pressed then
				local used = sb:mouse_pressed(x, y)
				if used then
					return true
				end
			end
			-- Modifiers sub-tab click (Loud / Stealth), after the sidebar rows
			-- that own the panel toggle. No-op unless the panel is open.
			if self._modifiers_panel_mouse_pressed and self:_modifiers_panel_mouse_pressed(x, y) then
				return true
			end
			return orig_mouse_pressed(self, button, x, y)
		end
	end

	-- update is a no-op today (CSRSidebarItem:update is empty), but the
	-- sidebar layer may grow per-frame work later (pulse/animation rows).
	-- Wiring update here now -- one-line cost -- means future animation
	-- changes don't need a second migration pass.
	Hooks:PostHook(MissionBriefingGui, "update", "CSR_BriefingSidebarUpdate", function(self, t, dt)
		if self._sidebar and self._sidebar.update then
			self._sidebar:update(t, dt)
		end
	end)
end

csr_log("[CSR] briefing_sidebar.lua loaded (MissionBriefingGui workspace sidebar + feature panels)")
