-- CSRMissionsMenuComponent — Items feature-panel (extracted from missions_menu.lua).
-- Loads on lib/managers/menu/menucomponentmanager AFTER missions_menu.lua (mod.txt
-- order), so the class table already exists; this file adds the Items panel methods
-- (catalogue grid + per-peer sections + hover tooltip) to it. Self-contained: its
-- own layout constants + the adaptive-grid helper live here.
if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

-- Items feature-panel layout. Rarity palette includes contraband even though
-- contraband items are excluded from the SELECTION-WINDOW pool (U1 drop-rate
-- redesign cut them from random rolls): the items themselves still exist and
-- can reach a player's inventory through other paths (e.g. the shop when ported
-- back), so the inventory view needs the matching frame tint. Contraband
-- orange matches the logbook's RARITY_FRAMES.contraband (logbook_menu.lua:257).
local items_panel_rarity_colors = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}
-- items_panel_icon_size is misnamed historically -- it is the CELL size (used
-- for the grid step and hover hit-test). The visible icon and the visible frame
-- have their own sizes below; the frame deliberately overflows the cell so it
-- reads as a card that's "a bit bigger than the icon" (user spec).
local items_panel_icon_size = 64
local items_panel_frame_size = 72
local items_panel_icon_gap = 8
-- Absolute floor for the cell size (RoR2-style adaptive items grid -- see
-- csr_adaptive_grid). Each player's inventory must fit a FIXED quarter of the panel
-- height, so cells shrink from items_panel_icon_size down to this as the count
-- grows; an inventory too large to fit its quarter even at this size overflows
-- (the readability floor). Low enough that the full 31-type inventory still fits a
-- quarter at typical panel heights.
local items_panel_min_icon_size = 28
local items_panel_peer_header_h = 22
-- 4-direction 1px offsets for the stack-count outline: the badge is drawn in black
-- at these offsets under the white copy, so "xN" stays readable over any icon at
-- small cell sizes -- no background box, no font scaling (user choice). Diesel text
-- has no native stroke; this multi-draw is the standard outline technique.
local items_panel_badge_outline = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- Cap (px) on how far below the cell top the stack badge's box bottom sits. The raw
-- anchor is cell_top + glyph_inset + drop, but glyph_inset (the glyph's centring
-- margin) grows with the cell, which dragged the number too low on big icons. Cap it
-- so the number stays near the top-right corner at every size; small icons, whose
-- glyph_inset is already below the cap, are unaffected.
local items_panel_badge_top_inset = 9
local items_panel_padding = 16

-- Adaptive grid sizing for the items panel: each player's inventory must fit a
-- FIXED region (a quarter of the panel height), so the cells share one square size
-- that SHRINKS as the count grows until every row fits BOTH the available width
-- and height. Returns the largest such size (<= max_size, clamped at min_size as
-- the floor) and the per-row column count. A count too large to fit even at
-- min_size overflows -- min_size is the readability floor. The inter-cell `gap` is
-- fixed (the size adapts, not the gap); the caller left-aligns, so a full row spans
-- the width and a partial last row hugs the left. cell_size is floored for crisp
-- rendering. Height-fit shrink loop, left-aligned (no justify-stretch) to
-- preserve the items panel's look.
local function csr_adaptive_grid(count, avail_w, avail_h, max_size, min_size, gap)
	if count <= 0 then
		return max_size, 1
	end
	-- Columns of `size` cells that fit avail_w, capped at count (a partial set
	-- leaves no empty trailing columns); rows derived from that.
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

