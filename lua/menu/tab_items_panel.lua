-- Crime Spree Roguelike - ITEMS / TRACKED tabs on the HUDStatsScreen right panel.
-- Replaces the right panel's static "Tracked Achievements" list with a
-- two-tab swap: ITEMS (default, all peers' CSR items grouped per peer) and
-- TRACKED (vanilla achievement list). Click the tab labels to switch.
-- Click handling is dispatched from tab_camera_lock.lua's mouse_pointer
-- (which is only active while TAB is held — same time the stats screen
-- is visible, so the scope is exactly right).

if not RequiredScript then
	return
end

local _active_tab = "items" -- module-local; persists across TAB open/close

local TAB_GAP = 18
local TAB_TOP_PAD = 8

-- Right-column wildcard slot (mirrors the briefing items page). Smaller than
-- the briefing slot because the TAB panel is more compact. Carry-1, so the
-- slot only ever holds one icon (or an empty placeholder). The 10px implicit
-- panel margin on each side stays untouched; LEFT_PAD / RIGHT_PAD stack on
-- top of those for additional inset (symmetric with the briefing model).
local TAB_WILDCARD_SLOT_WIDTH = 50
local TAB_WILDCARD_SLOT_GAP = 6
local TAB_WILDCARD_SLOT_RIGHT_PAD = 4
local TAB_MAIN_GRID_LEFT_PAD = 4
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

local function is_mp()
	return _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer()
end

local function local_pid()
	return (CSR_LocalPeerId and CSR_LocalPeerId()) or 1
end

-- Calculate cell size to fit grid in available area (mirrors items_page.lua /
-- ingame_items_tab.lua's calc).
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

local function render_grid(content, items, start_x, start_y, cell_size, area_w, positions, peer_id)
	local ICON_SCALE = _G.CSR_IconScale or {}
	local frame_size = cell_size + 2
	local DEFAULT_FRAME = 74
	local icon_size = math.floor(38 * (frame_size / DEFAULT_FRAME))
	local icons_per_row = math.max(1, math.floor(area_w / cell_size))

	for i, item in ipairs(items) do
		local col = (i - 1) % icons_per_row
		local row = math.floor((i - 1) / icons_per_row)
		local x = start_x + col * cell_size
		local y = start_y + row * cell_size

		if positions then
			table.insert(positions, {
				x1 = x,
				y1 = y,
				x2 = x + frame_size,
				y2 = y + frame_size,
				item = item,
				peer_id = peer_id,
			})
		end

		if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
			local fd = tweak_data.hud_icons[item.frame]
			content:bitmap({
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				w = frame_size,
				h = frame_size,
				x = x,
				y = y,
				color = item.color or Color.white,
				layer = 0,
			})
		end

		if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
			local id = tweak_data.hud_icons[item.icon]
			local sz = icon_size * (ICON_SCALE[item.icon] or 1)
			local off = (frame_size - sz) / 2
			content:bitmap({
				texture = id.texture,
				texture_rect = id.texture_rect,
				w = sz,
				h = sz,
				x = x + off,
				y = y + off,
				color = Color.white,
				layer = 2,
			})
		end

		if item.stacks and item.stacks >= 1 then
			local s = "x" .. tostring(item.stacks)
			local tx = x + frame_size - 30 - 4
			-- Black shadow ring for legibility against light frame textures.
			for dx = -1, 1 do
				for dy = -1, 1 do
					if not (dx == 0 and dy == 0) then
						content:text({
							text = s,
							font = tweak_data.menu.pd2_medium_font,
							font_size = 16,
							color = Color.black,
							x = tx + dx,
							y = y + dy,
							w = 30,
							layer = 4,
							align = "right",
							vertical = "top",
						})
					end
				end
			end
			content:text({
				text = s,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 16,
				color = Color.white,
				x = tx,
				y = y,
				w = 30,
				layer = 5,
				align = "right",
				vertical = "top",
			})
		end
	end
end

-- Render the right-column wildcard slot for one peer's section. If `wildcards`
-- is non-empty, draws the owned wildcard (frame + icon + stack count, with hit
-- detection so the tooltip works). Otherwise draws a dim magenta hexagon as a
-- reserved-but-empty placeholder. Carry-1, so at most one icon ever shown.
local function render_wildcard_cell(content, wildcards, slot_x, slot_y, slot_w, slot_h, positions, peer_id)
	local frame_size = math.min(slot_w, slot_h)
	local x = slot_x + math.floor((slot_w - frame_size) / 2)
	local y = slot_y

	if #wildcards == 0 then
		if tweak_data.hud_icons and tweak_data.hud_icons.csr_frame then
			local fd = tweak_data.hud_icons.csr_frame
			content:bitmap({
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				w = frame_size,
				h = frame_size,
				x = x,
				y = y,
				color = WILDCARD_PLACEHOLDER_COLOR,
				layer = 0,
			})
		end
		return
	end

	local item = wildcards[1]
	local DEFAULT_FRAME = 74
	local icon_size = math.floor(38 * (frame_size / DEFAULT_FRAME))
	local ICON_SCALE = _G.CSR_IconScale or {}

	if positions then
		table.insert(positions, {
			x1 = x,
			y1 = y,
			x2 = x + frame_size,
			y2 = y + frame_size,
			item = item,
			peer_id = peer_id,
		})
	end

	if item.frame and tweak_data.hud_icons and tweak_data.hud_icons[item.frame] then
		local fd = tweak_data.hud_icons[item.frame]
		content:bitmap({
			texture = fd.texture,
			texture_rect = fd.texture_rect,
			w = frame_size,
			h = frame_size,
			x = x,
			y = y,
			color = item.color or Color.white,
			layer = 0,
		})
	end

	if item.icon and tweak_data.hud_icons and tweak_data.hud_icons[item.icon] then
		local id = tweak_data.hud_icons[item.icon]
		local sz = icon_size * (ICON_SCALE[item.icon] or 1)
		local off = (frame_size - sz) / 2
		content:bitmap({
			texture = id.texture,
			texture_rect = id.texture_rect,
			w = sz,
			h = sz,
			x = x + off,
			y = y + off,
			color = Color.white,
			layer = 2,
		})
	end

	if item.stacks and item.stacks >= 1 then
		local s = "x" .. tostring(item.stacks)
		local tx = x + frame_size - 30 - 4
		for dx = -1, 1 do
			for dy = -1, 1 do
				if not (dx == 0 and dy == 0) then
					content:text({
						text = s,
						font = tweak_data.menu.pd2_medium_font,
						font_size = 16,
						color = Color.black,
						x = tx + dx,
						y = y + dy,
						w = 30,
						layer = 4,
						align = "right",
						vertical = "top",
					})
				end
			end
		end
		content:text({
			text = s,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 16,
			color = Color.white,
			x = tx,
			y = y,
			w = 30,
			layer = 5,
			align = "right",
			vertical = "top",
		})
	end
end

local function placeholder_text(content, text)
	content:text({
		text = text,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 18,
		color = Color(0.5, 0.5, 0.5),
		x = 10,
		y = 10,
	})
end

local function build_items(content, positions)
	local panel_w = content:w()
	local panel_h = content:h()

	if not _G.CSR_BuildItemsForPeer or not _G.CSR_PlayerItems then
		placeholder_text(content, "Items unavailable.")
		return
	end

	-- Singleplayer: just render local items, no peer header.
	if not is_mp() then
		local local_id = local_pid()
		local items = CSR_BuildItemsForPeer(local_id)
		local regular, wildcards = split_wildcards(items)
		local has_wildcards = #wildcards > 0
		local main_w
		local grid_x = 10 + TAB_MAIN_GRID_LEFT_PAD
		local slot_x
		local slot_h = panel_h - 20
		if has_wildcards then
			main_w = panel_w
				- 20
				- TAB_MAIN_GRID_LEFT_PAD
				- TAB_WILDCARD_SLOT_WIDTH
				- TAB_WILDCARD_SLOT_GAP
				- TAB_WILDCARD_SLOT_RIGHT_PAD
			slot_x = grid_x + main_w + TAB_WILDCARD_SLOT_GAP
		else
			main_w = panel_w - 20 - TAB_MAIN_GRID_LEFT_PAD
		end

		if #regular > 0 then
			local cell = calc_cell_size(#regular, main_w, panel_h - 10, 72, 24)
			render_grid(content, regular, grid_x, 10, cell, main_w, positions, local_id)
		elseif not has_wildcards then
			placeholder_text(content, managers.localization:text("menu_csr_items_placeholder"))
		end

		if has_wildcards then
			render_wildcard_cell(content, wildcards, slot_x, 10, TAB_WILDCARD_SLOT_WIDTH, slot_h, positions, local_id)
		end
		return
	end

	-- MP: section per peer. Layout in 4 vertical sections to leave room
	-- for full lobbies even if some peers have no items yet.
	local peer_ids = {}
	for pid, _ in pairs(_G.CSR_PlayerItems) do
		table.insert(peer_ids, pid)
	end
	table.sort(peer_ids)

	local any_items = false
	for _, pid in ipairs(peer_ids) do
		local d = _G.CSR_PlayerItems[pid]
		if d and d.items and #d.items > 0 then
			any_items = true
			break
		end
	end
	if not any_items then
		placeholder_text(content, managers.localization:text("menu_csr_items_placeholder"))
		return
	end

	local section_gap = 6
	local header_h = 18
	local section_h = math.floor((panel_h - 3 * section_gap) / 4)
	local grid_h = section_h - header_h

	for idx, pid in ipairs(peer_ids) do
		local data = _G.CSR_PlayerItems[pid]
		if data then
			local items = CSR_BuildItemsForPeer(pid)
			local section_y = (idx - 1) * (section_h + section_gap)

			if idx > 1 then
				content:rect({
					x = 10,
					y = section_y - math.floor(section_gap / 2),
					w = panel_w - 20,
					h = 1,
					color = Color(1, 0.4, 0.4, 0.4),
					layer = 1,
				})
			end

			-- Resolve display name: live peer name first, fall back to stored
			-- name in CSR_PlayerItems, finally generic "Player N".
			local player_name
			local session = managers.network and managers.network:session()
			if session then
				local peer = (pid == local_pid()) and session:local_peer() or session:peer(pid)
				player_name = peer and peer:name()
			end
			if not player_name or player_name == "" then
				player_name = (data.name and data.name ~= "") and data.name or ("Player " .. pid)
			end

			-- Color the peer name with their lobby color (Critical Rule 6: 4-arg Color).
			local peer_vec = tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[pid]
			local header_color = peer_vec and Color(1, peer_vec.x, peer_vec.y, peer_vec.z) or Color.white

			content:text({
				text = player_name,
				font = tweak_data.menu.pd2_medium_font,
				font_size = 14,
				color = header_color,
				x = 10,
				y = section_y,
				layer = 1,
			})

			local grid_y = section_y + header_h

			-- Split wildcards out for the dedicated right-column slot.
			local regular, wildcards = split_wildcards(items)
			local has_wildcards = #wildcards > 0
			local main_w
			local grid_x = 10 + TAB_MAIN_GRID_LEFT_PAD
			local slot_x
			if has_wildcards then
				main_w = panel_w
					- 20
					- TAB_MAIN_GRID_LEFT_PAD
					- TAB_WILDCARD_SLOT_WIDTH
					- TAB_WILDCARD_SLOT_GAP
					- TAB_WILDCARD_SLOT_RIGHT_PAD
				slot_x = grid_x + main_w + TAB_WILDCARD_SLOT_GAP
			else
				main_w = panel_w - 20 - TAB_MAIN_GRID_LEFT_PAD
			end

			if #regular > 0 then
				local cell = calc_cell_size(#regular, main_w, grid_h, math.min(72, grid_h), 24)
				render_grid(content, regular, grid_x, grid_y, cell, main_w, positions, pid)
			elseif not has_wildcards then
				content:text({
					text = "No items",
					font = tweak_data.menu.pd2_small_font,
					font_size = 12,
					color = Color(0.45, 0.45, 0.45),
					x = 10,
					y = grid_y,
					layer = 1,
				})
			end

			if has_wildcards then
				render_wildcard_cell(
					content,
					wildcards,
					slot_x,
					grid_y,
					TAB_WILDCARD_SLOT_WIDTH,
					grid_h,
					positions,
					pid
				)
			end
		end
	end
end

local function hide_tooltip(self)
	if self._csr_tooltip and alive(self._csr_tooltip) and self._csr_tooltip:visible() then
		self._csr_tooltip:set_visible(false)
	end
end

local function show_tooltip(self, item, anchor_x_world, anchor_y_world, peer_id)
	local tt = self._csr_tooltip
	if not tt or not alive(tt) then
		return
	end
	tt:clear()

	local w = 280
	local pad = 10

	local title = item.name or ""
	local local_peer_id = local_pid()
	if peer_id and peer_id ~= local_peer_id then
		local session = managers.network and managers.network:session()
		local peer = session and session:peer(peer_id)
		local pname = peer and peer:name()
		if pname and pname ~= "" then
			title = pname .. ": " .. title
		end
	end

	local desc = tt:text({
		text = item.desc or "",
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		x = pad,
		y = pad + 25,
		w = w - pad * 2,
		wrap = true,
		word_wrap = true,
		layer = 2,
	})
	local _, _, _, dh = desc:text_rect()
	local h = pad + 25 + dh + pad

	-- Anchor passed in screen-world coords; convert to tt's parent-local
	-- by subtracting the parent's world position. tt's parent is the
	-- HUDStatsScreen root panel (set in recreate_right PostHook).
	local parent = tt:parent()
	local px = anchor_x_world - parent:world_x() + 16
	local py = anchor_y_world - parent:world_y() + 8
	if px + w > parent:w() - 4 then
		px = parent:w() - w - 4
	end
	if py + h > parent:h() - 4 then
		py = parent:h() - h - 4
	end
	if px < 4 then
		px = 4
	end
	if py < 4 then
		py = 4
	end
	tt:set_shape(px, py, w, h)

	tt:rect({ color = Color.black, alpha = 0.9, layer = 0 })
	local bc = item.color or Color.white
	local bs = 2
	tt:rect({ x = 0, y = 0, w = w, h = bs, color = bc, alpha = 0.4, layer = 1 })
	tt:rect({ x = 0, y = h - bs, w = w, h = bs, color = bc, alpha = 0.4, layer = 1 })
	tt:rect({ x = 0, y = 0, w = bs, h = h, color = bc, alpha = 0.4, layer = 1 })
	tt:rect({ x = w - bs, y = 0, w = bs, h = h, color = bc, alpha = 0.4, layer = 1 })

	tt:text({
		text = title,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = item.color or Color.white,
		x = pad,
		y = pad,
		layer = 2,
	})

	tt:set_visible(true)
end

local function apply_tab_visibility(self)
	if self._csr_items_content and alive(self._csr_items_content) then
		self._csr_items_content:set_visible(_active_tab == "items")
	end
	if self._csr_tracked_content and alive(self._csr_tracked_content) then
		self._csr_tracked_content:set_visible(_active_tab == "tracked")
	end
	local active = Color.white
	local inactive = Color(0.4, 0.7, 1.0)
	if self._csr_tab_items_btn and alive(self._csr_tab_items_btn) then
		self._csr_tab_items_btn:set_color(_active_tab == "items" and active or inactive)
	end
	if self._csr_tab_tracked_btn and alive(self._csr_tab_tracked_btn) then
		self._csr_tab_tracked_btn:set_color(_active_tab == "tracked" and active or inactive)
	end
	-- Tooltip only makes sense over the items grid; hide it when on tracked.
	if _active_tab ~= "items" then
		hide_tooltip(self)
	end
end

Hooks:PostHook(HUDStatsScreen, "recreate_right", "CSR_StatsScreenItemsTab", function(self)
	-- HUD mods that wrap HUDStatsScreen:recreate_right (raw-override-by-capture)
	-- and stash references to children of self._right for later updates will
	-- crash with an access violation (uncatchable C++ AV) when our subsequent
	-- self._right:clear() invalidates those cached children. Both confirmed
	-- variants share the same EnhancedCrewLoadout.lua + LoadoutPanel.lua
	-- structure (HMH is a fork of VHUDPlus). Crash signature: destroy() on
	-- a Diesel userdata in _destroy_player_info, on the second TAB show.
	--   - _G.VHUDPlus    — VanillaHUD Plus (Core.lua sets the global)
	--   - _G.HMH         — Hotline Miami HUD (HMHCore.lua sets the global)
	-- Bail-out: CSR's items panel does not render in the TAB heist screen
	-- under either HUD. The HUD's own loadout overlay renders normally;
	-- player loses CSR's per-peer items grid but the game does not crash.
	-- Reported on 2026-05-07 against CSR 6.1.0 (host stack traces match).
	if _G.VHUDPlus or _G.HMH then
		return
	end
	-- Only swap in the ITEMS/TRACKED tabs during Crime Spree heists.
	-- Outside CS, vanilla's plain tracked-achievements panel renders
	-- normally. Same gate as tab_camera_lock.lua — is_active() only.
	local cs = managers.crime_spree
	if not cs or not cs.is_active or not cs:is_active() then
		return
	end
	-- Skip when mutators are active — vanilla shows mutators in that case
	-- and replacing it would hide the mutator readout, which is more
	-- useful than items in a mutator run.
	if managers.mutators and managers.mutators:are_mutators_active() then
		return
	end
	if not self._right or not alive(self._right) then
		return
	end

	-- Wipe vanilla's tracked-list rendering and rebuild with our tabbed
	-- layout. Vanilla already drew the bg + tracked text + music line; we
	-- re-add bg + music ourselves to keep the panel framing intact.
	self._right:clear()
	self._right:bitmap({
		texture = "guis/textures/test_blur_df",
		layer = -1,
		render_template = "VertexColorTexturedBlur3D",
		valign = "grow",
		w = self._right:w(),
		h = self._right:h(),
	})
	local rb = HUDBGBox_create(self._right, {}, {
		blend_mode = "normal",
		color = Color.white,
	})
	rb:child("bg"):set_color(Color(0, 0, 0):with_alpha(0.75))
	rb:child("bg"):set_alpha(1)

	local active = Color.white
	local inactive = Color(0.4, 0.7, 1.0)

	-- Tab label for the right side: use vanilla's localization key so the
	-- text matches the original screen ("TRACKED ACHIEVEMENTS" in EN).
	local tracked_label = "TRACKED ACHIEVEMENTS"
	if managers.localization and managers.localization.to_upper_text then
		local ok, txt = pcall(function()
			return managers.localization:to_upper_text("hud_stats_tracked")
		end)
		if ok and txt and txt ~= "" then
			tracked_label = txt
		end
	end

	local items_btn = self._right:text({
		name = "csr_tab_items_btn",
		text = "ITEMS",
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = (_active_tab == "items") and active or inactive,
		x = 10,
		y = TAB_TOP_PAD,
		layer = 5,
	})
	local _, _, iw, ih = items_btn:text_rect()
	items_btn:set_size(iw, ih)

	local tracked_btn = self._right:text({
		name = "csr_tab_tracked_btn",
		text = tracked_label,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = (_active_tab == "tracked") and active or inactive,
		x = items_btn:right() + TAB_GAP,
		y = TAB_TOP_PAD,
		layer = 5,
	})
	local _, _, tw, th = tracked_btn:text_rect()
	tracked_btn:set_size(tw, th)

	self._csr_tab_items_btn = items_btn
	self._csr_tab_tracked_btn = tracked_btn

	-- Bottom 30px reserved for music track text (vanilla puts it there).
	local content_y = items_btn:bottom() + 8
	local content_h = self._right:h() - content_y - 30

	local items_content = self._right:panel({
		name = "csr_items_content",
		x = 0,
		y = content_y,
		w = self._right:w(),
		h = content_h,
		layer = 1,
	})
	-- tracked_content must be an ExtendedPanel: vanilla's _create_tracked_list
	-- calls self._right:fine_text(...) which only exists on ExtendedPanel,
	-- not on raw Diesel panels. With our self._right swap below, the temp
	-- self._right needs the same surface area as the real one.
	local tracked_content = ExtendedPanel:new(self._right, {
		x = 0,
		y = content_y,
		w = self._right:w(),
		h = content_h,
		layer = 1,
	})

	self._csr_items_content = items_content
	self._csr_tracked_content = tracked_content

	-- Reset hover-rect list and (re)create the tooltip overlay. Parent it
	-- to `self` (HUDStatsScreen root) so it can render outside _right's
	-- bounds — important on narrow resolutions.
	self._csr_item_positions = {}
	if self._csr_tooltip and alive(self._csr_tooltip) then
		self._csr_tooltip:parent():remove(self._csr_tooltip)
	end
	self._csr_tooltip = self:panel({
		name = "csr_items_tooltip",
		visible = false,
		layer = 100,
	})

	build_items(items_content, self._csr_item_positions)

	-- Vanilla _create_tracked_list ignores its `panel` arg and writes to
	-- self._right directly. Temp-swap so we redirect into our tracked
	-- subpanel, then restore. This avoids reimplementing
	-- HudTrackedAchievement layout.
	local saved_right = self._right
	self._right = tracked_content
	pcall(function()
		self:_create_tracked_list(tracked_content)
	end)
	self._right = saved_right

	-- Music track text (vanilla reattaches this; we re-add since we cleared).
	local track_text = self._right:fine_text({
		text = managers.localization:to_upper_text("menu_es_playing_track")
			.. " "
			.. managers.music:current_track_string(),
		font_size = tweak_data.menu.pd2_small_font_size,
		font = tweak_data.menu.pd2_small_font,
		color = tweak_data.screen_colors.text,
	})
	track_text:set_leftbottom(10, self._right:h() - 10)

	apply_tab_visibility(self)
end)

-- Public click dispatch. tab_camera_lock.lua calls this from its
-- mouse_pointer:use_mouse press callback (only active while TAB is held,
-- which is exactly when the stats screen is visible). Returns true if
-- the click was consumed by a tab button so the caller doesn't fall
-- through to anything else.
local MOUSE_LMB = Idstring("0")

local function world_rect(elem)
	if not elem or not alive(elem) then
		return nil
	end
	local wx, wy = elem:world_position()
	return wx, wy, wx + elem:w(), wy + elem:h()
end

_G.CSR_StatsTabsItems_OnMousePress = function(button, x, y)
	if button ~= MOUSE_LMB then
		return false
	end
	local hud = managers.hud
	local stats = hud and hud._hud_statsscreen
	if not stats then
		return false
	end

	local function hit(elem)
		local x1, y1, x2, y2 = world_rect(elem)
		if not x1 then
			return false
		end
		return x >= x1 and x < x2 and y >= y1 and y < y2
	end

	if hit(stats._csr_tab_items_btn) and _active_tab ~= "items" then
		_active_tab = "items"
		apply_tab_visibility(stats)
		return true
	end
	if hit(stats._csr_tab_tracked_btn) and _active_tab ~= "tracked" then
		_active_tab = "tracked"
		apply_tab_visibility(stats)
		return true
	end
	return false
end

-- Hover dispatch — wired from tab_camera_lock.lua's mouse_pointer:use_mouse
-- mouse_move callback. Walks recorded item rects and shows a tooltip when
-- the cursor is inside one. (x, y) are in screen-world coords.
_G.CSR_StatsTabsItems_OnMouseMove = function(x, y)
	local hud = managers.hud
	local stats = hud and hud._hud_statsscreen
	if not stats then
		return
	end
	if _active_tab ~= "items" then
		hide_tooltip(stats)
		return
	end
	local content = stats._csr_items_content
	local positions = stats._csr_item_positions
	if not content or not alive(content) or not positions then
		hide_tooltip(stats)
		return
	end
	local wx = content:world_x()
	local wy = content:world_y()
	local lx = x - wx
	local ly = y - wy

	for _, pos in ipairs(positions) do
		if lx >= pos.x1 and lx <= pos.x2 and ly >= pos.y1 and ly <= pos.y2 then
			show_tooltip(stats, pos.item, wx + pos.x2, wy + pos.y2, pos.peer_id)
			return
		end
	end
	hide_tooltip(stats)
end
