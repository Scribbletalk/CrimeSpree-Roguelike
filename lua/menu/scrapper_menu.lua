-- Scrapper item-pick menu.
-- ---------------------------------------------------------------------------
-- Fullscreen workspace overlay. Renders the local player's scrappable items as
-- an icon grid styled like the Items panel (csr_frame + icon + stack counter,
-- rarity color tint). Picking a cell converts up to SCRAP_PER_USE_CAP stacks of
-- that item into scrap of the matching tier (via managers.csr add/remove_item),
-- plays the shredder animation, and closes.
-- ---------------------------------------------------------------------------
-- Input: mouse_pointer:use_mouse — last callback in stack receives events
-- (LIFO), so the overlay grabs all clicks until we remove_mouse on close.
-- WASD/Esc close via a per-frame raw-scancode poll (the player controller is
-- disabled while the menu is up, so action-name lookups won't work).

if not RequiredScript then
	return
end

-- Visual constants -- match the Items panel so the cells look identical.
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

-- Per-rarity tint of csr_frame.dds (alpha, r, g, b). Only common/uncommon/rare
-- can be scrapped, so the contraband/wildcard tints are never actually used here.
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

-- Raw scancodes for "player wants to move/cancel". We disable the player's whole
-- controller on open (the vanilla freeze trick), so action-name lookups all
-- return false; raw scancodes bypass that. Trade-off: rebound movement keys
-- won't close the menu -- those players right-click instead.
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

-- Player-facing display name from a registry def. def.name is the loc key (e.g.
-- "CUP OF JOE"); never fall back to def.type, which is the mechanical id (e.g.
-- "health" for Dog Tags -- see feedback_dog_tags_naming).
local function display_name_for(def)
	if not def then
		return "?"
	end
	if def.name and managers and managers.localization and managers.localization.text then
		local s = managers.localization:text(def.name)
		if s and s ~= "" then
			local nl = string.find(s, "\n", 1, true)
			if nl then
				return string.sub(s, 1, nl - 1)
			end
			return s
		end
	end
	return "?"
end

-- Short description from the def's desc loc key (same text as the Items panel
-- tooltip / selection popup -- Critical Rule 15).
local function desc_for(def)
	if def and def.desc and managers and managers.localization and managers.localization.text then
		local s = managers.localization:text(def.desc)
		if s and s ~= "" then
			return s
		end
	end
	return ""
end

-- The local player's scrappable items, grouped as { def, type, stacks }. U1
-- ownership is already a per-type count map, so this is a direct read of
-- managers.csr:player_items filtered to scrappable rarities. Gated on a run
-- being active (debug-mode bypass for safehouse testing). Iterates the registry
-- for a stable display order. Only common/uncommon/rare have a scrap output, so
-- contraband/wildcard (and scrap itself) are excluded -- clicking them would
-- have no valid output.
local SCRAPPABLE_RARITIES = {
	common = true,
	uncommon = true,
	rare = true,
}

