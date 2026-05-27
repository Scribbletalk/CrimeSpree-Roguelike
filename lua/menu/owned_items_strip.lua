-- CSROwnedItemsStrip — reusable read-only inventory strip widget.
--
-- Renders the local peer's CURRENT items (icon + rarity frame + "xN" badge) as a
-- wrapped grid inside a black / blurred / bordered panel, with a hover tooltip
-- (name + desc). Same visual vocabulary as the lobby Items panel. Shared by the
-- item-selection popup (above the cards) and the Black Market shop page.
--
-- The widget OWNS its panel + tooltip + hit-targets. The host:
--   * creates it with { parent, tooltip_parent, width, layer, max_height, anchor }
--   * calls :rebuild() to (re)draw from live manager state (on open + whenever the
--     inventory can have changed -- pick granted, item bought)
--   * forwards :mouse_moved(x, y) for the hover tooltip
--   * calls :destroy() on close (or lets the parent panel teardown cascade clean it)
--
-- `anchor(panel)` is invoked at the end of each rebuild to POSITION the freshly
-- sized panel: only the host knows where the strip belongs on its own screen
-- (above the selection title vs. below the shop cards). `max_height` bounds the
-- adaptive cell shrink so a large inventory can't climb out of the host's region.

if not RequiredScript then
	return
end

CSROwnedItemsStrip = CSROwnedItemsStrip or class()

local OWNED_CELL = 56 -- icon container / hit-test footprint
local OWNED_FRAME = 62 -- frame overflows the cell so it reads as a border
local OWNED_MIN_CELL = 30 -- readability floor for the shrink loop
local OWNED_GAP = 6 -- inter-cell gap (== frame overflow*2, so frames tile edge to edge)
local OWNED_PAD = 6 -- inner margin so the overflowing frame / badge are not clipped (kept >= frame overflow + badge rise; trimmed from 10 to shorten the strip)
local OWNED_GLYPH_RATIO = 0.5625 -- glyph fills this fraction of the cell (the lobby ratio)
local OWNED_BADGE_OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- Inventory-view rarity palette: INCLUDES contraband (orange) because owned items
-- can be contraband (shop / scrapper). Matches the lobby Items panel palette.
local OWNED_RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}

-- Resolve a localization KEY to text. Item defs store name/desc as keys; :text()
-- returns the localized string for a known key (and an "ERROR ..." placeholder for
-- an unknown one -- so we never feed already-resolved text back through it).
local function csr_loc(s)
	if s and managers.localization then
		return managers.localization:text(s)
	end
	return s
end

-- opts:
--   parent         : panel hosting the strip panel (required)
--   tooltip_parent : panel hosting the hover tooltip (default = parent)
--   width          : strip panel width in px (required)
--   layer          : strip panel layer (default 51)
--   max_height     : max strip height; the cell shrinks to fit (default 600)
--   align          : "center" (default) centres the item block in the panel width;
--                    "left" hugs the left inset
--   anchor         : function(panel) positions the freshly sized panel each rebuild
function CSROwnedItemsStrip:init(opts)
	opts = opts or {}
	self._parent = opts.parent
	self._tooltip_parent = opts.tooltip_parent or opts.parent
	self._width = opts.width or 600
	self._layer = opts.layer or 51
	self._max_height = opts.max_height or 600
	self._align = opts.align or "center"
	self._anchor = opts.anchor
	self._hit_targets = {}

	if self._parent and alive(self._parent) then
		self._panel = self._parent:panel({
			layer = self._layer,
		})
	end
end

function CSROwnedItemsStrip:panel()
	return self._panel
end

