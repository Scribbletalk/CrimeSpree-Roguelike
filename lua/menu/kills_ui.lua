-- Crime Spree Roguelike - Kills Bonus UI
-- Display team kills and bonus levels earned (red color)
-- Uses vanilla bonuses animation system (same as Bags Secured)

if not RequiredScript then
	return
end



-- Hook on level UI element creation - adds kills bonus display
Hooks:PostHook(CrimeSpreeResultTabItem, "_create_level", "CSR_ShowKillsBonus", function(self, total_w)

	-- Guard: only proceed if mission was successful
	if not self:success() then
		return
	end

	-- Get bonus levels from kills
	local bonus_levels = 0
	if managers.crime_spree then
		bonus_levels = managers.crime_spree._csr_bonus_kills or 0
	end

	if bonus_levels <= 0 then
		return
	end


	-- Find the "gain" element (main text showing earned levels)
	local gain = self._level_panel:child("gain")
	if not gain then
		return
	end

	local gain_x = gain:center_x()

	-- Font settings (matching vanilla game style)
	local font = tweak_data.menu.pd2_small_font
	local font_size = tweak_data.menu.pd2_small_font_size

	-- RED color for kills
	local red_color = Color(1, 1, 0, 0)

	-- Get current language
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")

	-- Build display text: "+2  KILL BONUS"
	local kill_bonus_label = lang == "ru" and "БОНУС ЗА УБИЙСТВА" or "KILL BONUS"
	local display_text = "+" .. bonus_levels .. "  " .. kill_bonus_label

	-- Single text element - all on one line, fades out together
	local kills_text = self._level_panel:text({
		name = "csr_kills_text",
		vertical = "center",
		blend_mode = "add",
		align = "center",
		alpha = 0,
		layer = 10,
		text = display_text,
		h = font_size,
		font_size = font_size,
		font = font,
		color = red_color
	})

	self:make_fine_text(kills_text)
	kills_text:set_center_x(gain_x)
	kills_text:set_top(gain:bottom() + 10)

	-- Add to vanilla animation system (same as Bags Secured)
	-- Same element in [1] and [2] - both reference the same text, fade out together
	if self._levels and self._levels.bonuses then
		table.insert(self._levels.bonuses, {
			kills_text,    -- [1] = same element
			kills_text,    -- [2] = same element
			bonus_levels   -- [3] = number for gain display
		})
	else
	end
end)

