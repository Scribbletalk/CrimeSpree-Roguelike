-- CSROwnedItemsStrip — reusable inventory strip widget (selection popup + BM shop).
-- Call :rebuild() after item changes, :mouse_moved() for hover tooltip, :destroy() on close.

if not RequiredScript then
	return
end

CSROwnedItemsStrip = CSROwnedItemsStrip or class()

local OWNED_CELL = 56 -- icon container / hit-test footprint
local OWNED_FRAME = 62 -- frame overflows the cell so it reads as a border
local OWNED_MIN_CELL = 30 -- readability floor for the shrink loop
local OWNED_GAP = 6 -- inter-cell gap
local OWNED_PAD = 6 -- inner margin so frame overflow and badge are not clipped
local OWNED_GLYPH_RATIO = 0.5625 -- matches the lobby Items panel ratio
local OWNED_BADGE_OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- Includes contraband: owned items can be contraband (shop / scrapper).
local OWNED_RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}

-- Resolve a localization key to text; nil-safe.
local function csr_loc(s)
	if s and managers.localization then
		return managers.localization:text(s)
	end
	return s
end

-- Square cell size + column count for `count` items filling grid_w x avail_h. Cells are sized so a FULL
-- row of `per_row` cells plus fixed gaps spans grid_w exactly (icons shrink to fill the row, gap fixed);
-- fewest columns (largest cells, capped at OWNED_CELL) whose rows still fit avail_h. Dense inventories
-- fall back to OWNED_MIN_CELL packed by width. Mirrors the lobby Items panel's csr_adaptive_grid.
local function csr_adaptive_grid(count, grid_w, avail_h)
	if count <= 0 then
		return OWNED_CELL, 1
	end
	for per_row = 1, count do
		local cell = math.min(OWNED_CELL, math.floor((grid_w - (per_row - 1) * OWNED_GAP) / per_row))
		local rows = math.ceil(count / per_row)
		if cell >= OWNED_MIN_CELL and rows * (cell + OWNED_GAP) - OWNED_GAP <= avail_h then
			return cell, per_row
		end
	end
	local per_row = math.max(1, math.floor((grid_w + OWNED_GAP) / (OWNED_MIN_CELL + OWNED_GAP)))
	return OWNED_MIN_CELL, math.min(count, per_row)
end

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

