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
-- Pad glyphs are unreadable at the row's own text size, so they run at the large font's native
-- size (fonts/font_large_mf.merged_font pulls in font_large_buttons, so the glyphs exist there) and
-- the bind row is given the height to hold one.
local pref_bind_row_h = 52
local pref_bind_glyph_font_size = 44

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

-- Right-hand side of the wildcard bind row, split in two so the pad glyph can be drawn large: the
-- glyph (nil for a keyboard key) and the text beside it -- the key name, or the d-pad direction the
-- one shared d-pad glyph cannot express. Recomputed on every repopulate and after a capture.
local function bind_value_parts()
	local bind_api = _G.CSR_WildcardBind
	local bind = bind_api and bind_api.binding()
	if not bind then
		return nil, managers.localization:text("csr_pref_bind_none")
	end
	return bind_api.display(bind)
end

-- Lays out that right side: the glyph sits against the right edge at its own drawn width, the text
-- is packed against it. Build and refresh both go through here, so the two cannot drift apart.
local function set_bind_value(btn, glyph_text, value_text)
	if not (alive(btn.panel) and alive(btn.glyph) and alive(btn.val)) then
		return
	end
	local right = btn.panel:w() - 8
	btn.glyph:set_text(glyph_text or "")
	btn.glyph:set_visible(glyph_text ~= nil)
	if glyph_text then
		local _, _, gw = btn.glyph:text_rect()
		btn.glyph:set_w(math.max(gw, 1))
		btn.glyph:set_right(right)
		right = right - btn.glyph:w() - 6
	end
	btn.val:set_text(value_text or "")
	btn.val:set_w(math.max(right - btn.panel:w() * 0.4, 40))
	btn.val:set_right(right)
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

	-- Wildcard bind row: label left, current binding right. Clicking opens a capture window that
	-- wildcard_bind.lua drives (keyboard keys and gamepad buttons; mouse stays on the BLT keybind).
	local function make_bind(label)
		local row = content:panel({ x = pad, y = y, w = row_w, h = pref_bind_row_h, layer = 5 })

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
			w = row_w * 0.4 - 8,
			h = pref_bind_row_h,
			align = "left",
			vertical = "center",
			layer = 2,
		})

		local glyph = row:text({
			text = "",
			font = tweak_data.menu.pd2_large_font,
			font_size = pref_bind_glyph_font_size,
			color = tweak_data.screen_colors.button_stage_3,
			h = pref_bind_row_h,
			align = "right",
			vertical = "center",
			layer = 2,
		})

		-- "PRESS A KEY OR BUTTON..." and a spelled-out key name are both longer than the row's right
		-- side, so this one wraps; two lines fit the taller bind row at this size.
		local val = row:text({
			text = "",
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.button_stage_3,
			wrap = true,
			word_wrap = true,
			w = row_w * 0.6 - 8,
			h = pref_bind_row_h,
			align = "right",
			vertical = "center",
			layer = 2,
		})

		y = y + pref_bind_row_h + pref_row_gap

		local btn = { kind = "bind", panel = row, hl = hl, val = val, glyph = glyph }
		set_bind_value(btn, bind_value_parts())
		return btn
	end

	local skip_bs = make_toggle(managers.localization:text("csr_pref_skip_blackscreen"), "skip_blackscreen")
	table.insert(self._preferences_buttons, skip_bs)

	local btn = make_toggle(managers.localization:text("csr_pref_block_item_heal"), "block_item_heal")
	table.insert(self._preferences_buttons, btn)

	local wc_bar = make_toggle(managers.localization:text("csr_pref_hud_wildcard_bar"), "hud_wildcard_use_bar")
	table.insert(self._preferences_buttons, wc_bar)

	if _G.CSR_WildcardBind then
		table.insert(self._preferences_buttons, make_bind(managers.localization:text("csr_pref_wildcard_bind")))
	end

	local sfx = make_slider(managers.localization:text("csr_pref_item_sound_volume"), "sfx_volume")
	table.insert(self._preferences_buttons, sfx)

	local aloe = make_slider(managers.localization:text("csr_pref_aloe_aura_opacity"), "aloe_aura_opacity")
	table.insert(self._preferences_buttons, aloe)
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
			elseif btn.kind == "bind" then
				-- Second click while listening cancels; the callback restores the row text either way.
				local bind_api = _G.CSR_WildcardBind
				if bind_api and bind_api.listening() then
					bind_api.cancel_listen()
				elseif bind_api then
					set_bind_value(btn, nil, managers.localization:text("csr_pref_bind_listening"))
					bind_api.begin_listen(function()
						set_bind_value(btn, bind_value_parts())
					end)
				end
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
