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
		-- Parity with briefing_wiring / HUD header: a guest's current_job may not have settled to
		-- "crime_spree" yet (csr_briefing_active false), so fall back to is_guesting so the sidebar
		-- still builds. Hardens against the host-state-arrives-late race.
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

		-- Match the lobby sidebar's vertical span so both screens read as the same column.
		local top = tweak_data.menu.pd2_large_font_size + 16
		local bottom = ws_panel:h() - tweak_data.menu.pd2_large_font_size * 1.5 - 20

		-- Pass self as owner so the feature-row callbacks can reach toggle_feature_panel.
		self._sidebar = CSRSidebar:new(ws_panel, top, bottom, self)

		-- Anchor fields read by the borrowed feature-panel helpers (lobby pair: missions_menu.lua):
		--   _csr_fp_parent       -- saferect ws_panel; feature panels + tooltip live here
		--   _csr_fp_right_anchor -- panel whose :left() bounds the feature panel on the right
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

	-- Park the MP lobby-code widget (MissionBriefingGui._lobby_code_text) in the top-right corner.
	-- Vanilla only repositions it for real Crime Spree (crime_spree:is_active()), which is false in
	-- CSR's standard gamemode, so without this it stays at the default x=0/y=80 top-left and overlaps
	-- the mission name (job_text). The ready-button panel (self._panel) is right-aligned to the
	-- saferect, so its right edge gives the corner anchor.
	function MissionBriefingGui:_csr_reposition_lobby_code()
		if not self._lobby_code_text then
			return
		end
		local panel = self._lobby_code_text:panel()
		if not (panel and alive(panel)) then
			return
		end
		-- Top-right corner: the ready-button panel (self._panel) is right-aligned to the saferect,
		-- so its right edge gives the corner anchor.
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

	-- Hide all CSR briefing chrome while the item-selection modal is open, restore on close.
	-- Driven per-frame from update(): forced each frame because the on_item_added refresh
	-- callbacks (reminder / items panel) can re-show a panel mid-modal after a pick.
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

		-- Re-sync peer items; _remote_peer_items are wiped across menu->game transition.
		if self._sidebar and _G.CSR_MP and _G.CSR_MP.is_multiplayer and _G.CSR_MP.is_multiplayer() then
			_G.CSR_MP.broadcast_own_items()
			if _G.CSR_MP.is_client and _G.CSR_MP.is_client() then
				_G.CSR_MP.request_all_items()
				-- Mid-heist drop-in guests may have missed the lobby ping; pull host-state here as fallback.
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
			local p = self._sidebar:panel()
			if p and alive(p) then
				p:set_visible(true)
			end
		end
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
		if self.hide_feature_panels then
			self:hide_feature_panels()
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "close", "CSR_BriefingSidebarClose", function(self)
		self:_csr_remove_sidebar()
	end)

	-- Raw wraps (Rule #1 exception): PostHook can't carry mouse_moved's (used,pointer) tuple.
	local orig_mouse_moved = MissionBriefingGui.mouse_moved
	if orig_mouse_moved then
		function MissionBriefingGui:mouse_moved(x, y)
			-- Modal open or sub-screen on top: clear sticky hover (-9999 pushes pointer outside all inside() checks).
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
			if self._modifiers_panel_mouse_pressed and self:_modifiers_panel_mouse_pressed(x, y) then
				return true
			end
			if self._preferences_panel_mouse_pressed and self:_preferences_panel_mouse_pressed(x, y) then
				return true
			end
			return orig_mouse_pressed(self, button, x, y)
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
end

-- MissionBriefingGui receives mouse_pressed/mouse_moved from MenuComponentManager but NOT
-- mouse_released (it's a special-cased gui, not a live component routed via mouse_released).
-- Forward release here so a Preferences slider drag started in the briefing can end.
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
