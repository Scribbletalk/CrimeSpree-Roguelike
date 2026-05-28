-- CSRHUDStageEndScreen — fork of vanilla HUDStageEndCrimeSpreeScreen.
-- Class rename + level-name source swap (vanilla reads current_played_mission
-- which we've already cleared by this point; we read managers.job:current_level_id).
-- Heavy stat work still delegated back to HUDStageEndScreen via reused vanilla statics.

CSRHUDStageEndScreen = CSRHUDStageEndScreen or class()

function CSRHUDStageEndScreen:init(hud, workspace)
	self._backdrop = MenuBackdropGUI:new(workspace)

	if not _G.IS_VR then
		self._backdrop:create_black_borders()
	end

	self._hud = hud
	self._workspace = workspace
	self._singleplayer = Global.game_settings.single_player
	local bg_font = tweak_data.menu.pd2_massive_font
	local title_font = tweak_data.menu.pd2_large_font
	local content_font = tweak_data.menu.pd2_medium_font
	local small_font = tweak_data.menu.pd2_small_font
	local bg_font_size = tweak_data.menu.pd2_massive_font_size
	local title_font_size = tweak_data.menu.pd2_large_font_size
	local content_font_size = tweak_data.menu.pd2_medium_font_size
	local small_font_size = tweak_data.menu.pd2_small_font_size
	local massive_font = bg_font
	local large_font = title_font
	local medium_font = content_font
	local massive_font_size = bg_font_size
	local large_font_size = title_font_size
	local medium_font_size = content_font_size
	self._background_layer_safe = self._backdrop:get_new_background_layer()
	self._background_layer_full = self._backdrop:get_new_background_layer()
	self._foreground_layer_safe = self._backdrop:get_new_foreground_layer()
	self._foreground_layer_full = self._backdrop:get_new_foreground_layer()

	self._backdrop:set_panel_to_saferect(self._background_layer_safe)
	self._backdrop:set_panel_to_saferect(self._foreground_layer_safe)

	-- Stage name from the level just played; vanilla's spree backend is already
	-- cleared by this point (mission_lifecycle nilled current_mission).
	local level_id = managers.job:current_level_id()
	local lvl_td = level_id and tweak_data.levels[level_id]
	self._stage_name = (lvl_td and lvl_td.name_id and managers.localization:to_upper_text(lvl_td.name_id)) or ""

	self._foreground_layer_safe:text({
		name = "stage_text",
		vertical = "center",
		align = "right",
		text = self._stage_name,
		h = title_font_size,
		font_size = title_font_size,
		font = title_font,
		color = tweak_data.screen_colors.text,
	})

	local bg_text = self._background_layer_full:text({
		name = "stage_text",
		vertical = "top",
		alpha = 0.4,
		align = "left",
		text = self._stage_name,
		h = bg_font_size,
		font_size = bg_font_size,
		font = bg_font,
		color = tweak_data.screen_colors.button_stage_3,
	})

	bg_text:set_world_center_y(self._foreground_layer_safe:child("stage_text"):world_center_y())
	bg_text:set_world_x(self._foreground_layer_safe:child("stage_text"):world_x())
	bg_text:move(-13, 9)
	bg_text:set_visible(false)
	self._backdrop:animate_bg_text(bg_text)
end

function CSRHUDStageEndScreen:hide()
	self._backdrop:hide()
end

function CSRHUDStageEndScreen:show()
	self._backdrop:show()
end

function CSRHUDStageEndScreen:update(t, dt) end

function CSRHUDStageEndScreen:update_layout()
	self._backdrop:_set_black_borders()
end

function CSRHUDStageEndScreen:set_success(success, server_left)
	HUDStageEndScreen.set_success(self, success, server_left)
end

function CSRHUDStageEndScreen:set_continue_button_text(text) end

function CSRHUDStageEndScreen:set_statistics(criminals_completed, success)
	HUDStageEndScreen.set_statistics(self, criminals_completed, success)
end

function CSRHUDStageEndScreen:set_special_packages(params) end

function CSRHUDStageEndScreen:set_speed_up(multiplier) end

function CSRHUDStageEndScreen:set_group_statistics(...)
	HUDStageEndScreen.set_group_statistics(self, ...)
end

function CSRHUDStageEndScreen:send_xp_data(data, done_clbk) end

csr_log("[CSR] hud_stage_endscreen.lua loaded")
