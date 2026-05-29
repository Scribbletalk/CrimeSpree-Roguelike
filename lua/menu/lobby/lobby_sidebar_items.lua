-- Items feature-panel methods added to CSRMissionsMenuComponent (loaded after missions_menu.lua).
if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

-- Contraband included even though excluded from random drops: items still reach inventory via shop.
local items_panel_rarity_colors = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}
-- Cell size (hit-test + grid step). Frame deliberately overflows cell to read as a "card".
local items_panel_icon_size = 64
local items_panel_frame_size = 72
local items_panel_icon_gap = 8
-- Readability floor for csr_adaptive_grid; full 31-type inventory still fits a quarter at typical heights.
local items_panel_min_icon_size = 28
local items_panel_peer_header_h = 22
-- 4-direction 1px offsets for stack-count outline; Diesel text has no native stroke so multi-draw is the standard technique.
local items_panel_badge_outline = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- Cap prevents big-icon centring margin from dragging the badge too far down; small icons are unaffected.
local items_panel_badge_top_inset = 9
local items_panel_padding = 16

-- Returns largest square cell size (≤max_size, ≥min_size) and per-row column count so all `count`
-- items fit avail_w×avail_h. Shrinks by 2px steps until rows fit height; left-aligned, fixed gap.
local function csr_adaptive_grid(count, avail_w, avail_h, max_size, min_size, gap)
	if count <= 0 then
		return max_size, 1
	end
	local function layout_for(size)
		local per_row = math.max(1, math.min(count, math.floor((avail_w + gap) / (size + gap))))
		return per_row, math.ceil(count / per_row)
	end
	local size = max_size
	while size > min_size do
		local _, rows = layout_for(size)
		if rows * (size + gap) - gap <= avail_h then
			break
		end
		size = size - 2
	end
	size = math.floor(math.max(size, min_size))
	local per_row = layout_for(size)
	return size, per_row
end

-- Uses tweak_data.peer_vector_colors so panel colors match teammate contours and chat.
function CSRMissionsMenuComponent:_items_panel_peer_color(peer_id)
	local v = tweak_data and tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[peer_id]
	if v then
		return Color(1, v.x, v.y, v.z)
	end
	return Color.white
end

