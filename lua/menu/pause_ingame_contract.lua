-- Rebuilds the ESC pause right panel for CSR heists.
-- CSR uses STANDARD gamemode so IngameContractGui renders; vanilla fills it from the temp
-- "crime_spree" job whose loc key is missing ("ERROR: ..."). We detect and rebuild from CSR data.

if not RequiredScript then
	return
end

if not IngameContractGui then
	return
end

-- Rarity -> frame tint. Mirrors lobby_sidebar_items.lua so the pause panel reads
-- the same as the briefing/lobby item grids. Contraband is included (shop-reachable).
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}

local ITEM_ICON_MAX = 56 -- preferred cell size; shrinks via the adaptive grid to fit height
local ITEM_ICON_MIN = 24 -- readability floor
local ITEM_GAP = 6
local GRID_MARGIN = 4 -- keeps the overflowing rarity frame off the left/right edges
local PEER_HEADER_H = 22
local PAUSE_SIDEBAR_W = 160 -- mini-sidebar strip width; matches lobby CSRSidebar.WIDTH so "PREFERENCES" fits
local FRAME_TO_CELL = 72 / 64 -- frame overflows the cell symmetrically (same ratio as the sidebar)
-- 4-direction 1px offsets for the stack-count outline; Diesel text has no native stroke.
local BADGE_OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- Caps the big-icon centring margin so the badge isn't dragged too far down (mirrors lobby sidebar).
local BADGE_TOP_INSET = 9
-- CSR heist marker: STANDARD gamemode + a temporary "crime_spree" job. Same
-- signal heist_packages.lua uses; holds for host, guest and single-player.
local function csr_heist_active()
	return managers.job and managers.job:current_job_id() == "crime_spree"
end

-- Adaptive grid: fewest columns (largest cells, capped at max) whose rows fit avail_h.
-- Ported from lobby_sidebar_items.lua.
local function csr_adaptive_grid(count, avail_w, avail_h, max_size, min_size, gap)
	if count <= 0 then
		return max_size, 1
	end
	for per_row = 1, count do
		local cell = math.min(max_size, math.floor((avail_w - (per_row - 1) * gap) / per_row))
		local rows = math.ceil(count / per_row)
		if cell >= min_size and rows * (cell + gap) - gap <= avail_h then
			return cell, per_row
		end
	end
	local per_row = math.max(1, math.floor((avail_w + gap) / (min_size + gap)))
	return min_size, math.min(count, per_row)
end

-- Teammate colors match contours/chat via tweak_data.peer_vector_colors.
local function csr_peer_color(peer_id)
	local v = tweak_data and tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[peer_id]
	if v then
		return Color(1, v.x, v.y, v.z)
	end
	return Color.white
end

