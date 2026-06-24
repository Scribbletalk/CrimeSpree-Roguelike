-- Logbook menu: catalogue grid, item details, statistics, achievements tabs.

if not RequiredScript then
	return
end

-- Rarity tint colours (must include contraband for palette completeness)
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 0.95, 0),
	rare = Color(0, 0.5, 1),
	contraband = Color(1, 0.5, 0),
	wildcard = Color(1, 0.3, 0.8),
}

-- Icon grid layout constants
local GRID_FRAME_SIZE = 90
local GRID_ICON_SIZE = 48
local GRID_PADDING_X = -2
local GRID_PADDING_Y = -2
local GRID_ITEMS_PER_ROW = 10
local GRID_MARGIN_X = 0
local GRID_MARGIN_Y = 0

-- Items-tab vertical layout constants — tightened so a 4th icon row fits within the same box.
local GRID_ROWS_PER_PAGE = 4
local TAB_BAR_TOP = 24 -- tab bar y inside the content box (was 60)
local TAB_BAR_HEIGHT = 30
local ITEMS_PANEL_TOP = 66 -- items-tab panel y inside the content box (was 100)
local ITEMS_PANEL_BOTTOM_PAD = 12 -- gap below the items panel inside the box (was 20)
local GRID_INNER_TOP = 16 -- grid y inside the items panel (was 30)
local GRID_NAV_RESERVE = 40 -- page-nav row budget at the items-panel bottom (was 44)

-- Logbook-only icon scale overrides (wildcard-sized items).
local LOGBOOK_ICON_SCALE = {
	csr_side_satchel = 0.9,
	csr_hippocratic_oath = 0.9,
}

-- Rarity frame icons — all share the same frame texture to avoid sizing issues.
local RARITY_FRAMES = {
	common = { frame = "csr_frame", color = Color.white },
	uncommon = { frame = "csr_frame", color = Color(0, 0.95, 0) },
	rare = { frame = "csr_frame", color = Color(0.3, 0.7, 1) },
	contraband = { frame = "csr_frame", color = Color(1, 0.4, 0) },
	wildcard = { frame = "csr_frame", color = Color(1, 0.3, 0.8) },
}

-- Sort order for the grid: rarity tier then name.
local RARITY_ORDER = {
	common = 1,
	uncommon = 2,
	rare = 3,
	contraband = 4,
	wildcard = 5,
}

CrimeSpreeLogbookMenuComponent = CrimeSpreeLogbookMenuComponent or class()

-- Hide the end-screen UI and block its input while the logbook overlay is open.
function CrimeSpreeLogbookMenuComponent:_suppress_endscreen()
	local mc = managers.menu_component
	if not mc then
		return
	end

	local sg = mc._stage_endscreen_gui
	if sg then
		self._sg_was_enabled = sg._enabled
		if sg.hide then
			sg:hide()
		end
		if sg._panel and alive(sg._panel) then
			self._sg_panel_was_visible = sg._panel:visible()
			sg._panel:set_visible(false)
		end
		if sg._fullscreen_panel and alive(sg._fullscreen_panel) then
			self._sg_fs_panel_was_visible = sg._fullscreen_panel:visible()
			sg._fullscreen_panel:set_visible(false)
		end
	end

	local cme = mc._crime_spree_mission_end
	if cme then
		if cme._panel and alive(cme._panel) then
			self._cme_panel_was_visible = cme._panel:visible()
			cme._panel:set_visible(false)
		end
		if cme._fullscreen_panel and alive(cme._fullscreen_panel) then
			self._cme_fs_panel_was_visible = cme._fullscreen_panel:visible()
			cme._fullscreen_panel:set_visible(false)
		end
		self._cme_instance = cme
		cme.mouse_pressed = function()
			return nil
		end
		cme.mouse_moved = function()
			return nil
		end
	end
end

function CrimeSpreeLogbookMenuComponent:_restore_endscreen()
	local mc = managers.menu_component
	if not mc then
		return
	end

	local sg = mc._stage_endscreen_gui
	if sg then
		if self._sg_panel_was_visible ~= nil and sg._panel and alive(sg._panel) then
			sg._panel:set_visible(self._sg_panel_was_visible)
		end
		if self._sg_fs_panel_was_visible ~= nil and sg._fullscreen_panel and alive(sg._fullscreen_panel) then
			sg._fullscreen_panel:set_visible(self._sg_fs_panel_was_visible)
		end
		if self._sg_was_enabled and sg.show then
			sg:show()
		end
	end

	local cme = self._cme_instance
	if cme then
		if self._cme_panel_was_visible ~= nil and cme._panel and alive(cme._panel) then
			cme._panel:set_visible(self._cme_panel_was_visible)
		end
		if self._cme_fs_panel_was_visible ~= nil and cme._fullscreen_panel and alive(cme._fullscreen_panel) then
			cme._fullscreen_panel:set_visible(self._cme_fs_panel_was_visible)
		end
		cme.mouse_pressed = nil
		cme.mouse_moved = nil
	end

	self._sg_was_enabled = nil
	self._sg_panel_was_visible = nil
	self._sg_fs_panel_was_visible = nil
	self._cme_instance = nil
	self._cme_panel_was_visible = nil
	self._cme_fs_panel_was_visible = nil
end

-- Hide the mission-name title (MissionBriefingGui._panel + HUDMissionBriefing job_text layers) while open.
-- Vanilla :hide() only dims to 0.5 and doesn't touch the HUD layer, so both must be hidden manually.
function CrimeSpreeLogbookMenuComponent:_suppress_briefing()
	local mbg = managers.menu_component and managers.menu_component._mission_briefing_gui
	if mbg and mbg._panel and alive(mbg._panel) then
		self._mbg = mbg
		self._mbg_panel_was_visible = mbg._panel:visible()
		mbg._panel:set_visible(false)
	end

	local hud = managers.hud and managers.hud._hud_mission_briefing
	if hud then
		local fg = hud._foreground_layer_one
		local bg = hud._background_layer_three
		self._mb_job_text_fg = fg and alive(fg) and fg:child("job_text") or nil
		self._mb_job_text_bg = bg and alive(bg) and bg:child("job_text") or nil
		if self._mb_job_text_fg then
			self._mb_job_text_fg:set_visible(false)
		end
		if self._mb_job_text_bg then
			self._mb_job_text_bg:set_visible(false)
		end
	end
