-- Modifiers feature-panel methods for CSRMissionsMenuComponent (split from missions_menu.lua).
-- Loads after missions_menu.lua (mod.txt order); methods land on the same class so briefing borrows them at runtime.
if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

-- Shared inner padding (mirrors the other sidebar files).
local items_panel_padding = 16

-- Sub-tab row geometry.
local modifiers_subtab_h = 28
local modifiers_subtab_gap = 6 -- gap between Loud / Stealth buttons
local modifiers_grid_top_gap = 16

-- Row list geometry.
local modifiers_row_icon_size = 48
local modifiers_row_text_gap = 12 -- icon right edge -> text column
local modifiers_row_gap = 12 -- vertical gap between rows
local modifiers_row_scrollbar_margin = 18 -- reserve space for the scroll bar

-- New-modifier highlight visuals.
-- PD2 button blue (screen_colors.button_stage_2) so the tint matches the in-menu selected-button look.
local modifiers_new_bg_color = tweak_data.screen_colors.button_stage_2 -- blue tint behind a freshly-unlocked row
local modifiers_new_bg_alpha = 0.22
local modifiers_new_bg_hold = 5 -- seconds the blue tint stays solid after the panel opens
local modifiers_new_bg_fade = 0.6 -- fade-out duration once the hold elapses

-- Hold the new-modifier blue tint solid for ~5s after the panel opens, fade it out, then clear the
-- highlight floor so it never returns (until a fresh unlock re-arms it). Driven off `driver` (the
-- content panel, killed on the next repopulate). dt==0 fallback keeps it ticking on the ESC pause.
local function csr_fade_new_bgs(driver, rects, mgr)
	local function animate_fade(o)
		local t = 0
		while t < modifiers_new_bg_hold do
			local dt = coroutine.yield()
			if dt == 0 then
				dt = TimerManager:main():delta_time()
			end
			t = t + dt
		end
		local ft = 0
		while ft < modifiers_new_bg_fade do
			local dt = coroutine.yield()
			if dt == 0 then
				dt = TimerManager:main():delta_time()
			end
			ft = ft + dt
			local a = modifiers_new_bg_alpha * math.max(0, 1 - ft / modifiers_new_bg_fade)
			for _, r in ipairs(rects) do
				if alive(r) then
					r:set_alpha(a)
				end
			end
		end
		for _, r in ipairs(rects) do
			if alive(r) then
				r:set_alpha(0)
			end
		end
		if mgr and mgr.clear_modifier_highlight then
			mgr:clear_modifier_highlight()
		end
	end
	driver:animate(animate_fade)
end

-- Build one Loud/Stealth sub-tab button. Active state is baked in at build time.
local function csr_build_modifier_subtab(parent, text_str, x, y, w, active)
	local p = parent:panel({
		x = x,
		y = y,
		w = w,
		h = modifiers_subtab_h,
		layer = 10,
	})
	p:rect({
		name = "bg",
		color = active and tweak_data.screen_colors.button_stage_2 or Color.black,
		alpha = active and 0.5 or 0.4,
		layer = 0,
	})
	BoxGuiObject:new(p:panel({ layer = 2 }), { sides = { 1, 1, 1, 1 } })
	p:text({
		name = "label",
		text = utf8.to_upper(text_str),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = active and Color.white or tweak_data.screen_colors.button_stage_3,
		align = "center",
		vertical = "center",
		w = p:w(),
		h = p:h(),
		layer = 3,
	})
	return p
end

