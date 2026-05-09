-- Scrapper item-pick menu.
-- ---------------------------------------------------------------------------
-- v2: fullscreen workspace overlay. Renders the local player's items as an
-- icon grid styled like the ITEMS tab (csr_frame + icon + stack counter,
-- rarity color tint). Picking a cell logs and closes — the actual scrap
-- payoff is wired in a later pass.
-- ---------------------------------------------------------------------------
-- Input: mouse_pointer:use_mouse — last callback in stack receives events
-- (LIFO), so the overlay grabs all clicks until we remove_mouse on close.
--   mouse_move(o, x, y, ws)
--   mouse_press(o, button, x, y)   button = Idstring("0") LMB / "1" RMB
-- The pointer manager auto-shows the cursor on use_mouse() and hides it on
-- remove_mouse() once the callback stack is empty (mousepointermanager.lua
-- _activate / _deactivate). The player's mouse-look gets re-routed to the
-- workspace, but WASD keeps working — accepted for v1, polish later.

if not RequiredScript then
	return
end

-- Visual constants — match items_page.lua so the cells look identical to the
-- ITEMS tab.
local FRAME_PX = 74
local ICON_PX = 38
local CELL_PX = FRAME_PX + 6
local TITLE_PX = 36
local SUBTITLE_PX = 22
local PADDING = 24
local INFO_AREA_PX = 96 -- name + multi-line description block
local CANCEL_HINT_PX = 22
local BORDER_PX = 2
local BORDER_COLOR = Color(1, 1, 1, 1) -- opaque white
local PANEL_COLOR = Color(0.7, 0, 0, 0) -- semi-transparent black (alpha, r, g, b)

-- Per-rarity tint of csr_frame.dds. Mirrors copier_spawner.lua:50-55 and
-- items_page.lua RARITY_COLOR_* constants. Wildcard is magenta per the
-- wildcard tier project memory.
local RARITY_COLOR = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0, 1),
}

local RARITY_LABEL = {
	common = "Common",
	uncommon = "Uncommon",
	rare = "Rare",
	contraband = "Contraband",
	wildcard = "Wildcard",
}

local HOVER_HIGHLIGHT = Color(0.4, 1, 0.85, 0.2)
local HOVER_TEXT_ALPHA = 0.9

local MOUSE_LMB = Idstring("0")
local MOUSE_RMB = Idstring("1")

-- Raw scancodes used to detect "player wants to move/cancel". We can't go
-- through the player's controller because we disable that whole controller on
-- open (the vanilla freeze trick — see playermovement.lua:1259), so action
-- name lookups would all return false. Raw scancodes bypass that and work
-- regardless of controller state. Trade-off: rebound movement keys won't
-- close the menu — those players should right-click instead.
local CLOSE_ON_KEYS = {
	Idstring("w"),
	Idstring("a"),
	Idstring("s"),
	Idstring("d"),
	Idstring("space"),
	Idstring("left ctrl"),
	Idstring("right ctrl"),
	Idstring("c"),
	Idstring("esc"),
}

local _state = nil

local function loc(key, fallback)
	if managers and managers.localization and managers.localization.text then
		local s = managers.localization:text(key)
		if s and s ~= "" and s ~= key then
			return s
		end
	end
	return fallback or key
end

-- Pull the player-facing display name from a registry def. Always goes through
-- def.loc_key (which localization.lua stores as "NAME\nDescription"); we take
-- the first line. Critical: never fall back to def.type — that field is the
-- mechanical id (e.g. "health" for Dog Tags) and is NOT a player-facing name.
-- See memory/feedback_dog_tags_naming.md.
local function display_name_for(def)
	if not def then
		return "?"
	end
	if def.loc_key and managers and managers.localization and managers.localization.text then
		local s = managers.localization:text(def.loc_key)
		if s and s ~= "" and s ~= def.loc_key then
			local nl = string.find(s, "\n", 1, true)
			if nl then
				return string.sub(s, 1, nl - 1)
			end
			return s
		end
	end
	return "?"
end