end

function CrimeSpreeLogbookMenuComponent:_restore_briefing()
	local mbg = self._mbg
	if mbg and self._mbg_panel_was_visible ~= nil and mbg._panel and alive(mbg._panel) then
		mbg._panel:set_visible(self._mbg_panel_was_visible)
	end
	if self._mb_job_text_fg and alive(self._mb_job_text_fg) then
		self._mb_job_text_fg:set_visible(true)
	end
	if self._mb_job_text_bg and alive(self._mb_job_text_bg) then
		self._mb_job_text_bg:set_visible(true)
	end
	self._mbg = nil
	self._mbg_panel_was_visible = nil
	self._mb_job_text_fg = nil
	self._mb_job_text_bg = nil
end

function CrimeSpreeLogbookMenuComponent:init(ws, fullscreen_ws, node)
	if not ws or not fullscreen_ws then
		return
	end

	if not managers or not managers.menu then
		return
	end

	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()

	self._items = {}
	self._hovered_item = nil
	self._selected_item = nil
	self._tooltip = nil
	self._input_focus = 1
	self._current_tab = "items"
	self._tab_buttons = {}
	self._tab_panels = {}
	self._page = 1

	self:_setup_logbook()
	self:_suppress_endscreen()
	self:_suppress_briefing()
end

function CrimeSpreeLogbookMenuComponent:close()
	self:_set_back_enabled(true)
	self:_restore_endscreen()
	self:_restore_briefing()
	if self._panel and alive(self._panel) and self._ws then
		self._ws:panel():remove(self._panel)
	end
end

function CrimeSpreeLogbookMenuComponent:input_focus()
	return self._input_focus or 0
end

-- Disable back-nav while details are open so ESC closes details, not the logbook.
function CrimeSpreeLogbookMenuComponent:_set_back_enabled(enabled)
	local active_menu = managers.menu and managers.menu:active_menu()
	if active_menu and active_menu.input then
		active_menu.input:set_back_enabled(enabled)
	end
end

function CrimeSpreeLogbookMenuComponent:back_pressed()
	if self._selected_item and self._content_panel then
		managers.menu_component:post_event("menu_back")
		self:_close_details()
		self:_set_back_enabled(true)
		return true
	end
end

function CrimeSpreeLogbookMenuComponent:_close_details()
	if self._details_panel and alive(self._details_panel) then
		self._panel:remove(self._details_panel)
		self._details_panel = nil
	end
	if self._content_panel and alive(self._content_panel) then
		self._content_panel:set_visible(true)
	end
	self._selected_item = nil
	self:_set_back_enabled(true)
end

function CrimeSpreeLogbookMenuComponent:_setup_logbook()
	-- Clear the "new item" flag so the "!" on the LOGBOOK button disappears.
	if _G.CSR_Logbook then
		_G.CSR_Logbook:clear_new()
		pcall(function()
			managers.menu:active_menu().logic:refresh_node("crime_spree_lobby")
		end)
	end

	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = parent:panel({
		name = "logbook_panel",
		layer = self._init_layer + 10,
	})

	local panel_w = 940
	-- Same height formula as BlackMarketGui: scales with workspace resolution.
	local grid_h_mul = (NOT_WIN_32 and 6.9 or 6.95) / 8
	local panel_h = math.floor((self._panel:h() - 70) * grid_h_mul)

	self._content_panel = self._panel:panel({
		name = "content_panel",
		w = panel_w,
		h = panel_h,
		layer = 10,
	})

	self._content_panel:set_center_x(self._panel:w() / 2)
	self._content_panel:set_center_y(self._panel:h() / 2)

	self._content_panel:rect({
		color = Color.black,
		alpha = 0.92,
		layer = -1,
	})

	BoxGuiObject:new(self._content_panel, {
		sides = { 2, 2, 2, 2 },
	})

	-- Header: pd2_large label over a faded pd2_massive ghost, same pattern as the lobby title.
	local header_label = managers.localization:text("csr_logbook_title")
	local header_ghost = self._panel:text({
		name = "csr_header_ghost",
		vertical = "top",
		align = "left",
		alpha = 0.4,
		h = 90,
		text = header_label,
		font = tweak_data.menu.pd2_massive_font,
		font_size = tweak_data.menu.pd2_massive_font_size,
		color = tweak_data.screen_colors.button_stage_3,
		layer = 5,
	})
	local header = self._panel:text({
		name = "csr_header",
		vertical = "top",
		align = "left",
		text = header_label,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = tweak_data.screen_colors.text,
		layer = 60,
	})
	local _, _, header_w, header_h = header:text_rect()
	header:set_size(header_w, header_h)
	header:set_left(0)
	header:set_top(0)
	header_ghost:set_world_left(header:world_left())
	header_ghost:set_world_center_y(header:world_center_y())
	header_ghost:move(-13, 9)

	-- BACK button, bottom-right of the outer panel — mirrors BlackMarketGui's layout.
	self._back_button = self._panel:text({
		name = "csr_back_button",
		vertical = "bottom",
		align = "right",
		text = utf8.to_upper(managers.localization:text("menu_back")),
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = tweak_data.screen_colors.button_stage_3,
		layer = 60,
	})
	local _, _, back_w, back_h = self._back_button:text_rect()
	self._back_button:set_size(back_w, back_h)
	self._back_button:set_right(self._panel:w())
	self._back_button:set_bottom(self._panel:h())

	self:_create_tabs()
	self:_create_tab_panels()
	self:_switch_tab("items")
end

