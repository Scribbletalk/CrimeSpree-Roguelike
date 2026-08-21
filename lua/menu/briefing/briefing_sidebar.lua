-- CSR mission-briefing sidebar + feature panels.
-- Reuses CSRSidebar and borrows feature-panel methods from CSRMissionsMenuComponent;
-- all panels live on the saferect workspace so mouse coords match click targets.

if not RequiredScript then
	return
end

-- True when CSR job is active but vanilla crime_spree manager is not yet running.
-- Keyed off current_job_id (not HUD header) so MP guests get the sidebar regardless of HUD-fork routing.
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

-- MenuComponentManager checks _mission_briefing_gui (confirm:1274, mouse_moved:2041, mouse_pressed:1567)
-- UNCONDITIONALLY while it is non-nil -- even when a CSR overlay node is on top. The logbook / black
-- market are live components that receive input only AFTER the briefing, so unless the briefing goes
-- input-transparent it consumes the event and starves the overlay's virtual cursor (its mouse_moved never
-- runs -> _csr_last_x stays nil -> its confirm replay clicks nothing). The selected node name is the
-- authoritative "overlay on top" signal; panel visibility is not (briefing update re-asserts it per frame).
local CSR_BRIEFING_OVERLAY_NODES = {
	logbook_screen = true,
	black_market_screen = true,
}
local function csr_briefing_overlay_open()
	local menu = managers.menu and managers.menu:active_menu()
	local logic = menu and menu.logic
	if not logic or not logic:selected_node() then
		return false
	end
	return CSR_BRIEFING_OVERLAY_NODES[logic:selected_node_name()] == true
end

-- Fire the overlay node's live component confirm_pressed directly. MenuComponentManager:confirm_pressed
-- reaches the overlay only via run_return_on_all_live_components, which stops at the first component
-- returning non-nil -- an upstream live component (endscreen / mission-end residue whose confirm_pressed
-- is not neutered by _suppress_endscreen) can swallow a controller A before the overlay is reached. Mouse
-- is unaffected: its dispatch stops only on a truthy "used", and that residue returns falsy. The briefing's
-- own confirm_pressed is queried early (before that machinery), so routing A to the overlay here makes it
-- land regardless of the blocker. The component id equals the selected node's menu_components string.
local function csr_route_confirm_to_overlay()
	local mc = managers.menu_component
	local menu = managers.menu and managers.menu:active_menu()
	local logic = menu and menu.logic
	local node = logic and logic:selected_node()
	local id = node and node:parameters().menu_components
	if not mc or not mc._alive_components or type(id) ~= "string" then
		return false
	end
	for _, comp_data in ipairs(mc._alive_components) do
		if comp_data.id == id and comp_data.component and comp_data.component.confirm_pressed then
			comp_data.component:confirm_pressed()
			return true
		end
	end
	return false
end