-- Group the local player's items by id_prefix so each unique type is one
-- cell with a stack counter. Returns list of { def, prefix, stacks }.
-- Hard-gated on managers.crime_spree:is_active(): items linger in
-- CSR_PlayerItems across CS runs (persisted via player_items_store), so
-- without this guard a prior run's items leak into the safehouse scrapper
-- menu. This is the same pattern bugfix_item_leak_outside_cs.md mandates
-- for CSR_CountStacks() — items must be invisible to UI outside an active
-- spree. Debug-mode bypass lets us test the menu in safehouse with items
-- granted via the debug menu.
local function build_groups()
	local debug_on = _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode
	local cs = managers and managers.crime_spree
	local in_cs = cs and cs.is_active and cs:is_active()
	if not (in_cs or debug_on) then
		return {}
	end
	local items_fn = _G.CSR_GetLocalItems
	local registry = _G.CSR_ITEM_BY_PREFIX
	if not (items_fn and registry) then
		return {}
	end
	local items = items_fn() or {}
	local groups = {}
	local order = {}
	-- Only rarities with a corresponding scrap output can be scrapped. Per the
	-- scrap design, contraband and wildcard have no scrap variant — clicking
	-- one would have no valid output, so hide them from the menu instead of
	-- showing dead cells. Mirrors RARITY_TO_SCRAP_PREFIX in on_pick().
	local SCRAPPABLE_RARITIES = {
		common = true,
		uncommon = true,
		rare = true,
	}
	for _, item in ipairs(items) do
		if item.id then
			local prefix = item.id:gsub("_%d+$", "")
			local def = registry[prefix]
			-- Skip scrap entries (can't scrap scrap) and any rarity without
			-- a scrap output (contraband, wildcard).
			if def and not def.is_scrap and SCRAPPABLE_RARITIES[def.rarity] then
				if not groups[prefix] then
					groups[prefix] = { def = def, prefix = prefix, stacks = 0 }
					table.insert(order, prefix)
				end
				groups[prefix].stacks = groups[prefix].stacks + 1
			end
		end
	end
	local list = {}
	for _, prefix in ipairs(order) do
		table.insert(list, groups[prefix])
	end
	return list
end

-- Cross-reference items_page.lua's hardcoded short descriptions (the same text
-- shown as the tooltip on the ITEMS tab and the selection-popup desc — see
-- Critical Rule 15) so the scrapper menu's hover panel reads identically.
-- _G.CSR_BuildItemsForPeer returns visual-only entries keyed by hud_icon, so
-- we build a name+desc-by-icon map and look it up by group.def.icon.
-- We can't use loc(loc_key) for the name because localization.lua joins
-- name and desc with "\n" into a single string per key — fetching it would
-- bleed the description into the hover_label and render as ghost text.
local function build_info_map()
	local builder = _G.CSR_BuildItemsForPeer
	if not builder then
		return {}
	end
	local local_peer = (_G.CSR_LocalPeerId and _G.CSR_LocalPeerId()) or 1
	local ok, list = pcall(builder, local_peer)
	if not ok or type(list) ~= "table" then
		return {}
	end
	local map = {}
	for _, entry in ipairs(list) do
		if entry.icon then
			map[entry.icon] = { name = entry.name, desc = entry.desc }
		end
	end
	return map
end

-- Fire-grace using PD2's vanilla cooldown field. PlayerStandard owns
-- `_menu_closed_fire_cooldown` (initialized to 0 in init, set to 0.15 by
-- vanilla after kit/inventory menus close — see playerstandard.lua:142/149),
-- and the action-forbidden check at line 4910 already gates primary_attack on
-- it being > 0. PlayerStandard:update at line 387-388 decrements it each
-- frame. Reusing this field means: no hook, no clock comparison, plays nice
-- with anything else also writing it (whichever is largest wins until
-- decremented).
local POST_CLICK_INPUT_GRACE = 0.25

local function start_fire_grace(grace_s)
	local pu = managers.player and managers.player:player_unit()
	if not (pu and alive(pu)) then
		return
	end
	local mvt = pu:movement()
	if not mvt or not mvt.current_state then
		return
	end
	local state = mvt:current_state()
	-- Field only exists on PlayerStandard. Skip silently when the player is
	-- in another state (driving, bleed-out, civilian) since shooting isn't
	-- possible there anyway.
	if state and state._menu_closed_fire_cooldown ~= nil then
		state._menu_closed_fire_cooldown = math.max(state._menu_closed_fire_cooldown, grace_s)
	end
end