-- Resolve a per-peer accent color (4-arg Color form, per Critical Rule #6).
-- tweak_data.peer_vector_colors is the same source vanilla teammate contours and
-- chat use, so the panel color-codes match what the player already associates
-- with each peer everywhere else in the UI.
function CSRMissionsMenuComponent:_items_panel_peer_color(peer_id)
	local v = tweak_data and tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[peer_id]
	if v then
		return Color(1, v.x, v.y, v.z)
	end
	return Color.white
end

-- Deterministic peer order: local peer first (always present, never duplicated),
-- then remote peers ascending by id. Used as the per-peer section order in the
-- items panel so adding/removing a teammate does not jumble existing sections.
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

	-- Also include any peer we hold SYNCED items for that the live session list
	-- missed (timing), plus the SP debug fake peer. Uses the synced name. A no-op
	-- once session:peers() already covers them (seen-guarded). Sorted by id for a
	-- stable section order.
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

-- Build / rebuild the items feature-panel content from the live manager state.
-- Idempotent: prior content panel is torn down first, hit-target list reset.
-- MP-shaped from day one (per-peer cycle); other peers render empty until the
-- count-model sync slice lands (design O4) -- the UI then just starts showing
-- their items with no code change.
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

	-- No section title: the sidebar row "Items" already labels the panel; an in-
	-- panel "ITEMS" header was visual duplication. Per-peer color-strip headers
	-- carry the structure on their own.
	local section_w = panel:w() - items_panel_padding * 2
	-- Each player's inventory occupies a FIXED quarter of the panel height, so the
	-- layout is stable for up to 4 players and a peer's grid never grows past its
	-- slot -- it shrinks to fit (like the Modifiers/Rewards panels). In SP the single
	-- peer fills the top quarter; the lower three are reserved for teammates.
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
			-- Local peer is identifiable by their color strip (matches chat /
			-- teammate contour color); no "(you)" suffix needed.
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

		-- Items render in ACQUISITION ORDER (first-obtained first); a duplicate only
		-- bumps the badge count and keeps its slot. player_items_order is the ordered
		-- type list (self-healing for legacy/remote), so no sort here.
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
			-- Grid sits below the header and fills the REST of this peer's quarter.
			-- 10px breathing room under the (vertical-centered, ~24px-glyph) 22px
			-- header before the icons. csr_adaptive_grid is height-aware: it shrinks
			-- the shared square cell (from items_panel_icon_size down to the min)
			-- until every row fits grid_h, so the inventory stays inside its quarter.
			-- Left-aligned, fixed gap; the rarity frame, glyph and badge all scale
			-- with the cell size.
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
			-- Frame keeps its 72/64 over-cell ratio so it still overflows the cell
			-- symmetrically at any size.
			local frame_size = math.floor(cell_size * items_panel_frame_size / items_panel_icon_size)
			local frame_overflow = (frame_size - cell_size) / 2
			local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")

			for i, entry in ipairs(items_list) do
				local col = (i - 1) % per_row
				local row = math.floor((i - 1) / per_row)
				local ix = items_panel_padding + col * step
				local iy = grid_y + row * step

				-- Frame is a SIBLING of the cell on `content`, not a child, so its
				-- 72x72 footprint can overflow the 64x64 cell by 4px each side --
				-- giving the frame a bigger visible read than the icon while
				-- keeping the cell as the precise hit-test footprint. Layer 5 here
				-- + cell layer 10 below puts the icon above the frame even though
				-- the frame extends past the cell bounds (no clipping).
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

				-- Resolve icon: a "/" means a full DB-mounted texture path (addon
				-- shipping its own .dds via DB:create_entry); otherwise a short
				-- hud_icons id (CSR's built-in items). Direct-path branch
				-- assumes 128x128 -- promote `icon` to a table if an addon
				-- needs a different rect.
				local icon_tex, icon_rect
				local raw_icon = entry.def.icon or "dog_tags"
				if type(raw_icon) == "string" and raw_icon:find("/", 1, true) then
					icon_tex, icon_rect = raw_icon, { 0, 0, 128, 128 }
				else
					icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(raw_icon)
				end
				-- Glyph fills 56.25% of the cell (the legacy 36px-in-64px ratio),
				-- times the optional per-item icon_scale, centred in the cell.
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

				-- Stack badge: white "xN" with a thin black outline (readable over any
				-- icon; no background box, no font scaling -- user choice). Anchored by
				-- its BOTTOM-LEFT to the glyph's TOP-RIGHT corner (align left + vertical
				-- bottom), so the number sits at the glyph corner and extends UP + RIGHT,
				-- always clear of the centred glyph. As the cell shrinks the glyph (and
				-- its corner) shrink too, so the fixed-size number automatically rides
				-- further up-right OUT of the icon instead of overlapping it. Shown
				-- unconditionally (incl. x1) so the inventory reads as a stack-count
				-- view. SIBLINGS of the cell on `content` (cell panels clip children in
				-- Diesel); w/h is just a generous container -- only the glyphs render,
				-- left/bottom-aligned at (badge_x, badge_y + h). Layers 19/20 put the
				-- outline (19) under the white glyph (20), both above frame (5)/cell (10).
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
				-- Box left = glyph right edge; box bottom (badge_y + h) sits a little below
				-- the cell top so the number rides the top-right corner. The vertical
				-- offset is min(glyph_inset, cap) + drop: the glyph_inset term tracks the
				-- corner on small icons but is capped so big icons (with a wide centring
				-- margin) don't drag the number low. drop is a fraction of the NUMBER's own
				-- (fixed) height, so the corner overlap reads the same at every size.
				local badge_x = ix + glyph_inset + glyph
				local badge_drop = math.floor(tweak_data.menu.pd2_small_font_size * 0.2)
				local badge_inset = math.min(glyph_inset, items_panel_badge_top_inset)
				local badge_y = (iy + badge_inset + badge_drop) - items_panel_icon_size
				-- Black outline copies first (under), then the white glyph on top. The
				-- params table is reused -- panel:text() reads it at call time and does
				-- not retain it, so mutating between calls is safe.
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

-- Edge-triggered hover for the items grid. mouse_moved is event-driven (not a
-- per-frame path), so the linear walk over hit targets is fine; the targets
-- list is small (28 items × N peers in the worst case).
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
			-- No "highlight" hover SFX: items are passive inventory entries,
			-- not selectable controls, and per-cell hover audio in a dense grid
			-- would chatter as the cursor crosses cells (user spec 2026-05-20).
			self:_show_items_tooltip(hovered)
		end
	end

	return hovered ~= nil
end

function CSRMissionsMenuComponent:_clear_items_tooltip()
	-- Tooltip parent must match where _show_items_tooltip created it (abstract
	-- _csr_fp_parent, set in _setup): on the briefing screen the tooltip lives
	-- on the saferect workspace panel, not on self._panel. Lobby's
	-- _csr_fp_parent == self._panel so this is a no-behavior-change rewrite
	-- there.
	local parent = self._csr_fp_parent or self._panel
	if self._items_tooltip and alive(self._items_tooltip) and parent and alive(parent) then
		parent:remove(self._items_tooltip)
	end
	self._items_tooltip = nil
end

-- Tooltip anchored to the hovered icon (not the cursor). Floats above the items
-- panel on self._panel layer 200 so it overlaps the sidebar / cards cleanly.
-- Clamped to self._panel bounds so an icon near the panel edge does not push
-- the tooltip off-screen.
function CSRMissionsMenuComponent:_show_items_tooltip(target)
	if not target or not alive(target.panel) then
		return
	end
	local def = target.def
	local pad = 6
	local tip_w = 200
	local name_h = tweak_data.menu.pd2_small_font_size + 2

	-- Tooltip is parented and clamped to the abstract feature-panels parent
	-- (set in _setup as _csr_fp_parent). Lobby keeps the historical behavior
	-- (_csr_fp_parent == self._panel); the briefing screen sets it to the
	-- saferect ws_panel so the tooltip can clamp against the full saferect.
	local fp_parent = self._csr_fp_parent or self._panel

	-- Build at placeholder height so we can host the text nodes for measurement.
	-- BoxGuiObject and the bg rect are added AFTER the final resize -- BoxGui
	-- bakes its corner/edge sprite positions at construction time, so creating
	-- it pre-resize leaves the corners stranded at the placeholder dimensions
	-- (the visible artefact the user reported as "weird corners").
	local tip = fp_parent:panel({
		layer = 200,
		w = tip_w,
		h = 200,
	})
	self._items_tooltip = tip

	local name_color = items_panel_rarity_colors[def.rarity] or Color.white
	-- Resolve display text. Items pass loc KEYS in def.name/def.desc (resolved
	-- per language here). Modifiers pass PRE-RESOLVED literals in def.name_text/
	-- def.desc_text (the combined "Title\nBody" loc string is split before it
	-- reaches us). Prefer the pre-resolved field when present: feeding an already
	-- localized literal back through :text() does NOT echo it -- the engine
	-- returns an "ERROR ..." placeholder for an unknown key, which is exactly the
	-- doubled-"ERROR" the modifier tooltip showed.
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

	-- Desc wraps within tip_w-2*pad; measured h tracks however many lines the
	-- text actually needs, so a one-word desc isn't padded with blank space.
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

	-- Final size, THEN chrome: BoxGui captures the panel's w/h at construction.
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