local function build_groups()
	local mgr = managers and managers.csr
	if not mgr or not mgr.registered_items then
		return {}
	end
	local debug_on = mgr.debug_enabled and mgr:debug_enabled()
	local in_run = mgr.is_run_active and mgr:is_run_active()
	if not (in_run or debug_on) then
		return {}
	end
	local counts = mgr:player_items(mgr:local_peer_id()) -- { [type] = n }
	local list = {}
	for _, def in ipairs(mgr:registered_items()) do
		local n = counts[def.type] or 0
		if n > 0 and not def.is_scrap and SCRAPPABLE_RARITIES[def.rarity] then
			list[#list + 1] = { def = def, type = def.type, stacks = n }
		end
	end
	return list
end

-- Fire-grace using PD2's vanilla cooldown field. PlayerStandard owns
-- `_menu_closed_fire_cooldown` (0 in init, set to 0.15 by vanilla after kit
-- menus close); its action-forbidden check already gates primary_attack on it
-- being > 0, and PlayerStandard:update decrements it each frame. Reusing it
-- means no hook, no clock comparison.
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
	-- Field only exists on PlayerStandard; skip silently in other states
	-- (driving, bleed-out, civilian) where shooting isn't possible anyway.
	if state and state._menu_closed_fire_cooldown ~= nil then
		state._menu_closed_fire_cooldown = math.max(state._menu_closed_fire_cooldown, grace_s)
	end
end

-- grace_s: when >0, suppresses LMB-fire for that many seconds (so the closing
-- click doesn't bleed into primary_attack on the frame the controller
-- re-enables). All other input re-enables instantly. nil = no grace.
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
	-- Re-enable the player controller immediately. alive() guards a unit that
	-- died / level-ended while the menu was up.
	if controller and player_unit and alive(player_unit) then
		pcall(function()
			controller:set_enabled(true)
		end)
	end
	-- Re-activate the scrapper interaction so the F-prompt returns. interact()
	-- in scrapper_interaction_ext.lua called set_active(false) on hold-complete.
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

-- Run the shredder's "interact" sequence (its only visible animation) on the
-- unit the menu was opened against, tied to the moment of scrapping. Stamps a
-- "busy until" timestamp the interaction extension reads to block re-entry
-- until the animation finishes.
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

-- Maximum stacks of one item a single scrap action consumes. Extra stacks stay
-- in inventory; the player holds F again to scrap the rest.
local SCRAP_PER_USE_CAP = 10

-- Real-item rarity -> matching scrap item type. Contraband/wildcard have no
-- entry (can't be scrapped); build_groups already filters them out.
local RARITY_TO_SCRAP_TYPE = {
	common = "scrap_common",
	uncommon = "scrap_uncommon",
	rare = "scrap_rare",
}

local function on_pick(group)
	local mgr = managers and managers.csr
	local rarity = group.def and group.def.rarity
	local item_type = group.def and group.def.type
	local scrap_type = RARITY_TO_SCRAP_TYPE[rarity]
	local stacks = tonumber(group.stacks) or 0

	-- No valid mapping / nothing to scrap: play the animation + close, no consume.
	if not (mgr and mgr.remove_item and mgr.add_item) or not (item_type and scrap_type) or stacks <= 0 then
		play_scrapper_anim()
		close_menu(POST_CLICK_INPUT_GRACE)
		return
	end

	local pid = mgr:local_peer_id()
	local to_scrap = math.min(stacks, SCRAP_PER_USE_CAP)
	local removed = 0
	for _ = 1, to_scrap do
		if mgr:remove_item(pid, item_type) then
			removed = removed + 1
		else
			break
		end
	end
	for _ = 1, removed do
		mgr:add_item(pid, scrap_type)
	end

	-- Local chat feedback (mirrors copier_spawner.lua): item name as the
	-- rarity-colored "author", short action body. Name pulled from the static
	-- loc key, not current inventory (the last stack may have just been removed).
	if removed > 0 and managers and managers.chat then
		local pretty_name = display_name_for(group.def)
		local color = RARITY_COLOR[rarity] or Color.white
		pcall(function()
			managers.chat:_receive_message(1, tostring(pretty_name), "scrapped (x" .. tostring(removed) .. ")", color)
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
			-- Tint the name+rarity line with the cell's rarity color. Set color
			-- BEFORE making visible so there's no one-frame default-color flash.
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
		-- RMB cancel: no fire-grace (RMB doesn't map to primary_attack).
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
		-- Click outside any cell + outside the panel = close (with grace so the
		-- click doesn't bleed into primary_attack on controller re-enable).
		if not _state.panel_rect:contains(x, y) then
			close_menu(POST_CLICK_INPUT_GRACE)
		end
	end
end

-- Tiny rect helper for the close-on-outside hit-test (panel:inside would always
-- report inside since the panel covers most of the screen).
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

local function build_panel(groups)
	local ws = managers.gui_data:create_fullscreen_workspace()
	local root = ws:panel()

	-- No backdrop: the world stays visible behind the menu. Input is captured by
	-- managers.mouse_pointer:use_mouse, not a covering quad.

	-- Clamp grid to 8 cells wide, fit within ~80% screen width. Empty groups
	-- reserve one row so the "no items" message has somewhere to print.
	local count = math.max(1, #groups)
	local max_cols = math.min(8, count)
	local cols = math.max(1, math.min(max_cols, math.floor(root:w() * 0.8 / CELL_PX)))
	local rows = math.ceil(count / cols)

	local grid_w = cols * CELL_PX
	local grid_h = rows * CELL_PX
	local panel_w = math.max(grid_w + PADDING * 2, 520)
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

	-- Semi-transparent black fill so the world dims but stays visible. Alpha is
	-- the FIRST Color arg (Critical Rule 6).
	panel:rect({
		color = PANEL_COLOR,
		layer = 0,
	})

	-- Border lines (4 edge rects; Diesel panels have no native stroke).
	panel:rect({ color = BORDER_COLOR, x = 0, y = 0, w = panel_w, h = BORDER_PX, layer = 5 })
	panel:rect({ color = BORDER_COLOR, x = 0, y = panel_h - BORDER_PX, w = panel_w, h = BORDER_PX, layer = 5 })
	panel:rect({ color = BORDER_COLOR, x = 0, y = 0, w = BORDER_PX, h = panel_h, layer = 5 })
	panel:rect({ color = BORDER_COLOR, x = panel_w - BORDER_PX, y = 0, w = BORDER_PX, h = panel_h, layer = 5 })

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

	local grid_x = math.floor((panel_w - grid_w) / 2)
	local grid_y = PADDING / 2 + TITLE_PX + SUBTITLE_PX + PADDING / 2
	local cells = {}

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
			local icon_scale = (managers.csr.item_icon_scale and managers.csr:item_icon_scale(group.def.type)) or 1
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

		-- Stack counter (top right) with 8-direction black shadow for readability.
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

		-- Cells track absolute workspace coords for hit-testing against
		-- mouse_pointer events (same space as the root panel -- fullscreen ws).
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
			label_color = RARITY_COLOR[group.def.rarity] or Color.white,
			desc = desc_for(group.def),
		})
	end

	-- Hover info area: name+rarity (top) + description (multi-line below).
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
	-- Empty groups still opens the panel -- it renders a "No items to scrap"
	-- message inside instead of bailing with a HUD hint.

	local ok_bp, ws, panel, cells, hover_label, hover_desc, panel_rect = pcall(build_panel, groups)
	if not ok_bp then
		return
	end
	local mouse_id = managers.mouse_pointer:get_id()

	-- Freeze the player: disable their input controller (the same vanilla pattern
	-- the incapacitated state uses -- locks mouse-look, WASD, shooting, jumping,
	-- interacting in one call). The menu's own input goes through
	-- managers.mouse_pointer, a different controller path, so it stays live.
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

-- Per-frame keyboard poll for WASD / Esc. Closes on the first frame any is
-- pressed. Installed once; bails immediately (zero cost) when the menu is closed.
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