-- grace_s: optional. When >0, suppresses LMB-fire for that many seconds via
-- the PreHook above. ALL other input (mouse-look, WASD, RMB, melee, etc.)
-- re-enables instantly when the controller is re-enabled — the grace is
-- targeted at the fire button only. Keyboard-driven close paths (WASD / Esc)
-- pass nil for no grace.
local function close_menu(grace_s)
	if not _state then
		return
	end
	local controller = _state.controller
	local player_unit = _state.player_unit
	local scrapper_unit = _state.unit
	if _state.mouse_id and managers.mouse_pointer then
		managers.mouse_pointer:remove_mouse(_state.mouse_id)
	end
	if _state.ws and managers.gui_data then
		managers.gui_data:destroy_workspace(_state.ws)
	end
	_state = nil
	-- Re-enable the player controller immediately. Guard with alive() because
	-- the player unit may have been destroyed (death, level end) while the
	-- menu was up — re-enabling a dead unit's controller would error.
	if controller and player_unit and alive(player_unit) then
		pcall(function()
			controller:set_enabled(true)
		end)
	end
	-- Re-activate the scrapper interaction so the F-prompt returns the next
	-- time the player aims at it. interact() in scrapper_interaction_ext.lua
	-- called set_active(false) on hold-complete to suppress the prompt while
	-- the menu was up.
	if scrapper_unit and alive(scrapper_unit) then
		local int_ext = scrapper_unit:interaction()
		if int_ext and int_ext.set_active then
			pcall(function()
				int_ext:set_active(true)
			end)
		end
	end
	if grace_s and grace_s > 0 then
		start_fire_grace(grace_s)
	end
end

-- Run the shredder's "interact" sequence on the unit the menu was opened
-- against. Sequence is the only visible animation the prop ships with, and
-- the user wants it tied to the moment of scrapping rather than the spawn.
-- We also stamp a "busy until" timestamp on the unit so the interaction
-- extension can block re-entry until the animation finishes — this is what
-- _interact_blocked() in scrapper_interaction_ext.lua reads.
local SCRAPPER_ANIM_LOCK_S = 3.0

_G.CSR_ScrapperBusyUntil = _G.CSR_ScrapperBusyUntil or {}

local function play_scrapper_anim()
	local unit = _state and _state.unit
	if not (unit and alive(unit)) then
		return
	end
	local damage_ext = unit:damage()
	if not (damage_ext and damage_ext.run_sequence_simple) then
		return
	end
	pcall(damage_ext.run_sequence_simple, damage_ext, "interact")
	local now = (Application and Application:time()) or 0
	_G.CSR_ScrapperBusyUntil[unit:key()] = now + SCRAPPER_ANIM_LOCK_S
end

-- Maximum stacks of a single item that one scrap action can consume. Stacks
-- beyond this remain in inventory; the player has to hold F again to scrap
-- the rest. Mirrors the user's spec: "scrapper can only scrap 10 stacks of
-- one item in one go".
local SCRAP_PER_USE_CAP = 10

-- Map from real-item rarity to the matching scrap id_prefix. Contraband and
-- wildcard intentionally have no entry — those items can't be scrapped (they
-- shouldn't reach on_pick because build_groups wouldn't include scrap defs,
-- but build_groups DOES include contraband real items, so we filter on the
-- producer side here).
local RARITY_TO_SCRAP_PREFIX = {
	common = "player_scrap_common_",
	uncommon = "player_scrap_uncommon_",
	rare = "player_scrap_rare_",
}

