-- CSRMissionsMenuComponent — Modifiers feature-panel (extracted from missions_menu.lua).
-- Loads on lib/managers/menu/menucomponentmanager AFTER missions_menu.lua (mod.txt
-- order); adds the Modifiers panel (Loud/Stealth sub-tabs + scroll list) and its
-- mouse routing to the class. The methods stay on the SAME class, so the briefing's
-- lazy method-borrow (briefing_sidebar.lua) still picks them up at runtime.
if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

-- Shared feature-panel inner padding (declared locally in each sidebar file).
local items_panel_padding = 16

-- Modifiers feature-panel sub-tab row (Loud / Stealth). The two buttons split
-- the panel width 50/50 (no gap -- a segmented control) and sit at the top; the
-- modifier icon grid renders below them. Icons are frameless and the grid has its
-- OWN size + gap rather than reusing the items metrics.
local modifiers_subtab_h = 28
local modifiers_subtab_gap = 6 -- small gap between the Loud / Stealth buttons
local modifiers_grid_top_gap = 16

-- Modifiers panel list rows (replaces the old icon grid): a vertical ScrollablePanel
-- where each row is an icon on the left + name (top) and wrapped description (below)
-- to its right. Row height grows to fit the wrapped description.
local modifiers_row_icon_size = 48
local modifiers_row_text_gap = 12 -- icon right edge -> text column
local modifiers_row_gap = 12 -- vertical gap between rows
local modifiers_row_scrollbar_margin = 18 -- reserve the right edge for the scroll bar

-- One Loud/Stealth tab button at the given x/width. Rebuilt (not mutated) on
-- every repopulate, so `active` is baked in at build time -- no separate
-- set_active path needed. Returns the hit-test panel; the caller stores it for
-- mouse_moved/pressed.
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
	-- Frame discarded like the feature-panel borders (anonymous; panel-tree
	-- teardown removes it with its parent).
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

