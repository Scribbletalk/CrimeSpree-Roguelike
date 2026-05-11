-- Crime Spree Roguelike Alpha 1 - Player items tab (with scrolling)

if not RequiredScript then
	return
end

-- === RARITY COLORS ===
-- Easy-to-change constants for text and frame colors
local RARITY_COLOR_COMMON = Color.white -- White
local RARITY_COLOR_UNCOMMON = Color(0, 0.95, 0) -- Green (95%)
local RARITY_COLOR_RARE = Color(0.3, 0.7, 1) -- Bright Blue
local RARITY_COLOR_CONTRABAND = Color(1, 0.4, 0) -- Orange
local RARITY_COLOR_WILDCARD = Color(1, 0.3, 0.8) -- Magenta

-- === WILDCARD SLOT ===
-- Right-column reserved cell. Size is derived per-render: width = height
-- (square, since the hex icon is 1:1) and matches the player section height
-- (BASE_SECTION_H). RIGHT_PAD adds a slight right inset from the panel edge;
-- LEFT_PAD does the same on the left for the rarity grid. Wildcards are
-- carry-1 so the cell only ever holds one icon (or an empty placeholder
-- when the player owns none).
local WILDCARD_SLOT_GAP = 8
local WILDCARD_SLOT_RIGHT_PAD = 8
local MAIN_GRID_LEFT_PAD = 8
local WILDCARD_ICON_FRAME_RATIO = 0.5 -- icon size / slot size (matches the ~0.51 rarity-grid default)
local WILDCARD_PLACEHOLDER_COLOR = Color(0.35, 1, 0.3, 0.8) -- dim magenta (alpha, r, g, b)

-- Split a flat items list into (regular, wildcards). Wildcards are tagged
-- via build_items_for_peer with is_wildcard=true.
local function split_wildcards(items)
	local regular, wildcards = {}, {}
	for _, item in ipairs(items) do
		if item.is_wildcard then
			table.insert(wildcards, item)
		else
			table.insert(regular, item)
		end
	end
	return regular, wildcards
end

-- === PLAYER ITEMS PAGE CLASS ===
-- Check that the parent class is available
if not CrimeSpreeModifierDetailsPage then
	return
end

-- Inherit from CrimeSpreeModifierDetailsPage for correct click handling
CrimeSpreePlayerItemsPage = CrimeSpreePlayerItemsPage or class(CrimeSpreeModifierDetailsPage)

function CrimeSpreePlayerItemsPage:init(name_id, page_panel, fullscreen_panel, parent)
	-- Call parent constructor
	CrimeSpreePlayerItemsPage.super.init(self, name_id, page_panel, fullscreen_panel, parent)

	self._scroll_offset = 0
	self._scroll_speed = 50
	self._fullscreen_panel = fullscreen_panel

	-- Store global reference so MP sync handlers can push refresh when tab is visible
	_G.CSR_ItemsPageInstance = self

	if self:panel() then
		local panel = self:panel()
		local screen_h = fullscreen_panel and fullscreen_panel:h() or 720
		local panel_y = panel:world_y()
		local new_height = screen_h - panel_y - 140

		-- Cache the 4-player ceiling so _setup_items can shrink the panel
		-- per actual player count and grow back without re-querying screen.
		self._max_panel_h = math.max(new_height, 300)
		panel:set_h(self._max_panel_h)
		panel:clear()

		-- In multiplayer as client, delay first setup to let sync data arrive
		if CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and not _G.CSR_MP_HostRank then
			panel:text({
				text = "Syncing...",
				font = tweak_data.menu.pd2_medium_font,
				font_size = 24,
				color = Color(0.6, 0.6, 0.6),
				align = "center",
				vertical = "center",
				w = panel:w(),
				h = panel:h(),
			})
			DelayedCalls:Add("CSR_ItemsPageDelayedInit", 0.5, function()
				if alive(panel) then
					panel:clear()
					self:_setup_items()
				end
			end)
		else
			self:_setup_items()
		end
	end
end

-- Old create_frame_bg function removed (not used in grid layout)

-- Old vertical list functions removed (replaced by grid layout with tooltips)

-- Scrap rows always render at the top of every items grid (Crime Spree menu
-- ITEMS tab, ESC items panel, TAB heist stats panel). Order within the scrap
-- bucket is Rare → Uncommon → Common; the rest of the list keeps its
-- original insertion order from build_items_for_peer below. Detection key
-- is item.icon == "csr_scrap" — set on all three scrap rows further down
-- (no other item shares that icon). scrapper_menu.lua treats the result as
-- an unordered icon→info map, so re-ordering doesn't affect it.
local SCRAP_ORDER = {
	["RARE SCRAP"] = 1,
	["UNCOMMON SCRAP"] = 2,
	["COMMON SCRAP"] = 3,
}
local function sort_scrap_first(items)
	local scrap, rest = {}, {}
	for _, it in ipairs(items) do
		if it.icon == "csr_scrap" then
			table.insert(scrap, it)
		else
			table.insert(rest, it)
		end
	end
	table.sort(scrap, function(a, b)
		return (SCRAP_ORDER[a.name] or 99) < (SCRAP_ORDER[b.name] or 99)
	end)
	for _, it in ipairs(rest) do
		table.insert(scrap, it)
	end
	return scrap
end