-- Local peer first, then remote peers sorted ascending. Stable order when teammates join/leave.
function CSRMissionsMenuComponent:_collect_peers_for_items_panel(local_pid)
	local out = {}
	local seen = {}

	local nm = managers and managers.network
	local session = nm and nm.session and nm:session()

	local local_peer = session and session.local_peer and session:local_peer()
	if local_peer then
		local lid = local_peer:id()
		out[1] = {
			id = lid,
			name = (local_peer.name and local_peer:name()) or "Player",
			color = self:_items_panel_peer_color(lid),
		}
		seen[lid] = true
	else
		out[1] = {
			id = local_pid,
			name = "Player",
			color = self:_items_panel_peer_color(local_pid),
		}
		seen[local_pid] = true
	end

	if session and session.peers then
		local peers = session:peers() or {}
		local remote = {}
		for pid, peer in pairs(peers) do
			if not seen[pid] then
				-- Mark seen so the remote_peer_ids() pass below does NOT re-add a peer
				-- the live session already covers (the host was listed twice: once here
				-- as a session peer, once there as a synced-item holder).
				seen[pid] = true
				remote[#remote + 1] = {
					id = pid,
					name = (peer.name and peer:name()) or ("Peer " .. tostring(pid)),
					color = self:_items_panel_peer_color(pid),
				}
			end
		end
		table.sort(remote, function(a, b)
			return a.id < b.id
		end)
		for _, p in ipairs(remote) do
			out[#out + 1] = p
		end
	end

	-- Include peers we hold synced items for that the session list missed (timing), plus SP debug peer.
	local mgr = managers and managers.csr
	if mgr and mgr.remote_peer_ids then
		local extra = {}
		for _, pid in ipairs(mgr:remote_peer_ids()) do
			if not seen[pid] then
				seen[pid] = true
				extra[#extra + 1] = {
					id = pid,
					name = (mgr.remote_peer_name and mgr:remote_peer_name(pid)) or ("Peer " .. tostring(pid)),
					color = self:_items_panel_peer_color(pid),
				}
			end
		end
		table.sort(extra, function(a, b)
			return a.id < b.id
		end)
		for _, p in ipairs(extra) do
			out[#out + 1] = p
		end
	end

	return out
end

-- Build / rebuild items panel. Idempotent: tears down prior content and resets hit targets first.
function CSRMissionsMenuComponent:_populate_items_panel()
	if not self._feature_panels or not alive(self._feature_panels.items) then
		return
	end
	local panel = self._feature_panels.items

	if self._items_content and alive(self._items_content) then
		panel:remove(self._items_content)
	end
	self._items_content = nil
	self._items_hit_targets = {}
	self:_clear_items_tooltip()
	self._items_hover_target = nil

	local content = panel:panel({
		layer = 5,
	})
	self._items_content = content

	local mgr = managers and managers.csr
	if not mgr or not mgr.registered_items then
		return
	end

	local by_type = {}
	for _, def in ipairs(mgr:registered_items()) do
		by_type[def.type] = def
	end

	local local_pid = mgr:local_peer_id()
	local peers_list = self:_collect_peers_for_items_panel(local_pid)

	local section_w = panel:w() - items_panel_padding * 2
	-- Fixed quarter-height per peer keeps layout stable for up to 4 players; grid shrinks to fit.
	local section_h = math.floor(panel:h() / 4)

	for index, peer_info in ipairs(peers_list) do
		local pid = peer_info.id
		local pcolor = peer_info.color
		local section_top = (index - 1) * section_h

		local header = content:panel({
			x = items_panel_padding,
			y = section_top + items_panel_padding,
			w = section_w,
			h = items_panel_peer_header_h,
		})

		header:rect({
			name = "peer_color_strip",
			color = pcolor,
			w = 4,
			h = header:h(),
		})
		header:text({
			name = "peer_name",
			text = peer_info.name,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = pcolor,
			x = 12,
			y = 0,
			w = header:w() - 12,
			h = header:h(),
			vertical = "center",
		})

		-- Acquisition order: duplicate bumps badge count only. player_items_order is self-healing for legacy/remote data.
		local counts = mgr:player_items(pid) or {}
		local items_list = {}
		for _, item_type in ipairs(mgr:player_items_order(pid)) do
			local def = by_type[item_type]
			local count = counts[item_type] or 0
			if def and count > 0 then
				items_list[#items_list + 1] = { def = def, count = count }
			end
		end

		if #items_list > 0 then
			local grid_y = section_top + items_panel_padding + items_panel_peer_header_h + 10
			local grid_h = section_top + section_h - grid_y - items_panel_padding
			local cell_size, per_row = csr_adaptive_grid(
				#items_list,
				section_w,
				grid_h,
				items_panel_icon_size,
				items_panel_min_icon_size,
				items_panel_icon_gap
			)
			local step = cell_size + items_panel_icon_gap
			-- Keep 72/64 frame-to-cell ratio so the frame overflows symmetrically at any cell size.
			local frame_size = math.floor(cell_size * items_panel_frame_size / items_panel_icon_size)
			local frame_overflow = (frame_size - cell_size) / 2
			local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")

			for i, entry in ipairs(items_list) do
				local col = (i - 1) % per_row
				local row = math.floor((i - 1) / per_row)
				local ix = items_panel_padding + col * step
				local iy = grid_y + row * step

				-- Frame is a sibling on `content` (not a child of cell) so its 72px footprint can
				-- overflow the 64px cell; layer 5 puts it below the cell (layer 10) despite the overlap.
				local frame_bmp = content:bitmap({
					name = "rarity_frame",
					texture = frame_tex,
					texture_rect = frame_rect,
					x = ix - frame_overflow,
					y = iy - frame_overflow,
					w = frame_size,
					h = frame_size,
					layer = 5,
				})
				frame_bmp:set_color(items_panel_rarity_colors[entry.def.rarity] or Color.white)

				local cell = content:panel({
					x = ix,
					y = iy,
					w = cell_size,
					h = cell_size,
					layer = 10,
				})

				-- "/" in icon = full DB-mounted texture path (addon .dds); otherwise a hud_icons id.
				local icon_tex, icon_rect
				local raw_icon = entry.def.icon or "dog_tags"
				if type(raw_icon) == "string" and raw_icon:find("/", 1, true) then
					icon_tex, icon_rect = raw_icon, { 0, 0, 128, 128 }
				else
					icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(raw_icon)
				end
				-- Legacy 36px-in-64px glyph ratio, scaled by optional per-item icon_scale.
				local glyph = math.floor(cell_size * (1 - 28 / items_panel_icon_size) * (entry.def.icon_scale or 1))
				local glyph_inset = math.floor((cell_size - glyph) / 2)
				cell:bitmap({
					name = "item_icon",
					texture = icon_tex,
					texture_rect = icon_rect,
					x = glyph_inset,
					y = glyph_inset,
					w = glyph,
					h = glyph,
					layer = 10,
				})

				-- Stack badge: white "xN" with black multi-draw outline (no bg box). Siblings of
				-- cell on `content` so they aren't clipped; layers 19 (outline) / 20 (white glyph).
				local badge = {
					name = "stack_badge",
					text = "x" .. tostring(entry.count),
					font = tweak_data.menu.pd2_small_font,
					font_size = tweak_data.menu.pd2_small_font_size,
					align = "left",
					vertical = "bottom",
					w = items_panel_icon_size,
					h = items_panel_icon_size,
				}
				local badge_x = ix + glyph_inset + glyph
				local badge_drop = math.floor(tweak_data.menu.pd2_small_font_size * 0.2)
				local badge_inset = math.min(glyph_inset, items_panel_badge_top_inset)
				local badge_y = (iy + badge_inset + badge_drop) - items_panel_icon_size
				-- params table is reused across text() calls; panel:text() reads it at call time.
				badge.color = Color.black
				badge.layer = 19
				for _, off in ipairs(items_panel_badge_outline) do
					badge.x, badge.y = badge_x + off[1], badge_y + off[2]
					content:text(badge)
				end
				badge.color = Color.white
				badge.layer = 20
				badge.x, badge.y = badge_x, badge_y
				content:text(badge)

				self._items_hit_targets[#self._items_hit_targets + 1] = {
					panel = cell,
					def = entry.def,
					count = entry.count,
				}
			end
		end
	end
end

-- Edge-triggered hover; linear walk is fine (≤28 items × N peers, event-driven not per-frame).
function CSRMissionsMenuComponent:_items_panel_mouse_moved(x, y)
	local panel = self._feature_panels and self._feature_panels.items
	if not panel or not alive(panel) or not panel:visible() then
		if self._items_hover_target ~= nil then
			self._items_hover_target = nil
			self:_clear_items_tooltip()
		end
		return false
	end
	if not self._items_hit_targets or #self._items_hit_targets == 0 then
		return false
	end

	local hovered = nil
	for _, target in ipairs(self._items_hit_targets) do
		if alive(target.panel) and target.panel:inside(x, y) then
			hovered = target
			break
		end
	end

	if hovered ~= self._items_hover_target then
		self._items_hover_target = hovered
		self:_clear_items_tooltip()
		if hovered then
			-- No hover SFX: per-cell audio chatters as cursor crosses a dense grid (user spec).
			self:_show_items_tooltip(hovered)
		end
	end

	return hovered ~= nil
end

function CSRMissionsMenuComponent:_clear_items_tooltip()
	-- Tooltip lives on _csr_fp_parent (saferect ws_panel on briefing, self._panel in lobby).
	local parent = self._csr_fp_parent or self._panel
	if self._items_tooltip and alive(self._items_tooltip) and parent and alive(parent) then
		parent:remove(self._items_tooltip)
	end
	self._items_tooltip = nil
end

-- Tooltip anchored to hovered cell, floated on layer 200, clamped to fp_parent bounds.
function CSRMissionsMenuComponent:_show_items_tooltip(target)
	if not target or not alive(target.panel) then
		return
	end
	local def = target.def
	local pad = 6
	local tip_w = 200
	local name_h = tweak_data.menu.pd2_small_font_size + 2

	local fp_parent = self._csr_fp_parent or self._panel

	-- Build at placeholder height, add BoxGui AFTER final resize: BoxGui bakes corner sprite
	-- positions at construction time, so pre-resize creation strands corners at wrong coords.
	local tip = fp_parent:panel({
		layer = 200,
		w = tip_w,
		h = 200,
	})
	self._items_tooltip = tip

	local name_color = items_panel_rarity_colors[def.rarity] or Color.white
	-- Items pass loc keys in def.name/desc; modifiers pass pre-resolved text in def.name_text/desc_text.
	-- Use pre-resolved when present: :text() on an unknown key returns "ERROR…" not the literal.
	local resolved_name = def.name_text
		or (def.name and managers.localization and managers.localization:text(def.name))
		or ""
	local resolved_desc = def.desc_text
		or (def.desc and managers.localization and managers.localization:text(def.desc))
		or ""
	local name_text = tip:text({
		name = "tooltip_name",
		text = resolved_name,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = name_color,
		x = pad,
		y = pad,
		w = tip_w - pad * 2,
		h = name_h,
		layer = 5,
	})

	local desc_text = tip:text({
		name = "tooltip_desc",
		text = resolved_desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		x = pad,
		y = pad + name_h + 2,
		w = tip_w - pad * 2,
		h = 160,
		wrap = true,
		wrap_word = true,
		layer = 5,
	})
	local _, _, _, dh = desc_text:text_rect()
	desc_text:set_h(dh)

	local tip_h = pad + name_h + 2 + dh + pad
	tip:set_h(tip_h)

	tip:rect({
		name = "tooltip_bg",
		color = Color.black,
		alpha = 0.9,
		layer = 0,
		w = tip_w,
		h = tip_h,
	})
	BoxGuiObject:new(tip, {
		sides = { 1, 1, 1, 1 },
	})

	local cell_x, cell_y = target.panel:world_position()
	local panel_x, panel_y = fp_parent:world_position()
	local local_x = cell_x - panel_x
	local local_y = cell_y - panel_y

	local tx = local_x + items_panel_icon_size + 6
	if tx + tip_w > fp_parent:w() then
		tx = local_x - tip_w - 6
	end
	if tx < 0 then
		tx = 0
	end

	local ty = local_y
	if ty + tip_h > fp_parent:h() then
		ty = fp_parent:h() - tip_h - 4
	end
	if ty < 0 then
		ty = 0
	end

	tip:set_position(tx, ty)
end
