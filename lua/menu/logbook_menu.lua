-- Crime Spree Roguelike - Logbook Menu Component
-- Interactive item catalogue with icons, statistics, and achievement tabs

if not RequiredScript then
	return
end

-- Guard: show_new_modifier crashes when get_modifier returns nil (e.g. playing as client)
-- Also suppress vanilla "NEW LOUD MODIFIER" popup for player_* items (they use chat notification instead)
if CrimeSpreeDetailsMenuComponent and CrimeSpreeDetailsMenuComponent.show_new_modifier then
	local _orig_show_new_modifier = CrimeSpreeDetailsMenuComponent.show_new_modifier
	function CrimeSpreeDetailsMenuComponent:show_new_modifier(modifier_id)
		local modifier = managers.crime_spree and managers.crime_spree:get_modifier(modifier_id)
		if not modifier then
			return
		end
		-- Player items already notify via chat "[CSR] Host picked: ITEM NAME"
		if modifier_id and string.find(modifier_id, "player_", 1, true) == 1 then
			return
		end
		return _orig_show_new_modifier(self, modifier_id)
	end
end

-- Item data table, sorted by rarity
local ITEMS_DATA = {
	-- COMMON
	{
		id = "dog_tags",
		icon = "csr_dog_tags",
		rarity = "common",
		name_en = "DOG TAGS",
		effect_en = "Increases maximum health by 10% (+10% per stack, linear).",
	},
	{
		id = "duct_tape",
		icon = "csr_duct_tape",
		rarity = "common",
		name_en = "DUCT TAPE",
		effect_en = "Increases interaction speed by 5% (+5% per stack, linear).\nInteraction speed affects lockpicking, bagging loot, reviving and repairing, etc.",
	},
	{
		id = "escape_plan",
		icon = "csr_escape_plan",
		rarity = "common",
		name_en = "ESCAPE PLAN",
		effect_en = "Increases movement speed by 3% (+3% per stack, hyperbolic).",
	},
	{
		id = "worn_bandaid",
		icon = "csr_worn_bandaid",
		rarity = "common",
		name_en = "WORN BAND-AID",
		effect_en = "Increases health regeneration by 5 (+5 per stack, linear) every 10 seconds.",
	},
	{
		id = "cup_of_joe",
		icon = "csr_cup_of_joe",
		rarity = "common",
		name_en = "CUP OF JOE",
		effect_en = "Increases maximum stamina by 10% (+10% per stack, linear).",
	},
	{
		id = "rebar",
		icon = "csr_rebar",
		rarity = "common",
		name_en = "PIECE OF REBAR",
		effect_en = "First hit on an enemy deals +15% (+10% per stack, linear) damage.",
	},
	{
		id = "half_a_glass",
		icon = "csr_half_a_glass",
		rarity = "common",
		name_en = "HALF-A-GLASS",
		effect_en = "Picking up a Gage package instantly refills 15% ammo for primary and secondary weapons and increases their max ammo by 2% (+1% per stack, linear) for the rest of the mission.",
	},

	-- UNCOMMON
	{
		id = "evidence_rounds",
		icon = "csr_evidence_rounds",
		rarity = "uncommon",
		name_en = "EVIDENCE ROUNDS",
		effect_en = "Increases damage from ALL sources by 5% (+5% per stack, linear).",
	},
	{
		id = "falcogini_keys",
		icon = "csr_falcogini_keys",
		rarity = "uncommon",
		name_en = "FALCOGINI KEYS",
		effect_en = "Increases chance to dodge by 5% (+5% per stack, hyperbolic).\nSuccessful dodging blocks incoming damage (does not work on self-inflicted damage).",
	},
	{
		id = "wolfs_toolbox",
		icon = "csr_toolbox",
		rarity = "uncommon",
		name_en = "WOLF'S TOOLBOX",
		effect_en = "Killing regular enemies reduces active drill/saw timer by 0.2 second(s) (+0.1s per stack, linear).\nKilling special enemies reduces timer by 1 second(s) (+0.5s per stack, linear).",
	},
	{
		id = "pink_slip",
		icon = "csr_pink_slip",
		rarity = "uncommon",
		name_en = "PINK SLIP",
		effect_en = "Killing any enemy restores 5 (+2.5 per stack, linear) health.",
	},
	{
		id = "the_edge",
		icon = "csr_the_edge",
		rarity = "uncommon",
		name_en = "THE EDGE",
		effect_en = "On your last down, dropping to low HP restores max HP + flat HP and grants brief invulnerability. Resets when downs are restored.",
	},
	{
		id = "overkill_rush",
		icon = "csr_overkill_rush",
		rarity = "uncommon",
		name_en = "OVERKILL RUSH",
		effect_en = "Killing any enemy grants you a rush stack. For each rush stack your fire rate and reload speed increase by 2% (+1% per stack, linear).\nAll rush stacks expire 4 seconds after the last kill.",
	},

	-- RARE
	{
		id = "bonnie_chip",
		icon = "csr_bonnie_chip",
		rarity = "rare",
		name_en = "BONNIE'S LUCKY CHIP",
		effect_en = "Gain 10% (+10% per stack, hyperbolic) chance to instantly kill an enemy on hit.\nHas 1.5 second cooldown.",
	},
	{
		id = "plush_shark",
		icon = "csr_plush_shark",
		rarity = "rare",
		name_en = "PLUSH SHARK",
		effect_en = "Protects from lethal damage once per life.\nOn activation restores 20% maximum health and grants invulnerability that lasts 10 seconds (+20s per stack, linear).\nCan be activated again if you were freed from custody.",
		notes_en = "BLÅHAJ from IKEA. This cute plushie friend will save you even in the most hopeless situation. Just don't ask how.",
	},
	{
		id = "jiro_last_wish",
		icon = "csr_jiro_last_wish",
		rarity = "rare",
		name_en = "JIRO'S LAST WISH",
		effect_en = "Grants an ability to sprint while charging a melee attack. Increases melee damage by 50% (+50% per stack, linear).",
	},
	{
		id = "dearest_possession",
		icon = "csr_dearest_possession",
		rarity = "rare",
		name_en = "DEAREST POSSESSION",
		effect_en = "Healing received at full HP is converted into temporary shields. Shield cap: 50% of maximum health (+50% per stack, linear). Shields decay at 20% per second.",
	},
	{
		id = "viklund_vinyl",
		icon = "csr_viklund_vinyl",
		rarity = "rare",
		name_en = "VIKLUND'S VINYL",
		effect_en = "Gain 80% chance on hit to chain 2 nearest enemies within 5m (+2m per stack, linear) range. Chained enemies receive 25% of the initial damage.",
	},
	{
		id = "lockes_beret",
		icon = "csr_lockes_beret",
		rarity = "rare",
		name_en = "LOCKE'S BERET",
		effect_en = "Every 30 seconds, heals everyone on your team (you, teammates, bots, jokers, turrets) for 10% of max health (+10% per stack, hyperbolic, capped at 50%).",
		community = true,
	},
	-- CONTRABAND
	{
		id = "dozer_guide",
		icon = "csr_dozer_guide",
		rarity = "contraband",
		name_en = "DOZER GUIDE",
		effect_en = "Increases armor by 50% (+50% per stack, linear) and damage by 5% (+5% per stack, linear) from ranged and melee weapons.\nBut decreases movement speed by 15% (+15% per stack, linear) (cannot be lower than 40% of normal movement speed) and chance to dodge by 5% (+5% per stack, linear).",
	},
	{
		id = "glass_pistol",
		icon = "csr_glass_pistol",
		rarity = "contraband",
		name_en = "GLASS PISTOL",
		effect_en = "Multiplies damage from ranged and melee weapons by x1.75 (x1.75 per stack, multiplicative).\nBut divides max health and armor by 2 (+2 per stack, multiplicative).",
	},
	{
		id = "equalizer",
		icon = "csr_equalizer",
		rarity = "contraband",
		name_en = "EQUALIZER",
		effect_en = "Increases damage against special enemies by 50% (+50% per stack, linear).\nBut reduces damage against regular enemies by 50% (-50% per stack, linear).",
	},
	{
		id = "crooked_badge",
		icon = "csr_crooked_badge",
		rarity = "contraband",
		name_en = "CROOKED BADGE",
		effect_en = "After each assault, 30% (+20%, hyperbolic) chance to restore 1 down. Chance above 100% guarantees multiple downs.\nBut bleedout timer is reduced by 10 (+1s, hyperbolic) seconds.",
	},
	{
		id = "dead_mans_trigger",
		icon = "csr_dead_mans_trigger",
		rarity = "contraband",
		name_en = "DEAD MAN'S TRIGGER",
		effect_en = "When going down you explode dealing 480 (+240 per stack, linear) damage in a 3 (+2 per stack, linear) meter radius. Damage scales with Crime Spree rank.",
	},

	-- WILDCARD
	{
		id = "familiar_friend",
		icon = "csr_familiar_friend",
		rarity = "wildcard",
		name_en = "FAMILIAR FRIEND",
		effect_en = "Active wildcard (carry-1). Press your wildcard key to fire a Spike Nova: 360° AoE damage around you. Damage scales with Crime Spree rank. 60-second cooldown. Stealth-blocked.",
	},
	{
		id = "side_satchel",
		icon = "csr_side_satchel",
		rarity = "wildcard",
		name_en = "SIDE SATCHEL",
		effect_en = "Passive wildcard (carry-1). Doubles the carry cap of mission specials (C4 4 → 8, keycards 1 → 2, drill parts 1 → 2, etc.).",
	},
	{
		id = "carrot_stick",
		icon = "csr_carrot_stick",
		rarity = "wildcard",
		name_en = "CARROT STICK",
		effect_en = "Active wildcard (carry-1). Press your wildcard key to instantly heal 33% of max HP and gain 20% damage reduction for 5 seconds. 90-second cooldown. Works in stealth.",
	},
	{
		id = "hippocratic_oath",
		icon = "csr_hippocratic_oath",
		rarity = "wildcard",
		name_en = "HIPPOCRATIC OATH",
		effect_en = "Passive wildcard (carry-1). On loud transition, a medic spawns and joins your crew. While within 3 metres of the medic, regenerate 1% max HP per second. After death, the medic respawns 6 minutes later. Loud only.",
	},
}

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