-- Idempotent: tears down prior content first. Hidden when the local peer owns nothing.
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

	-- Split off the carry-1 wildcard: it gets a fixed square slot at the right, never the grid.
	local pid = mgr:local_peer_id()
	local counts = mgr:player_items(pid) or {}
	local items_list = {}
	local wildcard_entry = nil
	for _, item_type in ipairs(mgr:display_items_order(pid) or {}) do
		local def = by_type[item_type]
		local count = counts[item_type] or 0
		if def and count > 0 then
			if def.rarity == "wildcard" then
				wildcard_entry = { def = def, count = count }
			else
				items_list[#items_list + 1] = { def = def, count = count }
			end
		end
	end

	if #items_list == 0 and not wildcard_entry then
		self._panel:set_visible(false)
		return
	end
	self._panel:set_visible(true)

	local count = #items_list
	local total_avail_w = self._width - OWNED_PAD * 2
	-- Fixed grid height: the strip always occupies max_height; icons shrink rather than the panel growing.
	local avail_h = math.max(OWNED_MIN_CELL, self._max_height - OWNED_PAD * 2)

	-- Wildcard square slot = full grid height, pinned to the right edge (mirrors the lobby Items panel).
	local wc_slot = math.floor(math.max(OWNED_MIN_CELL, math.min(avail_h, total_avail_w)))
	local wc_x = OWNED_PAD + total_avail_w - wc_slot

	-- Regular grid fills the width left of the wildcard slot; cells shrink to fit the fixed height.
	local grid_w = total_avail_w - wc_slot
	local cell, per_row = OWNED_CELL, 1
	if count > 0 and grid_w > 0 then
		cell, per_row = csr_adaptive_grid(count, grid_w, avail_h)
	end
	local step = cell + OWNED_GAP

	local frame_size = math.floor(cell * OWNED_FRAME / OWNED_CELL)
	local frame_overflow = (frame_size - cell) / 2

	local used_cols = (count > 0) and math.min(count, per_row) or 0
	local reg_block_w = (used_cols > 0) and (used_cols * step - OWNED_GAP) or 0
	-- Regulars left-align at OWNED_PAD; centered within their own region only when not left-aligned.
	local grid_left = OWNED_PAD
	if self._align ~= "left" and grid_w > 0 then
		grid_left = grid_left + math.max(0, math.floor((grid_w - reg_block_w) / 2))
	end
	-- Fixed height: strip occupies max_height regardless of item count.
	local strip_h = avail_h + OWNED_PAD * 2
	self._panel:set_size(self._width, strip_h)
	if self._anchor then
		self._anchor(self._panel)
	end

	local content = self._panel:panel({
		layer = 5,
	})
	self._content = content

	-- BoxGuiObject bakes corner positions at construction — must rebuild with the panel, not reuse.
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

		-- Sibling (not child) of the cell so the larger frame overflows without clipping.
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

		local raw_icon = entry.def.icon or "dog_tags"
		local icon_tex, icon_rect = _G.CSR.icon_data(raw_icon)
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

		-- Badge drawn as sibling on `content` because cell panels clip children.
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

	-- Wildcard slot (carry-1): filled card when held, else a translucent wildcard-tinted placeholder.
	do
		local wc_color = OWNED_RARITY_COLORS.wildcard or Color.white
		-- Frame overflows the slot by the same item ratio so its visible border lands on the slot edge.
		local wc_frame_size = math.floor(wc_slot * OWNED_FRAME / OWNED_CELL)
		local wc_frame_overflow = math.floor((wc_frame_size - wc_slot) / 2)
		local slot_frame = content:bitmap({
			name = "wildcard_frame",
			texture = frame_tex,
			texture_rect = frame_rect,
			x = wc_x - wc_frame_overflow,
			y = OWNED_PAD - wc_frame_overflow,
			w = wc_frame_size,
			h = wc_frame_size,
			layer = 5,
		})
		if wildcard_entry then
			slot_frame:set_color(wc_color)
			local cell_panel = content:panel({
				x = wc_x,
				y = OWNED_PAD,
				w = wc_slot,
				h = wc_slot,
				layer = 10,
			})
			local raw_icon = wildcard_entry.def.icon or "dog_tags"
			local icon_tex, icon_rect = _G.CSR.icon_data(raw_icon)
			-- Wildcard glyph uses the same cell ratio as regular items, centred inside the frame.
			local glyph = math.floor(wc_slot * OWNED_GLYPH_RATIO * (wildcard_entry.def.icon_scale or 1))
			local glyph_inset = math.floor((wc_slot - glyph) / 2)
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
			self._hit_targets[#self._hit_targets + 1] = {
				panel = cell_panel,
				def = wildcard_entry.def,
				count = 1,
			}
		else
			slot_frame:set_color(wc_color:with_alpha(0.3))
		end
	end
end

-- Edge-triggered: only rebuilds tooltip when the hovered cell changes, avoiding per-event leaks.
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

-- Tooltip below the icon, flips above if it would overflow the parent bottom.
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

	-- Build text first, measure, then resize and add BoxGuiObject (bakes at construction).
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
	-- Split contraband ". But ..." drawback into a red second block (mirrors shop cards).
	local full_desc = _G.CSR.item_text(def.desc, def) or ""
	local main_desc, but_desc = _G.CSR.split_drawback(full_desc)
	local desc_y = pad + name_h + 2
	local desc_text = tip:text({
		name = "tooltip_desc",
		text = main_desc or full_desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		x = pad,
		y = desc_y,
		w = tip_w - pad * 2,
		h = 160,
		wrap = true,
		wrap_word = true,
		layer = 5,
	})
	local _, _, _, dh = desc_text:text_rect()
	desc_text:set_h(dh)

	local content_h = dh
	if but_desc then
		local but_text = tip:text({
			name = "tooltip_but",
			text = but_desc,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color(1, 1, 0.3, 0.3),
			x = pad,
			y = desc_y + dh,
			w = tip_w - pad * 2,
			h = 160,
			wrap = true,
			wrap_word = true,
			layer = 5,
		})
		local _, _, _, bh = but_text:text_rect()
		but_text:set_h(bh)
		content_h = dh + bh
	end

	local tip_h = pad + name_h + 2 + content_h + pad
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

csr_log("[CSR] owned_items_strip.lua loaded (reusable inventory strip widget)")
