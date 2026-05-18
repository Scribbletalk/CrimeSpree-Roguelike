-- CSRHUDStageEndScreen — fork of vanilla HUDStageEndCrimeSpreeScreen.
--
-- Origin: pd2_source_code/lib/managers/hud/hudstageendcrimespreescreen.lua (106 lines)
-- Strategy: byte-for-byte copy with the class renamed and the level-name
-- source swapped off the spree backend. Everything else (the MenuBackdropGUI
-- layers, bg-text animation, the thin delegations to HUDStageEndScreen) is
-- byte-identical to vanilla.
--
-- This is the lightweight CS-style end-screen HUD backdrop. We fork it (not
-- the 3567-line HUDStageEndScreen) because the CS path delegates the heavy
-- stat work back to HUDStageEndScreen anyway via HUDStageEndScreen.set_* —
-- those vanilla globals are REUSED, never redefined (redefining them would
-- leak into every vanilla end screen — feedback_csr_only_no_vanilla_leak).
--
-- Class rename:
--   HUDStageEndCrimeSpreeScreen -> CSRHUDStageEndScreen
--
-- Backend swap / correctness fix (the only :init diff vs vanilla):
--   vanilla derives the stage name from
--     managers.crime_spree:get_mission(managers.crime_spree:current_played_mission())
--   CSR cannot: by the time this HUD builds, csr_mission_lifecycle's
--   at_enter PostHook has already called managers.csr:generate_mission_set()
--   which nils current_mission, so managers.csr:get_mission(nil) returns nil
--   and `mission.level.level_id` would crash. The robust, also-more-correct
--   source is the level actually just played — managers.job:current_level_id()
--   (still valid here; the job is not deactivated until _load_start_menu in
--   MissionEndState:at_exit, which runs later) -> tweak_data.levels[id].name_id.
--   Fully nil-guarded so a missing level just yields an empty title.
--
-- Routing (which HUD class instantiates) lives in csr_endscreen_wiring.lua,
-- gated on the run-scoped no-leak signal (job == "crime_spree" AND vanilla CS
-- NOT active) so vanilla / vanilla CS / Skirmish are byte-for-byte untouched.

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

	-- CSR backend swap: stage name from the level just played, not the spree
	-- mission backend (which is already cleared by this point — see header).
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

log("[CSR] csr_hud_stage_endscreen.lua loaded (CSRHUDStageEndScreen fork)")
