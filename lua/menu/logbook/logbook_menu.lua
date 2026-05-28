-- Crime Spree Roguelike - Logbook Menu Component
-- Interactive item catalogue with icons, statistics, and achievement tabs

if not RequiredScript then
	return
end

-- NOTE (U1 refactor port): the original file also wrapped
-- CrimeSpreeDetailsMenuComponent:show_new_modifier here to suppress the vanilla
-- "NEW LOUD MODIFIER" popup for player_* items. That block was intentionally
-- dropped during the port — it is unrelated to viewing the logbook, depends on
-- managers.crime_spree + the vanilla CS-details flow, and is dead code in the
-- refactor (vanilla Crime Spree is never activated). See the logbook port
-- decision in the session handoff.

-- Item catalogue is built dynamically from the live registry — see _build_items_list().

-- Rarity colours
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 0.95, 0),
	rare = Color(0, 0.5, 1),
	contraband = Color(1, 0.5, 0),
	wildcard = Color(1, 0.3, 0.8),
}

-- Icon grid layout constants (shared between _create_tabs and _create_icons_grid)
local GRID_FRAME_SIZE = 90
local GRID_ICON_SIZE = 48
local GRID_PADDING_X = -2
local GRID_PADDING_Y = -2
local GRID_ITEMS_PER_ROW = 10
local GRID_MARGIN_X = 0
local GRID_MARGIN_Y = 0

-- Items-tab vertical layout. The content box keeps its original size and centered
-- position; these only move the *contents* (tab bar + grid) higher INSIDE the box.
-- Tightened from the old defaults (tab bar 60 / items panel 100 / grid inset 30 /
-- nav 44) so the reclaimed ~88px lets a fourth 90px row fit within the same box,
-- without shrinking the icons. The catalogue shows GRID_ROWS_PER_PAGE rows.
local GRID_ROWS_PER_PAGE = 4
local TAB_BAR_TOP = 24 -- tab bar y inside the content box (was 60)
local TAB_BAR_HEIGHT = 30
local ITEMS_PANEL_TOP = 66 -- items-tab panel y inside the content box (was 100)
local ITEMS_PANEL_BOTTOM_PAD = 12 -- gap below the items panel inside the box (was 20)
local GRID_INNER_TOP = 16 -- grid y inside the items panel (was 30)
local GRID_NAV_RESERVE = 40 -- page-nav row budget at the items-panel bottom (was 44)

-- Logbook-only per-icon scale overrides. Takes precedence over _G.CSR_IconScale
-- so the items tab / wildcard slot can keep their own sizing.
local LOGBOOK_ICON_SCALE = {
	csr_side_satchel = 0.9,
	csr_hippocratic_oath = 0.9,
}

-- Rarity frame icons (same textures as items_page and selection popup)
-- All rarities use the same frame (rare) to avoid icon sizing issues
local RARITY_FRAMES = {
	common = { frame = "csr_frame", color = Color.white },
	uncommon = { frame = "csr_frame", color = Color(0, 0.95, 0) },
	rare = { frame = "csr_frame", color = Color(0.3, 0.7, 1) },
	contraband = { frame = "csr_frame", color = Color(1, 0.4, 0) },
	wildcard = { frame = "csr_frame", color = Color(1, 0.3, 0.8) },
}

-- Sort order for the registry-driven grid: groups items by rarity tier (then by
-- name) so the catalogue reads common -> ... -> wildcard like the old curated list.
local RARITY_ORDER = {
	common = 1,
	uncommon = 2,
	rare = 3,
	contraband = 4,
	wildcard = 5,
}

CrimeSpreeLogbookMenuComponent = CrimeSpreeLogbookMenuComponent or class()

-- Suppress underlying end-screen UI (crew stats / personal stats / mission-end buttons)
-- while the logbook is open on top. Same pattern as black_market_menu.lua — see that
-- file for the full rationale on why both visual hide AND input gating are required.
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

