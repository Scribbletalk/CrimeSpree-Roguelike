-- Rebuilds the in-game ESC (pause) right panel for Crime Spree Roguelike.
-- CSR runs heists in the STANDARD gamemode (it never enables the CS gamemode),
-- so managers.crime_spree:is_active() is false and the pause panel is the
-- regular IngameContractGui -- NOT the CrimeSpree variant. Vanilla fills it from
-- the temporary "crime_spree" job, whose briefing_id is "heist_crime_spree_brief"
-- (no such loc key -> "ERROR: ..." text). We detect a CSR heist by that temp job
-- id and rebuild from CSR-valid data.
--
-- Layout:
--   <MISSION NAME>            (big, where vanilla's "CONTRACT" header sat)
--   CRIME.NET INFO:          (section header)
--   <briefing / plan text>
--   CRIME SPREE RANK: N [CS]  (label white, number yellow, then CS icon)

if not RequiredScript then
	return
end

if not IngameContractGui then
	return
end

-- CSR heist marker: STANDARD gamemode + a temporary "crime_spree" job. Same
-- signal heist_packages.lua uses; holds for host, guest and single-player.
local function csr_heist_active()
	return managers.job and managers.job:current_job_id() == "crime_spree"
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

	-- "CRIME SPREE RANK: N <glyph>" -- label white, number yellow, then the CS
	-- glyph. The icon is a font glyph (copied 1:1 from the lobby mission cards):
	-- U+E018 in pd2_medium_font carries the Crime Spree emblem.
	local rank = managers.csr and managers.csr:rank() or 0
	local prefix = managers.localization:to_upper_text("csr_pause_rank") .. " "
	local cs_glyph = utf8.char(0xE018) -- Crime Spree glyph U+E018
	local rank_text = text_panel:text({
		text = prefix .. tostring(rank) .. " " .. cs_glyph,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = tweak_data.screen_colors.text,
		align = "left",
	})
	managers.hud:make_fine_text(rank_text)
	-- Color the number AND the CS glyph yellow; keep the "CRIME SPREE RANK:" label white.
	rank_text:set_range_color(
		utf8.len(prefix),
		utf8.len(rank_text:text()),
		tweak_data.screen_colors.crime_spree_risk
	)
	rank_text:set_top(info_body:bottom() + padding)

	-- Border frame, matching the vanilla contract look.
	self._sides = BoxGuiObject:new(self._panel, { sides = { 1, 1, 1, 1 } })

	self._text_panel = text_panel

	-- Snap children to integer positions to avoid blurry text (vanilla does this).
	self:_rec_round_object(self._panel)
end)

csr_log("[CSR] pause_ingame_contract.lua loaded")
