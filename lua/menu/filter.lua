-- Crime Spree Roguelike Alpha 1 - Enable filter for Modifiers tab UI

if not RequiredScript then
	return
end

-- Hook on add_modifiers_panel - enable filter before rendering
if CrimeSpreeModifierDetailsPage then
	Hooks:PreHook(CrimeSpreeModifierDetailsPage, "add_modifiers_panel", "CSR_EnableFilter", function(self)
		CSR_FilterForUI = true
	end)

	Hooks:PostHook(CrimeSpreeModifierDetailsPage, "add_modifiers_panel", "CSR_DisableFilter", function(self)
		CSR_FilterForUI = false
	end)

	-- Fix: _setup_panel_size() sets the component panel to 50% workspace height, which
	-- clips the Modifiers scroll. The STATS page fixes this via _expand_parents() when
	-- activated, but ITEMS (tab 1) activates first. Reuse the same expand logic here
	-- so parent panels are expanded from the very first tab activation.
	Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "init", "CSR_ExpandParentsOnInit", function(self)
		-- Widen tabs panel to full parent width (VHUDPlus also does this in _add_panels)
		if self._tabs_panel and alive(self._tabs_panel) then
			local parent = self._tabs_panel:parent()
			if parent and alive(parent) then
				self._tabs_panel:set_w(parent:w())
				if self._tabs_scroll_panel and alive(self._tabs_scroll_panel) then
					self._tabs_scroll_panel:set_w(parent:w())
				end
			end
		end

		-- Compress tab gaps when tabs overflow (VHUDPlus adds CREW SETUP + HIDE = 7 tabs total)
		if self._tabs_scroll_panel and alive(self._tabs_scroll_panel) then
			local children = self._tabs_scroll_panel:children()
			if #children > 0 then
				local last_child = children[#children]
				local available_w = self._tabs_scroll_panel:w()

				if last_child:right() > available_w then
					local total_tabs_w = 0
					for _, child in ipairs(children) do
						total_tabs_w = total_tabs_w + child:w()
					end
					local gaps = math.max(#children - 1, 1)
					local new_gap = math.max(2, math.floor((available_w - total_tabs_w) / gaps))

					local x = 0
					for _, child in ipairs(children) do
						child:set_x(x)
						x = x + child:w() + new_gap
					end
				end
			end
		end

		-- Add padlock icon to LOGBOOK tab when locked (reward_level > 0)
		if self._tabs and #self._tabs > 0 then
			local logbook_tab = self._tabs[#self._tabs]
			local is_locked = managers.crime_spree:reward_level() > 0
			if logbook_tab and logbook_tab.tab and is_locked then
				-- MenuGuiTabItem stores its panel in _page_item's parent children
				-- Access via the tab scroll panel's last child
				local tab_children = self._tabs_scroll_panel and self._tabs_scroll_panel:children() or {}
				local tab_panel = tab_children[#tab_children]
				if tab_panel and alive(tab_panel) then
					local lock_size = 16
					-- Place lock on component panel, positioned right next to the text
					local page_text = tab_panel:child("PageText")
					local lock = self._panel:bitmap({
						name = "csr_logbook_lock",
						texture = "guis/textures/pd2/skilltree/padlock",
						w = lock_size,
						h = lock_size,
						layer = 10,
						color = Color(0.6, 0.6, 0.6),
					})
					local panel_wx = self._panel:world_x()
					local panel_wy = self._panel:world_y()
					if page_text then
						-- Find where the text actually starts (center-aligned)
						local _, _, tw, _ = page_text:text_rect()
						local text_world_x = tab_panel:world_x() + (tab_panel:w() - tw) / 2
						lock:set_right(text_world_x - panel_wx - 1)
					else
						lock:set_right(tab_panel:world_x() - panel_wx - 1)
					end
					lock:set_center_y(tab_panel:world_y() - panel_wy + tab_panel:h() / 2 - 1)

					-- Build fixed tooltip above the tab, on the component panel
					local tooltip_text = "Available before the first heist"
					local padding = 8
					local tooltip_w = 240
					local tmp = self._panel:text({
						visible = false,
						text = tooltip_text,
						font = tweak_data.menu.pd2_small_font,
						font_size = tweak_data.menu.pd2_small_font_size,
						w = tooltip_w - padding * 2,
						wrap = true,
						word_wrap = true,
						layer = -999,
					})
					local _, _, _, th = tmp:text_rect()
					self._panel:remove(tmp)
					local tooltip_h = th + padding * 2

					-- Position: centered above the tab panel, clamped to panel bounds
					local tab_wx = tab_panel:world_x()
					local tab_wy = tab_panel:world_y()
					local panel_wx = self._panel:world_x()
					local panel_wy = self._panel:world_y()
					local tx = tab_wx - panel_wx + tab_panel:w() / 2 - tooltip_w / 2
					local ty = tab_wy - panel_wy - tooltip_h - 6
					-- Clamp so tooltip doesn't extend past panel edges
					tx = math.max(0, math.min(tx, self._panel:w() - tooltip_w))

					local border_color = Color(0.5, 0.5, 0.5)
					local border_size = 1

					local tooltip = self._panel:panel({
						name = "csr_logbook_tooltip",
						x = tx,
						y = ty,
						w = tooltip_w,
						h = tooltip_h,
						layer = 100,
						visible = false,
					})
					tooltip:rect({ x = 0, y = 0, w = tooltip_w, h = tooltip_h, color = Color.black, alpha = 0.88 })
					tooltip:rect({
						x = 0,
						y = 0,
						w = tooltip_w,
						h = border_size,
						color = border_color,
						alpha = 0.5,
						layer = 1,
					})
					tooltip:rect({
						x = 0,
						y = tooltip_h - border_size,
						w = tooltip_w,
						h = border_size,
						color = border_color,
						alpha = 0.5,
						layer = 1,
					})
					tooltip:rect({
						x = 0,
						y = 0,
						w = border_size,
						h = tooltip_h,
						color = border_color,
						alpha = 0.5,
						layer = 1,
					})
					tooltip:rect({
						x = tooltip_w - border_size,
						y = 0,
						w = border_size,
						h = tooltip_h,
						color = border_color,
						alpha = 0.5,
						layer = 1,
					})
					tooltip:text({
						text = tooltip_text,
						font = tweak_data.menu.pd2_small_font,
						font_size = tweak_data.menu.pd2_small_font_size,
						color = Color(0.9, 0.9, 0.9),
						align = "center",
						vertical = "center",
						x = padding,
						y = padding,
						w = tooltip_w - padding * 2,
						h = tooltip_h - padding * 2,
						layer = 2,
					})

					self._csr_logbook_tooltip = tooltip
					self._csr_logbook_tab_panel = tab_panel
					self._csr_logbook_locked = true
				end
			end
		end

		-- Find any tab page that has _expand_parents (STATS page)
		for _, tab_data in ipairs(self._tabs or {}) do
			local page = tab_data.page
			if page and page._expand_parents then
				page:_expand_parents()
				break
			end
		end
	end)

	-- Fix: vanilla tab system relies on mouse_moved reaching crime_spree_details via
	-- run_return_on_all_live_components. An earlier component returns false (not nil),
	-- stopping iteration. Result: no hover highlight, no cursor change, no tab switching.
	--
	-- Fix part 1: MenuUpdate hook polls mouse and runs tab hover directly every frame
	-- Sets _csr_tab_hover flag so cursor override (part 1b) knows to show "link"
	Hooks:Add("MenuUpdate", "CSR_TabHoverFix", function(t, dt)
		local mc = managers.menu_component
		if not mc then
			return
		end
		local comp = mc._crime_spree_details
		if not comp then
			return
		end
		if not comp._tabs or #comp._tabs < 2 then
			return
		end
		if not managers.mouse_pointer then
			return
		end

		local x, y = managers.mouse_pointer:modified_mouse_pos()
		if not x then
			return
		end

		-- Deselect old tab if mouse moved away
		if comp._selected_tab and not comp._selected_tab:inside(x, y) then
			comp._selected_tab:set_selected(false)
			comp._selected_tab = nil
		end

		-- Check all tabs for hover
		_G.CSR_TabHover = false
		if not comp._selected_tab then
			for _, tab_data in ipairs(comp._tabs) do
				if tab_data.tab and tab_data.tab:inside(x, y) then
					tab_data.tab:set_selected(true)
					comp._selected_tab = tab_data.tab
					_G.CSR_TabHover = true
					return
				end
			end
		else
			_G.CSR_TabHover = not comp._selected_tab:is_active()
		end
	end)

	-- Fix part 1b: cursor override — vanilla MenuInput:mouse_moved sets "arrow" at the end.
	-- PostHook runs after that and forces "link" when hovering a CS tab.
	Hooks:PostHook(MenuInput, "mouse_moved", "CSR_TabCursorFix", function(self)
		if _G.CSR_TabHover and managers.mouse_pointer then
			managers.mouse_pointer:set_pointer_image("link")
		end
	end)

	-- Fix part 2: PostHook on mouse_clicked — direct tab hit test as fallback
	Hooks:PostHook(MenuGuiComponentGeneric, "mouse_clicked", "CSR_DirectTabClick", function(self, o, button, x, y)
		if button ~= Idstring("0") then
			return
		end
		if not self._tabs or #self._tabs < 2 then
			return
		end

		-- If hover already set _selected_tab, vanilla handled it — skip
		if self._selected_tab then
			return
		end

		-- Direct hit test on each tab
		for _, tab_data in ipairs(self._tabs) do
			if tab_data.tab and tab_data.tab:inside(x, y) then
				self:set_active_page(tab_data.tab:index(), true)
				return
			end
		end
	end)

	-- Tooltip for locked LOGBOOK tab on hover
	Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "mouse_moved", "CSR_LogbookTooltip", function(self, o, x, y)
		if not self._csr_logbook_locked then
			return
		end
		local tp = self._csr_logbook_tab_panel
		local tooltip = self._csr_logbook_tooltip
		if not tp or not alive(tp) or not tooltip or not alive(tooltip) then
			return
		end

		if tp:inside(x, y) then
			tooltip:set_visible(true)
		else
			tooltip:set_visible(false)
		end
	end)
else
end