-- Rarity frame icons (same textures as items_page and selection popup)
-- All rarities use the same frame (rare) to avoid icon sizing issues
local RARITY_FRAMES = {
	common = { frame = "csr_frame", color = Color.white },
	uncommon = { frame = "csr_frame", color = Color(0, 0.95, 0) },
	rare = { frame = "csr_frame", color = Color(0.3, 0.7, 1) },
	contraband = { frame = "csr_frame", color = Color(1, 0.4, 0) },
	wildcard = { frame = "csr_frame", color = Color(1, 0.3, 0.8) },
}

CrimeSpreeLogbookMenuComponent = CrimeSpreeLogbookMenuComponent or class()

-- Suppress underlying end-screen UI (crew stats / personal stats / mission-end buttons)
-- while the logbook is open on top. Same pattern as gage_services_menu.lua — see that
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
		name = "csr_logbook_panel",
		layer = self._init_layer + 10,
	})

	local panel_w = 900
	local panel_h = 600

	panel_w = 940

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

	-- Title
	local title_text = "LOGBOOK"

	self._content_panel:text({
		name = "title",
		text = title_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = Color.white,
		x = 20,
		y = 10,
		layer = 10,
	})

	-- Close button (top-right corner) — hitbox slightly larger than icon
	local close_icon_size = 20
	local close_hitbox = 24
	local btn_padding = 8
	self._close_btn_panel = self._content_panel:panel({
		name = "close_btn",
		w = close_hitbox,
		h = close_hitbox,
		layer = 10,
	})
	self._close_btn_panel:set_right(panel_w - btn_padding)
	self._close_btn_panel:set_y(btn_padding)
	local close_offset = math.round((close_hitbox - close_icon_size) / 2)
	self._close_btn_panel:bitmap({
		texture = "guis/textures/pd2/crime_spree/csr_btn_close",
		w = close_icon_size,
		h = close_icon_size,
		x = close_offset,
		y = close_offset,
		blend_mode = "add",
		color = tweak_data.screen_colors.text,
	})

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
	local tab_height = 30
	local start_y = 60

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
	local panel_w = self._content_panel:w() - 40
	local panel_h = self._content_panel:h() - 120
	local panel_x = 20
	local panel_y = 100 -- Sits below the tab bar (was 90)

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
	-- Delegate to the icon grid builder
	self._items_panel_ref = self._tab_panels["items"] -- Temporary reference consumed by _create_icons_grid
	self:_create_icons_grid()
	self._items_panel_ref = nil
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
	local start_y = 30 -- Vertically aligned with the statistics tab

	-- Use the tab's own panel instead of the master content panel
	local panel = self._items_panel_ref or self._content_panel

	local start_x = math.floor((panel:w() - (items_per_row * (frame_size + padding_x) - padding_x)) / 2)
	local grid_width = items_per_row * (frame_size + padding_x) - padding_x + margin_x * 2
	local grid_height = math.ceil(#ITEMS_DATA / items_per_row) * (frame_size + padding_y) - padding_y + margin_y * 2

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

	-- Subtle grid lines between cells
	local total_rows = math.ceil(#ITEMS_DATA / items_per_row)
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

	for i, item_data in ipairs(ITEMS_DATA) do
		local x = start_x + ((i - 1) % 10) * (frame_size + padding_x)
		local y = start_y + math.floor((i - 1) / 10) * (frame_size + padding_y)

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

		local this_icon_size = icon_size * (ICON_SCALE[item_data.icon] or 1)
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
	local panel_h = 600

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

	-- Large icon
	local icon_size = 96
	if tweak_data.hud_icons and tweak_data.hud_icons[item_data.icon] then
		local icon_data = tweak_data.hud_icons[item_data.icon]
		self._details_panel:bitmap({
			texture = icon_data.texture,
			texture_rect = icon_data.texture_rect,
			w = icon_size,
			h = icon_size,
			x = 30,
			y = y_pos,
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
	if not effect_text or effect_text == loc_key then
		effect_text = item_data.effect_en
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

	-- Apply color tags: {g}text{/} = green, {r}text{/} = red
	-- Tags are stripped from display text, colors applied via set_range_color
	local COLOR_POS = Color(0.7, 1, 0.7)
	local COLOR_NEG = Color(1, 0.5, 0.5)
	local TAG_COLORS = { g = COLOR_POS, r = COLOR_NEG }
	local ranges = {}
	local clean = ""
	local i = 1
	local current_color = nil
	local color_start = nil
	while i <= #effect_text do
		local tag = effect_text:match("^{(/?[gr]?)}", i)
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
	if notes_text and notes_text ~= "" then
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

		self._details_panel:text({
			name = "lore_desc",
			text = notes_text,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color(1, 0.85, 0.85, 0.85),
			x = 30,
			y = y_pos,
			w = panel_w - 60,
			wrap = true,
			word_wrap = true,
			layer = 5,
		})
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

	-- Close button hover
	if self._close_btn_panel and alive(self._close_btn_panel) and self._close_btn_panel:inside(x, y) then
		if self._last_hovered_id ~= "close_btn" then
			self._last_hovered_id = "close_btn"
			managers.menu_component:post_event("highlight")
		end
		return true, "link"
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

	-- Close button click (grid view)
	if not self._selected_item and self._close_btn_panel and alive(self._close_btn_panel) then
		if self._close_btn_panel:inside(x, y) then
			managers.menu_component:post_event("menu_back")
			managers.menu:back()
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
	-- Scroll disabled (not needed yet)
	return true
end

function CrimeSpreeLogbookMenuComponent:mouse_wheel_down(x, y)
	return true
end