-- Build / rebuild the Modifiers feature-panel: sub-tab row + scrollable modifier list.
-- Idempotent: removes prior content before rebuilding. Borrowed by MissionBriefingGui.
function CSRMissionsMenuComponent:_populate_modifiers_panel()
	if not self._feature_panels or not alive(self._feature_panels.modifiers) then
		return
	end
	local panel = self._feature_panels.modifiers

	local mgr = managers and managers.csr
	-- Flag modifiers unlocked since last seen (host/SP flagged at completion; this also covers guests
	-- + missed observations). Arms glow_pending (the end-screen sidebar siren consumes it) and the
	-- highlight floor that drives the blue tint + 5s fade below.
	if mgr and mgr.refresh_modifier_highlight then
		mgr:refresh_modifier_highlight()
	end

	if self._modifiers_content and alive(self._modifiers_content) then
		panel:remove(self._modifiers_content)
	end
	self._modifiers_content = nil
	self._modifiers_subtab_buttons = nil
	-- Drop stale scroll ref so mouse handlers can't poke a dead panel between repopulates.
	self._modifiers_scroll = nil
	self._modifiers_hit_targets = {}
	self:_clear_items_tooltip()
	self._modifiers_hover_target = nil

	-- Default to Loud; persisted on the instance across repopulates.
	self._modifiers_subtab = self._modifiers_subtab == "stealth" and "stealth" or "loud"
	local is_stealth = self._modifiers_subtab == "stealth"

	local content = panel:panel({
		layer = 5,
	})
	self._modifiers_content = content

	-- Sub-tab row: two buttons split the panel width with a small gap, tiling flush.
	local pad = items_panel_padding
	local section_w = panel:w() - pad * 2
	local btn_w = math.floor((section_w - modifiers_subtab_gap) / 2)
	local b_loud = csr_build_modifier_subtab(content, "Loud", pad, pad, btn_w, not is_stealth)
	-- Stealth takes the remainder so odd-pixel widths still tile flush to the gap.
	local b_stealth = csr_build_modifier_subtab(
		content,
		"Stealth",
		pad + btn_w + modifiers_subtab_gap,
		pad,
		section_w - btn_w - modifiers_subtab_gap,
		is_stealth
	)
	self._modifiers_subtab_buttons = {
		loud = { panel = b_loud },
		stealth = { panel = b_stealth },
	}

	-- Loud-only ambient header: per-rank enemy HP/damage scaling pinned above the scroll list.
	-- Reads live from managers.csr:enemy_scaling so the shown number matches apply_modifiers.
	-- Hidden at rank 0 (0%). HP% == DMG% so one number covers both.
	local header_h = 0
	if not is_stealth then
		local smgr = managers and managers.csr
		local hp_pct = 0
		if smgr and smgr.enemy_scaling then
			hp_pct = (smgr:enemy_scaling()) or 0
		end
		if hp_pct > 0 then
			-- Yellow accent on the trailing value via set_range_color (same pattern as _create_status_bar).
			local prefix = "Enemy's base health and damage increased by "
			local full = prefix .. math.floor(hp_pct) .. "%"
			local header = content:text({
				name = "enemy_scaling_header",
				text = full,
				font = tweak_data.menu.pd2_small_font,
				font_size = tweak_data.menu.pd2_small_font_size,
				color = tweak_data.screen_colors.text,
				x = pad,
				y = pad + modifiers_subtab_h + modifiers_grid_top_gap,
				w = section_w,
				h = tweak_data.menu.pd2_small_font_size,
				wrap = true,
				word_wrap = true,
				layer = 10,
			})
			header:set_range_color(utf8.len(prefix), utf8.len(full), Color(1, 1, 1, 0))
			local _, _, _, lh = header:text_rect()
			header:set_h(lh)
			header_h = lh + modifiers_grid_top_gap
		end
	end

	-- Scroll list below the sub-tabs + optional ambient header.
	local list_top = pad + modifiers_subtab_h + modifiers_grid_top_gap + header_h
	local list_h = math.max(0, panel:h() - list_top - pad)
	local scroll = ScrollablePanel:new(content, "csr_modifiers_scroll", {
		x = pad,
		y = list_top,
		w = section_w,
		h = list_h,
		padding = 0,
		layer = 10,
	})
	self._modifiers_scroll = scroll
	local canvas = scroll:canvas()

	local list = (mgr and mgr.active_modifiers and mgr:active_modifiers(self._modifiers_subtab)) or {}
	if #list == 0 then
		scroll:update_canvas_size()
		return
	end

	-- Flag entries unlocked by the latest mission (sequence index > highlight floor) BEFORE the
	-- view-only reverse; nil floor (none unlocked yet) -> math.huge -> nothing flagged.
	local hl_floor = (mgr and mgr.modifier_highlight_floor and mgr:modifier_highlight_floor()) or math.huge
	local is_new = {}
	for i = 1, #list do
		is_new[i] = i > hl_floor
	end

	-- Stealth: collapse a tiered family to ONE row showing only its highest active tier (display-only;
	-- the mechanic still uses every entry via apply_modifiers). The seq lists a family's tiers ascending,
	-- so the last occurrence is the highest tier; it overwrites in place, keeping first-seen order and
	-- carrying its new-flag (a family bumped this mission stays highlighted).
	if is_stealth then
		local seen, clist, cnew = {}, {}, {}
		for i = 1, #list do
			local entry = list[i]
			local base = (entry.id and entry.id:match("^(.-)_%d+$")) or entry.id
			local at = seen[base]
			if at then
				clist[at], cnew[at] = entry, is_new[i]
			else
				clist[#clist + 1], cnew[#clist + 1] = entry, is_new[i]
				seen[base] = #clist
			end
		end
		list, is_new = clist, cnew
	end

	-- Reverse so the newest-unlocked modifier appears first (view-only; the source list is untouched).
	-- is_new rides along so each row keeps its new/old flag after the swap.
	for i = 1, math.floor(#list / 2) do
		list[i], list[#list - i + 1] = list[#list - i + 1], list[i]
		is_new[i], is_new[#list - i + 1] = is_new[#list - i + 1], is_new[i]
	end

	-- Text column reserves a right margin so wrapped lines never run under the scroll bar.
	local text_x = modifiers_row_icon_size + modifiers_row_text_gap
	local text_w = math.max(40, canvas:w() - text_x - modifiers_row_scrollbar_margin)
	local row_y = 0
	local new_bg_rects = {} -- collected blue tints, faded out together 5s after a real open

	for ri, entry in ipairs(list) do
		-- Combined "Title\nBody" loc string -> name (top) + description (wrapped).
		local full = (entry.loc and managers.localization and _G.CSR.item_text(entry.loc, entry)) or ""
		local title, body = full, ""
		local nl = full:find("\n", 1, true)
		if nl then
			title = full:sub(1, nl - 1)
			body = full:sub(nl + 1)
		end

		-- One panel per row, height set after measuring the wrapped description.
		local row = canvas:panel({
			x = 0,
			y = row_y,
			w = canvas:w(),
			h = modifiers_row_icon_size,
		})

		-- Icon (left); y adjusted below to vertically center against the text block.
		local icon_tex, icon_rect = _G.CSR.icon_data(entry.icon or "csr_dog_tags")
		local icon = row:bitmap({
			name = "mod_icon",
			texture = icon_tex,
			texture_rect = icon_rect,
			x = 0,
			y = 0,
			w = modifiers_row_icon_size,
			h = modifiers_row_icon_size,
			layer = 1,
		})

		-- Name (top of the text column).
		local name_text = row:text({
			name = "mod_name",
			text = title,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = tweak_data.screen_colors.text,
			x = text_x,
			y = 0,
			w = text_w,
			h = tweak_data.menu.pd2_medium_font_size,
			layer = 1,
		})
		local _, _, _, name_h = name_text:text_rect()
		name_text:set_h(name_h)

		-- Description (wrapped, below the name).
		local desc_text = row:text({
			name = "mod_desc",
			text = body,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = Color.white:with_alpha(0.7),
			x = text_x,
			y = name_h,
			w = text_w,
			h = 200,
			wrap = true,
			wrap_word = true,
			layer = 1,
		})
		local _, _, _, desc_h = desc_text:text_rect()
		desc_text:set_h(desc_h)

		-- Center icon and text block on the row mid-line (avoids top-aligned look when description wraps).
		local text_block_h = name_h + desc_h
		local row_h = math.max(modifiers_row_icon_size, text_block_h)
		row:set_h(row_h)
		-- Blue semi-transparent fill behind modifiers unlocked by the latest mission (layer 0, under
		-- the icon/text at layer 1). Persists until the next mission unlocks newer ones (floor moves).
		if is_new[ri] then
			new_bg_rects[#new_bg_rects + 1] = row:rect({
				name = "csr_new_bg",
				color = modifiers_new_bg_color,
				alpha = modifiers_new_bg_alpha,
				w = row:w(),
				h = row_h,
				layer = 0,
			})
		end
		icon:set_y(math.floor((row_h - modifiers_row_icon_size) / 2))
		local text_top = math.floor((row_h - text_block_h) / 2)
		name_text:set_y(text_top)
		desc_text:set_y(text_top + name_h)

		row_y = row_y + row_h + modifiers_row_gap
	end

	scroll:update_canvas_size()

	-- Real open with at least one freshly-unlocked row: arm the 5s hold -> fade-out -> clear-floor.
	-- Hidden initial builds are skipped so the highlight isn't consumed before the user ever sees it.
	if panel:visible() and #new_bg_rects > 0 then
		csr_fade_new_bgs(content, new_bg_rects, mgr)
	end
end

-- True when the modifiers scroll list is visible. Gates wheel/drag routing.
-- Borrowed by the briefing.
function CSRMissionsMenuComponent:_modifiers_scroll_visible()
	local panel = self._feature_panels and self._feature_panels.modifiers
	return self._modifiers_scroll ~= nil and panel ~= nil and alive(panel) and panel:visible()
end

-- Hover routing for the Modifiers panel: scroll bar + sub-tab link cursor.
-- Returns true if the cursor is over either, so the caller can flip the pointer.
function CSRMissionsMenuComponent:_modifiers_panel_mouse_moved(x, y)
	local panel = self._feature_panels and self._feature_panels.modifiers
	if not panel or not alive(panel) or not panel:visible() then
		return false
	end

	-- Scroll bar hover / drag (lobby grabs in mouse_pressed; briefing is hover-only).
	if self._modifiers_scroll then
		local used = self._modifiers_scroll:mouse_moved(nil, x, y)
		if used then
			return true
		end
	end

	-- Sub-tab hover -> link cursor.
	if self._modifiers_subtab_buttons then
		for _, b in pairs(self._modifiers_subtab_buttons) do
			if b.panel and alive(b.panel) and b.panel:inside(x, y) then
				return true
			end
		end
	end

	return false
end

-- Click handling for sub-tabs. Returns true if a tab was hit (switching rebuilds the list).
function CSRMissionsMenuComponent:_modifiers_panel_mouse_pressed(x, y)
	local panel = self._feature_panels and self._feature_panels.modifiers
	if not panel or not alive(panel) or not panel:visible() then
		return false
	end
	if not self._modifiers_subtab_buttons then
		return false
	end
	for key, b in pairs(self._modifiers_subtab_buttons) do
		if b.panel and alive(b.panel) and b.panel:inside(x, y) then
			if self._modifiers_subtab ~= key then
				self._modifiers_subtab = key
				managers.menu_component:post_event("menu_enter")
				self:_populate_modifiers_panel()
			end
			return true
		end
	end
	return false
end