function CrimeSpreeLogbookMenuComponent:init(ws, fullscreen_ws, node)
	-- Guard: component must be initialised in a valid menu context
	if not ws or not fullscreen_ws then
		return
	end

	-- Guard: core managers must be available
	if not managers or not managers.menu then
		return
	end

	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()

	self._items = {} -- Icon table: {bitmap, panel, data, original_size, highlight}
	self._hovered_item = nil
	self._selected_item = nil -- Item currently open in detail view
	self._tooltip = nil
	self._input_focus = 1 -- Request keyboard input focus
	self._current_tab = "items" -- Active tab: items, statistics, achievements
	self._tab_buttons = {} -- Tab button references
	self._tab_panels = {} -- Tab content panels
	self._page = 1 -- current page of the items-tab grid (pagination)

	self:_setup_logbook()
	self:_suppress_endscreen()
end

function CrimeSpreeLogbookMenuComponent:close()
	-- Ensure back is re-enabled before closing (safety net)
	self:_set_back_enabled(true)
	self:_restore_endscreen()
	if self._panel and alive(self._panel) and self._ws then
		self._ws:panel():remove(self._panel)
	end
end

function CrimeSpreeLogbookMenuComponent:input_focus()
	return self._input_focus or 0
end

-- Block menu back navigation while details view is open.
-- When details is shown, disable back so ESC doesn't close the logbook.
-- back_pressed (called before back navigation) closes details and re-enables back.

function CrimeSpreeLogbookMenuComponent:_set_back_enabled(enabled)
	local active_menu = managers.menu and managers.menu:active_menu()
	if active_menu and active_menu.input then
		active_menu.input:set_back_enabled(enabled)
	end
end

function CrimeSpreeLogbookMenuComponent:back_pressed()
	if self._selected_item and self._content_panel then
		-- Details view → close details, return to grid
		managers.menu_component:post_event("menu_back")
		self:_close_details()
		-- Re-enable back so next ESC closes the logbook normally
		self:_set_back_enabled(true)
		return true
	end
end

function CrimeSpreeLogbookMenuComponent:_close_details()
	if self._details_panel and alive(self._details_panel) then
		self._panel:remove(self._details_panel)
		self._details_panel = nil
	end
	-- Restore the grid view (re-show content_panel with the icon grid)
	if self._content_panel and alive(self._content_panel) then
		self._content_panel:set_visible(true)
	end
	self._selected_item = nil
	-- Re-enable back navigation
	self:_set_back_enabled(true)
end

function CrimeSpreeLogbookMenuComponent:_setup_logbook()
	-- Clear "new" flag when logbook is opened, then refresh the lobby node
	-- so the "!" on the LOGBOOK button disappears when returning
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
	-- Height matches the vanilla weapon-select grid (BlackMarketGui): a fraction of
	-- the workspace, so it scales with resolution instead of a fixed number.
	-- GRID_H_MUL = (6.9 or 6.95)/8; the -70 mirrors BlackMarketGui's grid_size offset.
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

	-- Panel background
	self._content_panel:rect({
		color = Color.black,
		alpha = 0.92,
		layer = -1,
	})

	-- Border
	BoxGuiObject:new(self._content_panel, {
		sides = { 2, 2, 2, 2 },
	})

	-- Branded header OUTSIDE the content box, in the lobby "CRIME SPREE ROGUELIKE"
	-- style: a crisp pd2_large foreground over a huge faded-blue pd2_massive ghost.
	-- Both layers live on the OUTER panel (not the box) and anchor just above the
	-- box's top-left, so the ghost spills over the backdrop like the lobby title.
	-- Ghost on a low layer (behind the box) so its lower half is masked by the box.
	local header_label = "LOGBOOK"
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
	-- Same spot as the lobby title: (0,0) of the (safe-workspace) outer panel, i.e.
	-- the safe-area top-left corner. These menus share the lobby's safe self._ws, so
	-- the lobby's implicit (0,0) maps here 1:1.
	header:set_left(0)
	header:set_top(0)
	header_ghost:set_world_left(header:world_left())
	header_ghost:set_world_center_y(header:world_center_y())
	header_ghost:move(-13, 9)

	-- PD2-style BACK button at the workspace bottom-right (replaces the old top-right
	-- close X). Mirrors vanilla BlackMarketGui's back_button: pd2_large, button_stage_3,
	-- flush bottom-right of the outer panel, symmetric with the top-left header.
	-- Exits the logbook (managers.menu:back()) from any view; the detail-view back
	-- button (csr_btn_back, top-right) is separate and untouched.
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

	-- Build tabs and their content panels
	self:_create_tabs()
	self:_create_tab_panels()

	-- Activate the first tab
	self:_switch_tab("items")
end