-- Methods borrowed from CSRMissionsMenuComponent onto MissionBriefingGui so the briefing
-- drives the same feature-panel pipeline as the lobby. Lazy: applied at first build, not load.
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
	"_modifiers_scroll_visible",
	"_populate_rewards_panel",
	"_populate_heister_panel",
	"_populate_preferences_panel",
	"_preferences_panel_mouse_moved",
	"_preferences_panel_mouse_pressed",
	"_preferences_panel_mouse_released",
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
		if _G.CSR_DEBUG then
			local C = managers and managers.csr
			csr_log(
				string.format(
					"[CSR][mpdbg] _csr_build_sidebar: have_sidebar=%s job_id=%s csr_active=%s is_guesting=%s",
					tostring(self._sidebar ~= nil),
					tostring(managers and managers.job and managers.job:current_job_id()),
					tostring(csr_briefing_active()),
					tostring(C and C.is_guesting and C:is_guesting())
				)
			)
		end
		-- Guest's current_job may not have settled yet; fall back to is_guesting to avoid
		-- the host-state-arrives-late race.
		local is_guesting = managers and managers.csr and managers.csr.is_guesting and managers.csr:is_guesting()
		if not (csr_briefing_active() or is_guesting) then
			if _G.CSR_DEBUG then
				csr_log("[CSR][mpdbg] _csr_build_sidebar: BAILED — not csr_briefing_active and not is_guesting")
			end
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

		-- Match lobby sidebar vertical span; pass self so feature-row callbacks reach toggle_feature_panel.
		local top = tweak_data.menu.pd2_large_font_size + 16
		local bottom = ws_panel:h() - tweak_data.menu.pd2_large_font_size * 1.5 - 20

		self._sidebar = CSRSidebar:new(ws_panel, top, bottom, self)

		-- Anchor fields used by borrowed feature-panel helpers (see missions_menu.lua).
		self._csr_fp_parent = ws_panel
		self._csr_fp_right_anchor = self._panel

		-- Build Items / Modifiers / Rewards panels (all hidden; toggle_feature_panel shows them).
		if self._create_feature_panels then
			self:_create_feature_panels()
		end

		-- Reopen the tab the player pinned on the lobby / a previous briefing (no-op if none).
		if self._csr_reopen_pinned_feature_panel then
			self:_csr_reopen_pinned_feature_panel()
		end

		-- Repaint the items panel when an item is picked; _csr_sidebar_unsub guards double-subscribe.
		local mgr = managers and managers.csr
		if not self._csr_sidebar_unsub and mgr and mgr.on_item_added then
			self._csr_sidebar_unsub = mgr:on_item_added(function()
				if self._populate_items_panel then
					self:_populate_items_panel()
				end
			end)
		end

		-- Park the lobby-code widget in the top-right corner (overlaps the mission name otherwise).
		self:_csr_reposition_lobby_code()
	end

	-- Move the MP lobby-code widget to the top-right corner. Vanilla only does this when
	-- crime_spree:is_active(), which is false in CSR's standard gamemode.
	function MissionBriefingGui:_csr_reposition_lobby_code()
		if not self._lobby_code_text then
			return
		end
		local panel = self._lobby_code_text:panel()
		if not (panel and alive(panel)) then
			return
		end
		local right = (self._panel and alive(self._panel) and self._panel:right()) or self._safe_workspace:panel():w()
		panel:set_right(right)
		panel:set_y(10)
	end

	function MissionBriefingGui:_csr_remove_sidebar()
		-- Drop subscription first: stale callback into destroyed panels crashes on next add_item.
		if self._csr_sidebar_unsub then
			self._csr_sidebar_unsub()
			self._csr_sidebar_unsub = nil
		end
		-- Feature panels live on ws_panel, not self._panel, so vanilla close() won't remove them.
		if self._feature_panels then
			local fp_parent = self._csr_fp_parent
			for _, p in pairs(self._feature_panels) do
				if p and alive(p) and fp_parent and alive(fp_parent) then
					fp_parent:remove(p)
				end
			end
			self._feature_panels = nil
		end
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

	-- Hide/restore all CSR briefing chrome while item-selection modal is open. Per-frame driven
	-- because on_item_added callbacks can re-show panels mid-modal.
	function MissionBriefingGui:_csr_set_chrome_hidden(hidden)
		if hidden then
			if self._sidebar then
				local p = self._sidebar:panel()
				if p and alive(p) then
					p:set_visible(false)
				end
			end
			-- Pinned tab lives in Global._csr_pinned_feature, so hiding all panels is non-destructive.
			if self.hide_feature_panels then
				self:hide_feature_panels()
			end
			if self._csr_reminder_panel and alive(self._csr_reminder_panel) then
				self._csr_reminder_panel:set_visible(false)
			end
			if self._csr_bm_panel and alive(self._csr_bm_panel) then
				self._csr_bm_panel:set_visible(false)
			end
			-- Missions/rank/difficulty header lives on the HUD-side briefing (separate object).
			local hud_b = managers and managers.hud and managers.hud._hud_mission_briefing
			local hdr = hud_b and hud_b._csr_progress_header
			if hdr and alive(hdr) then
				hdr:set_visible(false)
			end
			self._csr_chrome_hidden = true
		elseif self._csr_chrome_hidden then
			self._csr_chrome_hidden = nil
			if self._sidebar then
				local p = self._sidebar:panel()
				if p and alive(p) then
					p:set_visible(true)
				end
			end
			if self._csr_reopen_pinned_feature_panel then
				self:_csr_reopen_pinned_feature_panel()
			end
			-- Let each reminder recompute its own visibility (unselected count / BM affordability).
			if self._csr_refresh_reminder then
				self:_csr_refresh_reminder()
			end
			if self._csr_bm_refresh then
				self:_csr_bm_refresh()
			end
			local hud_b = managers and managers.hud and managers.hud._hud_mission_briefing
			local hdr = hud_b and hud_b._csr_progress_header
			if hdr and alive(hdr) then
				hdr:set_visible(true)
			end
		end
	end

	-- MP client crash guard: guest never runs select_mission so the crime_spree chain stays
	-- empty -> current_level_data() nil -> init nil-crash. Re-derive chain right before init.
	Hooks:PreHook(MissionBriefingGui, "init", "CSR_BriefingEnsureChain", function(self)
		if not managers or not managers.job or not managers.csr then
			return
		end
		if _G.CSR_DEBUG then
			csr_log(
				string.format(
					"[CSR][mpdbg] briefing init PreHook: job_id=%s has_level_data=%s (empty level_data + non-crime_spree job => plan/Bain text empty)",
					tostring(managers.job and managers.job:current_job_id()),
					tostring(managers.job:current_level_data() ~= nil)
				)
			)
		end
		if managers.job:current_level_data() then
			return
		end
		if managers.job:current_job_id() == "crime_spree" and managers.csr._setup_temporary_job then
			-- Job already active but chain empty (game-side manager re-init): re-derive the chain.
			managers.csr:_setup_temporary_job()
			csr_log("[CSR] briefing: re-derived empty crime_spree chain before init (MP client)")
		elseif managers.csr.ensure_guest_temp_job then
			-- Guest never runs select_mission -> no current_job. Activate the crime_spree temp job so
			-- current_level_data is populated. Primary activation is the at_enter PreHook (before the
			-- briefing HUD builds); this is the idempotent fallback if that didn't fire.
			managers.csr:ensure_guest_temp_job()
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "init", "CSR_BriefingSidebarInit", function(self)
		self:_csr_build_sidebar()

		-- Re-sync peer items; wiped across menu->game transition.
		if self._sidebar and _G.CSR_MP and _G.CSR_MP.is_multiplayer and _G.CSR_MP.is_multiplayer() then
			_G.CSR_MP.broadcast_own_items()
			if _G.CSR_MP.is_client and _G.CSR_MP.is_client() then
				_G.CSR_MP.request_all_items()
				-- Drop-in guests may have missed the lobby ping; pull host-state as fallback.
				if _G.CSR_MP.request_host_state then
					_G.CSR_MP.request_host_state()
				end
			end
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "show", "CSR_BriefingSidebarShow", function(self)
		if self._csr_build_sidebar then
			self:_csr_build_sidebar()
		end
		if self._sidebar then
			-- CSR briefing only (sidebar present): the sidebar/reminders are mouse-only, so on a
			-- controller drive them with the virtual cursor (idempotent; balanced in hide/close).
			CSR_ControllerNav.show_cursor(self)
			local p = self._sidebar:panel()
			if p and alive(p) then
				p:set_visible(true)
			end
		end
		if self._csr_reopen_pinned_feature_panel then
			self:_csr_reopen_pinned_feature_panel()
		end
		-- Missions/rank/difficulty strip lives on the HUD briefing; restore it when returning from a subscreen.
		local hud_b = managers and managers.hud and managers.hud._hud_mission_briefing
		local hdr = hud_b and hud_b._csr_progress_header
		if hdr and alive(hdr) then
			hdr:set_visible(true)
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "hide", "CSR_BriefingSidebarHide", function(self)
		CSR_ControllerNav.hide_cursor(self)
		if self._sidebar then
			local p = self._sidebar:panel()
			if p and alive(p) then
				p:set_visible(false)
			end
		end
		if self.hide_feature_panels then
			self:hide_feature_panels()
		end
		-- Hide the HUD-side run-progress strip while Black Market / Logbook cover the briefing.
		local hud_b = managers and managers.hud and managers.hud._hud_mission_briefing
		local hdr = hud_b and hud_b._csr_progress_header
		if hdr and alive(hdr) then
			hdr:set_visible(false)
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "close", "CSR_BriefingSidebarClose", function(self)
		CSR_ControllerNav.hide_cursor(self)
		self:_csr_remove_sidebar()
	end)

	-- Raw wraps: PostHook can't carry mouse_moved's (used,pointer) tuple.
	local orig_mouse_moved = MissionBriefingGui.mouse_moved
	if orig_mouse_moved then
		function MissionBriefingGui:mouse_moved(x, y)
			-- Covered by a CSR overlay (logbook / black market hide our panel but leave us enabled):
			-- stay transparent so MenuComponentManager:mouse_moved passes the event to the overlay
			-- component behind us. Our sidebar lives on a separate panel and is still hit-testable, so
			-- consuming here would block the overlay's hover AND its cursor (_csr_last_x) update.
			if csr_briefing_overlay_open() then
				return false, "arrow"
			end
			-- Stash the cursor for a controller confirm (A carries no coords). Store the real
			-- position for both the physical mouse and the virtual cursor, before any -9999 clear.
			self._csr_last_x, self._csr_last_y = x, y
			-- Modal open: clear sticky hover (-9999 pushes pointer outside all inside() checks).
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
				if self._preferences_panel_mouse_moved then
					self:_preferences_panel_mouse_moved(-9999, -9999)
				end
				return orig_mouse_moved(self, x, y)
			end

			if self._items_panel_mouse_moved then
				local items_used = self:_items_panel_mouse_moved(x, y)
				if items_used then
					return true, "link"
				end
			end

			if self._modifiers_panel_mouse_moved then
				local mods_used = self:_modifiers_panel_mouse_moved(x, y)
				if mods_used then
					return true, "link"
				end
			end

			if self._preferences_panel_mouse_moved then
				local pref_used = self:_preferences_panel_mouse_moved(x, y)
				if pref_used then
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
			-- Covered by a CSR overlay (logbook / black market): stay transparent so the click
			-- reaches the overlay component behind us (see mouse_moved for the rationale).
			if csr_briefing_overlay_open() then
				return
			end
			if _G._csr_item_selection or not self._enabled then
				return orig_mouse_pressed(self, button, x, y)
			end
			-- Wheel arrives as mouse_pressed here; route to modifiers scroll before sub-tab check.
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
			-- Scrollbar drag and the arrow buttons belong to the ScrollablePanel itself; the borrowed
			-- _modifiers_panel_mouse_pressed only covers the sub-tabs, so the briefing had neither.
			if
				self._modifiers_scroll
				and self._modifiers_scroll_visible
				and self:_modifiers_scroll_visible()
				and self._modifiers_scroll:mouse_pressed(button, x, y)
			then
				return true
			end
			if self._modifiers_panel_mouse_pressed and self:_modifiers_panel_mouse_pressed(x, y) then
				return true
			end
			if self._preferences_panel_mouse_pressed and self:_preferences_panel_mouse_pressed(x, y) then
				return true
			end
			return orig_mouse_pressed(self, button, x, y)
		end
	end

	-- Controller A is a discrete press+release via replay_click, but MissionBriefingGui has no vanilla
	-- mouse_released, so replay_click would fire only the press -- leaving a Preferences slider grab
	-- (_pref_dragging) stuck to the cursor. Mirror the lobby's release routing so the drag ends on A;
	-- press+release at the same point sets the slider to the cursor position. On a physical mouse
	-- MenuComponentManager does not route mouse_released here (the MCM:mouse_released PostHook below
	-- covers PC), so this method is reached only through replay_click.
	local orig_mouse_released = MissionBriefingGui.mouse_released
	function MissionBriefingGui:mouse_released(o, button, x, y)
		if self._preferences_panel_mouse_released and self:_preferences_panel_mouse_released(button, x, y) then
			return true
		end
		if self._modifiers_scroll then
			return self._modifiers_scroll:mouse_released(button, x, y)
		end
		if orig_mouse_released then
			return orig_mouse_released(self, o, button, x, y)
		end
	end

	-- Controller confirm (A) carries no cursor coords, so replay a click at the last cursor position.
	-- It routes through the mouse_pressed wrap above -> sidebar/reminders, then vanilla tabs/assets/
	-- ready-tick. Gamepad only, and only while our virtual cursor owns input. No fallthrough needed:
	-- on a gamepad vanilla confirm_pressed never readies up (that path is is_pc_controller-gated), and
	-- an open asset is closed by the replayed press too, so consuming A loses nothing.
	-- MenuComponentManager queries this gui's confirm BEFORE its live-component loop, so when a CSR
	-- overlay (logbook / black market) covers the briefing we forward A straight to the overlay's
	-- component here -- reaching it via the loop is unreliable (an upstream live component can swallow A
	-- first; see csr_route_confirm_to_overlay). Consuming A after routing also blocks a double fire.
	local orig_confirm_pressed = MissionBriefingGui.confirm_pressed
	if orig_confirm_pressed then
		function MissionBriefingGui:confirm_pressed(...)
			if csr_briefing_overlay_open() then
				-- Controller only: route A to the overlay component (pc keeps its native mouse-click path).
				if not managers.menu:is_pc_controller() and csr_route_confirm_to_overlay() then
					return true
				end
				return false
			end
			if
				not managers.menu:is_pc_controller()
				and self._csr_controller_mouse
				and self._csr_last_x
				and self._enabled
			then
				CSR_ControllerNav.replay_click(self, self._csr_last_x, self._csr_last_y)
				return true
			end
			return orig_confirm_pressed(self, ...)
		end
	end

	Hooks:PostHook(MissionBriefingGui, "update", "CSR_BriefingSidebarUpdate", function(self, t, dt)
		if self._sidebar and self._sidebar.update then
			self._sidebar:update(t, dt)
		end
		if self._csr_set_chrome_hidden then
			self:_csr_set_chrome_hidden(_G._csr_item_selection ~= nil)
		end
	end)

	-- Snap targets for the controller cursor: the sidebar rail plus the open feature panel.
	function MissionBriefingGui:csr_magnet_targets(out)
		if not self._enabled or csr_briefing_overlay_open() then
			return
		end
		CSR_ControllerNav.add_sidebar_targets(out, self._sidebar)
		CSR_ControllerNav.add_feature_panel_targets(out, self)
		-- Reminder plates open the item pick / Black Market, so they pull like any other button.
		CSR_ControllerNav.add_target(out, self._csr_reminder_panel)
		CSR_ControllerNav.add_target(out, self._csr_bm_panel)
	end
end

-- MissionBriefingGui is not routed mouse_released by MenuComponentManager, so forward it here
-- so Preferences slider drags can complete.
if MenuComponentManager and not _G._CSR_BRIEFING_PREF_RELEASE_HOOKED then
	_G._CSR_BRIEFING_PREF_RELEASE_HOOKED = true
	Hooks:PostHook(MenuComponentManager, "mouse_released", "CSR_Briefing_PrefRelease", function(self, o, button, x, y)
		local gui = self._mission_briefing_gui
		if gui and gui._preferences_panel_mouse_released then
			gui:_preferences_panel_mouse_released(button, x, y)
		end
	end)
end

csr_log("[CSR] briefing_sidebar.lua loaded (MissionBriefingGui workspace sidebar + feature panels)")
