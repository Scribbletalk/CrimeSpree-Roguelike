-- Crime Spree Roguelike - Difficulty Reward System + Infamy XP Multiplier
-- Reward scaling is handled in tweakdata (crimespree.lua).
-- This file: restores difficulty, applies infamy XP mult, shows infamy bonus on REWARDS tab.

if not RequiredScript then
	return
end

local required = string.lower(RequiredScript)

-- Debug logging (guarded by debug mode)
local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR Rewards] " .. tostring(msg))
	end
end

if required == "lib/managers/crimespreemanager" then
	-- Apply infamy XP multiplier to experience reward before calculate_rewards reads it
	-- NOTE: vanilla has NO "enable_crime_spree" method (only "enable_crime_spree_gamemode"),
	-- so previous PostHooks on that name were dead code. PreHook on calculate_rewards
	-- fires at the correct time for both cashout display AND award_rewards.
	Hooks:PreHook(CrimeSpreeManager, "calculate_rewards", "CSR_ApplyInfamyXPMultiplier", function(self)
		local infamy_mult = 1
		pcall(function()
			infamy_mult = managers.player:get_infamy_exp_multiplier()
		end)

		_G.CSR_InfamyXPMultiplier = infamy_mult

		if infamy_mult > 1 and tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.rewards then
			for _, reward in ipairs(tweak_data.crime_spree.rewards) do
				if reward.id == "experience" then
					-- Save base amount to prevent accumulation on repeated calls
					reward._csr_base_amount = reward._csr_base_amount or reward.amount
					reward.amount = reward._csr_base_amount * infamy_mult
					break
				end
			end
		end
	end)
elseif required == "lib/managers/menu/crimespreerewardsdetailspage" then
	-- Add infamy XP bonus text on the REWARDS tab, below the experience amount
	Hooks:PostHook(CrimeSpreeRewardsDetailsPage, "init", "CSR_ShowInfamyOnRewardsTab", function(self)
		local infamy_mult = 1
		pcall(function()
			infamy_mult = managers.player:get_infamy_exp_multiplier()
		end)

		if infamy_mult <= 1 then
			return
		end

		local panel = self:panel()
		if not panel or not panel:alive() then
			return
		end

		-- Calculate infamy bonus XP amount
		local reward_level = 0
		pcall(function()
			reward_level = managers.crime_spree:reward_level()
		end)

		local base_xp = 0
		if tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.rewards then
			for _, data in ipairs(tweak_data.crime_spree.rewards) do
				if data.id == "experience" then
					local base_amount = data._csr_base_amount or data.amount
					base_xp = math.max(math.floor(base_amount * reward_level), 0)
					break
				end
			end
		end

		local infamy_bonus_xp = math.floor(base_xp * (infamy_mult - 1))
		local amount_str = "+" .. managers.experience:cash_string(infamy_bonus_xp, "")

		-- Find the experience sub-panel: first panel child with column-sized width
		local num_rewards = #tweak_data.crime_spree.rewards
		local col_w = (panel:w() - 10) / num_rewards
		local exp_panel = nil

		for _, child in ipairs(panel:children()) do
			local ok, has_kids = pcall(function()
				return child.children and type(child.children) == "function"
			end)
			if ok and has_kids then
				local cw = child:w()
				local cx = child:x()
				if cx < 5 and cw < panel:w() * 0.5 and cw > 10 then
					exp_panel = child
					break
				end
			end
		end

		-- Helper: create label + amount pair in a target panel
		local function add_infamy_text(target, w_size, lowest_y)
			-- "INFAMY" label above the number
			local label = target:text({
				name = "csr_infamy_label",
				align = "center",
				vertical = "top",
				blend_mode = "add",
				layer = 11,
				text = "INFAMY",
				w = w_size,
				font_size = tweak_data.menu.pd2_small_font_size * 0.8,
				font = tweak_data.menu.pd2_small_font,
				color = Color(1, 0, 1):with_alpha(0.6),
			})
			label:set_top(lowest_y + 6)

			local _, _, _, lh = label:text_rect()
			label:set_h(lh)

			-- Amount right below the label
			local amount = target:text({
				name = "csr_infamy_amount",
				align = "center",
				vertical = "top",
				blend_mode = "add",
				layer = 11,
				text = amount_str,
				w = w_size,
				font_size = tweak_data.menu.pd2_small_font_size,
				font = tweak_data.menu.pd2_small_font,
				color = Color(1, 0, 1),
			})
			amount:set_top(label:bottom())
		end

		if exp_panel then
			-- Find the lowest text element (the reward amount)
			local lowest_bottom = 0
			for _, child in ipairs(exp_panel:children()) do
				local ok, is_text = pcall(function()
					return child.text and type(child.text) == "function"
				end)
				if ok and is_text then
					lowest_bottom = math.max(lowest_bottom, child:bottom())
				end
			end

			if lowest_bottom > 0 then
				-- Clamp position so text stays within panel bounds
				local max_y = exp_panel:h() - 50
				local clamped_y = math.min(lowest_bottom, max_y)
				add_infamy_text(exp_panel, exp_panel:w(), clamped_y)
				return
			end
		end

		-- Fallback: place in first column area on main panel
		add_infamy_text(panel, col_w, panel:h() * 0.35)
	end)
end