-- Build / rebuild the Modifiers feature-panel content: a Loud / Stealth sub-tab row
-- at the top and, below it, a vertical scroll list of the modifiers active for the
-- chosen sub-tab. Each row is an icon (left) + name (top) + wrapped description
-- (below) -- the description is inline now, so there is no hover tooltip anymore.
-- Idempotent: prior content (and the ScrollablePanel inside it) is removed first.
-- Borrowed by MissionBriefingGui (briefing_sidebar.lua METHODS_TO_BORROW) so both
-- surfaces share it; mouse routing lives in mouse_wheel_up/down + mouse_released +
-- the modifiers branches of mouse_moved/mouse_pressed (lobby) and the briefing's own
-- input wraps (wheel only -- the briefing never receives mouse_released).
function CSRMissionsMenuComponent:_populate_modifiers_panel()
	if not self._feature_panels or not alive(self._feature_panels.modifiers) then
		return
	end
	local panel = self._feature_panels.modifiers

	if self._modifiers_content and alive(self._modifiers_content) then
		panel:remove(self._modifiers_content)
	end
	self._modifiers_content = nil
	self._modifiers_subtab_buttons = nil
	-- The scroll lived inside the content panel just removed; drop the stale ref so
	-- the mouse handlers can't poke a dead panel between repopulates.
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

	-- Sub-tab row: the two buttons split the content width with a small gap between
	-- them -- together they still span the full panel width.
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

	-- Loud-only ambient header: the per-rank enemy HP/damage scaling (continuous in
	-- rank, separate from the unlockable modifiers listed below). Reads the percent
	-- from managers.csr:enemy_scaling so the shown number can't drift from what
	-- apply_modifiers applies. Fixed on `content` (NOT in the scroll canvas) so it
	-- stays pinned at the very top; the scroll list is pushed down by header_h.
	-- Hidden at 0% (rank 0). HP% == DMG% today, so one number covers both.
	local header_h = 0
	if not is_stealth then
		local smgr = managers and managers.csr
		local hp_pct = 0
		if smgr and smgr.enemy_scaling then
			hp_pct = (smgr:enemy_scaling()) or 0
		end
		if hp_pct > 0 then
			-- White sentence, yellow number + "%" (the mod's accent, same highlight
			-- the status bar uses). set_range_color recolors the trailing value
			-- substring -- the vanilla-proven pattern from _create_status_bar.
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

	-- Scroll list below the sub-tabs (engine ScrollablePanel: draggable bar + wheel,
	-- canvas clipped to the viewport). Content goes on :canvas(); update_canvas_size
	-- recomputes the scroll height from the rows after they are laid out. list_top
	-- includes header_h so the loud ambient header (when shown) sits above the list.
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

	local mgr = managers and managers.csr
	local list = (mgr and mgr.active_modifiers and mgr:active_modifiers(self._modifiers_subtab)) or {}
	if #list == 0 then
		-- Empty (rank 0, or this category's pool already exhausted): sub-tabs stand
		-- alone, empty scroll. No filler text -- matches the items panel convention.
		scroll:update_canvas_size()
		return
	end

	-- Newest-unlocked modifier first (user spec 2026-05-24): active_modifiers returns
	-- the unlock sequence oldest-first (entry i unlocked at rank i), so reversing it
	-- floats the modifier gained at the current rank to the TOP. Reversed in the VIEW
	-- only -- active_modifiers' "rank R is a prefix-superset of R+1" contract (relied
	-- on by apply_modifiers) stays intact. The list is a fresh per-call table, so the
	-- in-place reverse mutates nothing shared.
	for i = 1, math.floor(#list / 2) do
		list[i], list[#list - i + 1] = list[#list - i + 1], list[i]
	end

	-- Text column reserves a right margin for the scroll bar so a wrapped line never
	-- runs under it.
	local text_x = modifiers_row_icon_size + modifiers_row_text_gap
	local text_w = math.max(40, canvas:w() - text_x - modifiers_row_scrollbar_margin)
	local row_y = 0

	for _, entry in ipairs(list) do
		-- Combined "Title\nBody" loc string -> name (top) + description (wrapped).
		local full = (entry.loc and managers.localization and managers.localization:text(entry.loc)) or ""
		local title, body = full, ""
		local nl = full:find("\n", 1, true)
		if nl then
			title = full:sub(1, nl - 1)
			body = full:sub(nl + 1)
		end

		-- One panel per row, sized to the taller of the icon and the text block
		-- after the wrapped description is measured.
		local row = canvas:panel({
			x = 0,
			y = row_y,
			w = canvas:w(),
			h = modifiers_row_icon_size,
		})

		-- Icon (left). get_icon_data returns (texture, rect) and is nil-safe. The y is
		-- set below once the text block is measured so the icon centres against it.
		local icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(entry.icon or "csr_dog_tags")
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

		-- Name (top of the text column), measured + resized to its own line height.
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

		-- Description (below the name, wrapped); measured h tracks the line count.
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

		-- Center the icon AND the text block on the row's mid-line, so the icon sits
		-- vertically centered against the name+description block beside it (rather than
		-- top-aligned, which looked off when the description wrapped to several lines).
		local text_block_h = name_h + desc_h
		local row_h = math.max(modifiers_row_icon_size, text_block_h)
		row:set_h(row_h)
		icon:set_y(math.floor((row_h - modifiers_row_icon_size) / 2))
		local text_top = math.floor((row_h - text_block_h) / 2)
		name_text:set_y(text_top)
		desc_text:set_y(text_top + name_h)

		row_y = row_y + row_h + modifiers_row_gap
	end

	scroll:update_canvas_size()
end

-- True when the Modifiers scroll list exists AND its panel is visible. Gates the
-- scroll mouse routing so wheel / grab events do nothing while another tab is up.
-- Borrowed by the briefing so its input wrap can gate the same way.
function CSRMissionsMenuComponent:_modifiers_scroll_visible()
	local panel = self._feature_panels and self._feature_panels.modifiers
	return self._modifiers_scroll ~= nil and panel ~= nil and alive(panel) and panel:visible()
end

-- Hover for the Modifiers panel: scroll bar (hover / drag cursor) + sub-tab link
-- cursor. The description is inline in each row now, so there is no icon tooltip.
-- Returns true when the cursor is over the scroll bar or a sub-tab so the caller can
-- flip the pointer to "link". Shared by the lobby + the briefing.
function CSRMissionsMenuComponent:_modifiers_panel_mouse_moved(x, y)
	local panel = self._feature_panels and self._feature_panels.modifiers
	if not panel or not alive(panel) or not panel:visible() then
		return false
	end

	-- Scroll bar hover / drag. Drag is only ever active on the lobby (which grabs
	-- the bar in mouse_pressed); the briefing never grabs, so this is hover-only
	-- there. ScrollablePanel:mouse_moved returns (used, pointer).
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

-- Click handling for the Modifiers sub-tabs. Returns true if a sub-tab was hit
-- (switching repopulates the grid). Called from the lobby's mouse_pressed and
-- the briefing input wrap. Posts the same click SFX the sidebar / cards use.
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
