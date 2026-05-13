-- Crime Spree Roguelike - Replace vanilla READY with SELECT ITEM for clients on briefing screen
--
-- Problem: crime_spree_select_modifiers node only exists in menu_main (start_menu),
-- NOT in kit_menu (active during briefing). menu_main is only registered when
-- is_start_menu=true (menumanager.lua:55), so it does not exist during gameplay at all.
--
-- Solution: directly instantiate CrimeSpreeModifiersMenuComponent on the briefing screen,
-- override mouse_pressed/mouse_moved on MissionBriefingGui to forward input to the popup,
-- and override close/back methods on the component instance.
--
-- Input routing: MenuComponentManager:mouse_pressed calls _mission_briefing_gui:mouse_pressed
-- BEFORE run_return_on_all_live_components (menucomponentmanager.lua:1527 vs 1693).
-- So register_component alone does NOT receive input — we must forward events manually.

if not MissionBriefingGui then
	return
end

local COMP_ID = "csr_briefing_selection"

local function has_pending_items()
	if not (managers.crime_spree and managers.crime_spree:is_active()) then
		return false
	end
	-- Belt-and-suspenders: a current job that isn't "crime_spree" means we're on
	-- the briefing for a vanilla heist regardless of any stale gamemode/state
	-- the client may have inherited. Bail out before swapping READY -> SELECT ITEM.
	if managers.job and managers.job.current_job_id then
		local jid = managers.job:current_job_id()
		if jid and jid ~= "crime_spree" then
			return false
		end
	end
	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
	if not is_client then
		return false
	end
	-- Use modifiers_to_select("loud") rather than #my_items < total_drops:
	-- the naive check ignores shop purchases and late-join catchup items,
	-- which inflate #my_items without bumping total_drops and silently
	-- suppress the SELECT ITEM button after the first shop/catchup item.
	if not managers.crime_spree.modifiers_to_select then
		return false
	end
	local ok, pending = pcall(function()
		return managers.crime_spree:modifiers_to_select("loud") or 0
	end)
	return ok and pending and pending > 0 or false
end

local function close_briefing_selection()
	local comp = _G._csr_briefing_comp
	if not comp then
		return
	end
	-- Restore briefing GUI visibility
	local briefing = managers.menu_component and managers.menu_component._mission_briefing_gui
	if briefing then
		if briefing._panel and alive(briefing._panel) then
			briefing._panel:set_visible(true)
		end
		if briefing._fullscreen_panel and alive(briefing._fullscreen_panel) then
			briefing._fullscreen_panel:set_visible(true)
		end
	end
	pcall(function()
		comp:close()
	end)
	if managers.menu_component then
		managers.menu_component:unregister_component(COMP_ID)
	end
	_G._csr_briefing_comp = nil
	log("[CSR Briefing] Selection popup closed")
end