-- Build the items list for a specific peer_id.
-- Uses CSR_CountStacksForPeer so it works for any player in multiplayer.
local function build_items_for_peer(peer_id)
	local C = _G.CSR_ItemConstants or {}
	local items = {}

	local function count(id_prefix)
		return CSR_CountStacksForPeer(peer_id, id_prefix)
	end

	-- DOG TAGS
	local health_stacks = count("player_health_boost")
	if health_stacks > 0 then
		table.insert(items, {
			icon = "csr_dog_tags",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "DOG TAGS",
			stacks = health_stacks,
			desc = "Increases your max health.",
		})
	end

	-- EVIDENCE ROUNDS
	local damage_stacks = count("player_damage_boost")
	if damage_stacks > 0 then
		table.insert(items, {
			icon = "csr_evidence_rounds",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "EVIDENCE ROUNDS",
			stacks = damage_stacks,
			desc = "All your attacks deal more damage.",
		})
	end

	-- DOZER GUIDE
	local dozer_stacks = count("player_dozer_guide")
	if dozer_stacks > 0 then
		table.insert(items, {
			icon = "csr_dozer_guide",
			frame = "csr_frame",
			color = RARITY_COLOR_CONTRABAND,
			name = "DOZER GUIDE",
			stacks = dozer_stacks,
			desc = "Greatly increases your armor and damage,\nbut slows you down.",
		})
	end

	-- BONNIE'S LUCKY CHIP
	local bonnie_stacks = count("player_bonnie_chip")
	if bonnie_stacks > 0 then
		table.insert(items, {
			icon = "csr_bonnie_chip",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "BONNIE'S LUCKY CHIP",
			stacks = bonnie_stacks,
			desc = "Each hit has a small chance to instantly kill the target.",
		})
	end

	-- GLASS PISTOL
	local glass_stacks = count("player_glass_pistol")
	if glass_stacks > 0 then
		table.insert(items, {
			icon = "csr_glass_pistol",
			frame = "csr_frame",
			color = RARITY_COLOR_CONTRABAND,
			name = "GLASS PISTOL",
			stacks = glass_stacks,
			desc = "Massively increases all damage,\nbut halves your HP and armor.",
		})
	end

	-- FALCOGINI KEYS
	local keys_stacks = count("player_car_keys")
	if keys_stacks > 0 then
		table.insert(items, {
			icon = "csr_falcogini_keys",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "FALCOGINI KEYS",
			stacks = keys_stacks,
			desc = "Gives you a chance to dodge incoming damage.",
		})
	end

	-- PLUSH SHARK
	local shark_stacks = count("player_plush_shark")
	if shark_stacks > 0 then
		table.insert(items, {
			icon = "csr_plush_shark",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "PLUSH SHARK",
			stacks = shark_stacks,
			desc = "Saves you from custody once per life,\nrestores 1 down, full health and armor,\nthen grants brief invulnerability.",
		})
	end

	-- WOLF'S TOOLBOX
	local toolbox_stacks = count("player_wolfs_toolbox")
	if toolbox_stacks > 0 then
		table.insert(items, {
			icon = "csr_toolbox",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "WOLF'S TOOLBOX",
			stacks = toolbox_stacks,
			desc = "Killing enemies reduces the timer\non active drills and saws.",
		})
	end

	-- DUCT TAPE
	local duct_tape_stacks = count("player_duct_tape")
	if duct_tape_stacks > 0 then
		table.insert(items, {
			icon = "csr_duct_tape",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "DUCT TAPE",
			stacks = duct_tape_stacks,
			desc = "Makes you faster at interacting with objects.",
		})
	end

	-- ESCAPE PLAN
	local sneakers_stacks = count("player_escape_plan")
	if sneakers_stacks > 0 then
		table.insert(items, {
			icon = "csr_escape_plan",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "ESCAPE PLAN",
			stacks = sneakers_stacks,
			desc = "Increases your movement speed.",
		})
	end

	-- WORN BAND-AID
	local bandaid_stacks = count("player_worn_bandaid")
	if bandaid_stacks > 0 then
		table.insert(items, {
			icon = "csr_worn_bandaid",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "WORN BAND-AID",
			stacks = bandaid_stacks,
			desc = "Slowly regenerates a small amount of health over time.",
		})
	end

	-- CUP OF JOE
	local coffee_stacks = count("player_cup_of_joe")
	if coffee_stacks > 0 then
		table.insert(items, {
			icon = "csr_cup_of_joe",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "CUP OF JOE",
			stacks = coffee_stacks,
			desc = "Increases your maximum stamina.",
		})
	end

	-- PIECE OF REBAR
	local rebar_stacks = count("player_rebar_")
	if rebar_stacks > 0 then
		table.insert(items, {
			icon = "csr_rebar",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "PIECE OF REBAR",
			stacks = rebar_stacks,
			desc = "Your first hit on an enemy deals bonus damage.",
		})
	end

	-- HALF-A-GLASS
	local hag_stacks = count("player_half_a_glass_")
	if hag_stacks > 0 then
		table.insert(items, {
			icon = "csr_half_a_glass",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "HALF-A-GLASS",
			stacks = hag_stacks,
			desc = "Picking up Gage packages restores some ammo and increases max capacity for the mission.",
		})
	end

	-- PINK SLIP (Kill to Heal)
	local pink_slip_stacks = count("player_pink_slip_")
	if pink_slip_stacks > 0 then
		table.insert(items, {
			icon = "csr_pink_slip",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "PINK SLIP",
			stacks = pink_slip_stacks,
			desc = "Killing an enemy restores health.",
		})
	end

	-- THE EDGE (Last-resort heal)
	local the_edge_stacks = count("player_the_edge_")
	if the_edge_stacks > 0 then
		table.insert(items, {
			icon = "csr_the_edge",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "THE EDGE",
			stacks = the_edge_stacks,
			desc = "When critically low on health,\nrestores health and grants brief invulnerability.",
		})
	end

	-- OVERKILL RUSH (Kill Streak: Fire Rate + Reload Speed)
	local overkill_rush_stacks = count("player_overkill_rush_")
	if overkill_rush_stacks > 0 then
		table.insert(items, {
			icon = "csr_overkill_rush",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "OVERKILL RUSH",
			stacks = overkill_rush_stacks,
			desc = "Killing enemies temporarily increases fire rate and reload speed.",
		})
	end

	-- JIRO'S LAST WISH
	local jiro_stacks = count("player_jiro_last_wish")
	if jiro_stacks > 0 then
		table.insert(items, {
			icon = "csr_jiro_last_wish",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "JIRO'S LAST WISH",
			stacks = jiro_stacks,
			desc = "Sprint while charging a melee attack. Increases melee damage.",
		})
	end

	-- DEAREST POSSESSION
	local dp_stacks = count("player_dearest_possession")
	if dp_stacks > 0 then
		table.insert(items, {
			icon = "csr_dearest_possession",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "DEAREST POSSESSION",
			stacks = dp_stacks,
			desc = "Healing at full HP converts to temporary shields that quickly fade away.",
		})
	end

	-- VIKLUND'S VINYL
	local vv_stacks = count("player_viklund_vinyl")
	if vv_stacks > 0 then
		table.insert(items, {
			icon = "csr_viklund_vinyl",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "VIKLUND'S VINYL",
			stacks = vv_stacks,
			desc = "...and his beats were electric.",
		})
	end

	-- LOCKE'S BERET
	local lb_stacks = count("player_lockes_beret_")
	if lb_stacks > 0 then
		table.insert(items, {
			icon = "csr_lockes_beret",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "LOCKE'S BERET",
			stacks = lb_stacks,
			desc = "Periodically heals everyone in your team.",
		})
	end

	-- EQUALIZER
	local eq_stacks = count("player_equalizer_")
	if eq_stacks > 0 then
		table.insert(items, {
			icon = "csr_equalizer",
			frame = "csr_frame",
			color = RARITY_COLOR_CONTRABAND,
			name = "EQUALIZER",
			stacks = eq_stacks,
			desc = "Greatly increases damage against special enemies,\nbut reduces it against regular ones.",
		})
	end

	-- CROOKED BADGE
	local cb_stacks = count("player_crooked_badge_")
	if cb_stacks > 0 then
		table.insert(items, {
			icon = "csr_crooked_badge",
			frame = "csr_frame",
			color = RARITY_COLOR_CONTRABAND,
			name = "CROOKED BADGE",
			stacks = cb_stacks,
			desc = "Chance to restore a down after each assault.\nBut your bleedout timer is reduced.",
		})
	end

	-- DEAD MAN'S TRIGGER
	local dmt_stacks = count("player_dead_mans_trigger_")
	if dmt_stacks > 0 then
		table.insert(items, {
			icon = "csr_dead_mans_trigger",
			frame = "csr_frame",
			color = RARITY_COLOR_CONTRABAND,
			name = "DEAD MAN'S TRIGGER",
			stacks = dmt_stacks,
			desc = "Going down triggers an explosion around you.\nBut allies also receive damage from it.",
		})
	end

	-- WILDCARD items
	-- Tagged with is_wildcard=true so both surfaces (briefing items page +
	-- in-mission TAB) can split them out into the dedicated right-column slot.
	-- No `stacks` field — wildcards are carry-1, the "x1" counter is noise.
	-- FAMILIAR FRIEND
	if count("player_familiar_friend_") > 0 then
		table.insert(items, {
			icon = "csr_familiar_friend",
			frame = "csr_frame",
			color = RARITY_COLOR_WILDCARD,
			is_wildcard = true,
			name = "FAMILIAR FRIEND",
			desc = "Release spike nova around you.",
		})
	end

	-- SIDE SATCHEL
	if count("player_side_satchel_") > 0 then
		table.insert(items, {
			icon = "csr_side_satchel",
			frame = "csr_frame",
			color = RARITY_COLOR_WILDCARD,
			is_wildcard = true,
			name = "SIDE SATCHEL",
			desc = "Doubles the carry amount of mission equipment.",
		})
	end

	-- TURRON
	if count("player_turron_") > 0 then
		table.insert(items, {
			icon = "csr_turron",
			frame = "csr_frame",
			color = RARITY_COLOR_WILDCARD,
			is_wildcard = true,
			name = "TURRON",
			desc = "Heals you and reduces incoming damage for few seconds.",
		})
	end

	-- HIPPOCRATIC OATH
	if count("player_hippocratic_oath_") > 0 then
		table.insert(items, {
			icon = "csr_hippocratic_oath",
			frame = "csr_frame",
			color = RARITY_COLOR_WILDCARD,
			is_wildcard = true,
			name = "HIPPOCRATIC OATH",
			desc = "A medic joins your crew in loud and heals you when nearby.",
		})
	end

	-- COMMON SCRAP (produced by the in-world scrapper; printer fodder)
	local scrap_common_stacks = count("player_scrap_common_")
	if scrap_common_stacks > 0 then
		table.insert(items, {
			icon = "csr_scrap",
			frame = "csr_frame",
			color = RARITY_COLOR_COMMON,
			name = "COMMON SCRAP",
			stacks = scrap_common_stacks,
			desc = "Does nothing. Prioritized when used with Printers.",
		})
	end

	-- UNCOMMON SCRAP
	local scrap_uncommon_stacks = count("player_scrap_uncommon_")
	if scrap_uncommon_stacks > 0 then
		table.insert(items, {
			icon = "csr_scrap",
			frame = "csr_frame",
			color = RARITY_COLOR_UNCOMMON,
			name = "UNCOMMON SCRAP",
			stacks = scrap_uncommon_stacks,
			desc = "Does nothing. Prioritized when used with Printers.",
		})
	end

	-- RARE SCRAP
	local scrap_rare_stacks = count("player_scrap_rare_")
	if scrap_rare_stacks > 0 then
		table.insert(items, {
			icon = "csr_scrap",
			frame = "csr_frame",
			color = RARITY_COLOR_RARE,
			name = "RARE SCRAP",
			stacks = scrap_rare_stacks,
			desc = "Does nothing. Prioritized when used with Printers.",
		})
	end

	return sort_scrap_first(items)
