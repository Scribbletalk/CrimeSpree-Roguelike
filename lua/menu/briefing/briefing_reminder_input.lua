-- CSR mission-briefing unselected-items reminder (UI + input).
--
-- LIVES on MissionBriefingGui's saferect workspace (NOT on the HUD's
-- foreground_layer_one) for a single reason: input dispatch on the briefing
-- screen flows through MissionBriefingGui:mouse_moved/pressed, and those
-- callbacks receive coordinates in `_safe_workspace`-local space (saferect
-- origin). Rendering on the HUD's saferect-aligned panel and hit-testing
-- here produced a constant Y mismatch -- the visible plate was at HUD
-- coords, the click target at menu-saferect coords, off by saferect_y.
-- Living on the same workspace as the mouse dispatch eliminates the
-- mismatch natively: panel:inside(x, y) just works.
--
-- The visible POSITION still anchors to the CSR briefing's
-- _csr_progress_header (rendered on HUD), so the reminder reads as "the
-- row under the difficulty column above". We read the header's world rect
-- and convert to MissionBriefingGui workspace local coords.
--
-- Critical Rule #1 exception: mouse_moved returns (used, pointer) and
-- mouse_pressed returns `used` -- both values matter for the input
-- dispatcher upstream, and PostHook cannot carry return values. Raw chain
-- wrap is the established CSR convention for return-value hooks
-- (feedback_rule1_return_value_exception). _G guards stop hot-reload from
-- compounding wraps.
--
-- No-leak guarantee: the reminder is built only when a CSR briefing fork
-- is live (managers.hud._hud_mission_briefing._csr_progress_header is a
-- field that only exists on CSRMissionBriefing). When the briefing screen
-- runs in a non-CSR session, the reminder stays hidden and the wraps fall
-- through to vanilla return values.

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

	-- Build the reminder UI on the briefing GUI's saferect workspace. Run
	-- exactly once per MissionBriefingGui instance (the panels persist for
	-- the lifetime of the gui, which is the whole menu session per the
	-- MenuComponentManager:create_mission_briefing_gui memoised-lazy pattern).
	function MissionBriefingGui:_csr_build_reminder()
		if self._csr_reminder_panel and alive(self._csr_reminder_panel) then
			return
		end
		local ws_panel = self._safe_workspace and self._safe_workspace:panel()
		if not ws_panel or not alive(ws_panel) then
			return
		end

		-- Subscribe ONCE per MissionBriefingGui instance to CSRGameManager
		-- item-added events: any add_item caller drives the reminder counter
		-- repaint with no per-call-site wiring. Guarded by _csr_reminder_unsub
		-- so the show()-driven idempotent rebuild path doesn't stack
		-- subscriptions. Body is alive-guarded inside _csr_refresh_reminder
		-- (it short-circuits on a dead/missing panel), so the close-time
		-- unsub is belt-and-braces -- but it's still cheap, and required for
		-- correctness if MissionBriefingGui is ever destroyed + recreated
		-- (memoised-lazy today, may not be tomorrow).
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

	-- Update count, plate position+size, visibility. Called from init / show
	-- PostHooks AND from the selection-window's finalize (after a pick the
	-- count must drop without waiting for show()).
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

		-- WIDTH from MENU workspace (NOT from HUD header's :w()): the two
		-- workspaces' saferects may not have identical dimensions, and the
		-- earlier "BG got shorter" report came from inheriting HUD's width
		-- into a smaller menu workspace, getting clipped. CSRMissionBriefing
		-- itself builds its header as fw/2 right-anchored to fw (where fw is
		-- the HUD saferect width); we mirror that formula in MENU workspace
		-- so the plate sits right-half-saferect on whatever the menu's
		-- saferect actually is.
		-- Y still derives from the HUD header's screen position (via world-y
		-- diff) so the plate visually sits exactly under the difficulty row
		-- the player can see, no matter how the workspaces are aligned.
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

		-- Reset hover-derived colour every refresh; stale bright tint can't
		-- persist if the reminder rebuilds.
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
		-- Single hover SFX on the false->true transition. mouse_moved fires
		-- per pixel; this gate keeps it from buzzing.
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

	-- Build the reminder on every init (in practice runs once per session
	-- per the MenuComponentManager memoised lazy-create pattern; the
	-- idempotent _csr_build_reminder guard makes a retry safe). Refresh on
	-- show() so the count + position are correct each time the briefing
	-- screen comes up.
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

	-- Drop the CSRGameManager subscription when the gui closes. Belt-and-braces
	-- against MissionBriefingGui ever becoming non-memoised (today the
	-- MenuComponentManager lazy-creates and never closes the briefing gui mid-
	-- session, but coupling this teardown to close keeps the contract right).
	Hooks:PostHook(MissionBriefingGui, "close", "CSR_BriefingReminderClose", function(self)
		if self._csr_reminder_unsub then
			self._csr_reminder_unsub()
			self._csr_reminder_unsub = nil
		end
	end)

	-- Input wraps. While the modal selection window is up (_G._csr_item_selection
	-- is not nil), MissionBriefingGui must NOT consume any mouse event --
	-- MenuComponentManager:mouse_pressed dispatches MissionBriefingGui BEFORE
	-- it dispatches the alive_components loop, so a truthy return from vanilla
	-- here starves our selection window (priority -100) of clicks entirely.
	-- That was the briefing-side softlock (issue 2): the window opened but
	-- nothing inside could be clicked, because briefing UI under the modal
	-- consumed every click. Returning nil makes MenuComponentManager fall
	-- through to the live-components loop, where the selection window picks
	-- the click up first by priority. Same gate suppresses hover state on
	-- the reminder + every vanilla briefing button (READY / PLAN / ASSETS /
	-- skill tree / mutator toggle / etc.) -- nothing under the modal should
	-- react to the cursor.
	--
	-- When the modal is NOT up, our reminder hit-test runs FIRST -- if our
	-- plate is hit we consume, otherwise pass through to vanilla.
	local orig_mouse_moved = MissionBriefingGui.mouse_moved
	if orig_mouse_moved then
		function MissionBriefingGui:mouse_moved(x, y)
			-- Modal selection window open OR briefing disabled (a sub-screen --
			-- preplanning / loadout / skill tree -- sits on top; vanilla gates
			-- its own input on self._enabled): clear the reminder hover and don't
			-- hit-test. Vanilla returns nil when not self._enabled, so yielding
			-- here matches its contract.
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
			-- Modal open OR briefing disabled (preplanning / loadout / skill tree
			-- on top -- vanilla gates input on self._enabled): don't consume,
			-- don't run the reminder hit-test. Yielding nil lets the modal's live
			-- component pick up the click; when merely disabled vanilla bails to
			-- nil here anyway.
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