-- Local peer first, then session peers, then synced-only peers the session list missed
-- (timing) and the SP debug peer. Ported from the sidebar's _collect_peers_for_items_panel.
local function csr_collect_peers(mgr)
	local out, seen = {}, {}
	local local_pid = mgr:local_peer_id()
	local nm = managers and managers.network
	local session = nm and nm.session and nm:session()

	local local_peer = session and session.local_peer and session:local_peer()
	if local_peer then
		local lid = local_peer:id()
		out[1] = { id = lid, name = (local_peer.name and local_peer:name()) or "Player", color = csr_peer_color(lid) }
		seen[lid] = true
	else
		out[1] = { id = local_pid, name = "Player", color = csr_peer_color(local_pid) }
		seen[local_pid] = true
	end

	if session and session.peers then
		local remote = {}
		for pid, peer in pairs(session:peers() or {}) do
			if not seen[pid] then
				seen[pid] = true
				remote[#remote + 1] = {
					id = pid,
					name = (peer.name and peer:name()) or ("Peer " .. tostring(pid)),
					color = csr_peer_color(pid),
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

	if mgr.remote_peer_ids then
		local extra = {}
		for _, pid in ipairs(mgr:remote_peer_ids()) do
			if not seen[pid] then
				seen[pid] = true
				local nm2 = (mgr.remote_peer_name and mgr:remote_peer_name(pid)) or ("Peer " .. tostring(pid))
				extra[#extra + 1] = { id = pid, name = nm2, color = csr_peer_color(pid) }
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

-- Status header row: MISSIONS COMPLETED | RANK | DIFFICULTY. Mirrors lobby _create_status_bar.
-- Reuses lobby loc keys and getters; guest sees host figures. Returns bottom y.
local function csr_render_status_header(parent, top, w)
	local mgr = managers.csr
	local highlight = Color(1, 1, 1, 0)
	local cs_glyph = utf8.char(0xE018)
	local row_h = tweak_data.menu.pd2_medium_font_size
	local font = tweak_data.menu.pd2_medium_font
	local font_size = tweak_data.menu.pd2_medium_font_size

	local missions_prefix = managers.localization:to_upper_text("csr_lobby_missions_completed") .. ": "
	local missions_done = (mgr.mp_host_missions_completed and mgr:mp_host_missions_completed())
		or mgr:missions_completed()
	local missions_str = missions_prefix .. tostring(missions_done)
	local missions_text = parent:text({
		x = 0,
		y = top,
		w = w,
		h = row_h,
		vertical = "bottom",
		align = "left",
		text = missions_str,
		color = Color.white,
		font = font,
		font_size = font_size,
		layer = 1,
	})
	missions_text:set_range_color(utf8.len(missions_prefix), utf8.len(missions_str), highlight)

	local rank_prefix = managers.localization:to_upper_text("csr_lobby_rank") .. ": "
	local rank_str = rank_prefix .. tostring(mgr:host_rank()) .. " " .. cs_glyph
	local rank_text = parent:text({
		x = 0,
		y = top,
		w = w,
		h = row_h,
		vertical = "bottom",
		align = "center",
		text = rank_str,
		color = Color.white,
		font = font,
		font_size = font_size,
		layer = 1,
	})
	rank_text:set_range_color(utf8.len(rank_prefix), utf8.len(rank_str), highlight)

	-- While guesting show the HOST's difficulty; nil falls back to own.
	local diff_id = (mgr.mp_host_difficulty and mgr:mp_host_difficulty()) or mgr:difficulty()
	local diff_name_id = tweak_data.difficulty_name_ids[diff_id]
	local diff_text = diff_name_id and managers.localization:to_upper_text(diff_name_id) or tostring(diff_id)
	local diff_prefix = managers.localization:to_upper_text("csr_lobby_difficulty") .. ": "
	local diff_full = diff_prefix .. diff_text
	local diff_label = parent:text({
		x = 0,
		y = top,
		w = w,
		h = row_h,
		vertical = "bottom",
		align = "right",
		text = diff_full,
		color = Color.white,
		font = font,
		font_size = font_size,
		layer = 1,
	})
	diff_label:set_range_color(utf8.len(diff_prefix), utf8.len(diff_full), highlight)

	return top + row_h
end

-- Peer-name header + adaptive icon grid. ctx = shared render state table.
-- Each drawn cell appends a hit-target to ctx.targets for the tooltip hook.
local function csr_render_peer_items(ctx, peer, section_top, section_h)
	local parent, by_type, avail_w = ctx.parent, ctx.by_type, ctx.avail_w
	local frame_tex, frame_rect, mgr, targets = ctx.frame_tex, ctx.frame_rect, ctx.mgr, ctx.targets
	local pcolor = peer.color

	parent:rect({ color = pcolor, x = 0, y = section_top, w = 4, h = PEER_HEADER_H, layer = 2 })
	parent:text({
		text = peer.name,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = pcolor,
		x = 10,
		y = section_top,
		w = avail_w - 10,
		h = PEER_HEADER_H,
		vertical = "center",
		align = "left",
		layer = 2,
	})

	-- Scrap first (rare->uncommon->common), then acquisition order; the carry-1 wildcard is split
	-- off into its own fixed slot and never joins the grid (it can never stack).
	local counts = mgr:player_items(peer.id) or {}
	local items_list = {}
	local wildcard_entry = nil
	for _, item_type in ipairs(mgr:display_items_order(peer.id)) do
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
		return
	end

	local grid_top = section_top + PEER_HEADER_H + 4
	local grid_h = section_top + section_h - grid_top
	if grid_h < ITEM_ICON_MIN then
		return
	end

	-- Two columns: items grid (left, left-aligned) + wildcard slot pinned to the right edge. With few
	-- items a natural hole sits between them; grid_w stays maximal to keep that hole as small as possible.
	local avail_grid_w = avail_w - GRID_MARGIN * 2
	local wc_slot = math.max(ITEM_ICON_MIN, math.min(grid_h, avail_grid_w))
	local grid_w = avail_grid_w - wc_slot
	local wc_x = GRID_MARGIN + avail_grid_w - wc_slot
	local cell, per_row = csr_adaptive_grid(#items_list, grid_w, grid_h, ITEM_ICON_MAX, ITEM_ICON_MIN, ITEM_GAP)
	local step = cell + ITEM_GAP
	local frame_size = math.floor(cell * FRAME_TO_CELL)
	local frame_overflow = (frame_size - cell) / 2

	for i, entry in ipairs(items_list) do
		local col = (i - 1) % per_row
		local row = math.floor((i - 1) / per_row)
		local ix = GRID_MARGIN + col * step
		local iy = grid_top + row * step

		-- Rarity frame (overflows the cell, drawn under the glyph).
		local frame = parent:bitmap({
			texture = frame_tex,
			texture_rect = frame_rect,
			x = ix - frame_overflow,
			y = iy - frame_overflow,
			w = frame_size,
			h = frame_size,
			layer = 3,
		})
		frame:set_color(RARITY_COLORS[entry.def.rarity] or Color.white)

		local raw = entry.def.icon or "dog_tags"
		local icon_tex, icon_rect = _G.CSR.icon_data(raw)
		-- Legacy 36px-in-64px glyph ratio, scaled by optional per-item icon_scale.
		local glyph = math.floor(cell * (1 - 28 / 64) * (entry.def.icon_scale or 1))
		local glyph_inset = math.floor((cell - glyph) / 2)
		parent:bitmap({
			texture = icon_tex,
			texture_rect = icon_rect,
			x = ix + glyph_inset,
			y = iy + glyph_inset,
			w = glyph,
			h = glyph,
			layer = 4,
		})

		-- Stack badge: white "xN" with black multi-draw outline, top-right of the cell.
		-- Y math mirrors lobby sidebar; plain vertical=top placed it a font-height too low.
		if entry.count > 1 then
			local badge_drop = math.floor(tweak_data.menu.pd2_small_font_size * 0.2)
			local badge_inset = math.min(glyph_inset, BADGE_TOP_INSET)
			local badge_y = (iy + badge_inset + badge_drop) - cell
			local badge = {
				text = "x" .. tostring(entry.count),
				font = tweak_data.menu.pd2_small_font,
				font_size = tweak_data.menu.pd2_small_font_size,
				align = "right",
				vertical = "bottom",
				w = cell,
				h = cell,
			}
			badge.color = Color.black
			badge.layer = 5
			for _, off in ipairs(BADGE_OUTLINE) do
				badge.x, badge.y = ix + off[1], badge_y + off[2]
				parent:text(badge)
			end
			badge.color = Color.white
			badge.layer = 6
			badge.x, badge.y = ix, badge_y
			parent:text(badge)
		end

		-- Invisible hit panel over the cell; used only for tooltip hover-testing via :inside().
		local hit = parent:panel({ x = ix, y = iy, w = cell, h = cell, layer = 7 })
		targets[#targets + 1] = { panel = hit, def = entry.def, count = entry.count }
	end

	-- Wildcard slot (carry-1): a filled card when held, else a translucent wildcard-tinted placeholder.
	do
		local wc_color = RARITY_COLORS.wildcard or Color.white
		-- Frame overflows the slot by the 72/64 item ratio so its visible border lands on the slot edge.
		local wc_frame_size = math.floor(wc_slot * FRAME_TO_CELL)
		local wc_frame_overflow = math.floor((wc_frame_size - wc_slot) / 2)
		local slot_frame = parent:bitmap({
			texture = frame_tex,
			texture_rect = frame_rect,
			x = wc_x - wc_frame_overflow,
			y = grid_top - wc_frame_overflow,
			w = wc_frame_size,
			h = wc_frame_size,
			layer = 3,
		})
		if wildcard_entry then
			slot_frame:set_color(wc_color)
			local raw = wildcard_entry.def.icon or "dog_tags"
			local icon_tex, icon_rect = _G.CSR.icon_data(raw)
			-- Wildcard glyph uses the same 0.5625 cell ratio as regular items, centred inside the frame.
			local glyph = math.floor(wc_slot * (1 - 28 / 64) * (wildcard_entry.def.icon_scale or 1))
			local glyph_inset = math.floor((wc_slot - glyph) / 2)
			parent:bitmap({
				texture = icon_tex,
				texture_rect = icon_rect,
				x = wc_x + glyph_inset,
				y = grid_top + glyph_inset,
				w = glyph,
				h = glyph,
				layer = 4,
			})
			local hit = parent:panel({ x = wc_x, y = grid_top, w = wc_slot, h = wc_slot, layer = 7 })
			targets[#targets + 1] = { panel = hit, def = wildcard_entry.def, count = 1 }
		else
			slot_frame:set_color(wc_color:with_alpha(0.3))
		end
	end
end

-- Every player's inventory, one quarter-height section per peer (stable up to 4 players).
-- Returns the hover hit-targets ({ panel, def, count }) for the tooltip hook to consume.
local function csr_render_items(parent, top, avail_w, avail_h, mgr)
	local by_type = {}
	for _, def in ipairs(mgr:registered_items()) do
		by_type[def.type] = def
	end

	local peers = csr_collect_peers(mgr)
	-- Fixed quarter per peer (mirror the lobby sidebar): keeps the wildcard square modestly sized
	-- in SP/duo instead of ballooning to fill the whole items area when there are fewer than 4 peers.
	local section_h = math.floor(avail_h / 4)
	local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")

	local targets = {}
	local ctx = {
		parent = parent,
		by_type = by_type,
		avail_w = avail_w,
		frame_tex = frame_tex,
		frame_rect = frame_rect,
		mgr = mgr,
		targets = targets,
	}
	for index, peer in ipairs(peers) do
		csr_render_peer_items(ctx, peer, top + (index - 1) * section_h, section_h)
	end
	return targets
end

-- Tooltip teardown: removes the floating tip panel (idempotent; safe on a destroyed panel).
local function csr_clear_item_tooltip(self)
	if self._csr_item_tooltip and alive(self._csr_item_tooltip) and self._panel and alive(self._panel) then
		self._panel:remove(self._csr_item_tooltip)
	end
	self._csr_item_tooltip = nil
end

-- Floating tooltip (name in rarity color + wrapped desc) anchored to the hovered cell, clamped to
-- the contract panel. Built at a placeholder height, then BoxGui added AFTER the final resize --
-- BoxGui bakes corner-sprite positions at construction, so a pre-resize border strands the corners.
local function csr_show_item_tooltip(self, target)
	if not target or not alive(target.panel) or not self._panel or not alive(self._panel) then
		return
	end
	local def = target.def
	local parent = self._panel
	local pad = 6
	local tip_w = 220
	local name_h = tweak_data.menu.pd2_small_font_size + 2

	local tip = parent:panel({ layer = 200, w = tip_w, h = 200 })
	self._csr_item_tooltip = tip

	-- Items carry loc keys in def.name/desc; :text() returns "ERROR..." on an unknown key, so guard the key.
	local resolved_name = (def.name and managers.localization:text(def.name)) or ""
	local resolved_desc = (def.desc and _G.CSR.item_text(def.desc, def)) or ""

	tip:text({
		name = "tooltip_name",
		text = resolved_name,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = RARITY_COLORS[def.rarity] or Color.white,
		x = pad,
		y = pad,
		w = tip_w - pad * 2,
		h = name_h,
		layer = 1,
	})
	-- Split contraband ". But ..." drawback into a red second block (mirrors shop/lobby tooltips).
	local main_desc, but_desc = _G.CSR.split_drawback(resolved_desc)
	local desc_y = pad + name_h + 2
	local desc_text = tip:text({
		name = "tooltip_desc",
		text = main_desc,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		x = pad,
		y = desc_y,
		w = tip_w - pad * 2,
		h = 160,
		wrap = true,
		word_wrap = true,
		layer = 1,
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
			word_wrap = true,
			layer = 1,
		})
		local _, _, _, bh = but_text:text_rect()
		but_text:set_h(bh)
		content_h = dh + bh
	end

	local tip_h = pad + name_h + 2 + content_h + pad
	tip:set_h(tip_h)
	tip:rect({ name = "tooltip_bg", color = Color.black, alpha = 0.9, layer = 0, w = tip_w, h = tip_h })
	BoxGuiObject:new(tip, { sides = { 1, 1, 1, 1 } })

	-- Anchor to the right of the cell; flip left / clamp so it stays inside the contract panel.
	local cell_x, cell_y = target.panel:world_position()
	local panel_x, panel_y = parent:world_position()
	local local_x = cell_x - panel_x
	local local_y = cell_y - panel_y

	local tx = local_x + target.panel:w() + 6
	if tx + tip_w > parent:w() then
		tx = local_x - tip_w - 6
	end
	if tx < 0 then
		tx = 0
	end
	local ty = local_y
	if ty + tip_h > parent:h() then
		ty = parent:h() - tip_h - 4
	end
	if ty < 0 then
		ty = 0
	end
	tip:set_position(tx, ty)
end

-- Borrow Modifiers/Preferences renderers from CSRMissionsMenuComponent (single source of truth).
-- Items uses its own per-peer grid; _clear_items_tooltip is also borrowed (called by modifiers).
local PAUSE_METHODS_TO_BORROW = {
	"_clear_items_tooltip",
	"_populate_modifiers_panel",
	"_modifiers_panel_mouse_moved",
	"_modifiers_panel_mouse_pressed",
	"_modifiers_scroll_visible",
	"_populate_preferences_panel",
	"_preferences_panel_mouse_moved",
	"_preferences_panel_mouse_pressed",
	"_preferences_panel_mouse_released",
}

local function ensure_pause_methods_borrowed()
	if IngameContractGui._csr_methods_borrowed then
		return true
	end
	if not CSRMissionsMenuComponent then
		return false
	end
	for _, name in ipairs(PAUSE_METHODS_TO_BORROW) do
		IngameContractGui[name] = CSRMissionsMenuComponent[name]
	end
	IngameContractGui._csr_methods_borrowed = true
	return true
end

-- Pause-sidebar tabs. Items is always present; Modifiers/Preferences only when the borrow
-- succeeds (their renderers live on CSRMissionsMenuComponent). Order mirrors the lobby sidebar.
local PAUSE_TABS = {
	{ key = "items", text = "csr_sidebar_items", icon = "sidebar_casino" },
	{ key = "modifiers", text = "csr_sidebar_modifiers", icon = "sidebar_mutators" },
	{ key = "preferences", text = "csr_sidebar_preferences", icon = "sidebar_filters" },
}

-- Persists the last-selected tab across pause opens: IngameContractGui is rebuilt each ESC,
-- so the selection can't live on `self`; this file-scope upvalue survives the session.
local last_pause_tab = "items"

-- Switch the active pause tab: flip content visibility, move the selected-row marker, drop the
-- Items tooltip, and repopulate the dynamic panel so it reflects current state on (re)open.
function IngameContractGui:_csr_set_pause_tab(key)
	if self._csr_items_content and alive(self._csr_items_content) then
		self._csr_items_content:set_visible(key == "items")
	end
	if self._feature_panels then
		for k, p in pairs(self._feature_panels) do
			if alive(p) then
				p:set_visible(k == key)
			end
		end
	end

	-- Leaving Items: clear its floating tooltip (hidden hit panels still pass :inside()).
	csr_clear_item_tooltip(self)
	self._csr_item_hover = nil

	if self._csr_sidebar_items then
		for k, item in pairs(self._csr_sidebar_items) do
			item:set_selected(k == key)
		end
	end

	self._csr_active_tab = key
	last_pause_tab = key

	if key == "modifiers" and self._populate_modifiers_panel then
		self:_populate_modifiers_panel()
	elseif key == "preferences" and self._populate_preferences_panel then
		self:_populate_preferences_panel()
	end
end

Hooks:PostHook(IngameContractGui, "init", "CSR_IngameContract_Relayout", function(self, ws, node)
	if not csr_heist_active() then
		return
	end
	if not self._panel or not alive(self._panel) then
		return
	end

	-- Use Global.game_settings.level_id, not current_level_id() which returns the wrapper.
	local level_id = Global.game_settings and Global.game_settings.level_id
	if not level_id or level_id == "crime_spree" or not tweak_data.levels[level_id] then
		local mission = managers.csr and managers.csr:get_mission()
		level_id = (mission and mission.level and mission.level.level_id) or level_id
	end

	local level_tweak = level_id and tweak_data.levels[level_id]
	if not level_tweak then
		return -- nothing meaningful to show; leave vanilla's panel
	end

	-- Clean slate: drop vanilla's contract/briefing children, then rebuild.
	self._panel:set_visible(true)
	self._panel:clear()

	-- Shrink to lobby sidebar height (title+16 from top to 1.5*large_font from bottom).
	-- Keep vanilla's top anchor; only the height changes.
	local large_font = tweak_data.menu.pd2_large_font_size
	local sidebar_top = large_font + 16
	local sidebar_bottom = ws:panel():h() - large_font * 1.5
	self._panel:set_h(sidebar_bottom - sidebar_top)

	local padding = SystemInfo:platform() == Idstring("WIN32") and 10 or 5

	-- Big title: the mission name, in the same spot vanilla drew "CONTRACT ...".
	-- Copied 1:1 from vanilla IngameContractGui (bottom-anchored at y=5).
	local title = self._panel:text({
		text = "",
		vertical = "bottom",
		rotation = 360,
		layer = 1,
		font = tweak_data.menu.pd2_large_font,
		font_size = tweak_data.menu.pd2_large_font_size,
		color = tweak_data.screen_colors.text,
	})
	title:set_text(managers.localization:to_upper_text(level_tweak.name_id))
	title:set_bottom(5)

	local text_panel = self._panel:panel({
		layer = 1,
		x = padding,
		y = padding,
		w = self._panel:w() - padding * 2,
		h = self._panel:h() - padding * 2,
	})

	-- Status header: MISSIONS COMPLETED | RANK | DIFFICULTY, identical to the lobby's row
	-- above the mission cards. Anchored at the panel top (the briefing block is gone).
	local header_bottom = csr_render_status_header(text_panel, 0, text_panel:w())

	-- Mini sidebar (left) + tabbed content (right). Items has its own per-peer grid; Modifiers/Preferences
	-- borrow CSRMissionsMenuComponent renderers. Only drawn when there's room for at least one peer section.
	self._csr_sidebar_items = nil
	self._csr_active_tab = nil
	self._feature_panels = nil
	local mgr = managers.csr
	if mgr and mgr.registered_items and CSRSidebarItem then
		local section_top = header_bottom + padding
		local needed = tweak_data.menu.pd2_medium_font_size + 4 + PEER_HEADER_H + ITEM_ICON_MIN + 8
		if text_panel:h() - section_top >= needed then
			-- Sidebar container: narrow strip, full height of the items panel beside it.
			local section_h = text_panel:h() - section_top
			local sb_panel = text_panel:panel({
				x = 0,
				y = section_top,
				w = PAUSE_SIDEBAR_W,
				h = section_h,
				layer = 10,
			})
			sb_panel:rect({ color = Color.black, alpha = 0.4, layer = -1 })
			sb_panel:bitmap({
				texture = "guis/textures/test_blur_df",
				name = "blur_bg",
				render_template = "VertexColorTexturedBlur3D",
				layer = -1,
				halign = "scale",
				valign = "scale",
				w = sb_panel:w(),
				h = sb_panel:h(),
			})
			-- Modifiers/Preferences need the borrowed renderers; degrade to Items-only if unavailable.
			local have_features = ensure_pause_methods_borrowed()

			self._csr_sidebar_items = {}
			local item_margin = 2
			local row_y = padding
			for _, tab in ipairs(PAUSE_TABS) do
				if tab.key == "items" or have_features then
					local key = tab.key
					local item = CSRSidebarItem:new(sb_panel, {
						position = row_y,
						text = managers.localization:text(tab.text),
						icon = tab.icon,
						callback = function(gui)
							gui:_csr_set_pause_tab(key)
						end,
					})
					self._csr_sidebar_items[key] = item
					row_y = row_y + item:panel():height() + item_margin
				end
			end
			BoxGuiObject:new(sb_panel, { sides = { 1, 1, 1, 1 } })

			-- Items: bordered panel right of the sidebar; content inset by padding so overflowing frames clear the border.
			local items_x = PAUSE_SIDEBAR_W + padding
			local items_panel = text_panel:panel({
				x = items_x,
				y = section_top,
				w = text_panel:w() - items_x,
				h = section_h,
				layer = 10,
			})
			items_panel:rect({ color = Color.black, alpha = 0.4, layer = -1 })
			items_panel:bitmap({
				texture = "guis/textures/test_blur_df",
				name = "blur_bg",
				render_template = "VertexColorTexturedBlur3D",
				layer = -1,
				halign = "scale",
				valign = "scale",
				w = items_panel:w(),
				h = items_panel:h(),
			})
			BoxGuiObject:new(items_panel, { sides = { 1, 1, 1, 1 } })

			local content_x, content_y = padding, padding
			local content_w = items_panel:w() - padding * 2
			local content_h = items_panel:h() - padding * 2

			self._csr_items_content = items_panel:panel({ x = content_x, y = content_y, w = content_w, h = content_h })
			self._csr_item_targets = csr_render_items(self._csr_items_content, 0, content_w, content_h, mgr)

			-- Modifiers + Preferences tabs: feature panels filled by the borrowed renderers. Stacked
			-- on the same rect as the Items grid; _csr_set_pause_tab toggles which one is visible.
			if have_features then
				self._feature_panels = {}
				for _, key in ipairs({ "modifiers", "preferences" }) do
					local fp = items_panel:panel({
						x = content_x,
						y = content_y,
						w = content_w,
						h = content_h,
						layer = 5,
					})
					fp:set_visible(false)
					self._feature_panels[key] = fp
				end
				self:_populate_modifiers_panel()
				self:_populate_preferences_panel()
			end

			-- Restore the last-used tab; fall back to Items if that tab wasn't built this open
			-- (e.g. Modifiers/Preferences absent when the renderer borrow failed).
			local restore_tab = self._csr_sidebar_items[last_pause_tab] and last_pause_tab or "items"
			self:_csr_set_pause_tab(restore_tab)
		else
			csr_log(
				"[CSR] pause panel: no room for team items (avail=" .. tostring(text_panel:h() - section_top) .. ")"
			)
		end
	end

	self._text_panel = text_panel

	-- Border frame, matching the vanilla contract look.
	self._sides = BoxGuiObject:new(self._panel, { sides = { 1, 1, 1, 1 } })

	-- Snap children to integer positions to avoid blurry text (vanilla does this).
	self:_rec_round_object(self._panel)
end)

-- Item hover tooltips on the Items tab. Edge-triggered: only rebuild when the target changes.
-- self._csr_item_targets only exists on CSR heists, so non-CSR panels no-op.
Hooks:PostHook(IngameContractGui, "mouse_moved", "CSR_IngameContract_ItemTooltip", function(self, o, x, y)
	if not self._csr_item_targets or self._csr_active_tab ~= "items" then
		return
	end
	local hovered
	for _, t in ipairs(self._csr_item_targets) do
		if alive(t.panel) and t.panel:inside(x, y) then
			hovered = t
			break
		end
	end
	if hovered ~= self._csr_item_hover then
		self._csr_item_hover = hovered
		csr_clear_item_tooltip(self)
		if hovered then
			csr_show_item_tooltip(self, hovered)
		end
	end
end)

-- Sidebar hover highlights + in-panel hover. Handlers self-gate on panel:visible(), so calling
-- both is safe regardless of active tab; no-ops on non-CSR panels.
Hooks:PostHook(IngameContractGui, "mouse_moved", "CSR_IngameContract_SidebarHover", function(self, o, x, y)
	if self._csr_sidebar_items then
		for _, item in pairs(self._csr_sidebar_items) do
			if alive(item:panel()) then
				item:set_highlight(item:inside(x, y))
			end
		end
	end
	if self._modifiers_panel_mouse_moved then
		self:_modifiers_panel_mouse_moved(x, y)
	end
	if self._preferences_panel_mouse_moved then
		self:_preferences_panel_mouse_moved(x, y)
	end
end)

-- Sidebar tab clicks + in-panel clicks (left button only; wheel handled separately).
-- In-panel handlers run first and self-gate on visibility to avoid double-dispatch.
Hooks:PostHook(IngameContractGui, "mouse_pressed", "CSR_IngameContract_SidebarClick", function(self, button, x, y)
	if button ~= Idstring("0") then
		return
	end
	if self._modifiers_panel_mouse_pressed and self:_modifiers_panel_mouse_pressed(x, y) then
		return
	end
	if self._preferences_panel_mouse_pressed and self:_preferences_panel_mouse_pressed(x, y) then
		return
	end
	-- Grab the Modifiers scroll bar for dragging (_modifiers_panel_mouse_pressed only handles sub-tabs).
	if
		self._modifiers_scroll_visible
		and self:_modifiers_scroll_visible()
		and self._modifiers_scroll:mouse_pressed(button, x, y)
	then
		return
	end
	if self._csr_sidebar_items then
		for _, item in pairs(self._csr_sidebar_items) do
			if alive(item:panel()) and item:inside(x, y) and item:callback() then
				managers.menu_component:post_event("menu_enter")
				item:callback()(self)
				return
			end
		end
	end
end)

-- IngameContractGui has no vanilla mouse_released/wheel; define them here so MenuComponentManager
-- routes events. Return nil (not false) when not consumed to pass through to other components.

-- Preferences slider-drag release + Modifiers scroll-bar release.
local orig_contract_mouse_released = IngameContractGui.mouse_released
function IngameContractGui:mouse_released(o, button, x, y)
	if self._preferences_panel_mouse_released and self:_preferences_panel_mouse_released(button, x, y) then
		return true
	end
	-- Release a grabbed scroll bar (mouse_released -> release_scroll_bar returns true only if grabbed),
	-- always fed so a bar releases even if the cursor left the panel mid-drag.
	if self._modifiers_scroll and self._modifiers_scroll:mouse_released(button, x, y) then
		return true
	end
	if orig_contract_mouse_released then
		return orig_contract_mouse_released(self, o, button, x, y)
	end
end

-- Mouse wheel scrolls the Modifiers list (wheel never reaches mouse_pressed here). dir: up=1, down=-1.
local function csr_pause_scroll_wheel(self, dir, x, y)
	if self._modifiers_scroll_visible and self:_modifiers_scroll_visible() and self._modifiers_scroll then
		if self._modifiers_scroll:scroll(x, y, dir) then
			return true
		end
	end
	return nil
end

local orig_contract_wheel_up = IngameContractGui.mouse_wheel_up
function IngameContractGui:mouse_wheel_up(x, y)
	local used = csr_pause_scroll_wheel(self, 1, x, y)
	if used then
		return used
	end
	if orig_contract_wheel_up then
		return orig_contract_wheel_up(self, x, y)
	end
end

local orig_contract_wheel_down = IngameContractGui.mouse_wheel_down
function IngameContractGui:mouse_wheel_down(x, y)
	local used = csr_pause_scroll_wheel(self, -1, x, y)
	if used then
		return used
	end
	if orig_contract_wheel_down then
		return orig_contract_wheel_down(self, x, y)
	end
end

csr_log("[CSR] pause_ingame_contract.lua loaded")