local function open_selection_on_briefing()
	-- Already open
	if _G._csr_briefing_comp then
		return true
	end

	if not CrimeSpreeModifiersMenuComponent then
		log("[CSR Briefing] ERROR: CrimeSpreeModifiersMenuComponent not found")
		return false
	end

	local mcm = managers.menu_component
	if not mcm then
		log("[CSR Briefing] ERROR: managers.menu_component not found")
		return false
	end

	local ws = mcm._ws
	local fullscreen_ws = mcm._fullscreen_ws
	if not ws or not fullscreen_ws then
		log("[CSR Briefing] ERROR: workspaces not found")
		return false
	end

	-- Instantiate the vanilla selection component (node arg is unused — line 4-11)
	local ok, comp =
		pcall(CrimeSpreeModifiersMenuComponent.new, CrimeSpreeModifiersMenuComponent, ws, fullscreen_ws, nil)
	if not ok or not comp then
		log("[CSR Briefing] ERROR: failed to create component: " .. tostring(comp))
		return false
	end

	-- Override _on_back on this instance: close popup instead of managers.menu:back()
	function comp:_on_back()
		close_briefing_selection()
	end

	-- Override _on_finalize_modifier on this instance: same as vanilla but close popup
	-- instead of managers.menu:back() + refresh_node (which would break kit_menu)
	-- Vanilla source: CrimeSpreeModifiersMenuComponent.lua:245-279
	function comp:_on_finalize_modifier()
		if not self._selected_modifier then
			managers.menu:post_event("menu_error")
			return
		end

		managers.crime_spree:select_modifier(self._selected_modifier:data().id)
		managers.menu_component:post_event("item_buy")

		if MenuCallbackHandler and MenuCallbackHandler.save_progress then
			MenuCallbackHandler:save_progress()
		end

		-- Broadcast updated items to peers and refresh items page
		if _G.CSR_MP and CSR_MP.broadcast_own_items then
			CSR_MP.broadcast_own_items()
		end
		if _G.CSR_ItemsPageInstance and _G.CSR_ItemsPageInstance._setup_items then
			pcall(function()
				_G.CSR_ItemsPageInstance:_setup_items()
			end)
		end

		if self:modifiers_to_select() > 0 then
			-- Refresh buttons for next selection (vanilla pattern)
			local modifiers, modifiers_name = self:get_modifers()
			self._text_header:set_text(
				managers.localization:to_upper_text("menu_cs_modifiers_" .. tostring(modifiers_name))
			)
			self._current_num = self._current_num + 1
			self._number_header:set_text(
				managers.experience:cash_string(self._current_num, "")
					.. " / "
					.. managers.experience:cash_string(self._num_to_select, "")
			)
			for i = 1, tweak_data.crime_spree.max_modifiers_displayed do
				self._buttons[i]:set_modifier(modifiers[i])
				self._buttons[i]:set_active(false)
			end
			self:_on_select_modifier(nil)
			if self._selected_item and not self._selected_item._panel:visible() then
				self:_move_selection("left")
			end
		else
			-- All items selected — close popup
			close_briefing_selection()
		end
	end

	-- Hide briefing GUI panels (prevents tooltips/tabs from showing behind popup)
	local briefing = mcm._mission_briefing_gui
	if briefing then
		if briefing._panel and alive(briefing._panel) then
			briefing._panel:set_visible(false)
		end
		if briefing._fullscreen_panel and alive(briefing._fullscreen_panel) then
			briefing._fullscreen_panel:set_visible(false)
		end
	end
	-- Hide CSR items page tooltip (Diesel panels don't propagate visibility to children)
	if _G.CSR_ItemsPageInstance and _G.CSR_ItemsPageInstance._tooltip_panel then
		local tp = _G.CSR_ItemsPageInstance._tooltip_panel
		if alive(tp) then
			tp:set_visible(false)
		end
	end

	-- Register for update() calls (component manager routes update to alive components)
	mcm:register_component(COMP_ID, comp, 100)
	_G._csr_briefing_comp = comp

	log("[CSR Briefing] Selection popup opened")
	return true
end

-- === INPUT FORWARDING ===
-- When popup is open, suppress briefing GUI and forward input to the popup.
-- When popup is closed, pass through to vanilla briefing GUI.

local _orig_mouse_moved = Hooks:GetFunction(MissionBriefingGui, "mouse_moved") or MissionBriefingGui.mouse_moved

Hooks:OverrideFunction(MissionBriefingGui, "mouse_moved", function(self, x, y)
	local comp = _G._csr_briefing_comp
	if comp then
		-- Forward to popup; suppress briefing GUI mouse handling
		local used, pointer = comp:mouse_moved(nil, x, y)
		return used, pointer or "arrow"
	end

	-- Forward to CS details component (ITEMS, PRINTER, MODIFIERS tabs).
	-- MissionBriefingGui:mouse_moved is checked BEFORE run_return_on_all_live_components
	-- (menucomponentmanager.lua:1997 vs 2135), so registered components never get hover events.
	local cs_details = managers.menu_component and managers.menu_component._crime_spree_details
	if cs_details and cs_details.mouse_moved then
		local ok, used, pointer = pcall(cs_details.mouse_moved, cs_details, nil, x, y)
		if ok and used then
			return used, pointer or "arrow"
		end
	end

	return _orig_mouse_moved(self, x, y)
end)

local _orig_mouse_pressed = Hooks:GetFunction(MissionBriefingGui, "mouse_pressed") or MissionBriefingGui.mouse_pressed

Hooks:OverrideFunction(MissionBriefingGui, "mouse_pressed", function(self, button, x, y)
	local comp = _G._csr_briefing_comp
	if comp then
		if button == Idstring("0") then
			-- Forward click to popup
			local consumed = comp:mouse_pressed(nil, button, x, y)
			if consumed then
				return true
			end
		end
		-- Popup is open but click was outside buttons — suppress briefing GUI
		return
	end

	-- Forward to CS details component (ITEMS, PRINTER, MODIFIERS tabs).
	-- MissionBriefingGui:mouse_pressed always returns self._selected_item (truthy),
	-- so registered components never receive click events during briefing
	-- (menucomponentmanager.lua:1527 eats them before run_return_on_all_live_components:1693).
	local cs_details = managers.menu_component and managers.menu_component._crime_spree_details
	if cs_details and button == Idstring("0") then
		local ok, used = pcall(cs_details.mouse_pressed, cs_details, button, x, y)
		if ok and used then
			return true
		end
	end

	return _orig_mouse_pressed(self, button, x, y)
end)

-- (Removed dead mouse_clicked override on MissionBriefingGui — vanilla
-- MenuComponentManager:mouse_clicked only dispatches to blackmarket_gui,
-- skilltree_gui, and run_return_on_all_live_components, never to
-- _mission_briefing_gui:mouse_clicked. The override was unreachable.)

-- Store original on_ready_pressed
local _orig_on_ready_pressed = Hooks:GetFunction(MissionBriefingGui, "on_ready_pressed")
	or MissionBriefingGui.on_ready_pressed

Hooks:OverrideFunction(MissionBriefingGui, "on_ready_pressed", function(self, ready)
	if has_pending_items() then
		log("[CSR Briefing] SELECT ITEM pressed, opening selection popup")
		local opened = open_selection_on_briefing()
		if opened then
			return
		end
		log("[CSR Briefing] Popup failed to open, falling through to vanilla ready")
	end
	return _orig_on_ready_pressed(self, ready)
end)

-- Override ready_text to show SELECT ITEM when items pending
local _orig_ready_text = Hooks:GetFunction(MissionBriefingGui, "ready_text") or MissionBriefingGui.ready_text

Hooks:OverrideFunction(MissionBriefingGui, "ready_text", function(self)
	if has_pending_items() then
		return utf8.to_upper(managers.localization:text("menu_cs_select_modifier"))
	end
	return _orig_ready_text(self)
end)

-- Handle confirm (Enter) and back (Escape) keyboard input
local _orig_confirm_pressed = Hooks:GetFunction(MissionBriefingGui, "confirm_pressed")
	or MissionBriefingGui.confirm_pressed

Hooks:OverrideFunction(MissionBriefingGui, "confirm_pressed", function(self)
	local comp = _G._csr_briefing_comp
	if comp then
		comp:confirm_pressed()
		return true
	end
	return _orig_confirm_pressed(self)
end)

local _orig_back_pressed = Hooks:GetFunction(MissionBriefingGui, "back_pressed") or MissionBriefingGui.back_pressed

Hooks:OverrideFunction(MissionBriefingGui, "back_pressed", function(self)
	local comp = _G._csr_briefing_comp
	if comp then
		close_briefing_selection()
		return true
	end
	return _orig_back_pressed(self)
end)

-- PostHook on update to keep button text in sync after item selection
Hooks:PostHook(MissionBriefingGui, "update", "CSR_BriefingSelectItem_Update", function(self, t, dt)
	if not self._ready_button or not alive(self._ready_button) then
		return
	end

	-- Close popup if items are no longer pending (e.g. auto-fill happened elsewhere)
	if _G._csr_briefing_comp and not has_pending_items() then
		close_briefing_selection()
	end

	local pending = has_pending_items()
	local expected_text = pending and utf8.to_upper(managers.localization:text("menu_cs_select_modifier"))
		or self:ready_text()

	-- Only update if text changed to avoid constant set_text calls
	if self._csr_last_ready_text ~= expected_text then
		self._csr_last_ready_text = expected_text
		self._ready_button:set_text(expected_text)

		-- Resize after text change (vanilla pattern from missionbriefinggui.lua:3601-3603)
		local _, _, w, h = self._ready_button:text_rect()
		self._ready_button:set_size(w, h)

		-- Update big background text if it exists
		if self._fullscreen_panel and alive(self._fullscreen_panel) then
			local big = self._fullscreen_panel:child("ready_big_text")
			if big and alive(big) then
				big:set_text(expected_text)
				local _, _, bw, bh = big:text_rect()
				big:set_size(bw, bh)
			end
		end

		-- Reposition relative to tick box (vanilla pattern: missionbriefinggui.lua:3617-3618).
		-- Compat mods (e.g. HoloUI) can override via CSR_BriefingReadyButtonReposition.
		if _G.CSR_BriefingReadyButtonReposition then
			CSR_BriefingReadyButtonReposition(self)
		elseif self._ready_tick_box and alive(self._ready_tick_box) then
			self._ready_button:set_center_y(self._ready_tick_box:center_y())
			self._ready_button:set_right(self._ready_tick_box:left() - 5)
		end
	end
end)

-- Clean up on briefing close
Hooks:PostHook(MissionBriefingGui, "close", "CSR_BriefingSelectItem_Close", function(self)
	close_briefing_selection()
end)

log("[CSR] Briefing SELECT ITEM override loaded (direct component + input forwarding)")
