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
local pref_slider_h = 56
local slider_track_h = 10
local slider_handle_w = 6

-- menu_tickbox atlas: col 0=off / 24=on, row 0=normal / 24=hover (matches mod-options ItemToggle).
local function tickbox_rect(checked, hover)
	return { checked and 24 or 0, hover and 24 or 0, 24, 24 }
end

-- Apply a 0..1 fraction to a slider btn: snap to 5% (matches the Mod Options slider step), redraw
-- fill/handle/value, and update the setting IN MEMORY (defer_save) -- sound.lua master_volume()
-- reads it live so the change is audible immediately, but we don't write csr_save.json on every
-- drag frame. The disk write happens once when the drag ends (_preferences_panel_mouse_released).
local function csr_apply_slider(btn, frac)
	frac = math.clamp(frac, 0, 1)
	frac = math.floor(frac * 20 + 0.5) / 20
	btn.value = frac
	btn.fill:set_w(math.max(1, btn.track_w * frac))
	btn.handle:set_center_x(btn.track_x + btn.track_w * frac)
	btn.val:set_text(math.floor(frac * 100 + 0.5) .. "%")
	if btn.setting_key and managers.csr then
		managers.csr:set_setting(btn.setting_key, frac, true)
	end
end

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
	self._pref_dragging = nil

	local content = panel:panel({ layer = 5 })
	self._preferences_content = content

	local pad = items_panel_padding
	local row_w = panel:w() - pad * 2
	local y = pad

	local function make_toggle(label, setting_key)
		local checked = managers.csr and managers.csr:setting(setting_key) == true
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

		local cb = row:bitmap({
			name = "cb",
			texture = "guis/textures/menu_tickbox",
			texture_rect = tickbox_rect(checked, false),
			w = 24,
			h = 24,
			layer = 2,
		})
		cb:set_right(row_w - 8)
		cb:set_center_y(pref_row_h / 2)

		y = y + pref_row_h + pref_row_gap

		return { kind = "toggle", panel = row, hl = hl, cb = cb, checked = checked, setting_key = setting_key }
	end

	-- Draggable volume slider. Label + value on the top line, track/fill/handle on the bottom line.
	local function make_slider(label, setting_key)
		local cur = managers.csr and managers.csr:setting(setting_key)
		if type(cur) ~= "number" then
			cur = 1.0
		end
		cur = math.clamp(cur, 0, 1)

		local row = content:panel({ x = pad, y = y, w = row_w, h = pref_slider_h, layer = 5 })

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
			y = 6,
			w = row_w - 80,
			h = 22,
			align = "left",
			vertical = "center",
			layer = 2,
		})

		local val = row:text({
			text = math.floor(cur * 100 + 0.5) .. "%",
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			y = 6,
			w = 64,
			h = 22,
			align = "right",
			vertical = "center",
			layer = 2,
		})
		val:set_right(row_w - 8)

		local track_x = 8
		local track_w = row_w - 16
		local track_cy = pref_slider_h - 8 - slider_track_h / 2

		local track = row:rect({
			color = Color.black,
			alpha = 0.6,
			x = track_x,
			w = track_w,
			h = slider_track_h,
			layer = 2,
		})
		track:set_center_y(track_cy)

		local fill = row:rect({
			color = tweak_data.screen_colors.button_stage_3,
			x = track_x,
			w = math.max(1, track_w * cur),
			h = slider_track_h,
			layer = 3,
		})
		fill:set_center_y(track_cy)

		local handle = row:rect({
			color = tweak_data.screen_colors.text,
			w = slider_handle_w,
			h = slider_track_h + 8,
			layer = 4,
		})
		handle:set_center_x(track_x + track_w * cur)
		handle:set_center_y(track_cy)

		y = y + pref_slider_h + pref_row_gap

		return {
			kind = "slider",
			panel = row,
			hl = hl,
			val = val,
			fill = fill,
			handle = handle,
			track_x = track_x,
			track_w = track_w,
			setting_key = setting_key,
			value = cur,
		}
	end

	local btn = make_toggle("BLOCK HEALING EFFECTS FROM ITEMS", "block_item_heal")
	table.insert(self._preferences_buttons, btn)

	local wc_bar = make_toggle("ALTERNATIVE HUD DISPLAY FOR WILDCARDS", "hud_wildcard_use_bar")
	table.insert(self._preferences_buttons, wc_bar)

	local sfx = make_slider("ITEM SOUND VOLUME", "sfx_volume")
	table.insert(self._preferences_buttons, sfx)
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
	-- An active slider drag follows the cursor anywhere, even outside its row.
	local drag = self._pref_dragging
	if drag and alive(drag.panel) then
		local wx = drag.panel:world_position()
		csr_apply_slider(drag, (x - wx - drag.track_x) / drag.track_w)
		return true
	end
	local hit = false
	for _, btn in ipairs(self._preferences_buttons) do
		if alive(btn.panel) then
			local inside = btn.panel:inside(x, y)
			btn.hl:set_visible(inside)
			if btn.kind == "toggle" then
				btn.cb:set_texture_rect(unpack(tickbox_rect(btn.checked, inside)))
			end
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
			if btn.kind == "slider" then
				self._pref_dragging = btn
				local wx = btn.panel:world_position()
				csr_apply_slider(btn, (x - wx - btn.track_x) / btn.track_w)
			else
				btn.checked = not btn.checked
				btn.cb:set_texture_rect(unpack(tickbox_rect(btn.checked, true)))
				if btn.setting_key and managers.csr then
					managers.csr:set_setting(btn.setting_key, btn.checked)
				end
			end
			return true
		end
	end
	return false
end

-- Routed from CSRMissionsMenuComponent:mouse_released -- ends any slider drag and commits the
-- final value to disk once (the drag itself used defer_save to avoid per-frame writes).
function CSRMissionsMenuComponent:_preferences_panel_mouse_released(button, x, y)
	local drag = self._pref_dragging
	if drag then
		self._pref_dragging = nil
		if drag.setting_key and managers.csr then
			managers.csr:set_setting(drag.setting_key, drag.value)
		end
		return true
	end
	return false
end
