-- Rebuilds the in-game ESC (pause) right panel for Crime Spree Roguelike.
-- CSR runs heists in the STANDARD gamemode (it never enables the CS gamemode),
-- so managers.crime_spree:is_active() is false and the pause panel is the
-- regular IngameContractGui -- NOT the CrimeSpree variant. Vanilla fills it from
-- the temporary "crime_spree" job, whose briefing_id is "heist_crime_spree_brief"
-- (no such loc key -> "ERROR: ..." text). We detect a CSR heist by that temp job
-- id and rebuild from CSR-valid data.
--
-- Layout:
--   <MISSION NAME>              (big, where vanilla's "CONTRACT" header sat)
--   CRIME.NET INFO:            (section header)
--   <briefing / plan text>
--   CRIME SPREE RANK: N [CS]    (label white, number yellow, then CS icon)
--   DIFFICULTY: [skulls] NAME    (risk skulls + difficulty name, like the lobby screen)
--   ITEMS:                     (section header)
--   <peer name> [icons...]     (every player's inventory, grouped per peer)

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
local FRAME_TO_CELL = 72 / 64 -- frame overflows the cell symmetrically (same ratio as the sidebar)
-- 4-direction 1px offsets for the stack-count outline; Diesel text has no native stroke.
local BADGE_OUTLINE = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }
-- CSR heist marker: STANDARD gamemode + a temporary "crime_spree" job. Same
-- signal heist_packages.lua uses; holds for host, guest and single-player.
local function csr_heist_active()
	return managers.job and managers.job:current_job_id() == "crime_spree"
end

-- Largest square cell (<=max, >=min) and column count so `count` items fit avail_w x avail_h.
-- Shrinks by 2px steps until the row count fits the height. Ported from lobby_sidebar_items.lua.
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

-- Teammate colors match contours/chat via tweak_data.peer_vector_colors (Rule #6).
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

-- Difficulty row: "DIFFICULTY:"  [risk skulls]  <NAME>, all on one centered line. Skulls use the
-- full risk_* icons (active = red, inactive = white@0.25) exactly like the lobby creation screen.
-- The live heist difficulty is Global.game_settings.difficulty (internal id), with managers.csr as
-- fallback; both the skull count and the name derive from it so they never disagree. Returns bottom y.
local function csr_render_difficulty_row(parent, x, top, rank)
	local diff = (Global.game_settings and Global.game_settings.difficulty)
		or (managers.csr and managers.csr:difficulty())
		or "normal"
	local difficulty_id = (tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(diff)) or 2
	local stars = math.max(0, difficulty_id - 2)

	local label = parent:text({
		text = managers.localization:to_upper_text("csr_pause_difficulty"),
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.text,
		align = "left",
		layer = 1,
	})
	managers.hud:make_fine_text(label)
	local row_h = label:h()
	local center_y = top + row_h / 2
	label:set_left(x)
	label:set_center_y(center_y)

	-- Difficulty name; red above normal (matches crimenet), white otherwise.
	local last_right = label:right()
	local name_id = tweak_data.difficulty_name_ids and tweak_data.difficulty_name_ids[diff]
	if name_id then
		local name = parent:text({
			text = managers.localization:to_upper_text(name_id),
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = stars > 0 and tweak_data.screen_colors.risk or tweak_data.screen_colors.text,
			align = "left",
			layer = 1,
		})
		managers.hud:make_fine_text(name)
		name:set_left(last_right + 8)
		name:set_center_y(center_y)
		last_right = name:right()
	end

	if rank then
		local prefix = managers.localization:to_upper_text("csr_pause_rank") .. " "
		local cs_glyph = utf8.char(0xE018)
		local rank_t = parent:text({
			text = prefix .. tostring(rank) .. " " .. cs_glyph,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = tweak_data.screen_colors.text,
			align = "left",
			layer = 1,
		})
		managers.hud:make_fine_text(rank_t)
		rank_t:set_left(last_right + 16)
		rank_t:set_center_y(center_y)
		rank_t:set_range_color(utf8.len(prefix), utf8.len(rank_t:text()), tweak_data.screen_colors.crime_spree_risk)
	end

	return top + row_h
end

-- One peer-name header + an adaptive icon grid of that peer's owned items.
-- ctx bundles the shared render state: { parent, by_type, avail_w, frame_tex, frame_rect, mgr, targets }.
-- Each drawn cell appends a hover hit-target to ctx.targets for the tooltip hook.
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

	-- Wildcard owns a square slot at the right edge, full grid height; the grid keeps the rest.
	local avail_grid_w = avail_w - GRID_MARGIN * 2
	local wc_slot = math.max(ITEM_ICON_MIN, math.min(grid_h, avail_grid_w))
	local wc_x = GRID_MARGIN + avail_grid_w - wc_slot
	local grid_w = avail_grid_w - wc_slot - ITEM_GAP
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

		-- "/" in icon = full DB-mounted texture path (addon .dds); otherwise a hud_icons id.
		local raw = entry.def.icon or "dog_tags"
		local icon_tex, icon_rect
		if type(raw) == "string" and raw:find("/", 1, true) then
			icon_tex, icon_rect = raw, { 0, 0, 128, 128 }
		else
			icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(raw)
		end
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
		if entry.count > 1 then
			local badge = {
				text = "x" .. tostring(entry.count),
				font = tweak_data.menu.pd2_small_font,
				font_size = tweak_data.menu.pd2_small_font_size,
				align = "right",
				vertical = "top",
				w = cell,
				h = cell,
			}
			badge.color = Color.black
			badge.layer = 5
			for _, off in ipairs(BADGE_OUTLINE) do
				badge.x, badge.y = ix + off[1], iy + off[2]
				parent:text(badge)
			end
			badge.color = Color.white
			badge.layer = 6
			badge.x, badge.y = ix, iy
			parent:text(badge)
		end

		-- Invisible hit panel over the cell; used only for tooltip hover-testing via :inside().
		local hit = parent:panel({ x = ix, y = iy, w = cell, h = cell, layer = 7 })
		targets[#targets + 1] = { panel = hit, def = entry.def, count = entry.count }
	end

	-- Wildcard slot (carry-1): a filled card when held, else a translucent wildcard-tinted placeholder.
	do
		local wc_color = RARITY_COLORS.wildcard or Color.white
		local slot_frame = parent:bitmap({
			texture = frame_tex,
			texture_rect = frame_rect,
			x = wc_x,
			y = grid_top,
			w = wc_slot,
			h = wc_slot,
			layer = 3,
		})
		if wildcard_entry then
			slot_frame:set_color(wc_color)
			local raw = wildcard_entry.def.icon or "dog_tags"
			local icon_tex, icon_rect
			if type(raw) == "string" and raw:find("/", 1, true) then
				icon_tex, icon_rect = raw, { 0, 0, 128, 128 }
			else
				icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(raw)
			end
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
	local resolved_desc = (def.desc and managers.localization:text(def.desc)) or ""

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
		word_wrap = true,
		layer = 1,
	})
	local _, _, _, dh = desc_text:text_rect()
	desc_text:set_h(dh)

	local tip_h = pad + name_h + 2 + dh + pad
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

Hooks:PostHook(IngameContractGui, "init", "CSR_IngameContract_Relayout", function(self, ws, node)
	if not csr_heist_active() then
		return
	end
	if not self._panel or not alive(self._panel) then
		return
	end

	-- Resolve the real heist. CSR stores it in Global.game_settings.level_id
	-- (game_manager.select_mission). managers.job:current_level_id() would return
	-- the "crime_spree" wrapper level, so don't use it.
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

	-- "CRIME.NET INFO:" section header.
	local info_title = text_panel:text({
		text = managers.localization:to_upper_text("csr_pause_info"),
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.text,
		align = "left",
	})
	managers.hud:make_fine_text(info_title)
	info_title:set_top(0)

	-- Plan / briefing body text (the real heist briefing).
	local info_body = text_panel:text({
		name = "briefing_description",
		text = managers.localization:text(level_tweak.briefing_id),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		wrap = true,
		word_wrap = true,
		align = "left",
		vertical = "top",
		w = text_panel:w(),
	})
	local _, _, _, body_h = info_body:text_rect()
	info_body:set_h(body_h)
	info_body:set_top(info_title:bottom())

	local rank = managers.csr and managers.csr:rank() or 0
	-- Difficulty row: "DIFFICULTY: [skulls] NAME    RANK: N <glyph>" all on one line.
	local diff_bottom = csr_render_difficulty_row(text_panel, 0, info_body:bottom() + padding, rank)

	-- "ITEMS:" + every player's inventory below the difficulty row (like the lobby sidebar).
	-- Only drawn when there's vertical room for at least the header + one peer section,
	-- so a long briefing never leaves an orphan header.
	local mgr = managers.csr
	if mgr and mgr.registered_items then
		local header_top = diff_bottom + padding
		local needed = tweak_data.menu.pd2_medium_font_size + 4 + PEER_HEADER_H + ITEM_ICON_MIN + 8
		if text_panel:h() - header_top >= needed then
			local items_title = text_panel:text({
				text = managers.localization:to_upper_text("csr_pause_items"),
				font = tweak_data.menu.pd2_medium_font,
				font_size = tweak_data.menu.pd2_medium_font_size,
				color = tweak_data.screen_colors.text,
				align = "left",
			})
			managers.hud:make_fine_text(items_title)
			items_title:set_top(header_top)

			local items_top = items_title:bottom() + 4
			self._csr_item_targets =
				csr_render_items(text_panel, items_top, text_panel:w(), text_panel:h() - items_top, mgr)
		else
			csr_log("[CSR] pause panel: no room for team items (avail=" .. tostring(text_panel:h() - header_top) .. ")")
		end
	end

	self._text_panel = text_panel

	-- Border frame, matching the vanilla contract look.
	self._sides = BoxGuiObject:new(self._panel, { sides = { 1, 1, 1, 1 } })

	-- Snap children to integer positions to avoid blurry text (vanilla does this).
	self:_rec_round_object(self._panel)
end)

-- Item hover tooltips. PostHook (vanilla mouse_moved drives the potential-rewards hover and is
-- called across the whole component). Edge-triggered: only rebuild the tip when the target changes.
-- Guarded by self._csr_item_targets, which is only set on a CSR heist, so non-CSR panels no-op.
Hooks:PostHook(IngameContractGui, "mouse_moved", "CSR_IngameContract_ItemTooltip", function(self, o, x, y)
	if not self._csr_item_targets then
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

csr_log("[CSR] pause_ingame_contract.lua loaded")
