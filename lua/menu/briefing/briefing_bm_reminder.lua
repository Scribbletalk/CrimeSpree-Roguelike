-- CSR mission-briefing Black Market affordability reminder.
--
-- A second plate on MissionBriefingGui's saferect workspace (immediately below
-- the item reminder from briefing_reminder_input.lua). Visible when the local
-- peer has enough Gage Tokens to afford at least one unsold slot in the current
-- lineup. Clicking it opens the Black Market via managers.menu:open_node.
--
-- Positioning: same HUD-header anchor (hy + hh + fs) as the item reminder, but
-- offset UP by the BM panel height + 2px gap so BM sits just above the item reminder.
-- See briefing_reminder_input.lua for the coordinate-space rationale.
--
-- Mouse chain: this file is loaded AFTER briefing_reminder_input.lua in mod.txt,
-- so its raw wraps are the outermost layer. In mouse_moved orig (the item-reminder
-- wrapper) runs FIRST so it can clear its own hover before we apply the BM hover;
-- this prevents a stale-bright glitch when the cursor moves between the two plates.
-- In mouse_pressed BM hit-test runs before calling orig.
--
-- Critical Rule #1 exception: same as briefing_reminder_input.lua
-- (return-value hooks, feedback_rule1_return_value_exception).

if not RequiredScript then
	return
end

local BM_DIM = Color(1, 0.35, 0.7, 1)
local BM_BRIGHT = Color(1, 0.65, 0.88, 1)
local PAD_X, PAD_Y = 8, 3

local function csr_briefing_hud()
	local hm = managers and managers.hud
	local b = hm and hm._hud_mission_briefing
	if b and b._csr_progress_header and alive(b._csr_progress_header) then
		return b
	end
	return nil
end

-- True when the local peer has tokens ≥ the price of at least one unsold lineup slot.
local function can_afford_bm()
	local m = managers and managers.csr
	if not (m and m.is_run_active and m:is_run_active()) then
		return false
	end
	if not CSR_Shop then
		return false
	end
	local pid = CSR_Shop.local_peer_id()
	local tokens = CSR_Shop.tokens(pid)
	local lineup = CSR_Shop.get_lineup and CSR_Shop.get_lineup(pid) or {}
	for _, slot in ipairs(lineup) do
		if not slot.sold then
			local price = CSR_Shop.PRICE and CSR_Shop.PRICE[slot.rarity] or math.huge
			if tokens >= price then
				return true
			end
		end
	end
	return false
end

