-- Crime Spree Roguelike - Bags Bonus UI
-- Display secured bags as additional earned crime spree levels

if not RequiredScript then
	return
end



-- Hook on level UI element creation - adds secured bags bonus display
Hooks:PostHook(CrimeSpreeResultTabItem, "_create_level", "CSR_ShowBagsBonus", function(self, total_w)

	-- Guard: only proceed if mission was successful
	if not self:success() then
		return
	end


	-- Get bonus bag count from CrimeSpreeManager
	local bonus_bags = 0
	if managers.crime_spree then
		if managers.crime_spree._csr_bonus_bags then
			bonus_bags = managers.crime_spree._csr_bonus_bags
		else
		end
	else
	end

	if bonus_bags <= 0 then
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
	local color = tweak_data.screen_colors.regular_color

	-- Create "Bags Secured:" label (start with alpha=0 for vanilla animation)
	local bonus_label = self._level_panel:text({
		name = "csr_bags_label",
		blend_mode = "add",
		vertical = "center",
		alpha = 0,
		align = "center",
		layer = 10,
		text = managers.localization:to_upper_text("hud_stats_bags_secured"),
		h = font_size,
		font_size = font_size,
		font = font,
		color = color
	})

	self:make_fine_text(bonus_label)
	bonus_label:set_center_x(gain_x)
	bonus_label:set_top(gain:bottom() + 10)

	-- Create "+X levels" text
	local bonus_amount = self._level_panel:text({
		name = "csr_bags_amount",
		vertical = "center",
		blend_mode = "add",
		w = 200,
		align = "center",
		alpha = 0,
		layer = 10,
		text = "+" .. managers.localization:text("menu_cs_level", {level = bonus_bags}),
		h = font_size,
		font_size = font_size,
		font = font,
		color = color
	})

	bonus_amount:set_center_x(gain_x)
	bonus_amount:set_top(bonus_label:bottom())

	-- Append to vanilla animation queue at the END
	-- This makes "Bags Secured" appear AFTER all other bonuses (including Mission Complete)
	if self._levels and self._levels.bonuses then
		table.insert(self._levels.bonuses, {
			bonus_label,
			bonus_amount,
			bonus_bags
		})
	else
	end

	-- Use DelayedCalls for fade-out to avoid conflicting with vanilla animation
	DelayedCalls:Add("CSR_BagsBonusFadeOut", 7.75, function()
		if not alive(bonus_label) or not alive(bonus_amount) then
			return
		end

		-- Fade out via a separate panel animation (not on the element itself)
		self._level_panel:animate(function(panel)
			local fade_time = 1.0
			local t = 0
			local start_alpha_label = bonus_label:alpha()
			local start_alpha_amount = bonus_amount:alpha()

			while t < fade_time do
				local dt = coroutine.yield()
				t = t + dt
				local progress = t / fade_time

				if alive(bonus_label) then
					bonus_label:set_alpha(math.lerp(start_alpha_label, 0, progress))
				end
				if alive(bonus_amount) then
					bonus_amount:set_alpha(math.lerp(start_alpha_amount, 0, progress))
				end
			end

			-- Remove elements
			if alive(bonus_label) then
				panel:remove(bonus_label)
			end
			if alive(bonus_amount) then
				panel:remove(bonus_amount)
			end
		end)
	end)
end)