local function on_pick(group)
	local rarity = group.def and group.def.rarity
	local stacks = tonumber(group.stacks) or 0
	local scrap_prefix = RARITY_TO_SCRAP_PREFIX[rarity]

	-- Contraband / unknown rarity: no scrap mapping. Just play the animation
	-- and close, but don't consume anything. (Hover should ideally hide
	-- contraband, but for now this is a no-op safety bail.)
	if not scrap_prefix or stacks <= 0 then
		play_scrapper_anim()
		close_menu(POST_CLICK_INPUT_GRACE)
		return
	end

	-- Consume up to SCRAP_PER_USE_CAP stacks of the source item. We need the
	-- actual source-item id_prefix (with trailing underscore) to remove
	-- specific instance ids — group.def.id_prefix has it in registry form.
	local src_prefix = group.def.id_prefix
	if not src_prefix then
		play_scrapper_anim()
		close_menu(POST_CLICK_INPUT_GRACE)
		return
	end

	local to_scrap = math.min(stacks, SCRAP_PER_USE_CAP)
	local items_list = (_G.CSR_GetLocalItems and _G.CSR_GetLocalItems()) or {}

	-- Collect the full ids of source items to remove. Iterate the stored list
	-- and pick the first `to_scrap` whose id starts with src_prefix.
	local to_remove_ids = {}
	for _, it in ipairs(items_list) do
		if #to_remove_ids >= to_scrap then
			break
		end
		if it.id and string.find(it.id, src_prefix, 1, true) == 1 then
			table.insert(to_remove_ids, it.id)
		end
	end

	-- Apply: remove sources, add same-count scraps. Defensive — bail without
	-- side effects if the store API is missing.
	if not (_G.CSR_RemoveItem and _G.CSR_AddItem) then
		play_scrapper_anim()
		close_menu(POST_CLICK_INPUT_GRACE)
		return
	end

	local removed_count = 0
	for _, full_id in ipairs(to_remove_ids) do
		if _G.CSR_RemoveItem(full_id) then
			removed_count = removed_count + 1
		end
	end
	for _ = 1, removed_count do
		_G.CSR_AddItem(scrap_prefix)
	end

	-- Refresh any open Items tab so the change is visible immediately.
	if _G.CSR_ItemsPageInstance and _G.CSR_ItemsPageInstance._setup_items then
		pcall(function()
			_G.CSR_ItemsPageInstance:_setup_items()
		end)
	end

	-- Push to other peers in MP so they see our updated inventory.
	if _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer() and CSR_MP.broadcast_own_items then
		CSR_MP.broadcast_own_items()
	end

	-- Local chat feedback. Mirrors copier_spawner.lua's pattern: item name
	-- as the "author" (rendered in rarity color), short action body. Pulls
	-- the human-readable name from the same info_map used to render hover
	-- text, falling back to def.type if missing.
	if removed_count > 0 and managers and managers.chat and ChatManager and ChatManager.GAME then
		-- Pull the name straight from the registry's loc_key, NOT from info_map.
		-- info_map reflects the player's CURRENT inventory (rebuilt here after the
		-- removal pass above), so when the player just scrapped the last stack of
		-- a type, info_map[icon] is gone and any fallback to group.def.type prints
		-- the mechanical id ("HEALTH" for Dog Tags). loc_key is static.
		local pretty_name = display_name_for(group.def)
		local color = (RARITY_COLOR and RARITY_COLOR[rarity]) or Color.white
		pcall(function()
			managers.chat:_receive_message(
				1,
				tostring(pretty_name),
				"scrapped (x" .. tostring(removed_count) .. ")",
				color
			)
		end)
	end

	play_scrapper_anim()
	close_menu(POST_CLICK_INPUT_GRACE)
end

local function find_cell_under(x, y)
	if not _state then
		return nil
	end
	for _, cell in ipairs(_state.cells) do
		if x >= cell.x and x <= cell.x + cell.w and y >= cell.y and y <= cell.y + cell.h then
			return cell
		end
	end
	return nil
end

local function set_hover(cell)
	if _state.hovered == cell then
		return
	end
	_state.hovered = cell
	for _, c in ipairs(_state.cells) do
		c.highlight:set_visible(c == cell)
	end
	if _state.hover_label then
		if cell then
			_state.hover_label:set_text(cell.label_text)
			-- Tint the name+rarity line with the cell's rarity color so it
			-- visually echoes the icon frame tint. Set color BEFORE making
			-- the label visible so there's no one-frame default-color flash.
			local col = cell.label_color or Color.white
			if _state.hover_label.set_color then
				_state.hover_label:set_color(col:with_alpha(HOVER_TEXT_ALPHA))
			end
			_state.hover_label:set_visible(true)
		else
			_state.hover_label:set_visible(false)
		end
	end
	if _state.hover_desc then
		if cell and cell.desc and cell.desc ~= "" then
			_state.hover_desc:set_text(cell.desc)
			_state.hover_desc:set_visible(true)
		else
			_state.hover_desc:set_visible(false)
		end
	end
end

local function on_mouse_move(o, x, y, ws)
	if not _state then
		return
	end
	set_hover(find_cell_under(x, y))
end

local function on_mouse_press(o, button, x, y)
	if not _state then
		return
	end
	if button == MOUSE_RMB then
		-- RMB cancel: no fire-grace. RMB doesn't map to primary_attack, and
		-- the user explicitly wanted only LMB suppressed.
		close_menu()
		return
	end
	if button ~= MOUSE_LMB then
		return
	end
	local cell = find_cell_under(x, y)
	if cell then
		on_pick(cell.group)
	else
		-- Click outside any item cell + outside the panel = close. Same
		-- 0.5s grace as a pick — the click would otherwise bleed into
		-- primary_attack on the frame the controller re-enables.
		if not _state.panel_rect:contains(x, y) then
			close_menu(POST_CLICK_INPUT_GRACE)
		end
	end