if MissionBriefingGui and not _G._CSR_BM_REMINDER_HOOKED then
	_G._CSR_BM_REMINDER_HOOKED = true

	function MissionBriefingGui:_csr_bm_build()
		if self._csr_bm_panel and alive(self._csr_bm_panel) then
			return
		end
		local ws_panel = self._safe_workspace and self._safe_workspace:panel()
		if not ws_panel or not alive(ws_panel) then
			return
		end
		self._csr_bm_panel = ws_panel:panel({
			layer = 51,
			visible = false,
		})
		self._csr_bm_bg = self._csr_bm_panel:rect({
			layer = 0,
			color = BM_DIM,
			alpha = 0.1,
			halign = "scale",
			valign = "scale",
		})
		self._csr_bm_text = self._csr_bm_panel:text({
			layer = 1,
			text = "",
			color = BM_DIM,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size * 1.2,
			align = "right",
			vertical = "center",
		})
		self._csr_bm_hovered = false
	end

	function MissionBriefingGui:_csr_bm_refresh()
		if not self._csr_bm_panel or not alive(self._csr_bm_panel) then
			return
		end
		local hud_briefing = csr_briefing_hud()
		if not hud_briefing then
			self._csr_bm_panel:set_visible(false)
			return
		end

		self._csr_bm_text:set_text(managers.localization:to_upper_text("csr_briefing_bm_affordable"))

		local ws_panel = self._safe_workspace:panel()
		local hdr = hud_briefing._csr_progress_header
		local fw = ws_panel:w()
		local plate_w = fw / 2
		local hy = hdr:world_y() - ws_panel:world_y()
		local hh = hdr:h()
		local fs = tweak_data.menu.pd2_medium_font_size
		local text_h = fs * 1.2

		self._csr_bm_panel:set_size(plate_w, text_h + PAD_Y * 2)
		self._csr_bm_panel:set_right(fw)
		self._csr_bm_panel:set_bottom(hy + hh + fs - 2)

		self._csr_bm_text:set_size(plate_w - PAD_X * 2, text_h)
		self._csr_bm_text:set_position(PAD_X, PAD_Y)

		self._csr_bm_text:set_color(BM_DIM)
		self._csr_bm_bg:set_color(BM_DIM)
		self._csr_bm_hovered = false

		self._csr_bm_panel:set_visible(can_afford_bm())
	end

	function MissionBriefingGui:_csr_bm_hit_test(x, y)
		if not self._csr_bm_panel or not alive(self._csr_bm_panel) then
			return false
		end
		if not self._csr_bm_panel:visible() then
			return false
		end
		return self._csr_bm_panel:inside(x, y)
	end

	function MissionBriefingGui:_csr_bm_set_hover(state)
		if not self._csr_bm_text or not alive(self._csr_bm_text) then
			return
		end
		if state == self._csr_bm_hovered then
			return
		end
		self._csr_bm_hovered = state
		local c = state and BM_BRIGHT or BM_DIM
		self._csr_bm_text:set_color(c)
		if self._csr_bm_bg and alive(self._csr_bm_bg) then
			self._csr_bm_bg:set_color(c)
		end
		if state and managers.menu_component then
			managers.menu_component:post_event("highlight")
		end
	end

	function MissionBriefingGui:_csr_on_bm_clicked()
		if managers.menu_component then
			managers.menu_component:post_event("menu_enter")
		end
		local ok, err = pcall(function()
			managers.menu:open_node("black_market_screen")
		end)
		if not ok then
			log("[CSR] briefing_bm_reminder: open_node failed: " .. tostring(err))
		end
	end

	Hooks:PostHook(MissionBriefingGui, "init", "CSR_BmReminderInit", function(self)
		self:_csr_bm_build()
	end)

	Hooks:PostHook(MissionBriefingGui, "show", "CSR_BmReminderShow", function(self)
		if self._csr_bm_build then
			self:_csr_bm_build()
		end
		if self._csr_bm_refresh then
			self:_csr_bm_refresh()
		end
	end)

	Hooks:PostHook(MissionBriefingGui, "hide", "CSR_BmReminderHide", function(self)
		if self._csr_bm_panel and alive(self._csr_bm_panel) then
			self._csr_bm_panel:set_visible(false)
		end
	end)

	-- Mouse wraps: outermost layer (loaded after briefing_reminder_input.lua).
	-- mouse_moved: call orig FIRST so item reminder can clear its own hover, then
	-- overlay BM hit-test on top. mouse_pressed: check BM plate first, then fall
	-- through to item reminder + vanilla via orig.
	local orig_mm = MissionBriefingGui.mouse_moved
	if orig_mm then
		function MissionBriefingGui:mouse_moved(x, y)
			if _G._csr_item_selection or not self._enabled then
				if self._csr_bm_set_hover then
					self:_csr_bm_set_hover(false)
				end
				return orig_mm(self, x, y)
			end
			local used, ptr = orig_mm(self, x, y)
			local hit = self._csr_bm_hit_test and self:_csr_bm_hit_test(x, y) or false
			if self._csr_bm_set_hover then
				self:_csr_bm_set_hover(hit)
			end
			if hit then
				return true, "link"
			end
			return used, ptr
		end
	end

	local orig_mp = MissionBriefingGui.mouse_pressed
	if orig_mp then
		function MissionBriefingGui:mouse_pressed(button, x, y)
			if _G._csr_item_selection or not self._enabled then
				return orig_mp(self, button, x, y)
			end
			if self._csr_bm_hit_test and self:_csr_bm_hit_test(x, y) then
				self:_csr_on_bm_clicked()
				return true
			end
			return orig_mp(self, button, x, y)
		end
	end
end

