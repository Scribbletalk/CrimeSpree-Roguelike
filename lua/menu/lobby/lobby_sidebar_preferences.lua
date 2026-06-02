-- CSRMissionsMenuComponent — Preferences feature-panel (extends class from missions_menu.lua).
-- Settings that affect gameplay feel but aren't per-item tuning.

if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

local items_panel_padding = 16
local pref_row_h = 36
local pref_row_gap = 4

function CSRMissionsMenuComponent:_populate_preferences_panel()
	if not self._feature_panels or not alive(self._feature_panels.preferences) then
		return
	end
	local panel = self._feature_panels.preferences

	if self._preferences_content and alive(self._preferences_content) then
		panel:remove(self._preferences_content)
	end
	self._preferences_content = nil
	self._preferences_buttons = {}

	local content = panel:panel({ layer = 5 })
	self._preferences_content = content

	local pad = items_panel_padding
	local row_w = panel:w() - pad * 2
	local y = pad

	local function make_toggle(label, checked)
		local row = content:panel({ x = pad, y = y, w = row_w, h = pref_row_h, layer = 5 })

		row:rect({ name = "bg", color = Color.black, alpha = 0.4, layer = 0 })
		local hl = row:rect({
			name = "hl",
			blend_mode = "add",
			color = tweak_data.screen_colors.button_stage_3,
			layer = 0,
		})
		hl:set_visible(false)

		BoxGuiObject:new(row:panel({ layer = 2 }), { sides = { 1, 1, 1, 1 } })

		row:text({
			text = label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			x = 8,
			w = row_w - 64,
			h = pref_row_h,
			align = "left",
			vertical = "center",
			layer = 2,
		})

		local val = row:text({
			text = checked and "ON" or "OFF",
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = checked and tweak_data.screen_colors.stats_positive or tweak_data.screen_colors.button_stage_3,
			x = 0,
			w = row_w - 8,
			h = pref_row_h,
			align = "right",
			vertical = "center",
			layer = 2,
		})

		y = y + pref_row_h + pref_row_gap

		return { panel = row, hl = hl, val = val, checked = checked }
	end

	local btn = make_toggle("Block healing effects from items", false)
	table.insert(self._preferences_buttons, btn)
end

function CSRMissionsMenuComponent:_preferences_panel_mouse_moved(x, y)
	if not self._preferences_buttons then
		return false
	end
	if not self._feature_panels or not alive(self._feature_panels.preferences) then
		return false
	end
	if not self._feature_panels.preferences:visible() then
		return false
	end
	local hit = false
	for _, btn in ipairs(self._preferences_buttons) do
		if alive(btn.panel) then
			local inside = btn.panel:inside(x, y)
			btn.hl:set_visible(inside)
			if inside then
				hit = true
			end
		end
	end
	return hit
end

function CSRMissionsMenuComponent:_preferences_panel_mouse_pressed(x, y)
	if not self._preferences_buttons then
		return false
	end
	if not self._feature_panels or not alive(self._feature_panels.preferences) then
		return false
	end
	if not self._feature_panels.preferences:visible() then
		return false
	end
	for _, btn in ipairs(self._preferences_buttons) do
		if alive(btn.panel) and btn.panel:inside(x, y) then
			btn.checked = not btn.checked
			btn.val:set_text(btn.checked and "ON" or "OFF")
			btn.val:set_color(
				btn.checked and tweak_data.screen_colors.stats_positive or tweak_data.screen_colors.button_stage_3
			)
			return true
		end
	end
	return false
end