end

-- Expose for other screens (e.g. in-game pause menu items tab)
_G.CSR_BuildItemsForPeer = build_items_for_peer

-- Render one player's item grid into `content` starting at `start_y`.
-- Appends hit-detection entries into `self._item_positions`.
-- Returns the y position immediately after the last row of icons.
-- Calculate cell size to fit all items within available width and height.
-- Returns cell size clamped between min_cell and max_cell.
local function calc_cell_size(item_count, avail_w, avail_h, max_cell, min_cell)
	if item_count <= 0 then
		return max_cell
	end
	local cell = max_cell
	while cell > min_cell do
		local cols = math.max(1, math.floor(avail_w / cell))
		local rows = math.ceil(item_count / cols)
		if rows * cell <= avail_h then
			return cell
		end
		cell = cell - 2
	end
	return min_cell
end

-- Render the right-column wildcard slot for one peer. Frame is stretched to
-- slot_w x slot_h (a tall pill) so the wildcard column fills the full
-- items-panel height. When `wildcards` is non-empty, the icon stays square
-- (no warp) and centers in the column, with stack counter top-right and
-- hit detection covering the entire stretched frame. When empty, a dim
-- magenta placeholder fills the same area. Carry-1 means at most one icon.
function CrimeSpreePlayerItemsPage:_render_wildcard_slot(content, wildcards, slot_x, slot_y, slot_w, slot_h, peer_id)
	if #wildcards > 0 then
		local item = wildcards[1]
		local ICON_SCALE = _G.CSR_IconScale or {}

		if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
			local fd = tweak_data.hud_icons[item.frame]
			content:bitmap({
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				w = slot_w,
				h = slot_h,
				x = slot_x,
				y = slot_y,
				color = item.color or Color.white,
				layer = 0,
			})
		end

		if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
			local icon_data = tweak_data.hud_icons[item.icon]
			local base_icon = math.floor(slot_w * WILDCARD_ICON_FRAME_RATIO)
			local this_icon_size = base_icon * (ICON_SCALE[item.icon] or 1)
			local ix = slot_x + math.floor((slot_w - this_icon_size) / 2)
			local iy = slot_y + math.floor((slot_h - this_icon_size) / 2)
			content:bitmap({
				texture = icon_data.texture,
				texture_rect = icon_data.texture_rect,
				w = this_icon_size,
				h = this_icon_size,
				x = ix,
				y = iy,
				color = Color.white,
				layer = 2,
			})
		end

		if item.stacks and item.stacks >= 1 then
			local stack_str = "x" .. tostring(item.stacks)
			local stack_font = 16
			local sw = 30
			local text_x = slot_x + slot_w - sw - 4
			local text_y = slot_y
			for dx = -1, 1 do
				for dy = -1, 1 do
					if not (dx == 0 and dy == 0) then
						content:text({
							text = stack_str,
							font = tweak_data.menu.pd2_medium_font,
							font_size = stack_font,
							color = Color.black,
							x = text_x + dx,
							y = text_y + dy,
							w = sw,
							layer = 4,
							align = "right",
							vertical = "top",
						})
					end
				end
			end
			content:text({
				text = stack_str,
				font = tweak_data.menu.pd2_medium_font,
				font_size = stack_font,
				color = Color.white,
				x = text_x,
				y = text_y,
				w = sw,
				layer = 5,
				align = "right",
				vertical = "top",
			})
		end

		table.insert(self._item_positions, {
			x1 = slot_x,
			y1 = slot_y,
			x2 = slot_x + slot_w,
			y2 = slot_y + slot_h,
			item = item,
			peer_id = peer_id,
		})
		return
	end

	-- Empty placeholder: dim magenta frame stretched to fill the entire slot.
	if tweak_data.hud_icons and tweak_data.hud_icons.csr_frame then
		local fd = tweak_data.hud_icons.csr_frame
		content:bitmap({
			texture = fd.texture,
			texture_rect = fd.texture_rect,
			w = slot_w,
			h = slot_h,
			x = slot_x,
			y = slot_y,
			color = WILDCARD_PLACEHOLDER_COLOR,
			layer = 0,
		})
	end