end

-- Tiny rect helper — Lua doesn't ship one, and `panel:inside(x, y)` is a
-- hit-test on the live panel which we don't want for the close-on-outside
-- check (panel covers most of the screen and would never report outside).
local function rect(x, y, w, h)
	return {
		x = x,
		y = y,
		w = w,
		h = h,
		contains = function(self, px, py)
			return px >= self.x and px <= self.x + self.w and py >= self.y and py <= self.y + self.h
		end,
	}
end

local function build_panel(groups, info_map)
	local ws = managers.gui_data:create_fullscreen_workspace()
	local root = ws:panel()

	-- No backdrop: the world stays fully visible behind the menu (per design).
	-- Input is captured by managers.mouse_pointer:use_mouse, not by a backdrop
	-- rect, so click-blocking doesn't need a covering quad.

	-- Sizing: clamp grid width to 8 cells max, then fit within ~80% screen
	-- width. Vertical = grid + dedicated info area + cancel hint.
	-- Empty groups: reserve one row's worth of vertical space so the panel
	-- has somewhere to print the "no items" message.
	local count = math.max(1, #groups)
	local max_cols = math.min(8, count)
	local cols = math.max(1, math.min(max_cols, math.floor(root:w() * 0.8 / CELL_PX)))
	local rows = math.ceil(count / cols)

	local grid_w = cols * CELL_PX
	local grid_h = rows * CELL_PX
	local panel_w = math.max(grid_w + PADDING * 2, 520)
	-- Stack: top padding + title + subtitle + grid + gap + info area + cancel hint + bottom padding
	local panel_h = PADDING / 2
		+ TITLE_PX
		+ SUBTITLE_PX
		+ PADDING / 2
		+ grid_h
		+ PADDING / 2
		+ INFO_AREA_PX
		+ CANCEL_HINT_PX
		+ PADDING / 2
	local panel_x = math.floor((root:w() - panel_w) / 2)
	local panel_y = math.floor((root:h() - panel_h) / 2)

	local panel = root:panel({
		x = panel_x,
		y = panel_y,
		w = panel_w,
		h = panel_h,
		layer = 10,
	})

	-- Panel fill: semi-transparent black so the world dims but stays visible
	-- through the menu. Alpha is the FIRST argument in Diesel's Color(a, r, g, b)
	-- (Critical Rule 6). 0.7 reads dark enough for white text without obscuring
	-- the world, which is what the user wants while picking an item.
	panel:rect({
		color = PANEL_COLOR,
		layer = 0,
	})

	-- Border lines (4 edge-aligned rects: top / bottom / left / right). Diesel
	-- panels have no native stroke, so we draw them as rects. Layer 5 places
	-- them above the panel fill but below the icon grid + text content.
	panel:rect({ color = BORDER_COLOR, x = 0, y = 0, w = panel_w, h = BORDER_PX, layer = 5 })
	panel:rect({ color = BORDER_COLOR, x = 0, y = panel_h - BORDER_PX, w = panel_w, h = BORDER_PX, layer = 5 })
	panel:rect({ color = BORDER_COLOR, x = 0, y = 0, w = BORDER_PX, h = panel_h, layer = 5 })
	panel:rect({ color = BORDER_COLOR, x = panel_w - BORDER_PX, y = 0, w = BORDER_PX, h = panel_h, layer = 5 })

	-- Title
	panel:text({
		text = loc("csr_scrapper_pick_title", "SCRAPPER"),
		font = tweak_data.menu.pd2_large_font,
		font_size = 28,
		color = tweak_data.screen_colors.title,
		x = 0,
		y = PADDING / 2,
		w = panel_w,
		h = TITLE_PX,
		align = "center",
		layer = 1,
	})

	-- Subtitle
	panel:text({
		text = loc("csr_scrapper_pick_text", "Pick an item to turn into scrap."),
		font = tweak_data.menu.pd2_small_font,
		font_size = 18,
		color = tweak_data.screen_colors.text,
		x = 0,
		y = PADDING / 2 + TITLE_PX,
		w = panel_w,
		h = SUBTITLE_PX,
		align = "center",
		layer = 1,
	})

	-- Cells
	local grid_x = math.floor((panel_w - grid_w) / 2)
	local grid_y = PADDING / 2 + TITLE_PX + SUBTITLE_PX + PADDING / 2
	local cells = {}

	-- Empty-state message rendered in the cell-grid area when no items.
	if #groups == 0 then
		panel:text({
			text = loc("csr_scrapper_no_items", "No items to scrap"),
			font = tweak_data.menu.pd2_medium_font,
			font_size = 22,
			color = tweak_data.screen_colors.text:with_alpha(0.6),
			x = 0,
			y = grid_y,
			w = panel_w,
			h = grid_h,
			align = "center",
			vertical = "center",
			layer = 1,
		})
	end

	for i, group in ipairs(groups) do
		local col = (i - 1) % cols
		local row = math.floor((i - 1) / cols)
		local cx = grid_x + col * CELL_PX
		local cy = grid_y + row * CELL_PX

		local cell_panel = panel:panel({
			x = cx,
			y = cy,
			w = CELL_PX,
			h = CELL_PX,
			layer = 1,
		})

		-- Hover highlight (hidden until mouse over)
		local highlight = cell_panel:rect({
			color = HOVER_HIGHLIGHT,
			layer = 0,
			visible = false,
		})

		-- Frame (csr_frame, tinted by rarity)
		local frame_data = tweak_data.hud_icons and tweak_data.hud_icons.csr_frame
		if frame_data then
			cell_panel:bitmap({
				texture = frame_data.texture,
				texture_rect = frame_data.texture_rect,
				w = FRAME_PX,
				h = FRAME_PX,
				x = (CELL_PX - FRAME_PX) / 2,
				y = (CELL_PX - FRAME_PX) / 2,
				color = RARITY_COLOR[group.def.rarity] or Color.white,
				layer = 1,
			})
		end

		-- Icon (centered in frame)
		local icon_data = group.def.icon and tweak_data.hud_icons and tweak_data.hud_icons[group.def.icon]
		if icon_data then
			local icon_scale = (_G.CSR_IconScale and _G.CSR_IconScale[group.def.icon]) or 1
			local sized = ICON_PX * icon_scale
			cell_panel:bitmap({
				texture = icon_data.texture,
				texture_rect = icon_data.texture_rect,
				w = sized,
				h = sized,
				x = (CELL_PX - sized) / 2,
				y = (CELL_PX - sized) / 2,
				color = Color.white,
				layer = 2,
			})
		end

		-- Stack counter (top right). Mirrors items_page.lua:461-501 — always
		-- shows (even for stack=1), with 8-direction black shadow for
		-- readability against varied icon backgrounds.
		if group.stacks and group.stacks >= 1 then
			local stack_str = "x" .. tostring(group.stacks)
			local stack_font = 16
			local sw = 30
			local text_x = CELL_PX - sw - 4
			local text_y = 2
			for dx = -1, 1 do
				for dy = -1, 1 do
					if not (dx == 0 and dy == 0) then
						cell_panel:text({
							text = stack_str,
							font = tweak_data.menu.pd2_medium_font,
							font_size = stack_font,
							color = Color.black,
							x = text_x + dx,
							y = text_y + dy,
							w = sw,
							h = 18,
							layer = 4,
							align = "right",
							vertical = "top",
						})
					end
				end
			end
			cell_panel:text({
				text = stack_str,
				font = tweak_data.menu.pd2_medium_font,
				font_size = stack_font,
				color = Color.white,
				x = text_x,
				y = text_y,
				w = sw,
				h = 18,
				layer = 5,
				align = "right",
				vertical = "top",
			})
		end

		-- Cells track absolute screen coordinates for hit-testing against
		-- mouse_pointer events (which give workspace-space x/y, same as the
		-- root panel since we used a fullscreen workspace).
		local info = (info_map and info_map[group.def.icon]) or {}
		-- Display name comes from def.loc_key, never def.type. def.type is the
		-- mechanical id (e.g. "health" for Dog Tags) and is NOT player-facing.
		local item_name = display_name_for(group.def)
		table.insert(cells, {
			x = panel_x + cx,
			y = panel_y + cy,
			w = CELL_PX,
			h = CELL_PX,
			highlight = highlight,
			group = group,
			label_text = string.format(
				"%s x%d (%s)",
				item_name,
				group.stacks,
				RARITY_LABEL[group.def.rarity] or group.def.rarity or ""
			),
			-- Cache the rarity color so set_hover can re-tint hover_label
			-- per-cell without re-looking it up each frame.
			label_color = RARITY_COLOR[group.def.rarity] or Color.white,
			desc = info.desc or "",
		})
	end

	-- Hover info area: name+rarity (top line) + description (multi-line below).
	-- Sits between the grid and the cancel hint, INFO_AREA_PX tall.
	local info_y = grid_y + grid_h + PADDING / 2
	local hover_label = panel:text({
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = tweak_data.screen_colors.text:with_alpha(HOVER_TEXT_ALPHA),
		x = PADDING,
		y = info_y,
		w = panel_w - PADDING * 2,
		h = 24,
		align = "center",
		layer = 1,
		visible = false,
	})

	local hover_desc = panel:text({
		text = "",
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = tweak_data.screen_colors.text:with_alpha(0.85),
		x = PADDING,
		y = info_y + 26,
		w = panel_w - PADDING * 2,
		h = INFO_AREA_PX - 26,
		align = "center",
		vertical = "top",
		wrap = true,
		word_wrap = true,
		layer = 1,
		visible = false,
	})

	-- Cancel hint (right-click)
	panel:text({
		text = loc("csr_scrapper_cancel_hint", "Movement keys or click outside window to close."),
		font = tweak_data.menu.pd2_small_font,
		font_size = 14,
		color = tweak_data.screen_colors.text:with_alpha(0.6),
		x = 0,
		y = panel_h - CANCEL_HINT_PX - PADDING / 2,
		w = panel_w,
		h = CANCEL_HINT_PX,
		align = "center",
		layer = 1,
	})

	return ws, panel, cells, hover_label, hover_desc, rect(panel_x, panel_y, panel_w, panel_h)
end

_G.CSR_ScrapperMenu_Open = function(unit)
	if _state then
		return -- already open; ignore re-entry
	end

	if not (managers and managers.gui_data and managers.mouse_pointer and tweak_data and tweak_data.hud_icons) then
		return
	end

	local groups = build_groups()
	-- Empty groups still opens the panel — we render a "No items to scrap"
	-- message inside it instead of bailing with a HUD hint.

	local ok_im, info_map = pcall(build_info_map)
	if not ok_im then
		info_map = {}
	end
	local ok_bp, ws, panel, cells, hover_label, hover_desc, panel_rect = pcall(build_panel, groups, info_map)
	if not ok_bp then
		return
	end
	local mouse_id = managers.mouse_pointer:get_id()

	-- Freeze the player: disable their input controller. This is the same
	-- vanilla pattern playermovement.lua:1259 uses for the incapacitated state
	-- — locks mouse-look, WASD, shooting, jumping, interacting in one call.
	-- The menu's own mouse input goes through managers.mouse_pointer, which
	-- uses a different controller path, so it stays live.
	local player_unit = managers.player and managers.player:player_unit()
	local player_controller = nil
	if player_unit and alive(player_unit) and player_unit:base() and player_unit:base().controller then
		player_controller = player_unit:base():controller()
		if player_controller then
			pcall(function()
				player_controller:set_enabled(false)
			end)
		end
	end

	_state = {
		ws = ws,
		panel = panel,
		cells = cells,
		hover_label = hover_label,
		hover_desc = hover_desc,
		panel_rect = panel_rect,
		mouse_id = mouse_id,
		hovered = nil,
		player_unit = player_unit,
		controller = player_controller,
		unit = unit,
	}

	managers.mouse_pointer:use_mouse({
		mouse_move = on_mouse_move,
		mouse_press = on_mouse_press,
		id = mouse_id,
	})
end

-- Per-frame keyboard poll for WASD / Esc. Closes the menu on the first frame
-- any of those keys is pressed. Hook is installed once at file load and
-- bails immediately when the menu isn't open. Polls happen even outside
-- heists but are zero-cost in that case (early return on _state).
Hooks:Add("GameSetupUpdate", "CSR_ScrapperMenu_KeyPoll", function(t, dt)
	if not _state then
		return
	end
	if not (_G.Input and Input.keyboard) then
		return
	end
	local kb = Input:keyboard()
	if not kb then
		return
	end
	for _, key in ipairs(CLOSE_ON_KEYS) do
		if kb:pressed(key) then
			close_menu()
			return
		end
	end
end)

_G.CSR_ScrapperMenu_Close = close_menu
