-- CSR mission-briefing unselected-items reminder (UI + input).
-- Must live on MissionBriefingGui's saferect workspace: mouse coords are in that
-- space, so hit-testing against a HUD panel produces a Y mismatch.

if not RequiredScript then
	return
end

local UNSELECTED_DIM = Color(1, 0.85, 0.78, 0)
local UNSELECTED_BRIGHT = Color(1, 1, 1, 0)
local PAD_X, PAD_Y = 8, 3

local function csr_briefing_hud()
	local hm = managers and managers.hud
	local b = hm and hm._hud_mission_briefing
	if b and b._csr_progress_header and alive(b._csr_progress_header) then
		return b
	end
	return nil
end

local function unselected_item_count()
	if not managers or not managers.csr then
		return 0
	end
	local host_rank = managers.csr:host_rank() or 0
	local owned = managers.csr:rank_item_count(managers.csr:local_peer_id()) or 0
	return math.max(0, host_rank - owned)
end

if MissionBriefingGui and not _G._CSR_BRIEFING_REMINDER_INPUT_HOOKED then
	_G._CSR_BRIEFING_REMINDER_INPUT_HOOKED = true

	function MissionBriefingGui:_csr_build_reminder()
		if self._csr_reminder_panel and alive(self._csr_reminder_panel) then
			return
		end
		local ws_panel = self._safe_workspace and self._safe_workspace:panel()
		if not ws_panel or not alive(ws_panel) then
			return
		end

		-- Subscribe once; guard prevents stacking on idempotent rebuild.
		local mgr = managers and managers.csr
		if not self._csr_reminder_unsub and mgr and mgr.on_item_added then
			self._csr_reminder_unsub = mgr:on_item_added(function()
				if self._csr_refresh_reminder then
					self:_csr_refresh_reminder()
				end
			end)
		end

		self._csr_reminder_panel = ws_panel:panel({
			layer = 51,
			visible = false,
		})
		self._csr_reminder_bg = self._csr_reminder_panel:rect({
			layer = 0,
			color = UNSELECTED_DIM,
			alpha = 0.1,
			halign = "scale",
			valign = "scale",
		})
		self._csr_reminder_text = self._csr_reminder_panel:text({
			layer = 1,
			text = "",
			color = UNSELECTED_DIM,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size * 1.2,
			align = "right",
			vertical = "center",
		})
		self._csr_reminder_hovered = false
	end

	-- Also called from selection-window finalize so the count drops immediately after a pick.
	function MissionBriefingGui:_csr_refresh_reminder()
		if not self._csr_reminder_panel or not alive(self._csr_reminder_panel) then
			return
		end
		local hud_briefing = csr_briefing_hud()
		if not hud_briefing then
			self._csr_reminder_panel:set_visible(false)
			return
		end

		local count = unselected_item_count()
		self._csr_reminder_text:set_text(managers.localization:to_upper_text("csr_lobby_unselected_items", {
			count = count,
		}))

		-- Width from MENU workspace (not HUD header): the two saferects may differ,
		-- causing clipping if we inherit HUD's width. Y from HUD world coords so
		-- the plate sits visually under the difficulty row regardless of workspace alignment.
		local ws_panel = self._safe_workspace:panel()
		local hdr = hud_briefing._csr_progress_header
		local fw = ws_panel:w()
		local plate_w = fw / 2
		local hy = hdr:world_y() - ws_panel:world_y()
		local hh = hdr:h()
		local text_h = tweak_data.menu.pd2_medium_font_size * 1.2

		self._csr_reminder_panel:set_size(plate_w, text_h + PAD_Y * 2)
		self._csr_reminder_panel:set_right(fw)
		self._csr_reminder_panel:set_top(hy + hh + tweak_data.menu.pd2_medium_font_size)

		self._csr_reminder_text:set_size(plate_w - PAD_X * 2, text_h)
		self._csr_reminder_text:set_position(PAD_X, PAD_Y)

		self._csr_reminder_text:set_color(UNSELECTED_DIM)
		self._csr_reminder_bg:set_color(UNSELECTED_DIM)
		self._csr_reminder_hovered = false

		self._csr_reminder_panel:set_visible(count > 0)
	end

	function MissionBriefingGui:_csr_reminder_hit_test(x, y)
		if not self._csr_reminder_panel or not alive(self._csr_reminder_panel) then
			return false
		end
		if not self._csr_reminder_panel:visible() then
			return false
		end
		return self._csr_reminder_panel:inside(x, y)
	end

	function MissionBriefingGui:_csr_reminder_set_hover(state)
		if not self._csr_reminder_text or not alive(self._csr_reminder_text) then
			return
		end
		if state == self._csr_reminder_hovered then
			return
		end
		self._csr_reminder_hovered = state
		local c = state and UNSELECTED_BRIGHT or UNSELECTED_DIM
		self._csr_reminder_text:set_color(c)
		if self._csr_reminder_bg and alive(self._csr_reminder_bg) then
			self._csr_reminder_bg:set_color(c)
		end
		-- Gate to one SFX per transition; mouse_moved fires per pixel.
		if state and managers.menu_component then
			managers.menu_component:post_event("highlight")
		end
	end

	function MissionBriefingGui:_csr_on_reminder_clicked()
		if managers.menu_component then
			managers.menu_component:post_event("menu_enter")
		end
		if _G.CSR_OpenItemSelection and not _G._csr_item_selection then
			_G.CSR_OpenItemSelection(unselected_item_count())
		end
	end

	Hooks:PostHook(MissionBriefingGui, "init", "CSR_BriefingReminderInit", function(self)
		self:_csr_build_reminder()
	end)

	Hooks:PostHook(MissionBriefingGui, "show", "CSR_BriefingReminderShow", function(self)
		if self._csr_build_reminder then
			self:_csr_build_reminder()
		end
		if self._csr_refresh_reminder then
			self:_csr_refresh_reminder()
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "hide", "CSR_BriefingReminderHide", function(self)
		if self._csr_reminder_panel and alive(self._csr_reminder_panel) then
			self._csr_reminder_panel:set_visible(false)
		end
	end)

	-- Plate lives on the shared saferect workspace, so vanilla close() -- which only removes its own
	-- _panel and _fullscreen_panel (missionbriefinggui.lua:4829) -- leaves it on screen: pressing READY
	-- closed the briefing and the plate stayed up. Remove it ourselves; a fresh briefing rebuilds it.
	Hooks:PostHook(MissionBriefingGui, "close", "CSR_BriefingReminderClose", function(self)
		if self._csr_reminder_unsub then
			self._csr_reminder_unsub()
			self._csr_reminder_unsub = nil
		end
		local ws_panel = self._safe_workspace and self._safe_workspace:panel()
		if self._csr_reminder_panel and alive(self._csr_reminder_panel) and ws_panel and alive(ws_panel) then
			ws_panel:remove(self._csr_reminder_panel)
		end
		self._csr_reminder_panel = nil
		self._csr_reminder_bg = nil
		self._csr_reminder_text = nil
	end)

	-- Raw wraps needed: mouse_moved/pressed return values matter to the dispatcher
	-- and PostHook can't carry return values.
	-- When modal is open, yield nil so the selection window (lower priority) gets clicks.
	local orig_mouse_moved = MissionBriefingGui.mouse_moved
	if orig_mouse_moved then
		function MissionBriefingGui:mouse_moved(x, y)
			if _G._csr_item_selection or not self._enabled then
				if self._csr_reminder_set_hover then
					self:_csr_reminder_set_hover(false)
				end
				return
			end
			local hit = self._csr_reminder_hit_test and self:_csr_reminder_hit_test(x, y) or false
			if self._csr_reminder_set_hover then
				self:_csr_reminder_set_hover(hit)
			end
			if hit then
				return true, "link"
			end
			return orig_mouse_moved(self, x, y)
		end
	end

	local orig_mouse_pressed = MissionBriefingGui.mouse_pressed
	if orig_mouse_pressed then
		function MissionBriefingGui:mouse_pressed(button, x, y)
			if _G._csr_item_selection or not self._enabled then
				return
			end
			if self._csr_reminder_hit_test and self:_csr_reminder_hit_test(x, y) then
				self:_csr_on_reminder_clicked()
				return true
			end
			return orig_mouse_pressed(self, button, x, y)
		end
	end
end

csr_log("[CSR] briefing_reminder_input.lua loaded (MissionBriefingGui workspace reminder)")