-- Lobby BM reminder — same plate on CSRMissionsMenuComponent (the mission-select
-- lobby). Positioned above the unselected-items reminder. Since this file loads at
-- missionbriefinggui time (after menucomponentmanager), CSRMissionsMenuComponent
-- already exists; PostHooks + chain-wraps are safe to install here.
if CSRMissionsMenuComponent and not _G._CSR_BM_LOBBY_REMINDER_HOOKED then
	_G._CSR_BM_LOBBY_REMINDER_HOOKED = true
	csr_log("[CSR] bm_reminder: lobby section registered (CSRMissionsMenuComponent found)")

	function CSRMissionsMenuComponent:_csr_bm_lobby_build()
		if self._csr_bm_lobby_panel and alive(self._csr_bm_lobby_panel) then
			return
		end
		if not self._panel or not alive(self._panel) then
			csr_log("[CSR] bm_reminder: lobby build skipped – panel dead")
			return
		end
		csr_log("[CSR] bm_reminder: lobby build start")
		self._csr_bm_lobby_panel = self._panel:panel({ layer = 51, visible = false })
		self._csr_bm_lobby_bg = self._panel:rect({ layer = 1, color = BM_DIM, alpha = 0.1 })
		self._csr_bm_lobby_text = self._csr_bm_lobby_panel:text({
			layer = 52,
			text = "",
			color = BM_DIM,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size * 1.2,
		})
		self._csr_bm_lobby_hovered = false
		-- Text is static; snug once at build time.
		self._csr_bm_lobby_text:set_text(managers.localization:to_upper_text("csr_briefing_bm_affordable"))
		BlackMarketGui.make_fine_text(nil, self._csr_bm_lobby_text)
		local tw, th = self._csr_bm_lobby_text:w(), self._csr_bm_lobby_text:h()
		self._csr_bm_lobby_text:set_position(PAD_X, PAD_Y)
		self._csr_bm_lobby_panel:set_size(tw + PAD_X * 2, th + PAD_Y * 2)
		self._csr_bm_lobby_panel:set_right(self._title_panel:right())
		self._csr_bm_lobby_bg:set_w(self._title_panel:w())
		self._csr_bm_lobby_bg:set_h(th)
		self._csr_bm_lobby_bg:set_right(self._title_panel:right())
	end

	function CSRMissionsMenuComponent:_csr_bm_lobby_refresh()
		if not self._csr_bm_lobby_panel or not alive(self._csr_bm_lobby_panel) then
			csr_log("[CSR] bm_reminder: lobby refresh skipped – panel nil or dead")
			return
		end
		-- Re-anchor above unselected reminder each refresh (its top shifts with digit count).
		if self._unselected_panel and alive(self._unselected_panel) then
			self._csr_bm_lobby_panel:set_bottom(self._unselected_panel:top() - 2)
			if self._csr_bm_lobby_bg and alive(self._csr_bm_lobby_bg) then
				self._csr_bm_lobby_bg:set_center_y(self._csr_bm_lobby_panel:center_y())
			end
		end
		local visible = can_afford_bm()
		csr_log("[CSR] bm_reminder: lobby refresh visible=" .. tostring(visible))
		self._csr_bm_lobby_panel:set_visible(visible)
		if self._csr_bm_lobby_bg and alive(self._csr_bm_lobby_bg) then
			self._csr_bm_lobby_bg:set_visible(visible)
		end
		if self._csr_bm_lobby_text and alive(self._csr_bm_lobby_text) then
			self._csr_bm_lobby_text:set_color(BM_DIM)
		end
		self._csr_bm_lobby_hovered = false
	end

	function CSRMissionsMenuComponent:_csr_bm_lobby_set_hover(state)
		if not self._csr_bm_lobby_text or not alive(self._csr_bm_lobby_text) then
			return
		end
		if state == self._csr_bm_lobby_hovered then
			return
		end
		self._csr_bm_lobby_hovered = state
		local c = state and BM_BRIGHT or BM_DIM
		self._csr_bm_lobby_text:set_color(c)
		if self._csr_bm_lobby_bg and alive(self._csr_bm_lobby_bg) then
			self._csr_bm_lobby_bg:set_color(c)
		end
		if state and managers.menu_component then
			managers.menu_component:post_event("highlight")
		end
	end

	Hooks:PostHook(CSRMissionsMenuComponent, "_create_status_bar", "CSR_BmLobbyBuild", function(self)
		self:_csr_bm_lobby_build()
		self:_csr_bm_lobby_refresh()
	end)

	Hooks:PostHook(CSRMissionsMenuComponent, "_refresh_unselected_items", "CSR_BmLobbyRefresh", function(self)
		self:_csr_bm_lobby_refresh()
	end)

	local orig_lmm = CSRMissionsMenuComponent.mouse_moved
	if orig_lmm then
		function CSRMissionsMenuComponent:mouse_moved(o, x, y)
			local used, pointer = orig_lmm(self, o, x, y)
			local hit = not _G._csr_item_selection
				and self._csr_bm_lobby_panel ~= nil
				and alive(self._csr_bm_lobby_panel)
				and self._csr_bm_lobby_panel:visible()
				and self._csr_bm_lobby_panel:inside(x, y)
			if self._csr_bm_lobby_set_hover then
				self:_csr_bm_lobby_set_hover(hit)
			end
			if hit then
				used = true
				pointer = "link"
			end
			return used, pointer
		end
	end

	local orig_lmp = CSRMissionsMenuComponent.mouse_pressed
	if orig_lmp then
		function CSRMissionsMenuComponent:mouse_pressed(button, x, y)
			if
				not _G._csr_item_selection
				and self._csr_bm_lobby_panel
				and alive(self._csr_bm_lobby_panel)
				and self._csr_bm_lobby_panel:visible()
				and self._csr_bm_lobby_panel:inside(x, y)
			then
				if managers.menu_component then
					managers.menu_component:post_event("menu_enter")
				end
				local ok, err = pcall(function()
					managers.menu:open_node("black_market_screen")
				end)
				if not ok then
					log("[CSR] briefing_bm_reminder: lobby open_node failed: " .. tostring(err))
				end
				return true
			end
			return orig_lmp(self, button, x, y)
		end
	end
end

csr_log("[CSR] briefing_bm_reminder.lua loaded (Black Market affordability reminder)")
