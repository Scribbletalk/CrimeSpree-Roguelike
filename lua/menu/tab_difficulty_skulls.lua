-- Crime Spree Roguelike - Difficulty skulls on the TAB stats screen
-- In CS mode vanilla shows "Difficulty  Level X"
-- We change it to "Crime Spree  Level X" and add skull icons below

if not RequiredScript then
	return
end

local DIFFICULTY_SKULLS = {
	normal = 0,
	hard = 1,
	very_hard = 2,
	overkill = 3,
	mayhem = 4,
	death_wish = 5,
	death_sentence = 6,
}
local TOTAL_SKULLS = 6

local SKULL_ICONS = {
	"risk_swat",
	"risk_fbi",
	"risk_death_squad",
	"risk_easy_wish",
	"risk_murder_squad",
	"risk_sm_wish",
}

Hooks:PostHook(HUDStatsScreen, "recreate_left", "CSR_TabDifficultySkulls", function(self)
	-- Match vanilla's branching exactly (newhudstatsscreen.lua line 163):
	-- vanilla renders the CS layout iff is_active() is true. Using in_progress()
	-- as a fallback would fire our hook in a regular heist when the player has
	-- a stale CS run flag (disconnected mid-spree, etc.), and we'd rename the
	-- non-CS "DIFFICULTY  Overkill" line to "CRIME SPREE:" + skulls.
	local cs = managers.crime_spree
	if not cs or not cs.is_active or not cs:is_active() then
		return
	end

	if not self._left or not alive(self._left) then
		return
	end

	local panel = self._left

	-- Find vanilla "DIFFICULTY" text element
	local difficulty_label = nil
	local level_text = nil
	local diff_upper = managers.localization:to_upper_text("menu_lobby_difficulty_title")

	for i = 0, panel:num_children() - 1 do
		local child = panel:child(i)
		if child and child.text and child:text() == diff_upper then
			difficulty_label = child
		end
	end

	if not difficulty_label then
		return
	end

	-- Find the "Level X" text (same row, to the right of difficulty label)
	local diff_y = difficulty_label:top()
	for i = 0, panel:num_children() - 1 do
		local child = panel:child(i)
		if child and child ~= difficulty_label and child.text then
			if math.abs(child:top() - diff_y) < 3 and child:left() > difficulty_label:left() then
				level_text = child
			end
		end
	end

	-- 1. Rename "DIFFICULTY" to "CRIME SPREE"
	difficulty_label:set_text("CRIME SPREE:")
	local _, _, tw, th = difficulty_label:text_rect()
	difficulty_label:set_size(tw, th)

	if level_text then
		level_text:set_left(difficulty_label:right() + 8)
	end

	-- 2. Add skull icons below
	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
	local difficulty
	if is_client then
		difficulty = _G.CSR_MP_HostDifficulty
			or _G.CSR_CurrentDifficulty
			or (managers.crime_spree and managers.crime_spree._global and managers.crime_spree._global.selected_difficulty)
			or "overkill"
	else
		difficulty = (
			managers.crime_spree
			and managers.crime_spree._global
			and managers.crime_spree._global.selected_difficulty
		)
			or _G.CSR_CurrentDifficulty
			or "overkill"
	end

	local lit = DIFFICULTY_SKULLS[difficulty] or 3
	local anchor_bottom = level_text and level_text:bottom() or difficulty_label:bottom()
	local base_x = difficulty_label:left()
	local base_y = anchor_bottom + 2
	local medium_font_size = tweak_data.hud_stats.loot_size

	-- "DIFFICULTY:" label
	local label = panel:text({
		name = "csr_tab_diff_label",
		text = "DIFFICULTY:",
		font = tweak_data.menu.pd2_medium_font,
		font_size = medium_font_size,
		color = tweak_data.screen_colors.text,
		layer = 1,
	})
	local _, _, lw, lh = label:text_rect()
	label:set_size(lw, lh)
	label:set_position(base_x, base_y)

	-- Skull icons after the label
	local skull_s = 16
	local spacing = skull_s + 2
	local skulls_x = label:right() + 8
	local skulls_y = base_y + math.round((lh - skull_s) / 2)

	for i = 1, TOTAL_SKULLS do
		local active = i <= lit
		local icon_name = SKULL_ICONS[i]
		local texture, rect = tweak_data.hud_icons:get_icon_data(icon_name)
		panel:bitmap({
			name = "csr_tab_skull_" .. i,
			texture = texture,
			texture_rect = rect,
			w = skull_s,
			h = skull_s,
			x = skulls_x + (i - 1) * spacing,
			y = skulls_y,
			alpha = active and 1 or 0.25,
			blend_mode = active and "add" or "normal",
			color = active and tweak_data.screen_colors.risk or Color.black,
			layer = 1,
		})
	end

	-- 3. Shift elements below the original line down to make room for skulls
	-- Only shift elements in the top half — the loot panel is bottom-anchored
	-- and must not be moved (it's an ExtendedPanel pinned to self._left bottom)
	local shift = lh + 4
	local panel_mid = panel:h() / 2
	for i = 0, panel:num_children() - 1 do
		local child = panel:child(i)
		if child then
			local name = child:name() or ""
			local is_ours = name:find("csr_tab_") == 1
			local is_above = child:top() <= anchor_bottom + 1
			if not is_ours and not is_above and child:top() < panel_mid then
				child:move(0, shift)
			end
		end
	end
end)