function CrimeSpreeLogbookMenuComponent:_create_tabs()
	local tabs = {
		{ id = "items", label = managers.localization:text("csr_logbook_tab_items") },
		{ id = "statistics", label = managers.localization:text("csr_logbook_tab_statistics") },
		{ id = "achievements", label = managers.localization:text("csr_logbook_tab_achievements") },
	}

	local panel_w = self._content_panel:w()
	local grid_total_w = GRID_ITEMS_PER_ROW * (GRID_FRAME_SIZE + GRID_PADDING_X) - GRID_PADDING_X + GRID_MARGIN_X * 2
	local margin_left = math.floor((panel_w - grid_total_w) / 2)
	local margin_right = margin_left
	local tab_spacing = 10
	local tab_height = TAB_BAR_HEIGHT
	local start_y = TAB_BAR_TOP

	local available_width = panel_w - margin_left - margin_right - (tab_spacing * (#tabs - 1))
	local tab_width = available_width / #tabs

	for i, tab_data in ipairs(tabs) do
		local x = margin_left + (i - 1) * (tab_width + tab_spacing)

		local tab_bg = self._content_panel:rect({
			name = "tab_bg_" .. tab_data.id,
			color = Color(0.2, 0.2, 0.2),
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 5,
		})

		local tab_text = self._content_panel:text({
			name = "tab_text_" .. tab_data.id,
			text = tab_data.label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			align = "center",
			vertical = "center",
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 6,
		})

		self._tab_buttons[tab_data.id] = {
			bg = tab_bg,
			text = tab_text,
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
		}
	end

	self._content_panel:rect({
		name = "tabs_divider",
		color = Color(0.4, 0.4, 0.4),
		x = margin_left,
		y = start_y + tab_height + 5,
		w = panel_w - margin_left - margin_right,
		h = 2,
		layer = 5,
	})
end

function CrimeSpreeLogbookMenuComponent:_create_tab_panels()
	local panel_x = 20
	local panel_y = ITEMS_PANEL_TOP
	local panel_w = self._content_panel:w() - 40
	local panel_h = self._content_panel:h() - panel_y - ITEMS_PANEL_BOTTOM_PAD

	self._tab_panels["items"] = self._content_panel:panel({
		name = "items_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8,
	})

	self._tab_panels["statistics"] = self._content_panel:panel({
		name = "statistics_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8,
	})

	self._tab_panels["achievements"] = self._content_panel:panel({
		name = "achievements_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8,
	})

	self:_populate_items_tab()
	self:_populate_statistics_tab()
	self:_populate_achievements_tab()
end

function CrimeSpreeLogbookMenuComponent:_switch_tab(tab_id)
	self._current_tab = tab_id

	for id, button in pairs(self._tab_buttons) do
		if id == tab_id then
			button.bg:set_color(Color(0.85, 0.7, 0.2))
			button.text:set_color(Color.black)
		else
			button.bg:set_color(Color(0.15, 0.15, 0.15))
			button.text:set_color(Color(0.5, 0.5, 0.5))
		end
	end

	for id, panel in pairs(self._tab_panels) do
		panel:set_visible(id == tab_id)
	end

	if tab_id == "statistics" then
		local panel = self._tab_panels["statistics"]
		if panel and alive(panel) then
			panel:clear()
			self._stats_panel_ref = panel
			self:_create_statistics()
			self._stats_panel_ref = nil
		end
	end
end

function CrimeSpreeLogbookMenuComponent:_populate_items_tab()
	self._items_list = self:_build_items_list()
	self._page = self._page or 1
	self:_render_items_page()
end

-- Build the sorted catalogue from the live registry.
function CrimeSpreeLogbookMenuComponent:_build_items_list()
	local list = {}
	local reg = (managers.csr and managers.csr.registered_items) and managers.csr:registered_items() or {}
	for _, e in ipairs(reg) do
		-- Scrap is shown but has no _effect/_notes keys; detail view falls back to desc.
		list[#list + 1] = {
			id = e.type,
			icon = e.icon,
			rarity = e.rarity,
			is_scrap = e.is_scrap or nil,
			loc_macros = e.loc_macros,
			name_en = string.upper((e.name and managers.localization:text(e.name)) or tostring(e.type)),
			effect_en = (e.full_desc and _G.CSR.item_text(e.full_desc, e))
				or (e.desc and _G.CSR.item_text(e.desc, e))
				or "",
			community = e.addon ~= nil or nil,
		}
	end
	table.sort(list, function(a, b)
		local ra = RARITY_ORDER[a.rarity] or 99
		local rb = RARITY_ORDER[b.rarity] or 99
		if ra ~= rb then
			return ra < rb
		end
		-- Scrap sinks to end of its tier.
		local sa, sb = a.is_scrap and 1 or 0, b.is_scrap and 1 or 0
		if sa ~= sb then
			return sa < sb
		end
		return tostring(a.name_en) < tostring(b.name_en)
	end)
	return list
end

-- Rows per page: capped at GRID_ROWS_PER_PAGE, drops on short workspaces.
function CrimeSpreeLogbookMenuComponent:_grid_rows_per_page()
	local panel = self._tab_panels and self._tab_panels["items"]
	local h = (panel and alive(panel) and panel:h()) or 480
	local fit = math.max(1, math.floor((h - GRID_INNER_TOP - GRID_NAV_RESERVE) / (GRID_FRAME_SIZE + GRID_PADDING_Y)))
	return math.min(GRID_ROWS_PER_PAGE, fit)
end

function CrimeSpreeLogbookMenuComponent:_items_per_page()
	return self:_grid_rows_per_page() * GRID_ITEMS_PER_ROW
end

function CrimeSpreeLogbookMenuComponent:_render_items_page()
	local panel = self._tab_panels and self._tab_panels["items"]
	if not panel or not alive(panel) then
		return
	end
	local per_page = self:_items_per_page()
	local total_pages = math.max(1, math.ceil(#(self._items_list or {}) / per_page))
	self._page = math.max(1, math.min(self._page or 1, total_pages))

	panel:clear()
	self._items = {}
	self._hovered_item = nil
	self._prev_btn_panel = nil
	self._next_btn_panel = nil

	self._items_panel_ref = panel
	self:_create_icons_grid()
	self:_create_page_nav(total_pages)
	self._items_panel_ref = nil
end

-- Page nav row at the bottom; arrows dim and are inert at the edges.
function CrimeSpreeLogbookMenuComponent:_create_page_nav(total_pages)
	if not total_pages or total_pages <= 1 then
		return
	end
	local panel = self._items_panel_ref
	if not panel or not alive(panel) then
		return
	end
	local page = self._page or 1
	local nav_h = 36
	local nav_y = panel:h() - nav_h
	local cx = panel:w() / 2
	local label_w = 200
	local arrow_w = 40

	panel:text({
		name = "page_indicator",
		text = string.format("PAGE %d / %d", page, total_pages),
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color.white,
		align = "center",
		vertical = "center",
		x = cx - label_w / 2,
		y = nav_y,
		w = label_w,
		h = nav_h,
		layer = 6,
	})

	self._prev_btn_panel = panel:panel({
		name = "prev_btn",
		x = cx - label_w / 2 - arrow_w - 10,
		y = nav_y,
		w = arrow_w,
		h = nav_h,
		layer = 6,
	})
	self._prev_btn_panel:text({
		name = "prev_arrow",
		text = "<",
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = page <= 1 and Color(1, 0.4, 0.4, 0.4) or tweak_data.screen_colors.button_stage_3,
		align = "center",
		vertical = "center",
		w = arrow_w,
		h = nav_h,
		layer = 6,
	})

	self._next_btn_panel = panel:panel({
		name = "next_btn",
		x = cx + label_w / 2 + 10,
		y = nav_y,
		w = arrow_w,
		h = nav_h,
		layer = 6,
	})
	self._next_btn_panel:text({
		name = "next_arrow",
		text = ">",
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = page >= total_pages and Color(1, 0.4, 0.4, 0.4) or tweak_data.screen_colors.button_stage_3,
		align = "center",
		vertical = "center",
		w = arrow_w,
		h = nav_h,
		layer = 6,
	})
end

function CrimeSpreeLogbookMenuComponent:_populate_statistics_tab()
	self._stats_panel_ref = self._tab_panels["statistics"]
	self:_create_statistics()
	self._stats_panel_ref = nil
end

function CrimeSpreeLogbookMenuComponent:_populate_achievements_tab()
	local panel = self._tab_panels["achievements"]
	local placeholder = managers.localization:text("csr_logbook_achievements_placeholder")

	panel:text({
		name = "achievements_placeholder",
		text = placeholder,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.text,
		align = "center",
		vertical = "center",
		w = panel:w(),
		h = panel:h(),
		layer = 10,
	})
end

-- Three-column career-stats board: RECORDS / TOTALS / ITEMS.
-- Values from career_stat(); Items Unlocked reads CSR_Logbook progress directly.
function CrimeSpreeLogbookMenuComponent:_create_statistics()
	local panel = self._stats_panel_ref or self._content_panel
	local loc = managers.localization
	local mgr = managers.csr

	local function career(key)
		return (mgr and mgr.career_stat and mgr:career_stat(key, 0)) or 0
	end

	-- Thousands separator, integer-only.
	local function fmt(num)
		local s = tostring(math.floor(tonumber(num) or 0))
		local k
		repeat
			s, k = string.gsub(s, "^(-?%d+)(%d%d%d)", "%1,%2")
		until k == 0
		return s
	end

	-- Compact suffix form for large numbers: 1 234 567 → "1.2M", 45 000 → "45.0K".
	local function fmt_compact(num)
		local n = math.floor(tonumber(num) or 0)
		if n >= 1e9 then
			return string.format("%.1fB", n / 1e9)
		elseif n >= 1e6 then
			return string.format("%.1fM", n / 1e6)
		elseif n >= 1e3 then
			return string.format("%.1fK", n / 1e3)
		end
		return tostring(n)
	end

	-- Cross-check registry vs unlock dict: stale save keys and is_scrap entries don't inflate counters.
	local total_items = 0
	local unlocked_items = 0
	if mgr and mgr.registered_items then
		local unlocked_set = (
			_G.CSR_Logbook
			and _G.CSR_Logbook.get_unlocked_items
			and _G.CSR_Logbook:get_unlocked_items()
		) or {}
		for _, def in ipairs(mgr:registered_items()) do
			if not def.is_scrap then
				total_items = total_items + 1
				if unlocked_set[def.type] then
					unlocked_items = unlocked_items + 1
				end
			end
		end
	end

	-- Favorite wildcard = the wildcard with the most completed heists (localized name; "None" until
	-- a heist is finished while holding one).
	local fav_wildcard_name = loc:text("csr_logbook_none")
	local fav_type = mgr and mgr.favorite_wildcard and mgr:favorite_wildcard()
	if fav_type then
		local def = mgr.item_def and mgr:item_def(fav_type)
		fav_wildcard_name = (def and def.name and loc:text(def.name)) or fav_type
	end

	local columns = {
		{
			header = loc:text("csr_logbook_col_records"),
			rows = {
				{ label = loc:text("csr_logbook_stat_rank"), value = fmt(career("highest_rank")) },
				{
					label = loc:text("csr_logbook_stat_longest_spree"),
					value = fmt(career("longest_spree")) .. " " .. loc:text("csr_logbook_unit_missions"),
				},
				{ label = loc:text("csr_logbook_stat_most_purchases"), value = fmt(career("most_purchases")) },
				{ label = loc:text("csr_logbook_stat_most_items"), value = fmt(career("most_items")) },
				{ label = loc:text("csr_logbook_stat_most_damage_hit"), value = fmt(career("most_damage_hit")) },
			},
		},
		{
			header = loc:text("csr_logbook_col_totals"),
			rows = {
				{ label = loc:text("csr_logbook_stat_missions"), value = fmt(career("total_missions")) },
				{ label = loc:text("csr_logbook_stat_kills"), value = fmt(career("total_kills")) },
				{ label = loc:text("csr_logbook_stat_specials"), value = fmt(career("total_specials")) },
				{
					label = loc:text("csr_logbook_stat_damage_dealt"),
					value = fmt_compact(career("total_damage_dealt")),
				},
				{
					label = loc:text("csr_logbook_stat_damage_taken"),
					value = fmt_compact(career("total_damage_taken")),
				},
				{ label = loc:text("csr_logbook_stat_coins"), value = fmt(career("total_coins")) },
				{ label = loc:text("csr_logbook_stat_cash"), value = fmt_compact(career("total_cash")) },
				{ label = loc:text("csr_logbook_stat_experience"), value = fmt_compact(career("total_experience")) },
				{ label = loc:text("csr_logbook_stat_loot"), value = fmt(career("total_loot")) },
				{ label = loc:text("csr_logbook_stat_purchases"), value = fmt(career("total_purchases")) },
			},
		},
		{
			header = loc:text("csr_logbook_col_items"),
			rows = {
				{ label = loc:text("csr_logbook_stat_unlocked"), value = unlocked_items .. " / " .. total_items },
				{ label = loc:text("csr_logbook_stat_favorite_wildcard"), value = fav_wildcard_name },
			},
		},
	}

	local font = tweak_data.menu.pd2_small_font
	local font_size = tweak_data.menu.pd2_small_font_size
	local col_w = panel:w() / 3
	local pad = 16
	local header_y = 16
	local rows_top = 60
	local row_h = 26

	for ci, col in ipairs(columns) do
		local col_x = (ci - 1) * col_w

		-- Divider between columns (skip the left edge of the first one).
		if ci > 1 then
			panel:rect({
				name = "stats_col_div_" .. ci,
				color = Color.white,
				alpha = 0.15,
				x = col_x,
				y = header_y,
				w = 2,
				h = panel:h() - header_y - 20,
				layer = 9,
			})
		end

		panel:text({
			name = "stats_col_header_" .. ci,
			text = col.header,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = Color(1, 0.8, 0.4),
			align = "center",
			x = col_x + pad,
			y = header_y,
			w = col_w - pad * 2,
			h = 28,
			layer = 10,
		})

		panel:rect({
			name = "stats_col_underline_" .. ci,
			color = Color(1, 0.8, 0.4),
			alpha = 0.5,
			x = col_x + pad,
			y = header_y + 32,
			w = col_w - pad * 2,
			h = 2,
			layer = 10,
		})

		for ri, row in ipairs(col.rows) do
			local ry = rows_top + (ri - 1) * row_h
			panel:text({
				name = "stats_" .. ci .. "_lbl_" .. ri,
				text = row.label,
				font = font,
				font_size = font_size,
				color = tweak_data.screen_colors.text,
				align = "left",
				x = col_x + pad,
				y = ry,
				w = col_w - pad * 2,
				h = row_h,
				layer = 10,
			})
			panel:text({
				name = "stats_" .. ci .. "_val_" .. ri,
				text = row.value,
				font = font,
				font_size = font_size,
				color = Color.white,
				align = "right",
				x = col_x + pad,
				y = ry,
				w = col_w - pad * 2,
				h = row_h,
				layer = 10,
			})
		end
	end
end

function CrimeSpreeLogbookMenuComponent:_create_icons_grid()
	local frame_size = GRID_FRAME_SIZE
	local icon_size = GRID_ICON_SIZE
	local padding_x = GRID_PADDING_X
	local padding_y = GRID_PADDING_Y
	local items_per_row = GRID_ITEMS_PER_ROW
	local margin_x = GRID_MARGIN_X
	local margin_y = GRID_MARGIN_Y
	local ICON_SCALE = _G.CSR_IconScale or {}
	local start_y = GRID_INNER_TOP

	local panel = self._items_panel_ref or self._content_panel

	local items_list = self._items_list or {}
	local per_page = self:_items_per_page()
	local first = ((self._page or 1) - 1) * per_page
	local page_items = {}
	for li = 1, per_page do
		local it = items_list[first + li]
		if not it then
			break
		end
		page_items[li] = it
	end
	local rows_per_page = self:_grid_rows_per_page()

	local start_x = math.floor((panel:w() - (items_per_row * (frame_size + padding_x) - padding_x)) / 2)
	local grid_width = items_per_row * (frame_size + padding_x) - padding_x + margin_x * 2
	local grid_height = rows_per_page * (frame_size + padding_y) - padding_y + margin_y * 2

	local border_color = Color(0.4, 0.4, 0.4)
	local grid_bg = panel:rect({
		name = "items_grid_bg",
		color = Color.black,
		alpha = 0.3,
		x = start_x - margin_x,
		y = start_y - margin_y,
		w = grid_width,
		h = grid_height,
		layer = 0,
	})

	panel:rect({
		color = border_color,
		x = start_x - margin_x,
		y = start_y - margin_y,
		w = grid_width,
		h = 2,
		layer = 1,
	})
	panel:rect({
		color = border_color,
		x = start_x - margin_x,
		y = start_y - margin_y + grid_height - 2,
		w = grid_width,
		h = 2,
		layer = 1,
	})
	panel:rect({
		color = border_color,
		x = start_x - margin_x,
		y = start_y - margin_y,
		w = 2,
		h = grid_height,
		layer = 1,
	})
	panel:rect({
		color = border_color,
		x = start_x - margin_x + grid_width - 2,
		y = start_y - margin_y,
		w = 2,
		h = grid_height,
		layer = 1,
	})

	local total_rows = rows_per_page
	for row = 1, total_rows - 1 do
		panel:rect({
			color = Color.white,
			alpha = 0.04,
			x = start_x - margin_x,
			y = start_y + row * (frame_size + padding_y) - math.floor(padding_y / 2),
			w = grid_width,
			h = 1,
			layer = 1,
		})
	end
	for col = 1, items_per_row - 1 do
		panel:rect({
			color = Color.white,
			alpha = 0.04,
			x = start_x + col * (frame_size + padding_x) - math.floor(padding_x / 2),
			y = start_y - margin_y,
			w = 1,
			h = grid_height,
			layer = 1,
		})
	end

	for i, item_data in ipairs(page_items) do
		local x = start_x + ((i - 1) % items_per_row) * (frame_size + padding_x)
		local y = start_y + math.floor((i - 1) / items_per_row) * (frame_size + padding_y)

		local item_panel = panel:panel({
			name = "item_" .. item_data.id,
			x = x,
			y = y,
			w = frame_size,
			h = frame_size,
			layer = 5,
		})

		local highlight = item_panel:rect({
			name = "highlight",
			color = Color.white,
			alpha = 0,
			layer = 0,
			blend_mode = "add",
		})

		local is_unlocked = _G.CSR_Logbook and _G.CSR_Logbook:is_unlocked(item_data.id) or false
		local frame_info = RARITY_FRAMES[item_data.rarity]
		if frame_info and tweak_data.hud_icons and tweak_data.hud_icons[frame_info.frame] then
			local fd = tweak_data.hud_icons[frame_info.frame]
			item_panel:bitmap({
				name = "rarity_frame",
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				w = frame_size,
				h = frame_size,
				color = frame_info.color,
				alpha = is_unlocked and 1 or 0.35,
				layer = 0,
			})
		end

		-- Scale precedence: LOGBOOK_ICON_SCALE -> ICON_SCALE global -> registered icon_scale -> 1.
		local reg_scale = (managers.csr and managers.csr.item_icon_scale) and managers.csr:item_icon_scale(item_data.id)
			or 1
		local this_icon_size = icon_size
			* (LOGBOOK_ICON_SCALE[item_data.icon] or ICON_SCALE[item_data.icon] or reg_scale)
		local icon_offset = (frame_size - this_icon_size) / 2

		if is_unlocked then
			if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
				local icon_data = tweak_data.hud_icons[item_data.icon]
				local bitmap = item_panel:bitmap({
					name = "icon",
					texture = icon_data.texture,
					texture_rect = icon_data.texture_rect,
					x = icon_offset,
					y = icon_offset,
					w = this_icon_size,
					h = this_icon_size,
					color = Color.white,
					layer = 1,
				})

				table.insert(self._items, {
					bitmap = bitmap,
					panel = item_panel,
					data = item_data,
					original_size = frame_size,
					original_x = x,
					original_y = y,
					highlight = highlight,
				})
			end
		else
			-- Locked: "?" marker, not clickable.
			item_panel:text({
				name = "locked_indicator",
				text = "?",
				font = tweak_data.menu.pd2_large_font,
				font_size = 48,
				color = Color(0.5, 0.5, 0.5),
				align = "center",
				vertical = "center",
				w = frame_size,
				h = frame_size,
				layer = 2,
			})
		end
	end
end

function CrimeSpreeLogbookMenuComponent:_show_item_details(item_data)
	self:_set_back_enabled(false)

	if self._tooltip and alive(self._tooltip) then
		self._content_panel:remove(self._tooltip)
		self._tooltip = nil
	end

	self._content_panel:set_visible(false)

	if self._details_panel and alive(self._details_panel) then
		self._panel:remove(self._details_panel)
	end

	local panel_w = 940
	local grid_h_mul = (NOT_WIN_32 and 6.9 or 6.95) / 8
	local panel_h = math.floor((self._panel:h() - 70) * grid_h_mul)

	-- Sibling of content_panel so it sits above the opaque background.
	self._details_panel = self._panel:panel({
		name = "details_panel",
		w = panel_w,
		h = panel_h,
		layer = 10,
	})

	self._details_panel:set_center(self._panel:w() / 2, self._panel:h() / 2)

	self._details_panel:rect({
		color = Color.black,
		alpha = 0.95,
		layer = -1,
	})

	BoxGuiObject:new(self._details_panel, {
		sides = { 2, 2, 2, 2 },
	})

	local y_pos = 20

	-- icon_size is the layout slot; glyph = slot * scale, centred so text column stays fixed.
	local icon_size = 96
	if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
		local icon_data = tweak_data.hud_icons[item_data.icon]
		local scale = (managers.csr and managers.csr.item_icon_scale) and managers.csr:item_icon_scale(item_data.id)
			or 1
		local glyph = icon_size * scale
		local off = (icon_size - glyph) / 2
		self._details_panel:bitmap({
			texture = icon_data.texture,
			texture_rect = icon_data.texture_rect,
			w = glyph,
			h = glyph,
			x = 30 + off,
			y = y_pos + off,
			color = Color.white,
			layer = 5,
		})
	end

	local name_text = item_data.name_en
	local rarity_color = RARITY_COLORS[item_data.rarity] or Color.white

	local text_x = 30 + icon_size + 20
	local text_w = panel_w - text_x - 20

	local name_obj = self._details_panel:text({
		name = "item_name",
		text = name_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = rarity_color,
		x = text_x,
		y = y_pos,
		layer = 5,
	})
	local _, _, _, name_h = name_obj:text_rect()

	local rarity_obj = self._details_panel:text({
		name = "item_rarity",
		text = string.upper(item_data.rarity),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = rarity_color,
		x = text_x,
		y = y_pos + name_h + 4,
		layer = 5,
	})
	local _, _, _, rarity_h = rarity_obj:text_rect()
	local text_y = y_pos + name_h + 4 + rarity_h + 6

	if item_data.community then
		local community_obj = self._details_panel:text({
			name = "item_community_tag",
			text = managers.localization:text("csr_logbook_community_item"),
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color(1, 0.85, 0.4),
			x = text_x,
			y = text_y,
			layer = 5,
		})
		local _, _, _, community_h = community_obj:text_rect()
		text_y = text_y + community_h + 4
	end

	-- Effect-gate: detailed effects are readable only between runs (0 missions completed).
	-- MP-correct: host's mirrored count when guesting, else own count (same getter as the lobby counter).
	local csr_mgr = managers.csr
	local missions_done = (csr_mgr and csr_mgr.mp_host_missions_completed and csr_mgr:mp_host_missions_completed())
		or (csr_mgr and csr_mgr:missions_completed())
		or 0
	local effects_sealed = missions_done > 0

	local loc_key = "csr_logbook_" .. item_data.id .. "_effect"
	local effect_text
	if effects_sealed then
		effect_text = managers.localization:text("csr_logbook_effect_sealed")
	else
		effect_text = _G.CSR.item_text(loc_key, item_data)
		-- :text() returns "ERROR <key>" for unknown keys; fall back to the list entry's desc.
		if not effect_text or effect_text == "" or effect_text == loc_key or effect_text:find("^ERROR") then
			effect_text = item_data.effect_en or ""
		end
	end
	local effect_panel = self._details_panel:panel({
		x = text_x,
		y = text_y,
		w = text_w,
		h = 200,
		layer = 5,
	})
	local effect_desc = effect_panel:text({
		name = "effect_desc",
		text = effect_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		-- Sealed placeholder gets a muted blue-grey so it reads as "locked", not a real effect line.
		color = effects_sealed and Color(1, 0.7, 0.75, 0.85) or tweak_data.screen_colors.text,
		x = 0,
		y = 0,
		w = text_w,
		wrap = true,
		word_wrap = true,
		layer = 5,
	})

	-- Sealed placeholder carries no {g}/{r}/{b} tags or parens; skip the colorizer entirely.
	if not effects_sealed then
		-- Color tags: {g}/{r}/{b} → green/red/blue; stripped from text, applied via set_range_color.
		local COLOR_POS = Color(0.7, 1, 0.7)
		local COLOR_NEG = Color(1, 0.5, 0.5)
		local COLOR_INFO = Color(0.6, 0.8, 1.0)
		local TAG_COLORS = { g = COLOR_POS, r = COLOR_NEG, b = COLOR_INFO }
		local ranges = {}
		local clean = ""
		local i = 1
		local current_color = nil
		local color_start = nil
		while i <= #effect_text do
			local tag = effect_text:match("^{(/?[grb]?)}", i)
			if tag then
				if tag == "/" then
					if current_color and color_start then
						table.insert(ranges, { s = color_start, e = #clean, color = current_color })
					end
					current_color = nil
					color_start = nil
				else
					current_color = TAG_COLORS[tag]
					color_start = #clean
				end
				i = i + #tag + 2
			else
				clean = clean .. effect_text:sub(i, i)
				i = i + 1
			end
		end
		effect_desc:set_text(clean)
		for _, r in ipairs(ranges) do
			effect_desc:set_range_color(r.s, r.e, r.color)
		end
		local COLOR_DIM = Color(0.55, 0.55, 0.55)
		local depth = 0
		for ci = 1, #clean do
			local ch = clean:sub(ci, ci)
			if ch == "(" then
				depth = depth + 1
			end
			if depth > 0 then
				effect_desc:set_range_color(ci - 1, ci, COLOR_DIM)
			end
			if ch == ")" then
				depth = depth - 1
			end
		end
	end

	local _, _, _, effect_h = effect_desc:text_rect()
	y_pos = math.max(y_pos + icon_size, text_y + effect_h) + 20

	-- Static tuning macros from the def by default; evidence_rounds overrides with a runtime counter.
	local notes_params = item_data.loc_macros
	if item_data.id == "evidence_rounds" then
		notes_params = { rounds = tostring(math.max(31, _G.CSR_BulletsFiredToday or 0)) }
	end
	local notes_text = managers.localization:text("csr_logbook_" .. item_data.id .. "_notes", notes_params)
	-- Skip NOTES when no _notes key exists (scrap) — :text() returns "ERROR <key>".
	if notes_text and notes_text ~= "" and not notes_text:find("^ERROR") then
		self._details_panel:text({
			name = "lore_title",
			text = managers.localization:text("csr_logbook_notes"),
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = Color.white,
			x = 30,
			y = y_pos,
			layer = 5,
		})

		y_pos = y_pos + 30

		local notes_h = math.max(40, panel_h - y_pos - 20)
		self._notes_scroll = ScrollablePanel:new(self._details_panel, "logbook_notes", {
			x = 30,
			y = y_pos,
			w = panel_w - 60,
			h = notes_h,
			layer = 5,
		})
		local lore_desc = self._notes_scroll:canvas():text({
			name = "lore_desc",
			text = notes_text,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color(1, 0.85, 0.85, 0.85),
			x = 0,
			y = 0,
			w = self._notes_scroll:canvas_scroll_width(),
			wrap = true,
			word_wrap = true,
			layer = 5,
		})
		local _, _, _, lore_h = lore_desc:text_rect()
		lore_desc:set_h(lore_h)
		self._notes_scroll:update_canvas_size()
	end

	local btn_size = 24
	local btn_padding = 8
	self._back_btn_panel = self._details_panel:panel({
		name = "back_btn",
		w = btn_size,
		h = btn_size,
		layer = 5,
	})
	self._back_btn_panel:set_right(panel_w - btn_padding)
	self._back_btn_panel:set_y(btn_padding)
	self._back_btn_panel:bitmap({
		texture = "guis/textures/pd2/crime_spree/csr_btn_back",
		w = btn_size,
		h = btn_size,
		blend_mode = "add",
		color = tweak_data.screen_colors.text,
	})
end

function CrimeSpreeLogbookMenuComponent:mouse_moved(o, x, y)
	if not self._content_panel then
		return false
	end

	if self._selected_item then
		if self._tooltip and alive(self._tooltip) then
			self._content_panel:remove(self._tooltip)
			self._tooltip = nil
		end
		if self._back_btn_panel and alive(self._back_btn_panel) and self._back_btn_panel:inside(x, y) then
			if self._last_hovered_id ~= "back_btn" then
				self._last_hovered_id = "back_btn"
				managers.menu_component:post_event("highlight")
			end
			return true, "link"
		end
		self._last_hovered_id = nil
		return false, "arrow"
	end

	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	if self._back_button and alive(self._back_button) then
		if self._back_button:inside(x, y) then
			self._back_button:set_color(tweak_data.screen_colors.button_stage_2)
			if self._last_hovered_id ~= "back_btn" then
				self._last_hovered_id = "back_btn"
				managers.menu_component:post_event("highlight")
			end
			return true, "link"
		else
			self._back_button:set_color(tweak_data.screen_colors.button_stage_3)
		end
	end

	for tab_id, button in pairs(self._tab_buttons) do
		if
			local_x >= button.x
			and local_x <= button.x + button.w
			and local_y >= button.y
			and local_y <= button.y + button.h
		then
			if self._last_hovered_id ~= "tab_" .. tab_id then
				self._last_hovered_id = "tab_" .. tab_id
				managers.menu_component:post_event("highlight")
			end
			return true, "link"
		end
	end

	self._last_hovered_id = nil

	if self._current_tab ~= "items" then
		return false, "arrow"
	end

	if self._prev_btn_panel and alive(self._prev_btn_panel) and self._prev_btn_panel:inside(x, y) then
		if self._last_hovered_id ~= "prev_btn" then
			self._last_hovered_id = "prev_btn"
			managers.menu_component:post_event("highlight")
		end
		return true, "link"
	end
	if self._next_btn_panel and alive(self._next_btn_panel) and self._next_btn_panel:inside(x, y) then
		if self._last_hovered_id ~= "next_btn" then
			self._last_hovered_id = "next_btn"
			managers.menu_component:post_event("highlight")
		end
		return true, "link"
	end

	if self._tooltip and alive(self._tooltip) then
		self._content_panel:remove(self._tooltip)
		self._tooltip = nil
	end

	local new_hovered = nil

	for i, item in ipairs(self._items) do
		if alive(item.panel) then
			local item_x, item_y = item.panel:world_position()
			local panel_w, panel_h = item.panel:size()

			if x >= item_x and x <= item_x + panel_w and y >= item_y and y <= item_y + panel_h then
				new_hovered = item
				break
			end
		end
	end

	if new_hovered ~= self._hovered_item then
		if self._hovered_item and alive(self._hovered_item.highlight) then
			self._hovered_item.highlight:set_alpha(0)
		end

		if new_hovered and alive(new_hovered.highlight) then
			new_hovered.highlight:set_alpha(0.15)
			managers.menu_component:post_event("highlight")
		end

		self._hovered_item = new_hovered
		self._last_hovered_id = new_hovered and ("item_" .. tostring(new_hovered.data and new_hovered.data.id)) or nil
	end

	return true, new_hovered and "link" or "arrow"
end

function CrimeSpreeLogbookMenuComponent:mouse_pressed(button, x, y)
	if not self._content_panel or not self._items then
		return
	end

	if button == Idstring("1") then
		return
	end

	if self._back_button and alive(self._back_button) and self._back_button:inside(x, y) then
		managers.menu_component:post_event("menu_back")
		managers.menu:back()
		return true
	end

	if not self._selected_item and self._current_tab == "items" then
		if self._prev_btn_panel and alive(self._prev_btn_panel) and self._prev_btn_panel:inside(x, y) then
			if (self._page or 1) > 1 then
				self._page = self._page - 1
				managers.menu_component:post_event("menu_enter")
				self:_render_items_page()
			end
			return true
		end
		if self._next_btn_panel and alive(self._next_btn_panel) and self._next_btn_panel:inside(x, y) then
			local per_page = self:_items_per_page()
			local total = math.max(1, math.ceil(#(self._items_list or {}) / per_page))
			if (self._page or 1) < total then
				self._page = self._page + 1
				managers.menu_component:post_event("menu_enter")
				self:_render_items_page()
			end
			return true
		end
	end

	if self._selected_item then
		if self._back_btn_panel and alive(self._back_btn_panel) and self._back_btn_panel:inside(x, y) then
			managers.menu_component:post_event("menu_enter")
			self:_close_details()
		end
		return true
	end

	if self._current_tab == "items" and self._hovered_item then
		managers.menu_component:post_event("menu_enter")
		self._selected_item = self._hovered_item.data
		self:_show_item_details(self._selected_item)
		return true
	end

	return false
end

function CrimeSpreeLogbookMenuComponent:mouse_released(o, button, x, y)
	if not self._tab_buttons or not self._content_panel then
		return false
	end

	if button == Idstring("1") then
		return false
	end

	if self._selected_item then
		return true
	end

	if not x or not y then
		if managers.mouse_pointer then
			x, y = managers.mouse_pointer:world_position()
		end
	end

	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	for tab_id, button_data in pairs(self._tab_buttons) do
		if
			local_x >= button_data.x
			and local_x <= button_data.x + button_data.w
			and local_y >= button_data.y
			and local_y <= button_data.y + button_data.h
		then
			managers.menu_component:post_event("menu_enter")
			self:_switch_tab(tab_id)
			return true
		end
	end

	return false
end

function CrimeSpreeLogbookMenuComponent:mouse_wheel_up(x, y)
	if self._selected_item then
		if self._notes_scroll and self._notes_scroll:alive() then
			self._notes_scroll:perform_scroll(ScrollablePanel.SCROLL_SPEED * TimerManager:main():delta_time() * 200, 1)
		end
		return true
	end
	if self._current_tab == "items" and (self._page or 1) > 1 then
		self._page = self._page - 1
		self:_render_items_page()
	end
	return true
end

function CrimeSpreeLogbookMenuComponent:mouse_wheel_down(x, y)
	if self._selected_item then
		if self._notes_scroll and self._notes_scroll:alive() then
			self._notes_scroll:perform_scroll(ScrollablePanel.SCROLL_SPEED * TimerManager:main():delta_time() * 200, -1)
		end
		return true
	end
	if self._current_tab == "items" then
		local per_page = self:_items_per_page()
		local total = math.max(1, math.ceil(#(self._items_list or {}) / per_page))
		if (self._page or 1) < total then
			self._page = self._page + 1
			self:_render_items_page()
		end
	end
	return true
end

csr_log(
	"[CSR Logbook] logbook_menu.lua loaded; CrimeSpreeLogbookMenuComponent defined="
		.. tostring(CrimeSpreeLogbookMenuComponent ~= nil)
)