-- (Re)build the strip content from live manager state. Idempotent: prior content
-- + hover state are torn down first, so it is safe to call on open AND whenever the
-- inventory can have changed. Hidden entirely when the local peer owns nothing.
function CSROwnedItemsStrip:rebuild()
	if not self._panel or not alive(self._panel) then
		return
	end

	if self._content and alive(self._content) then
		self._panel:remove(self._content)
	end
	self._content = nil
	self._hit_targets = {}
	self._hover_target = nil
	self:_clear_tooltip()

	local mgr = managers and managers.csr
	if not mgr or not mgr.registered_items or not mgr.local_peer_id then
		self._panel:set_visible(false)
		return
	end

	local by_type = {}
	for _, def in ipairs(mgr:registered_items()) do
		by_type[def.type] = def
	end

	-- Items in ACQUISITION ORDER (first-obtained first); a duplicate only bumps the
	-- badge count. player_items_order is the self-healing ordered type list.
	local pid = mgr:local_peer_id()
	local counts = mgr:player_items(pid) or {}
	local items_list = {}
	for _, item_type in ipairs(mgr:player_items_order(pid) or {}) do
		local def = by_type[item_type]
		local count = counts[item_type] or 0
		if def and count > 0 then
			items_list[#items_list + 1] = { def = def, count = count }
		end
	end

	if #items_list == 0 then
		self._panel:set_visible(false)
		return
	end
	self._panel:set_visible(true)

	-- Grid is inset by OWNED_PAD on every side so the frame (overflows the cell) and
	-- the "xN" badge (rides the icon corner) are never clipped by the content panel.
	local count = #items_list
	local grid_w = self._width - OWNED_PAD * 2
	-- Grid height budget: the host's max_height minus the panel's own padding. Floored
	-- at OWNED_MIN_CELL (NOT OWNED_CELL) -- flooring at the full cell would stop the
	-- cell from ever shrinking below one full row, making a small max_height a no-op.
	local avail_h = math.max(OWNED_MIN_CELL, self._max_height - OWNED_PAD * 2)

	local function layout_for(size)
		local step = size + OWNED_GAP
		local per_row = math.max(1, math.min(count, math.floor((grid_w + OWNED_GAP) / step)))
		return per_row, math.ceil(count / per_row), step
	end

	-- Shrink the shared square cell until every wrapped row fits avail_h (same
	-- adaptive idea as the lobby Items grid). OWNED_MIN_CELL is the readability
	-- floor; an inventory too large even at the floor overflows (rare).
	local cell = OWNED_CELL
	local per_row, rows, step = layout_for(cell)
	while cell > OWNED_MIN_CELL and rows * (cell + OWNED_GAP) - OWNED_GAP > avail_h do
		cell = cell - 2
		per_row, rows, step = layout_for(cell)
	end
	cell = math.floor(math.max(cell, OWNED_MIN_CELL))
	per_row, rows, step = layout_for(cell)

	-- Frame keeps its over-cell ratio so it overflows symmetrically at any size.
	local frame_size = math.floor(cell * OWNED_FRAME / OWNED_CELL)
	local frame_overflow = (frame_size - cell) / 2

	-- Panel spans the configured width. The item block hugs the left inset when
	-- align == "left"; otherwise it is centred horizontally so a short row sits in the
	-- middle (a partial last row left-aligns within the centred full-row block).
	-- Height tracks the row count.
	local used_cols = math.min(count, per_row)
	local block_w = used_cols * step - OWNED_GAP
	local grid_left = OWNED_PAD
	if self._align ~= "left" then
		grid_left = grid_left + math.max(0, math.floor((self._width - OWNED_PAD * 2 - block_w) / 2))
	end
	local strip_h = rows * step - OWNED_GAP + OWNED_PAD * 2
	self._panel:set_size(self._width, strip_h)
	if self._anchor then
		self._anchor(self._panel)
	end

	local content = self._panel:panel({
		layer = 5,
	})
	self._content = content

	-- Black background + blur + bordered corners, matching the lobby Items panel
	-- (missions_menu.lua _create_feature_panels). Drawn on `content` (torn down and
	-- rebuilt each populate) so it resizes with the strip and never accumulates;
	-- BoxGuiObject bakes its corner positions at construction, so it must be rebuilt
	-- with the panel rather than created once on the persistent strip panel.
	local bg = content:panel({
		layer = -1,
	})
	bg:rect({
		alpha = 0.4,
		color = Color.black,
	})
	bg:bitmap({
		texture = "guis/textures/test_blur_df",
		name = "blur_bg",
		halign = "scale",
		valign = "scale",
		layer = -1,
		render_template = "VertexColorTexturedBlur3D",
		w = bg:w(),
		h = bg:h(),
	})
	BoxGuiObject:new(
		content:panel({
			layer = 100,
		}),
		{
			sides = { 1, 1, 1, 1 },
		}
	)

	local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")

	for i, entry in ipairs(items_list) do
		local col = (i - 1) % per_row
		local row = math.floor((i - 1) / per_row)
		local ix = grid_left + col * step
		local iy = OWNED_PAD + row * step

		-- Frame is a SIBLING of the cell (not its child) so its larger footprint can
		-- overflow the cell symmetrically; layer 5 (frame) < layer 10 (cell) keeps the
		-- icon above the frame even where the frame extends past the cell.
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
		frame_bmp:set_color(OWNED_RARITY_COLORS[entry.def.rarity] or Color.white)

		local cell_panel = content:panel({
			x = ix,
			y = iy,
			w = cell,
			h = cell,
			layer = 10,
		})

		-- Resolve icon: a "/" means a full DB-mounted texture path (addon shipping its
		-- own .dds); otherwise a short hud_icons id (CSR's built-in items).
		local icon_tex, icon_rect
		local raw_icon = entry.def.icon or "dog_tags"
		if type(raw_icon) == "string" and raw_icon:find("/", 1, true) then
			icon_tex, icon_rect = raw_icon, { 0, 0, 128, 128 }
		else
			icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(raw_icon)
		end
		local glyph = math.floor(cell * OWNED_GLYPH_RATIO * (entry.def.icon_scale or 1))
		local glyph_inset = math.floor((cell - glyph) / 2)
		cell_panel:bitmap({
			name = "item_icon",
			texture = icon_tex,
			texture_rect = icon_rect,
			x = glyph_inset,
			y = glyph_inset,
			w = glyph,
			h = glyph,
			layer = 10,
		})

		-- Stack badge "xN": white glyph with a thin black outline (no bg box), drawn as
		-- siblings on `content` because cell panels clip children. Anchored bottom-left
		-- to the glyph's top-right corner so it stays clear of the centred glyph at any
		-- cell size; layers 19/20 (outline under white) sit above frame (5) / cell (10).
		local badge_x = ix + glyph_inset + glyph
		local badge_drop = math.floor(tweak_data.menu.pd2_small_font_size * 0.2)
		local badge_y = iy + math.min(glyph_inset, 9) + badge_drop - OWNED_CELL
		local badge = {
			name = "stack_badge",
			text = "x" .. tostring(entry.count),
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			align = "left",
			vertical = "bottom",
			w = OWNED_CELL,
			h = OWNED_CELL,
		}
		badge.color = Color.black
		badge.layer = 19
		for _, off in ipairs(OWNED_BADGE_OUTLINE) do
			badge.x, badge.y = badge_x + off[1], badge_y + off[2]
			content:text(badge)
		end
		badge.color = Color.white
		badge.layer = 20
		badge.x, badge.y = badge_x, badge_y
		content:text(badge)

		self._hit_targets[#self._hit_targets + 1] = {
			panel = cell_panel,
			def = entry.def,
			count = entry.count,
		}
	end
end

-- Edge-triggered hover: only rebuilds the tooltip when the hovered cell CHANGES, so
-- moving within one icon does not recreate (and leak) the tooltip panel every event.
-- Returns true while a cell is hovered (the host may use it to set a link cursor).
function CSROwnedItemsStrip:mouse_moved(x, y)
	if not self._panel or not alive(self._panel) or not self._panel:visible() then
		if self._hover_target ~= nil then
			self._hover_target = nil
			self:_clear_tooltip()
		end
		return false
	end
	if not self._hit_targets or #self._hit_targets == 0 then
		return false
	end

	local hovered = nil
	for _, target in ipairs(self._hit_targets) do
		if alive(target.panel) and target.panel:inside(x, y) then
			hovered = target
			break
		end
	end

	if hovered ~= self._hover_target then
		self._hover_target = hovered
		self:_clear_tooltip()
		if hovered then
			self:_show_tooltip(hovered)
		end
	end

	return hovered ~= nil
end

function CSROwnedItemsStrip:_clear_tooltip()
	local parent = self._tooltip_parent
	if self._tooltip and alive(self._tooltip) and parent and alive(parent) then
		parent:remove(self._tooltip)
	end
	self._tooltip = nil
end

-- Tooltip anchored below the hovered icon (flipping above it if it would overflow
-- the parent bottom), clamped to the tooltip parent on both axes.
function CSROwnedItemsStrip:_show_tooltip(target)
	if not target or not alive(target.panel) then
		return
	end
	local parent = self._tooltip_parent
	if not parent or not alive(parent) then
		return
	end

	local def = target.def
	local pad = 6
	local tip_w = 220
	local name_h = tweak_data.menu.pd2_small_font_size + 2

	-- Build at a placeholder height to host the text nodes, measure, then resize and
	-- add chrome LAST (BoxGuiObject bakes its corner sprites at construction time, so
	-- building it pre-resize would strand the corners at the placeholder size).
	local tip = parent:panel({
		layer = 200,
		w = tip_w,
		h = 200,
	})
	self._tooltip = tip

	local name_color = OWNED_RARITY_COLORS[def.rarity] or Color.white
	tip:text({
		name = "tooltip_name",
		text = csr_loc(def.name) or "",
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
		text = csr_loc(def.desc) or "",
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
	local parent_x, parent_y = parent:world_position()
	local local_x = cell_x - parent_x
	local local_y = cell_y - parent_y

	local tx = local_x
	if tx + tip_w > parent:w() then
		tx = parent:w() - tip_w
	end
	if tx < 0 then
		tx = 0
	end

	local ty = local_y + target.panel:h() + 6
	if ty + tip_h > parent:h() then
		ty = local_y - tip_h - 6
	end
	if ty < 0 then
		ty = 0
	end

	tip:set_position(tx, ty)
end

function CSROwnedItemsStrip:destroy()
	self:_clear_tooltip()
	if self._panel and alive(self._panel) and self._parent and alive(self._parent) then
		self._parent:remove(self._panel)
	end
	self._panel = nil
	self._content = nil
	self._hit_targets = {}
	self._hover_target = nil
end

log("[CSR] owned_items_strip.lua loaded (reusable inventory strip widget)")