end

function CrimeSpreePlayerItemsPage:_render_item_grid(
	content,
	items,
	start_y,
	peer_id,
	cell_override,
	area_x,
	area_w,
	force_single_col,
	left_align
)
	-- Per-icon scale overrides (1.0 = default, <1.0 = smaller, >1.0 = bigger)
	local ICON_SCALE = _G.CSR_IconScale or {}

	local DEFAULT_FRAME = 74
	local DEFAULT_CELL = DEFAULT_FRAME - 2
	local icon_cell = cell_override or DEFAULT_CELL
	local frame_size = icon_cell + 2
	local icon_size = math.floor(38 * (frame_size / DEFAULT_FRAME)) -- Scale icon proportionally
	-- area_x / area_w restrict rendering to a sub-rect of `content`. Default = full content width.
	area_x = area_x or 0
	area_w = area_w or content:w()
	local content_width = area_w
	-- Wildcards force a 1-column vertical stack even if the cell is small enough
	-- to allow multiple columns inside the slot width.
	local icons_per_row
	if force_single_col then
		icons_per_row = 1
	else
		icons_per_row = math.max(1, math.floor(content_width / icon_cell))
	end
	-- Horizontal alignment: left_align=true pins the leftmost icon to area_x
	-- (used by the main rarity grid so it doesn't drift right when item count
	-- shrinks). Otherwise center the row in the sub-rect (used by the
	-- wildcard slot delegate so the single icon sits in the middle).
	local total_row_width = icons_per_row * icon_cell
	local start_x
	if left_align then
		start_x = area_x
	else
		start_x = area_x + math.floor((content_width - total_row_width) / 2)
	end

	-- Draw icons in grid
	for i, item in ipairs(items) do
		local col = (i - 1) % icons_per_row
		local row = math.floor((i - 1) / icons_per_row)
		local x = start_x + col * icon_cell
		local y = start_y + row * icon_cell

		-- Frame (DDS hexagon texture, unified for all rarities)
		if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
			local frame_data = tweak_data.hud_icons[item.frame]
			content:bitmap({
				texture = frame_data.texture,
				texture_rect = frame_data.texture_rect,
				w = frame_size,
				h = frame_size,
				x = x,
				y = y,
				color = item.color or Color.white,
				layer = 0,
			})
		end

		-- Icon (centered in frame)
		if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
			local icon_data = tweak_data.hud_icons[item.icon]
			local this_icon_size = icon_size * (ICON_SCALE[item.icon] or 1)
			local icon_offset = (frame_size - this_icon_size) / 2 -- Center icon within frame
			local ix = x + icon_offset
			local iy = y + icon_offset

			content:bitmap({
				texture = icon_data.texture,
				texture_rect = icon_data.texture_rect,
				w = this_icon_size,
				h = this_icon_size,
				x = ix,
				y = iy,
				color = Color.white,
				layer = 2,
			})
		end

		-- Stack counter (top right corner)
		if item.stacks and item.stacks >= 1 then
			local stack_str = "x" .. tostring(item.stacks)
			local stack_font = 16
			local sw = 30
			local text_x = x + frame_size - sw - 4
			local text_y = y

			-- Text shadow
			for dx = -1, 1 do
				for dy = -1, 1 do
					if not (dx == 0 and dy == 0) then
						content:text({
							text = stack_str,
							font = tweak_data.menu.pd2_medium_font,
							font_size = stack_font,
							color = Color.black,
							x = text_x + dx,
							y = text_y + dy,
							w = sw,
							layer = 4,
							align = "right",
							vertical = "top",
						})
					end
				end
			end

			-- Main text
			content:text({
				text = stack_str,
				font = tweak_data.menu.pd2_medium_font,
				font_size = stack_font,
				color = Color.white,
				x = text_x,
				y = text_y,
				w = sw,
				layer = 5,
				align = "right",
				vertical = "top",
			})
		end

		-- Save position for hit detection (include peer_id for tooltip owner label)
		table.insert(self._item_positions, {
			x1 = x,
			y1 = y,
			x2 = x + frame_size,
			y2 = y + frame_size,
			item = item,
			peer_id = peer_id,
		})
	end

	-- Return the y coordinate just below the last row
	local row_count = math.ceil(#items / icons_per_row)
	return start_y + row_count * icon_cell
end

function CrimeSpreePlayerItemsPage:_setup_items()
	local panel = self:panel()
	if not panel or not alive(panel) then
		return
	end

	-- Resize panel to fit the actual lobby size. Per-section height is fixed
	-- (BASE_SECTION_H = what each player gets in a full 4-player layout); only
	-- the total height shrinks/grows. 1 player = ¼ panel, 4 players = full.
	local fake_4 = _G.CSR_DEBUG_FAKE_4_PLAYERS == true
	local in_mp = fake_4 or (_G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer())
	local peer_ids = {}
	if fake_4 then
		peer_ids = { 1, 2, 3, 4 }
	elseif in_mp then
		for pid, _ in pairs(_G.CSR_PlayerItems) do
			table.insert(peer_ids, pid)
		end
		table.sort(peer_ids)
	end
	local num_players = in_mp and math.max(1, math.min(4, #peer_ids)) or 1

	local section_gap = 6
	local max_h = self._max_panel_h or panel:h()
	local BASE_SECTION_H = math.floor((max_h - 3 * section_gap) / 4)
	local target_h = num_players * BASE_SECTION_H + math.max(0, num_players - 1) * section_gap
	if panel:h() ~= target_h then
		panel:set_h(target_h)
	end

	-- Wildcard column is square: 1:1 hex, sized at 70% of the section height
	-- so it doesn't dominate the row. Vertically centered at each call site.
	local wildcard_slot_size = math.floor(BASE_SECTION_H * 0.7)

	-- Create dark background (alive check: panel:clear() in delayed init destroys children)
	if not self._background or not alive(self._background) then
		self._background = panel:rect({
			name = "csr_items_background",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			color = Color.black,
			alpha = 0.4,
			layer = -1,
		})
	elseif self._background:h() ~= panel:h() then
		self._background:set_h(panel:h())
	end

	-- Create nested panel for content (alive check: panel:clear() in delayed init destroys children)
	if not self._content_panel or not alive(self._content_panel) then
		self._content_panel = panel:panel({
			name = "csr_items_content",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
		})
	elseif self._content_panel:h() ~= panel:h() then
		self._content_panel:set_h(panel:h())
	end

	local content = self._content_panel
	content:clear()

	-- Check if Crime Spree is active. Use is_active() OR in_progress() for
	-- consistency with the project-wide pattern; this code path doesn't currently
	-- run inside an active heist transition, but defensive against future entry
	-- points (see pd2_cs_is_active_vs_in_progress memory).
	local cs = managers.crime_spree
	local cs_running = cs and ((cs.is_active and cs:is_active()) or (cs.in_progress and cs:in_progress()))
	if not cs_running then
		local placeholder = managers.localization:text("menu_csr_items_placeholder")
		content:text({
			text = placeholder,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 20,
			y = 25,
		})
		return
	end

	-- Reset hit-detection table before rebuilding all sections
	self._item_positions = {}

	-- fake_4 / in_mp / peer_ids / num_players were resolved above for sizing.
	if in_mp then
		-- === MULTIPLAYER: one section per player, sorted by peer_id ===

		-- Check if any player has items at all
		local any_items = fake_4
		for _, pid in ipairs(peer_ids) do
			local data = _G.CSR_PlayerItems[pid]
			if data and data.items and #data.items > 0 then
				any_items = true
				break
			end
		end

		if not any_items then
			local placeholder = managers.localization:text("menu_csr_items_placeholder")
			content:text({
				text = placeholder,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 20,
				color = Color(0.5, 0.5, 0.5),
				x = 20,
				y = 25,
			})
		else
			local local_peer_id = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			local header_font_size = 16
			local header_h = header_font_size + 4
			local DEFAULT_CELL = 72
			local MIN_CELL = 20

			-- Per-section height stays at the 4-player baseline; total panel
			-- height was already shrunk to fit num_players sections + gaps.
			local section_h = BASE_SECTION_H
			local grid_h = section_h - header_h

			local local_pid_for_fake = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			for idx, pid in ipairs(peer_ids) do
				local data = _G.CSR_PlayerItems[pid]
				if fake_4 and not data then
					-- Fake-4 mode: fabricate a data shell so the section
					-- renders even when this peer_id has no real data.
					data = { items = {}, name = "DEBUG Player " .. pid }
				end
				if data then
					-- In fake-4 mode, use the local player's items for every
					-- fake peer so the layout shows real content.
					local source_pid = (fake_4 and not _G.CSR_PlayerItems[pid]) and local_pid_for_fake or pid
					local items = build_items_for_peer(source_pid)
					local section_y = (idx - 1) * (section_h + section_gap)

					-- Separator line between players (not before the first)
					if idx > 1 then
						local line_y = section_y - math.floor(section_gap / 2)
						content:rect({
							x = 20,
							y = line_y,
							w = content:w() - 40,
							h = 1,
							color = Color(1, 0.4, 0.4, 0.4),
							layer = 1,
						})
					end

					-- Resolve player name from live session (cached name may be stale/empty)
					local player_name
					local session = managers.network and managers.network:session()
					if session then
						local peer = (pid == local_peer_id) and session:local_peer() or session:peer(pid)
						player_name = peer and peer:name()
					end
					if not player_name or player_name == "" then
						player_name = (data.name and data.name ~= "") and data.name or ("Player " .. pid)
					end

					-- Vanilla peer colors, saturated for contrast on dark background
					local peer_vec = tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[pid]
					local header_color
					if peer_vec then
						local r, g, b = peer_vec.x, peer_vec.y, peer_vec.z
						local grey = (r + g + b) / 3
						local sat = 1.5
						header_color = Color(
							1,
							math.min(math.max(grey + (r - grey) * sat, 0), 1),
							math.min(math.max(grey + (g - grey) * sat, 0), 1),
							math.min(math.max(grey + (b - grey) * sat, 0), 1)
						)
					else
						header_color = Color.white
					end

					content:text({
						text = player_name,
						font = tweak_data.menu.pd2_medium_font,
						font_size = header_font_size,
						color = header_color,
						x = 20,
						y = section_y,
						layer = 1,
					})

					local grid_y = section_y + header_h

					-- Split wildcards out for the dedicated right-column slot.
					local regular, wildcards = split_wildcards(items)
					local main_w = content:w()
						- MAIN_GRID_LEFT_PAD
						- wildcard_slot_size
						- WILDCARD_SLOT_GAP
						- WILDCARD_SLOT_RIGHT_PAD
					local slot_x = MAIN_GRID_LEFT_PAD + main_w + WILDCARD_SLOT_GAP

					if #regular > 0 then
						local start_cell = math.min(DEFAULT_CELL, grid_h)
						local cell = calc_cell_size(#regular, main_w, grid_h, start_cell, MIN_CELL)
						-- left_align=true → row pins to area_x (= LEFT_PAD), so it
						-- doesn't drift right inside main_w when the count shrinks.
						self:_render_item_grid(
							content,
							regular,
							grid_y,
							pid,
							cell,
							MAIN_GRID_LEFT_PAD,
							main_w,
							false,
							true
						)
					elseif #wildcards == 0 then
						content:text({
							text = "No items yet",
							font = tweak_data.menu.pd2_small_font,
							font_size = 14,
							color = Color(0.45, 0.45, 0.45),
							x = 20,
							y = grid_y,
							layer = 1,
						})
					end

					-- Always reserve the right-column slot, even when empty — so layout
					-- doesn't reflow on first wildcard pickup. Slot is a square
					-- vertically centered within the player's section so it sits
					-- visually balanced beside the items grid.
					local slot_y = section_y + math.floor((section_h - wildcard_slot_size) / 2)
					self:_render_wildcard_slot(
						content,
						wildcards,
						slot_x,
						slot_y,
						wildcard_slot_size,
						wildcard_slot_size,
						pid
					)
				end
			end
		end
	else
		-- === SINGLEPLAYER: render local player's items without header ===
		local local_peer_id = CSR_LocalPeerId and CSR_LocalPeerId() or 1
		local items = build_items_for_peer(local_peer_id)

		-- Split wildcards out for the dedicated right-column slot.
		local regular, wildcards = split_wildcards(items)
		local main_w = content:w()
			- MAIN_GRID_LEFT_PAD
			- wildcard_slot_size
			- WILDCARD_SLOT_GAP
			- WILDCARD_SLOT_RIGHT_PAD
		local slot_x = MAIN_GRID_LEFT_PAD + main_w + WILDCARD_SLOT_GAP

		if #regular > 0 then
			-- left_align=true → row pins to area_x (= LEFT_PAD).
			self:_render_item_grid(content, regular, 10, local_peer_id, nil, MAIN_GRID_LEFT_PAD, main_w, false, true)
		elseif #wildcards == 0 then
			local placeholder = managers.localization:text("menu_csr_items_placeholder")
			content:text({
				text = placeholder,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 20,
				color = Color(0.5, 0.5, 0.5),
				x = 20,
				y = 25,
			})
		end

		-- Always reserve the right-column slot, even when empty. Slot is a
		-- square vertically centered within the panel so it sits visually
		-- balanced beside the items grid.
		local slot_y = math.floor((content:h() - wildcard_slot_size) / 2)
		self:_render_wildcard_slot(
			content,
			wildcards,
			slot_x,
			slot_y,
			wildcard_slot_size,
			wildcard_slot_size,
			local_peer_id
		)
	end

	-- Create tooltip panel on fullscreen_panel so it can overflow tab boundaries
	if self._tooltip_panel then
		pcall(function()
			self._tooltip_panel:parent():remove(self._tooltip_panel)
		end)
		self._tooltip_panel = nil
	end
	if self._fullscreen_panel then
		self._tooltip_panel = self._fullscreen_panel:panel({
			name = "csr_tooltip",
			visible = false,
			layer = 100,
		})
	end

	-- Decorative border
	self:_create_corners()
end

-- Create decorative corners (BoxGuiObject - same as in logbook)
function CrimeSpreePlayerItemsPage:_create_corners()
	local panel = self:panel()
	if not panel then
		return
	end

	if BoxGuiObject then
		self._box = BoxGuiObject:new(panel, {
			sides = { 1, 1, 1, 1 },
			color = Color.white,
		})
	else
	end
end

-- Scrollbar no longer needed (grid items fit in available space)

-- Rebuild items on every tab switch so new items from host appear
function CrimeSpreePlayerItemsPage:set_active(active)
	if active then
		self:_setup_items()
	end
	return CrimeSpreePlayerItemsPage.super.set_active(self, active)
end

function CrimeSpreePlayerItemsPage:get_legend()
	return {}
end

-- Handle mouse hover to show tooltip
-- NOTE: Diesel Engine passes event object (o) as first parameter, then coordinates
function CrimeSpreePlayerItemsPage:mouse_moved(o, x, y)
	-- Hide tooltip when this tab is not active (vanilla calls mouse_moved on ALL pages)
	-- Also hide when the item selection popup is open (crime_spree_select_modifiers node)
	local active_menu = managers.menu and managers.menu:active_menu()
	local sel_node = active_menu and active_menu.logic and active_menu.logic:selected_node()
	local sel_name = sel_node and sel_node:parameters() and sel_node:parameters().name
	local popup_open = sel_name == "crime_spree_select_modifiers" or _G._csr_briefing_comp ~= nil

	if not self._active or popup_open then
		if self._tooltip_panel and self._tooltip_panel:visible() then
			self._tooltip_panel:set_visible(false)
		end
		return false
	end

	-- Validate that coordinates are numbers
	if type(x) ~= "number" or type(y) ~= "number" then
		return false
	end

	if not self._item_positions or not self._tooltip_panel then
		return false
	end

	local content = self._content_panel
	if not content then
		return false
	end

	-- Safely get panel world coordinates
	local world_x = content:world_x()
	local world_y = content:world_y()

	if type(world_x) ~= "number" or type(world_y) ~= "number" then
		return false
	end

	-- Convert mouse coordinates to content panel local coordinates
	local local_x = x - world_x
	local local_y = y - world_y

	-- Check if mouse is hovering over an icon
	local hovered_item = nil
	local hovered_pos = nil
	for _, pos in ipairs(self._item_positions) do
		if local_x >= pos.x1 and local_x <= pos.x2 and local_y >= pos.y1 and local_y <= pos.y2 then
			hovered_item = pos.item
			hovered_pos = pos
			break
		end
	end

	if hovered_item and hovered_pos then
		-- Anchor tooltip to bottom-right of the icon frame (world coordinates)
		self:_show_tooltip(hovered_item, hovered_pos.x2, hovered_pos.y2, hovered_pos.peer_id)
	else
		-- Hide tooltip
		if self._tooltip_panel:visible() then
			self._tooltip_panel:set_visible(false)
		end
	end

	return false -- Do NOT block other mouse events (important for button clicks)
end

-- Show tooltip for item (positioned on fullscreen_panel in world coordinates).
-- peer_id is optional; when provided and not the local player, the owner name is prepended to the title.
function CrimeSpreePlayerItemsPage:_show_tooltip(item, local_x, local_y, peer_id)
	local tooltip = self._tooltip_panel
	if not tooltip then
		return
	end
	if type(local_x) ~= "number" or type(local_y) ~= "number" then
		return
	end

	local content = self._content_panel
	local fs = self._fullscreen_panel
	if not content or not fs then
		return
	end

	tooltip:clear()

	local tooltip_w = 280
	local padding = 10

	local title_text = item.name

	-- Measure description text height
	local desc_text = tooltip:text({
		text = item.desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		x = padding,
		y = padding + 25,
		w = tooltip_w - padding * 2,
		wrap = true,
		word_wrap = true,
		layer = 2,
	})

	local _, _, _, desc_h = desc_text:text_rect()
	local tooltip_h = padding + 25 + desc_h + padding

	-- Convert content-local icon position to fullscreen_panel coordinates
	local world_x = content:world_x() + local_x
	local world_y = content:world_y() + local_y
	local tooltip_x = world_x - fs:world_x() + 25
	local tooltip_y = world_y - fs:world_y() + 15

	-- Clamp to screen bounds
	local screen_w = fs:w()
	local screen_h = fs:h()
	if tooltip_x + tooltip_w > screen_w - 10 then
		tooltip_x = screen_w - tooltip_w - 10
	end
	if tooltip_y + tooltip_h > screen_h - 10 then
		tooltip_y = screen_h - tooltip_h - 10
	end

	tooltip:set_shape(tooltip_x, tooltip_y, tooltip_w, tooltip_h)

	-- Background
	tooltip:rect({
		color = Color.black,
		alpha = 0.9,
		layer = 0,
	})

	-- Border
	local border_color = item.color or Color.white
	local border_size = 2
	tooltip:rect({ x = 0, y = 0, w = tooltip_w, h = border_size, color = border_color, alpha = 0.4, layer = 1 })
	tooltip:rect({
		x = 0,
		y = tooltip_h - border_size,
		w = tooltip_w,
		h = border_size,
		color = border_color,
		alpha = 0.4,
		layer = 1,
	})
	tooltip:rect({ x = 0, y = 0, w = border_size, h = tooltip_h, color = border_color, alpha = 0.4, layer = 1 })
	tooltip:rect({
		x = tooltip_w - border_size,
		y = 0,
		w = border_size,
		h = tooltip_h,
		color = border_color,
		alpha = 0.4,
		layer = 1,
	})

	-- Title
	tooltip:text({
		text = title_text,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = item.color or Color.white,
		x = padding,
		y = padding,
		layer = 2,
	})

	tooltip:set_visible(true)
end

function CrimeSpreePlayerItemsPage:mouse_wheel_up(x, y)
	return false -- Scrolling removed
end

function CrimeSpreePlayerItemsPage:mouse_wheel_down(x, y)
	return false -- Scrolling removed
end

function CrimeSpreePlayerItemsPage:update(t, dt)
	-- Do NOT call super.update: parent's _next_text and _scroll are destroyed by panel:clear() in init,
	-- calling super.update on a non-host causes a C++ access violation when server_spree_level changes.
end

-- === HOOK TO ADD TAB ===
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddPlayerItemsTab", function(self, tabs_data)
	table.insert(tabs_data, 1, {
		name_id = "menu_csr_items",
		width_multiplier = 1,
		page_class = "CrimeSpreePlayerItemsPage",
	})
end)

-- Clear stale page instances when the CS details component is destroyed.
-- Without this, CSR_*PageInstance globals point to dead objects after lobby
-- transitions, and refreshes from outside (e.g. the printer in the Gage's
-- Services window) crash inside panel:w() because pcall can't catch native
-- access violations from dead panel references.
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "close", "CSR_ClearPageInstances", function(self)
	_G.CSR_ItemsPageInstance = nil
	_G.CSR_PrinterPageInstance = nil
	_G.CSR_StatsPageInstance = nil
end)
