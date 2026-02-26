-- Crime Spree Roguelike - Forced Modifiers Notification
-- Shows popup after mission when forced modifiers are added
-- v2.50: Fixed mouse_pos crash + added click handling + debug logging



-- Unique callback ID for GameSetupUpdate hook
local HOOK_ID = "CSR_ForcedModsNotification_Update"

CSRForcedModsNotification = CSRForcedModsNotification or class()

function CSRForcedModsNotification:init(modifiers)

	if not modifiers or #modifiers == 0 then
		return
	end


	-- Save global reference
	_G.CSR_ForcedModsNotificationInstance = self

	-- Create fullscreen workspace manually
	self._ws = managers.gui_data:create_fullscreen_workspace()
	if not self._ws then
		return
	end

	-- === BACKDROP ===
	self._backdrop = self._ws:panel():rect({
		name = "csr_notification_backdrop",
		color = Color.black,
		alpha = 0,
		layer = 999,
		w = self._ws:panel():w(),
		h = self._ws:panel():h()
	})

	-- Calculate panel height
	local panel_height = self:calculate_height(#modifiers)

	-- === MAIN PANEL ===
	self._panel = self._ws:panel():panel({
		name = "csr_forced_mods_notification",
		w = 600,
		h = panel_height,
		layer = 1000
	})

	-- Center
	self._panel:set_center(self._ws:panel():center())
	self._panel:set_alpha(0)

	-- === BACKGROUND ===
	self._bg = self._panel:rect({
		color = Color.black,
		alpha = 0.95,
		layer = 0
	})

	if BoxGuiObject then
		pcall(function()
			BoxGuiObject:new(self._panel, { sides = {2, 2, 2, 2} })
		end)
	end

	-- === TITLE ===
	local max_level = 0
	for _, mod in ipairs(modifiers) do
		if mod.level and mod.level > max_level then
			max_level = mod.level
		end
	end

	self._title = self._panel:text({
		text = "FORCED MODIFIERS ADDED",
		font = tweak_data.menu.pd2_large_font,
		font_size = 28,
		color = Color(1, 0.85, 0.7, 0.2),
		align = "center",
		vertical = "top",
		y = 15,
		layer = 10
	})

	if max_level > 0 then
		self._level_text = self._panel:text({
			text = "Level " .. max_level,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 22,
			color = Color(0.7, 0.7, 0.7),
			align = "center",
			vertical = "top",
			y = 50,
			layer = 10
		})
	end

	-- === MODIFIER CARDS ===
	self:populate_modifiers(modifiers)

	-- === HINT TEXT ===
	local lang = CSR_Settings and CSR_Settings:GetLanguage() or "en"
	local hint_text = lang == "ru" and "Press ESC or button below" or "Press ESC or button below"

	self._hint = self._panel:text({
		text = hint_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 18,
		color = Color(0.7, 0.7, 0.7),
		align = "center",
		vertical = "bottom",
		layer = 10
	})

	local _, _, _, h = self._hint:text_rect()
	self._hint:set_bottom(self._panel:h() - 70)

	-- === CLOSE BUTTON ===
	local button_panel = self._panel:panel({
		x = (self._panel:w() - 200) / 2,
		y = self._panel:h() - 60,
		w = 200,
		h = 40,
		layer = 15
	})

	button_panel:rect({
		color = Color(0.3, 0.3, 0.3),
		alpha = 0.9,
		layer = 0
	})

	self._button_highlight = button_panel:rect({
		color = Color.white,
		alpha = 0,
		blend_mode = "add",
		layer = 1
	})

	button_panel:text({
		text = "CLOSE",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 22,
		color = Color.white,
		align = "center",
		vertical = "center",
		layer = 10
	})

	self._close_button = button_panel

	-- === FADE-IN ===
	self:animate_fade_in()

	-- === REGISTER GameSetupUpdate HOOK for mouse/keyboard ===
	Hooks:Add("GameSetupUpdate", HOOK_ID, function(t, dt)
		local inst = _G.CSR_ForcedModsNotificationInstance
		if not inst or not alive(inst._panel) then
			return
		end

		-- ESC handling
		if Input:keyboard() and Input:keyboard():pressed(Idstring("esc")) then
			inst:close()
			-- Clear ESC state so game menu doesn't open
			pcall(function()
				Input:keyboard():clear_key_state(Idstring("esc"))
			end)
			return
		end

		-- Mouse handling (v2.50: modified_mouse_pos returns TWO numbers, NOT a table!)
		if managers.mouse_pointer then
			local x, y = managers.mouse_pointer:modified_mouse_pos()
			if x and y then
				local used, cursor = inst:mouse_moved(x, y)
				if cursor then
					managers.mouse_pointer:set_pointer_image(cursor)
				end
			end
		end

		-- Mouse click handling (v2.50: LMB press)
		if Input:mouse() and Input:mouse():pressed(Idstring("0")) then
			if managers.mouse_pointer then
				local x, y = managers.mouse_pointer:modified_mouse_pos()
				if x and y then
					inst:mouse_pressed(Idstring("0"), x, y)
				end
			end
		end
	end)


	-- v2.50: Debug logging
end

-- === MODIFIER TEXT ===
function CSRForcedModsNotification:get_modifier_text(mod)
	local name = "Unknown Modifier"
	local desc = ""

	if managers.localization then
		local clean_id = mod.id:gsub("^csr_", "")

		local base_id = clean_id
		local is_stealth_tiered = clean_id:find("^less_pagers_") or
		                           clean_id:find("^civilian_alarm_")

		if not is_stealth_tiered then
			base_id = clean_id:gsub("_(%d+)$", "")
		end

		local name_key = "menu_cs_modifier_" .. base_id
		local text = managers.localization:text(name_key)

		if text and not text:find("ERROR", 1, true) then
			local lines = {}
			for line in text:gmatch("[^\n]+") do
				table.insert(lines, line)
			end

			if #lines >= 2 then
				name = lines[1]
				desc = lines[2]
			else
				name = text
				desc = ""
			end
		else
			name = clean_id:gsub("_", " "):upper()
			desc = ""

			local mod_data = self:get_modifier_data(mod)
			if mod_data and mod_data.description then
				desc = mod_data.description
			end
		end
	else
		local clean_id = mod.id:gsub("^csr_", "")
		name = clean_id:gsub("_", " "):upper()
		desc = ""
	end

	return name, desc
end

-- === MODIFIER DATA ===
function CSRForcedModsNotification:get_modifier_data(mod)
	local mod_data = nil

	if managers and managers.crime_spree then
		local ok, result = pcall(function()
			return managers.crime_spree:get_modifier(mod.id)
		end)
		if ok then
			mod_data = result
		end
	end

	if not mod_data and _G.CSR_ForcedModifierLookup then
		mod_data = _G.CSR_ForcedModifierLookup[mod.id]
	end

	return mod_data
end

-- === POPULATE MODIFIER CARDS ===
function CSRForcedModsNotification:populate_modifiers(modifiers)
	local y_offset = 95
	local card_height = 110
	local card_spacing = 10

	for i, mod in ipairs(modifiers) do
		local name, desc = self:get_modifier_text(mod)
		local mod_data = self:get_modifier_data(mod)

		local card_y = y_offset + (i - 1) * (card_height + card_spacing)
		local card_panel = self._panel:panel({
			x = 30,
			y = card_y,
			w = self._panel:w() - 60,
			h = card_height,
			layer = 5
		})

		card_panel:rect({
			color = Color(0.2, 0.2, 0.2),
			alpha = 0.8,
			layer = 0
		})

		card_panel:rect({
			color = Color.white,
			alpha = 0.1,
			h = 1,
			blend_mode = "add",
			layer = 1
		})

		-- Icon
		if mod_data and mod_data.icon then
			local ok, icon_texture, icon_rect = pcall(function()
				return tweak_data.hud_icons:get_icon_data(mod_data.icon)
			end)

			if ok and icon_texture then
				local icon_size = 64
				card_panel:bitmap({
					texture = icon_texture,
					texture_rect = icon_rect,
					w = icon_size,
					h = icon_size,
					x = 15,
					y = (card_height - icon_size) / 2,
					color = Color.white,
					layer = 10
				})
			end
		end

		-- Text
		local text_x = 95
		local text_w = card_panel:w() - text_x - 20

		card_panel:text({
			text = name,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 24,
			color = Color.white,
			x = text_x,
			y = 15,
			w = text_w,
			h = 22,
			layer = 10,
			wrap = true,
			word_wrap = true
		})

		card_panel:text({
			text = desc,
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = Color(0.7, 0.7, 0.7),
			x = text_x,
			y = 42,
			w = text_w,
			h = card_height - 42 - 10,
			layer = 10,
			wrap = true,
			word_wrap = true
		})

	end
end

-- === CALCULATE HEIGHT ===
function CSRForcedModsNotification:calculate_height(num_mods)
	local header_height = 115
	local footer_height = 100
	local card_height = 110
	local card_spacing = 10

	local cards_total = num_mods * card_height + (num_mods - 1) * card_spacing
	return header_height + cards_total + footer_height
end

-- === FADE-IN ===
function CSRForcedModsNotification:animate_fade_in()
	self._panel:animate(function(panel)
		local fade_time = 0.3
		local t = 0
		while t < fade_time do
			local dt = coroutine.yield()
			t = t + dt
			local progress = t / fade_time

			if alive(panel) then
				panel:set_alpha(math.lerp(0, 1, progress))
			end

			if alive(self._backdrop) then
				self._backdrop:set_alpha(math.lerp(0, 0.6, progress))
			end
		end

		if alive(panel) then
			panel:set_alpha(1)
		end
		if alive(self._backdrop) then
			self._backdrop:set_alpha(0.6)
		end
	end)
end

-- === CLOSE ===
function CSRForcedModsNotification:close()

	-- v2.50: Debug logging

	-- Remove hook FIRST
	Hooks:Remove(HOOK_ID)

	-- Clear global reference immediately
	if _G.CSR_ForcedModsNotificationInstance == self then
		_G.CSR_ForcedModsNotificationInstance = nil
	end

	if alive(self._panel) then
		self._panel:animate(function(panel)
			local fade_time = 0.2
			local t = 0

			while t < fade_time do
				local dt = coroutine.yield()
				t = t + dt
				local progress = t / fade_time

				if alive(panel) then
					panel:set_alpha(math.lerp(1, 0, progress))
				end

				if alive(self._backdrop) then
					self._backdrop:set_alpha(math.lerp(0.6, 0, progress))
				end
			end

			-- Destroy workspace after fade-out
			if self._ws then
				managers.gui_data:destroy_workspace(self._ws)
				self._ws = nil
			end

		end)
	else
		-- Panel already dead, just destroy workspace
		if self._ws then
			managers.gui_data:destroy_workspace(self._ws)
			self._ws = nil
		end
	end
end

-- === MOUSE MOVED ===
function CSRForcedModsNotification:mouse_moved(x, y)
	if not alive(self._panel) or not alive(self._close_button) then
		return false, "arrow"
	end

	local panel_x, panel_y = self._panel:world_position()
	local local_x = x - panel_x
	local local_y = y - panel_y

	local btn_x, btn_y = self._close_button:position()
	local btn_w, btn_h = self._close_button:size()

	local is_hover = local_x >= btn_x and local_x <= (btn_x + btn_w) and
	                 local_y >= btn_y and local_y <= (btn_y + btn_h)

	if alive(self._button_highlight) then
		self._button_highlight:set_alpha(is_hover and 0.2 or 0)
	end

	return is_hover, is_hover and "link" or "arrow"
end

-- === MOUSE PRESSED (blocks clicks behind popup) ===
function CSRForcedModsNotification:mouse_pressed(button, x, y)
	if not alive(self._panel) then
		return false
	end

	-- Check click on close button
	if alive(self._close_button) then
		local panel_x, panel_y = self._panel:world_position()
		local local_x = x - panel_x
		local local_y = y - panel_y

		local btn_x, btn_y = self._close_button:position()
		local btn_w, btn_h = self._close_button:size()

		local is_click = local_x >= btn_x and local_x <= (btn_x + btn_w) and
		                 local_y >= btn_y and local_y <= (btn_y + btn_h)

		if is_click then
			self:close()
			return true
		end
	end

	-- Block all other clicks
	return true
end