function CrimeSpreeLogbookMenuComponent:_create_tabs()
	local tabs = {
		{ id = "items", label = "ITEMS" },
		{ id = "statistics", label = "STATISTICS" },
		{ id = "achievements", label = "ACHIEVEMENTS" },
	}

	local panel_w = self._content_panel:w()
	-- Align tab bar with the icon grid block (grid + its side margins)
	local grid_total_w = GRID_ITEMS_PER_ROW * (GRID_FRAME_SIZE + GRID_PADDING_X) - GRID_PADDING_X + GRID_MARGIN_X * 2
	local margin_left = math.floor((panel_w - grid_total_w) / 2)
	local margin_right = margin_left
	local tab_spacing = 10
	local tab_height = TAB_BAR_HEIGHT
	local start_y = TAB_BAR_TOP

	-- Compute tab width so tabs fill the full panel width evenly
	local available_width = panel_w - margin_left - margin_right - (tab_spacing * (#tabs - 1))
	local tab_width = available_width / #tabs

	for i, tab_data in ipairs(tabs) do
		local x = margin_left + (i - 1) * (tab_width + tab_spacing)

		-- Tab background
		local tab_bg = self._content_panel:rect({
			name = "tab_bg_" .. tab_data.id,
			color = Color(0.2, 0.2, 0.2),
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
			layer = 5,
		})

		-- Tab label
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

		-- Store references for tab switching
		self._tab_buttons[tab_data.id] = {
			bg = tab_bg,
			text = tab_text,
			x = x,
			y = start_y,
			w = tab_width,
			h = tab_height,
		}
	end

	-- Divider line below the tabs
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
	local panel_y = ITEMS_PANEL_TOP -- sits just below the tab bar / divider
	local panel_w = self._content_panel:w() - 40
	local panel_h = self._content_panel:h() - panel_y - ITEMS_PANEL_BOTTOM_PAD

	-- Items tab panel
	self._tab_panels["items"] = self._content_panel:panel({
		name = "items_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8,
	})

	-- Statistics tab panel
	self._tab_panels["statistics"] = self._content_panel:panel({
		name = "statistics_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8,
	})

	-- Achievements tab panel
	self._tab_panels["achievements"] = self._content_panel:panel({
		name = "achievements_panel",
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 8,
	})

	-- Populate each tab with its content
	self:_populate_items_tab()
	self:_populate_statistics_tab()
	self:_populate_achievements_tab()
end

function CrimeSpreeLogbookMenuComponent:_switch_tab(tab_id)
	self._current_tab = tab_id

	-- Update tab button colours
	for id, button in pairs(self._tab_buttons) do
		if id == tab_id then
			-- Active tab: dark gold
			button.bg:set_color(Color(0.85, 0.7, 0.2))
			button.text:set_color(Color.black) -- Black text for contrast on gold
		else
			-- Inactive tab: near-black
			button.bg:set_color(Color(0.15, 0.15, 0.15))
			button.text:set_color(Color(0.5, 0.5, 0.5)) -- Grey text
		end
	end

	-- Show/hide tab content panels
	for id, panel in pairs(self._tab_panels) do
		panel:set_visible(id == tab_id)
	end

	-- Refresh statistics every time the tab is opened so values stay current
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
	-- Build the catalogue from the live registry (dynamic count) and render the
	-- current page. Pagination is driven by how many items are registered, so
	-- ported/added/mod items appear automatically.
	self._items_list = self:_build_items_list()
	self._page = self._page or 1
	self:_render_items_page()
end

-- Catalogue list from the item registry, mapped to the field names the grid +
-- detail view already expect (id / icon / rarity / name_en / effect_en /
-- community), sorted by rarity then name. name_en/effect_en are localized from
-- the def's loc keys; the detail view still PREFERS csr_logbook_<id>_effect and
-- only falls back to effect_en, so ported items read from localization.lua as before.
function CrimeSpreeLogbookMenuComponent:_build_items_list()
	local list = {}
	local reg = (managers.csr and managers.csr.registered_items) and managers.csr:registered_items() or {}
	for _, e in ipairs(reg) do
		-- Scrap (printer fodder) IS shown in the compendium, sorted to the END of its
		-- tier (see the sort below). It has no _effect/_notes loc keys, so the detail
		-- view falls back to its desc for the effect and skips the NOTES block.
		list[#list + 1] = {
			id = e.type,
			icon = e.icon,
			rarity = e.rarity,
			is_scrap = e.is_scrap or nil,
			name_en = string.upper((e.name and managers.localization:text(e.name)) or tostring(e.type)),
			effect_en = (e.full_desc and managers.localization:text(e.full_desc))
				or (e.desc and managers.localization:text(e.desc))
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
		-- Scrap sinks to the END of its tier (after the real items).
		local sa, sb = a.is_scrap and 1 or 0, b.is_scrap and 1 or 0
		if sa ~= sb then
			return sa < sb
		end
		return tostring(a.name_en) < tostring(b.name_en)
	end)
	return list
end

-- Rows shown per page: capped at GRID_ROWS_PER_PAGE (the box is sized for exactly
-- that many) but allowed to drop below it on a short workspace that can't fit them.
-- The cap stops a tall workspace from sprouting sparse 5th+ rows of empty cells.
-- The grid is ALWAYS drawn at this many rows regardless of fill, so a partially
-- filled page still shows the full grid frame.
function CrimeSpreeLogbookMenuComponent:_grid_rows_per_page()
	local panel = self._tab_panels and self._tab_panels["items"]
	local h = (panel and alive(panel) and panel:h()) or 480
	local fit = math.max(1, math.floor((h - GRID_INNER_TOP - GRID_NAV_RESERVE) / (GRID_FRAME_SIZE + GRID_PADDING_Y)))
	return math.min(GRID_ROWS_PER_PAGE, fit)
end

-- Item cells per page = full rows × per-row count.
function CrimeSpreeLogbookMenuComponent:_items_per_page()
	return self:_grid_rows_per_page() * GRID_ITEMS_PER_ROW
end

-- (Re)draw the current page: clear the items panel, rebuild the grid slice + the
-- page-nav row. Page is clamped to [1, total_pages].
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

-- Page navigation row (◄ "<"  PAGE X / Y  ">" ►) at the bottom of the items
-- panel. Only drawn when there is more than one page; arrows dim at the edges
-- and their clicks are guarded in mouse_pressed.
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
	-- Delegate to the statistics builder
	self._stats_panel_ref = self._tab_panels["statistics"] -- Temporary reference consumed by _create_statistics
	self:_create_statistics()
	self._stats_panel_ref = nil
end

function CrimeSpreeLogbookMenuComponent:_populate_achievements_tab()
	local panel = self._tab_panels["achievements"]

	-- Placeholder
	local placeholder = "ACHIEVEMENTS COMING IN FUTURE UPDATES"

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

function CrimeSpreeLogbookMenuComponent:_create_statistics()
	if not CSR_MetaProgress then
		return
	end

	local stats = CSR_MetaProgress:GetStats()

	local stats_y = 20
	local stats_x = 10
	local font = tweak_data.menu.pd2_small_font
	local font_size = tweak_data.menu.pd2_small_font_size

	-- Use the tab's own panel instead of the master content panel
	local panel = self._stats_panel_ref or self._content_panel

	-- Section heading
	local stats_title = "STATISTICS"
	panel:text({
		name = "stats_title",
		text = stats_title,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color(1, 0.8, 0.8, 1), -- Pale yellow
		x = stats_x,
		y = stats_y,
		layer = 10,
	})

	-- Format large numbers with thousands separators (1000 → 1,000)
	local function format_number(num)
		local formatted = tostring(num)
		local k
		while true do
			formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
			if k == 0 then
				break
			end
		end
		return formatted
	end

	-- Format cash as $1.2M / $1.2K / $123
	local function format_cash(amount)
		if amount >= 1000000 then
			return string.format("$%.1fM", amount / 1000000)
		elseif amount >= 1000 then
			return string.format("$%.1fK", amount / 1000)
		else
			return "$" .. amount
		end
	end

	-- Statistics list (3 columns)
	local stats_list = {
		-- Left column
		{
			label = "Missions Completed:",
			value = format_number(stats.total_missions),
			x = stats_x,
			y = stats_y + 35,
		},
		{
			label = "Total Kills:",
			value = format_number(stats.total_kills),
			x = stats_x,
			y = stats_y + 55,
		},
		{
			label = "Bags Secured:",
			value = format_number(stats.total_bags),
			x = stats_x,
			y = stats_y + 75,
		},
		-- Middle column
		{
			label = "Highest Level:",
			value = format_number(stats.highest_level),
			x = stats_x + 300,
			y = stats_y + 35,
		},
		{
			label = "Total Cash Earned:",
			value = format_cash(stats.total_cash),
			x = stats_x + 300,
			y = stats_y + 55,
		},
		{
			label = "Total Coins Earned:",
			value = format_number(math.floor(stats.total_coins or 0)),
			x = stats_x + 300,
			y = stats_y + 75,
		},
	}

	-- Render each stat row
	for i, stat in ipairs(stats_list) do
		-- Label
		panel:text({
			name = "stat_label_" .. i,
			text = stat.label,
			font = font,
			font_size = font_size,
			color = tweak_data.screen_colors.text,
			x = stat.x,
			y = stat.y,
			layer = 10,
		})

		-- Value (right of the label)
		local value_text = panel:text({
			name = "stat_value_" .. i,
			text = stat.value,
			font = font,
			font_size = font_size,
			color = Color.white,
			x = stat.x + 200,
			y = stat.y,
			layer = 10,
		})
	end

	-- Divider line
	panel:rect({
		name = "stats_divider",
		color = Color.white,
		alpha = 0.3,
		x = stats_x,
		y = stats_y + 100,
		w = 840,
		h = 2,
		layer = 9,
	})
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
	local start_y = GRID_INNER_TOP -- Vertically aligned with the statistics tab

	-- Use the tab's own panel instead of the master content panel
	local panel = self._items_panel_ref or self._content_panel

	-- Slice the registry-driven catalogue down to THIS page.
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
	-- Grid is drawn at the FULL page row capacity (not the occupied-row count) so
	-- the frame is always shown, even on an empty or partially-filled page.
	local rows_per_page = self:_grid_rows_per_page()

	local start_x = math.floor((panel:w() - (items_per_row * (frame_size + padding_x) - padding_x)) / 2)
	local grid_width = items_per_row * (frame_size + padding_x) - padding_x + margin_x * 2
	local grid_height = rows_per_page * (frame_size + padding_y) - padding_y + margin_y * 2

	local border_color = Color(0.4, 0.4, 0.4) -- Dark grey

	-- Background for the icon grid area
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

	-- Border (4 lines)
	-- Top
	panel:rect({
		color = border_color,
		x = start_x - margin_x,
		y = start_y - margin_y,
		w = grid_width,
		h = 2,
		layer = 1,
	})
	-- Bottom
	panel:rect({
		color = border_color,
		x = start_x - margin_x,
		y = start_y - margin_y + grid_height - 2,
		w = grid_width,
		h = 2,
		layer = 1,
	})
	-- Left
	panel:rect({
		color = border_color,
		x = start_x - margin_x,
		y = start_y - margin_y,
		w = 2,
		h = grid_height,
		layer = 1,
	})
	-- Right
	panel:rect({
		color = border_color,
		x = start_x - margin_x + grid_width - 2,
		y = start_y - margin_y,
		w = 2,
		h = grid_height,
		layer = 1,
	})

	-- Subtle grid lines between cells (drawn for the full grid, not just filled rows)
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

		-- Per-item panel (used for positioning and hit-testing)
		local item_panel = panel:panel({
			name = "item_" .. item_data.id,
			x = x,
			y = y,
			w = frame_size,
			h = frame_size,
			layer = 5,
		})

		-- Highlight overlay (invisible by default)
		local highlight = item_panel:rect({
			name = "highlight",
			color = Color.white,
			alpha = 0,
			layer = 0,
			blend_mode = "add",
		})

		-- Check whether this item has been unlocked in the logbook
		local is_unlocked = _G.CSR_Logbook and _G.CSR_Logbook:is_unlocked(item_data.id) or false

		-- Rarity frame (full cell size)
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

		-- Per-icon scale precedence: logbook-only override (legacy; currently the
		-- not-yet-registered wildcards) -> dead ICON_SCALE global -> the item's
		-- registered icon_scale (managers.csr) -> 1.
		local reg_scale = (managers.csr and managers.csr.item_icon_scale) and managers.csr:item_icon_scale(item_data.id)
			or 1
		local this_icon_size = icon_size
			* (LOGBOOK_ICON_SCALE[item_data.icon] or ICON_SCALE[item_data.icon] or reg_scale)
		local icon_offset = (frame_size - this_icon_size) / 2

		if is_unlocked then
			-- Unlocked: show icon and add to the clickable items list
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
			-- Locked: dark background + large "?" marker, not clickable
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

-- Open the item detail panel
function CrimeSpreeLogbookMenuComponent:_show_item_details(item_data)
	-- Block ESC from closing the logbook while details are open
	self:_set_back_enabled(false)

	-- Hide tooltip when opening details
	if self._tooltip and alive(self._tooltip) then
		self._content_panel:remove(self._tooltip)
		self._tooltip = nil
	end

	-- Hide the grid view — the details panel takes the full screen
	self._content_panel:set_visible(false)

	-- Remove any existing details panel
	if self._details_panel and alive(self._details_panel) then
		self._panel:remove(self._details_panel)
	end

	local panel_w = 940
	-- Same height formula as the grid view / vanilla weapon-select panel (scales with
	-- the workspace), so the detail box matches the rest of the logbook.
	local grid_h_mul = (NOT_WIN_32 and 6.9 or 6.95) / 8
	local panel_h = math.floor((self._panel:h() - 70) * grid_h_mul)

	-- Create details_panel as a sibling of content_panel, not a child
	self._details_panel = self._panel:panel({
		name = "details_panel",
		w = panel_w,
		h = panel_h,
		layer = 10,
	})

	self._details_panel:set_center(self._panel:w() / 2, self._panel:h() / 2)

	-- Background
	self._details_panel:rect({
		color = Color.black,
		alpha = 0.95,
		layer = -1,
	})

	BoxGuiObject:new(self._details_panel, {
		sides = { 2, 2, 2, 2 },
	})

	local y_pos = 20

	-- Large icon. icon_size is the fixed layout SLOT (it also positions the name
	-- column to the icon's right); the drawn glyph is slot * icon_scale, centred
	-- in the slot, so a per-item icon_scale never shifts the text column.
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

	-- Item name
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

	-- Community item tag — shown for items contributed by the community.
	if item_data.community then
		local community_obj = self._details_panel:text({
			name = "item_community_tag",
			text = "COMMUNITY ITEM",
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

	-- Effect alongside icon; sub-panel anchors wrap to x=0 of the sub-panel
	local loc_key = "csr_logbook_" .. item_data.id .. "_effect"
	local effect_text = managers.localization:text(loc_key)
	-- :text returns "ERROR <key>" for an unknown id (e.g. scrap has no _effect key);
	-- fall back to the list entry's effect_en (its desc) in that case.
	if not effect_text or effect_text == "" or effect_text == loc_key or effect_text:find("^ERROR") then
		effect_text = item_data.effect_en or ""
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
		color = tweak_data.screen_colors.text,
		x = 0,
		y = 0,
		w = text_w,
		wrap = true,
		word_wrap = true,
		layer = 5,
	})

	-- Apply color tags: {g}text{/} = green, {r}text{/} = red, {b}text{/} = blue
	-- Tags are stripped from display text, colors applied via set_range_color
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
			i = i + #tag + 2 -- skip {X}
		else
			clean = clean .. effect_text:sub(i, i)
			i = i + 1
		end
	end
	effect_desc:set_text(clean)
	for _, r in ipairs(ranges) do
		effect_desc:set_range_color(r.s, r.e, r.color)
	end
	-- Dim text inside parentheses
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

	local _, _, _, effect_h = effect_desc:text_rect()
	y_pos = math.max(y_pos + icon_size, text_y + effect_h) + 20

	local notes_params = item_data.id == "evidence_rounds"
			and { rounds = tostring(math.max(31, _G.CSR_BulletsFiredToday or 0)) }
		or nil
	local notes_text = managers.localization:text("csr_logbook_" .. item_data.id .. "_notes", notes_params)
	-- Skip the NOTES block when there is no _notes key (scrap) -- :text returns "ERROR <key>".
	if notes_text and notes_text ~= "" and not notes_text:find("^ERROR") then
		self._details_panel:text({
			name = "lore_title",
			text = "NOTES:",
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = Color.white,
			x = 30,
			y = y_pos,
			layer = 5,
		})

		y_pos = y_pos + 30

		-- Lore can be long and the detail box height now scales with the workspace,
		-- so the text may not fit. Put it in a vanilla ScrollablePanel (mouse-wheel
		-- scroll + scroll bar), sized from the notes top to a small bottom margin.
		-- Only this block changes -- redesign-friendly.
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

	-- Back button (top-right corner) — panel-based for reliable hit-test
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

-- Mouse handlers
function CrimeSpreeLogbookMenuComponent:mouse_moved(o, x, y)
	-- Guard: component must be initialised before handling mouse events
	if not self._content_panel then
		return false
	end

	-- In details view: only handle back button hover
	if self._selected_item then
		if self._tooltip and alive(self._tooltip) then
			self._content_panel:remove(self._tooltip)
			self._tooltip = nil
		end
		-- Back button hover
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

	-- Convert world coordinates to local for hit-testing
	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Back button hover (bottom-right): brighten on hover, dim otherwise.
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

	-- Tab hover check (switch cursor to hand)
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

	-- Reset hover ID when not on any tab
	self._last_hovered_id = nil

	-- Icon hover check only applies on the items tab
	if self._current_tab ~= "items" then
		return false, "arrow"
	end

	-- Page-arrow hover (panels live in the items panel; :inside takes world coords).
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

	-- Clear any existing tooltip
	if self._tooltip and alive(self._tooltip) then
		self._content_panel:remove(self._tooltip)
		self._tooltip = nil
	end

	local new_hovered = nil

	-- x, y are already world coordinates from the engine
	-- Hit-test each icon panel
	for i, item in ipairs(self._items) do
		if alive(item.panel) then
			local panel_x, panel_y = item.panel:world_position()
			local panel_w, panel_h = item.panel:size()

			if x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h then
				new_hovered = item
				if not self._hovered_item or self._hovered_item ~= item then
				end
				break
			end
		end
	end

	-- Update hover highlight (tooltips disabled by user request)
	if new_hovered ~= self._hovered_item then
		-- Clear highlight from previously hovered icon
		if self._hovered_item and alive(self._hovered_item.highlight) then
			self._hovered_item.highlight:set_alpha(0)
		end

		-- Highlight the newly hovered icon + play sound
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
	-- Guard: component must be initialised
	if not self._content_panel or not self._items then
		return
	end

	-- Ignore right clicks
	if button == Idstring("1") then
		return
	end

	-- Back button click (bottom-right) -- exits the logbook from any view.
	if self._back_button and alive(self._back_button) and self._back_button:inside(x, y) then
		managers.menu_component:post_event("menu_back")
		managers.menu:back()
		return true
	end

	-- Page arrows (items tab, grid view). Guarded at the edges so a dimmed arrow
	-- is inert; a successful flip re-renders the grid for the new page.
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

	-- In details view: only back button closes details, all other clicks consumed
	if self._selected_item then
		if self._back_btn_panel and alive(self._back_btn_panel) and self._back_btn_panel:inside(x, y) then
			managers.menu_component:post_event("menu_enter")
			self:_close_details()
		end
		return true
	end

	-- Icon click (items tab only)
	if self._current_tab == "items" and self._hovered_item then
		managers.menu_component:post_event("menu_enter")
		self._selected_item = self._hovered_item.data
		self:_show_item_details(self._selected_item)
		return true
	end

	return false
end

function CrimeSpreeLogbookMenuComponent:mouse_released(o, button, x, y)
	-- Guard: component must be initialised
	if not self._tab_buttons or not self._content_panel then
		return false
	end

	-- Ignore right clicks
	if button == Idstring("1") then
		return false
	end

	-- Block tab switching while item details are open
	if self._selected_item then
		return true
	end

	-- Fall back to managers.mouse_pointer if coordinates were not passed
	if not x or not y then
		if managers.mouse_pointer then
			x, y = managers.mouse_pointer:world_position()
		end
	end

	-- Convert world coordinates to local
	local panel_x, panel_y = self._content_panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	-- Hit-test tab buttons
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
	-- Detail view: scroll the lore notes. Grid view: previous page.
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
	-- Detail view: scroll the lore notes. Grid view: next page.
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

-- Diagnostic load trace (click-triggered subsystem, kept per debug policy).
csr_log(
	"[CSR Logbook] logbook_menu.lua loaded; CrimeSpreeLogbookMenuComponent defined="
		.. tostring(CrimeSpreeLogbookMenuComponent ~= nil)
)
