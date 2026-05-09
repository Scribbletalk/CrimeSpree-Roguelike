-- Crime Spree Roguelike - Rank Catchup/Penalty UI
-- Shows rank adjustment when client is behind or ahead of host
-- Uses vanilla bonuses animation system (same as Bags Secured / Kill Bonus)

if not RequiredScript then
	return
end

-- Hook on level UI element creation - adds rank catchup/penalty display
Hooks:PostHook(CrimeSpreeResultTabItem, "_create_level", "CSR_ShowRankAdjustment", function(self, total_w)
	-- Guard: only proceed if mission was successful
	if not self:success() then
		return
	end

	-- Get rank adjustment from CrimeSpreeManager
	local adjustment = 0
	if managers.crime_spree then
		adjustment = managers.crime_spree._csr_rank_adjustment or 0
	end

	if adjustment == 0 then
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

	-- Positive = catchup (orange), negative = penalty (red)
	local is_catchup = adjustment > 0
	local color = is_catchup and tweak_data.screen_colors.heat_warm_color or Color(1, 1, 0, 0)
	local label_key = is_catchup and "menu_csr_catchup_bonus" or "menu_csr_rank_penalty"
	local display_value = math.abs(adjustment)
	local sign = is_catchup and "+" or "-"

	-- Label on first line
	local rank_label = self._level_panel:text({
		name = "csr_rank_label",
		blend_mode = "add",
		vertical = "center",
		alpha = 0,
		align = "center",
		layer = 10,
		text = managers.localization:to_upper_text(label_key),
		h = font_size,
		font_size = font_size,
		font = font,
		color = color,
	})

	self:make_fine_text(rank_label)
	rank_label:set_center_x(gain_x)
	rank_label:set_top(gain:bottom() + 10)

	-- "+X" or "-X" on second line
	local rank_amount = self._level_panel:text({
		name = "csr_rank_amount",
		vertical = "center",
		blend_mode = "add",
		w = 200,
		align = "center",
		alpha = 0,
		layer = 10,
		text = sign .. managers.localization:text("menu_cs_level", { level = display_value }),
		h = font_size,
		font_size = font_size,
		font = font,
		color = color,
	})

	rank_amount:set_center_x(gain_x)
	rank_amount:set_top(rank_label:bottom())

	-- Add to vanilla animation system (adjustment drives the gain counter up or down)
	if self._levels and self._levels.bonuses then
		table.insert(self._levels.bonuses, {
			rank_label,
			rank_amount,
			adjustment,
		})
	end
end)
