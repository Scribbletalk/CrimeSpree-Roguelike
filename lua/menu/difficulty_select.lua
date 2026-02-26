-- Crime Spree Roguelike - Difficulty Selection Menu
-- Replaces the starting level selector with a starting difficulty selector

if not RequiredScript then
	return
end



-- Global variables
_G.CSR_SelectedDifficulty = _G.CSR_SelectedDifficulty or "normal"
_G.CSR_SelectedStartLevel = _G.CSR_SelectedStartLevel or 0  -- Store selected starting level
_G.CSR_DifficultyButtons = nil  -- Store buttons globally

-- Variables for auto-scroll when arrow buttons are held
_G.CSR_ArrowHeld = nil  -- "left", "right" or nil
_G.CSR_ArrowHoldTime = 0  -- Time the arrow has been held
_G.CSR_ArrowLastScroll = 0  -- Time of last scroll tick

-- Hook on Crime Spree menu creation
Hooks:PostHook(CrimeSpreeContractMenuComponent, "_setup_new_crime_spree", "CSR_AddDifficultySelection", function(self, text_w, text_h)

	-- CRITICAL: Expand _levels_panel height to fit difficulty buttons + level buttons
	if self._levels_panel and self._levels_panel.set_h then
		local current_h = self._levels_panel:h()
		-- Increase height further so level buttons are not clipped
		local new_h = current_h + 240  -- Was 180, increased to 240
		self._levels_panel:set_h(new_h)

		-- Shift panel upward
		local x, y = self._levels_panel:position()
		self._levels_panel:set_y(math.max(0, y - 180))  -- 180px as requested
	end

	-- Hide vanilla "STARTING LEVEL:" text (recursive search)
	local function hide_vanilla_text(panel, depth)
		if not panel or depth > 8 then return end

		if panel.children and type(panel.children) == "function" then
			for i, child in ipairs(panel:children()) do
				if child.text and type(child.text) == "function" then
					local text = child:text()
					if type(text) == "string" and string.find(string.upper(text), "STARTING") then
						child:set_alpha(0)  -- Hide vanilla text
					end
				end
				hide_vanilla_text(child, depth + 1)
			end
		end
	end

	-- Search and hide across the entire panel
	if self._panel then
		hide_vanilla_text(self._panel, 0)
	end

	-- Create our own "Starting Difficulty" header directly in _levels_panel
	local lang = (CSR_Settings and CSR_Settings:GetLanguage()) or "en"
	local title_text = lang == "ru" and "НАЧАЛЬНАЯ СЛОЖНОСТЬ:" or "STARTING DIFFICULTY:"

	local title = self._levels_panel:text({
		name = "csr_difficulty_title",
		text = title_text,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size or 18,
		align = "left",
		vertical = "top",
		layer = 3,
		x = 10,
		y = 5,
		w = self._levels_panel:w()
	})


	-- Hide vanilla level buttons - we create our own
	if self._buttons then
		for _, btn in ipairs(self._buttons) do
			if btn._panel and btn._panel:alive() then
				btn._panel:set_visible(false)
			end
		end
	end

	-- List of all difficulties (with line breaks for long names)
	-- Multipliers are shown relative to Normal as baseline (factor of vanilla values)
	-- Icons - skull masks per difficulty from blackmarket
	local difficulties = {
		{id = "normal", name = "NORMAL", reward_ui = "STANDARD REWARDS", mask_id = "dnm"},  -- Normal Skull (Do Normal Missions)
		{id = "hard", name = "HARD", reward_ui = "×2 REWARDS", mask_id = "skullhard"},
		{id = "very_hard", name = "VERY\nHARD", reward_ui = "×4 REWARDS", mask_id = "skullveryhard"},
		{id = "overkill", name = "OVERKILL", reward_ui = "×8 REWARDS", mask_id = "skulloverkill"},
		{id = "mayhem", name = "MAYHEM", reward_ui = "×10 REWARDS", mask_id = "skulloverkillplus"},
		{id = "death_wish", name = "DEATH\nWISH", reward_ui = "×12 REWARDS", mask_id = "gitgud_e_wish"},
		{id = "death_sentence", name = "DEATH\nSENTENCE", reward_ui = "×14 REWARDS", mask_id = "gitgud_sm_wish"}
	}

	local padding = tweak_data.gui.crime_net.contract_gui.padding or 10
	local num_buttons = #difficulties
	local btn_w = (self._levels_panel:w() - padding * (num_buttons - 1)) / num_buttons
	local btn_h = 80  -- Restored normal size
	local buttons_y_offset = 40  -- INCREASED top offset to avoid overlapping "STARTING DIFFICULTY:" header

	CSR_DifficultyButtons = {}

	-- Create buttons for each difficulty
	for idx, diff_data in ipairs(difficulties) do
		local x_pos = (idx - 1) * (btn_w + padding)

		-- Create button panel (shifted down by buttons_y_offset)
		local btn_panel = self._levels_panel:panel({
			name = "difficulty_" .. diff_data.id,
			w = btn_w,
			h = btn_h,
			x = x_pos,
			y = buttons_y_offset
		})

		-- Button background
		local bg = btn_panel:rect({
			name = "background",
			color = Color.black,
			alpha = 0.4,
			layer = 0
		})

		-- Corner border (matching original buttons)
		BoxGuiObject:new(btn_panel, {
			sides = {1, 1, 1, 1}
		})

		-- Difficulty mask icon
		if diff_data.mask_id then
			local icon_size = 38  -- Restored normal size
			-- Get mask icon path
			local mask_texture = "guis/textures/pd2/blackmarket/icons/masks/" .. diff_data.mask_id

			-- Add DLC path for DLC masks
			if diff_data.mask_id == "dnm" then
				-- Normal Skull (Do Normal Missions)
				mask_texture = "guis/dlcs/dnm/textures/pd2/blackmarket/icons/masks/" .. diff_data.mask_id
			elseif string.find(diff_data.mask_id, "gitgud") then
				-- Death Wish and Death Sentence masks
				mask_texture = "guis/dlcs/gitgud/textures/pd2/blackmarket/icons/masks/" .. diff_data.mask_id
			end

			local icon = btn_panel:bitmap({
				name = "difficulty_icon",
				texture = mask_texture,
				w = icon_size,
				h = icon_size,
				x = (btn_w - icon_size) / 2,  -- Center horizontally
				y = 5,
				layer = 2,
				color = Color.white
			})
		end

		-- Hover highlight
		local highlight = btn_panel:rect({
			name = "highlight",
			color = Color.white,
			alpha = 0,
			layer = 1
		})

		-- Active background (when selected)
		local active_bg = btn_panel:rect({
			name = "active_bg",
			color = tweak_data.screen_colors.crime_spree_risk or Color("66ccff"),
			alpha = 0.3,
			layer = 1,
			visible = _G.CSR_SelectedDifficulty == diff_data.id
		})

		-- Difficulty name text (below icon)
		local difficulty_text = btn_panel:text({
			name = "difficulty_text",
			text = diff_data.name,
			color = Color.white,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 15,  -- Restored normal size
			align = "center",
			vertical = "bottom",
			layer = 2,
			y = 0,
			h = btn_h - 6,
			word_wrap = true,
			wrap = true,
			break_long_words = false
		})

		-- Store button for click handling
		table.insert(CSR_DifficultyButtons, {
			panel = btn_panel,
			difficulty = diff_data.id,
			active_bg = active_bg,
			highlight = highlight,
			selected = false  -- Track hover state
		})
	end

	-- Create large reward multiplier text below difficulty buttons, above level buttons
	local reward_display_y = buttons_y_offset + btn_h + 10  -- Account for button offset
	local reward_display = self._levels_panel:text({
		name = "csr_reward_display",
		text = "",
		color = tweak_data.screen_colors.crime_spree_risk or Color("66ccff"),
		font = tweak_data.menu.pd2_large_font,
		font_size = 28,  -- Restored normal size
		align = "center",
		vertical = "top",
		layer = 2,
		y = reward_display_y,
		w = self._levels_panel:w()
	})

	-- Create "STARTING LEVEL:" text below rewards
	local starting_level_text = lang == "ru" and "НАЧАЛЬНЫЙ УРОВЕНЬ:" or "STARTING LEVEL:"
	local starting_level_y = reward_display_y + 40  -- Below rewards
	local starting_level_label = self._levels_panel:text({
		name = "csr_starting_level_label",
		text = starting_level_text,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size or 18,
		align = "left",
		vertical = "top",
		layer = 3,
		x = 10,
		y = starting_level_y,
		w = self._levels_panel:w()
	})


	-- === NEW STARTING LEVEL BUTTON SYSTEM ===
	-- Generate 21 levels (every 20): 20, 40, 60...420
	local all_start_levels = {}
	for i = 1, 21 do
		table.insert(all_start_levels, i * 20)
	end

	-- Unlock formula: start_level = highest_level / 4
	-- Uses highest_level for the currently selected difficulty and all higher ones
	local function is_level_unlocked(level)
		local highest_for_difficulty = 0
		if _G.CSR_MetaProgress and _G.CSR_MetaProgress.GetHighestLevelForDifficulty then
			highest_for_difficulty = _G.CSR_MetaProgress:GetHighestLevelForDifficulty(_G.CSR_SelectedDifficulty)
		end
		return highest_for_difficulty >= (level * 4)
	end

	-- Vanilla costs (hardcoded — tweakdata is zeroed for free levels)
	-- Verified from in-game: level 20 = 21 coins → 6 + 20 * 0.75 = 21
	local VANILLA_INITIAL_COST = 6
	local VANILLA_COST_PER_LEVEL = 0.75
	local level_buttons_y = starting_level_y + 30
	local level_btn_h = 110
	local level_padding = 10

	-- Show 3 buttons out of 21 + "0" button on left + "MAX" button on right + arrows
	local visible_count = 3
	local current_scroll = 1  -- Index of first visible button

	_G.CSR_LevelButtons = {}
	_G.CSR_AllStartLevels = all_start_levels
	_G.CSR_CurrentScroll = current_scroll

	-- Width for 7 elements: [0] [<] [btn] [btn] [btn] [>] [MAX]
	-- Arrows are narrower (50%), all other buttons are equal width
	-- Formula: 5 regular + 2 arrows (0.5×) = 5W + 1W = 6W
	local total_width = self._levels_panel:w()
	local btn_width = (total_width - level_padding * 6) / 6.0  -- 5 regular + 2 arrows (0.5× each)
	local arrow_width = btn_width * 0.5

	-- Level button creation function
	local function create_level_button(level, x_pos, is_zero, is_max)
		-- Always use vanilla costs for display (tweakdata is zeroed for free start)
		local cost = is_zero and 0 or math.floor(VANILLA_INITIAL_COST + (level * VANILLA_COST_PER_LEVEL))
		local is_unlocked = is_zero or is_max or is_level_unlocked(level)

		local panel = self._levels_panel:panel({
			name = "level_button_" .. level,
			w = btn_width,
			h = level_btn_h,
			x = x_pos,
			y = level_buttons_y
		})

		-- Background (grey if locked)
		local bg_color = is_unlocked and Color.black or Color(0.3, 0.3, 0.3)
		local bg = panel:rect({
			name = "background",
			color = bg_color,
			alpha = 0.6,
			layer = 0
		})

		BoxGuiObject:new(panel, { sides = {1, 1, 1, 1} })

		local highlight = panel:rect({
			name = "highlight",
			color = Color.white,
			alpha = 0,
			layer = 1
		})

		local active_bg = panel:rect({
			name = "active_bg",
			color = tweak_data.screen_colors.crime_spree_risk or Color("66ccff"),
			alpha = 0.3,
			layer = 1,
			visible = false
		})

		-- Level text
		local level_display = is_max and ("MAX\n" .. level) or tostring(level)
		local level_text = panel:text({
			name = "level_text",
			text = level_display .. " \xEE\x80\x98",
			color = is_unlocked and Color.yellow or Color(0.5, 0.5, 0.5),
			font = tweak_data.menu.pd2_large_font,
			font_size = is_max and 24 or 32,
			align = "center",
			vertical = "center",
			layer = 2
		})

		-- Cost text: only shown for MAX (coin cost) and locked (reach requirement)
		local cost_display
		if is_max then
			cost_display = tostring(cost) .. " \xEE\x80\x9D"
		elseif not is_unlocked then
			local required = level * 4
			cost_display = "Reach " .. required
		else
			cost_display = ""
		end

		local cost_text = panel:text({
			name = "cost_text",
			text = cost_display,
			color = Color.white,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 14,
			align = "center",
			vertical = "bottom",
			layer = 2,
			y = 0,
			h = level_btn_h - 5
		})

		return {
			panel = panel,
			level = level,
			cost = cost,
			is_unlocked = is_unlocked,
			active_bg = active_bg,
			highlight = highlight,
			selected = false
		}
	end

	-- Arrow button creation function
	local function create_arrow_button(text, x_pos, direction, width)
		local panel = self._levels_panel:panel({
			name = "arrow_" .. direction,
			w = width,
			h = level_btn_h,
			x = x_pos,
			y = level_buttons_y
		})

		panel:rect({
			name = "background",
			color = Color.black,
			alpha = 0.4,
			layer = 0
		})

		BoxGuiObject:new(panel, { sides = {1, 1, 1, 1} })

		local highlight = panel:rect({
			name = "highlight",
			color = Color.white,
			alpha = 0,
			layer = 1
		})

		panel:text({
			name = "arrow_text",
			text = text,
			color = Color.white,
			font = tweak_data.menu.pd2_large_font,
			font_size = 48,
			align = "center",
			vertical = "center",
			layer = 2
		})

		return {
			panel = panel,
			highlight = highlight,
			direction = direction,
			selected = false
		}
	end

	-- Create "0" button on the left
	local x_pos = 0
	local zero_btn = create_level_button(0, x_pos, true, false)
	table.insert(_G.CSR_LevelButtons, zero_btn)
	x_pos = x_pos + btn_width + level_padding

	-- Create "<" arrow button (narrow)
	local left_arrow = create_arrow_button("<", x_pos, "left", arrow_width)
	_G.CSR_LeftArrow = left_arrow
	x_pos = x_pos + arrow_width + level_padding

	-- Create 3 center buttons (filled later)
	_G.CSR_VisibleButtons = {}
	for i = 1, visible_count do
		_G.CSR_VisibleButtons[i] = {
			panel = nil,  -- Created in update_visible_buttons
			x_pos = x_pos
		}
		x_pos = x_pos + btn_width + level_padding
	end

	-- Create ">" arrow button (narrow)
	local right_arrow = create_arrow_button(">", x_pos, "right", arrow_width)
	_G.CSR_RightArrow = right_arrow
	x_pos = x_pos + arrow_width + level_padding

	-- Store X position for MAX button
	local max_button_x = x_pos

	-- Create MAX button on the right (uses highest level for current difficulty)
	local highest_for_difficulty = 0
	if _G.CSR_MetaProgress and _G.CSR_MetaProgress.GetHighestLevelForDifficulty then
		highest_for_difficulty = _G.CSR_MetaProgress:GetHighestLevelForDifficulty(_G.CSR_SelectedDifficulty)
	end

	if highest_for_difficulty > 0 then
		local max_btn = create_level_button(highest_for_difficulty, max_button_x, false, true)
		table.insert(_G.CSR_LevelButtons, max_btn)
		_G.CSR_MaxButton = max_btn
	else
		_G.CSR_MaxButton = nil
	end

	-- Function to refresh visible buttons
	local function update_visible_buttons()
		-- CRITICAL: Check that panel still exists before proceeding
		if not self._levels_panel or not alive(self._levels_panel) then
			return
		end

		local scroll = _G.CSR_CurrentScroll or 1
		local all_levels = _G.CSR_AllStartLevels or {}

		for i = 1, visible_count do
			local level_index = scroll + i - 1
			if level_index <= #all_levels then
				local level = all_levels[level_index]
				local slot = _G.CSR_VisibleButtons[i]

				-- Remove old button if present
				if slot and slot.panel and slot.panel:alive() then
					self._levels_panel:remove(slot.panel)
				end

				-- Create new button
				local btn = create_level_button(level, slot.x_pos, false, false)
				slot.panel = btn.panel
				slot.level = level
				slot.cost = btn.cost
				slot.is_unlocked = btn.is_unlocked
				slot.active_bg = btn.active_bg
				slot.highlight = btn.highlight
				slot.selected = false
			end
		end

	end

	-- Initialize visible buttons
	update_visible_buttons()

	-- CRITICAL: Auto-select level 0 when menu opens (fix for 100-coins bug)
	if managers.crime_spree then
		managers.crime_spree:set_starting_level(0)
		_G.CSR_SelectedStartLevel = 0  -- Store for restoration on difficulty change

		-- Visually highlight the "0" button
		if zero_btn and zero_btn.active_bg and zero_btn.active_bg:alive() then
			zero_btn.active_bg:set_visible(true)
		end
	end

	-- Store function globally for click handlers
	_G.CSR_UpdateVisibleButtons = update_visible_buttons

	-- Function to refresh unlock status for all buttons (called on difficulty change)
	local function update_level_buttons_unlock_status()
		-- CRITICAL: Check that panel still exists
		if not self._levels_panel or not alive(self._levels_panel) then
			return
		end

		-- Get highest_level for the currently selected difficulty
		local highest_for_difficulty = 0
		if _G.CSR_MetaProgress and _G.CSR_MetaProgress.GetHighestLevelForDifficulty then
			highest_for_difficulty = _G.CSR_MetaProgress:GetHighestLevelForDifficulty(_G.CSR_SelectedDifficulty)
		end


		-- Update static buttons (0 and MAX)
		if _G.CSR_LevelButtons then
			for _, btn in ipairs(_G.CSR_LevelButtons) do
				if btn.panel and btn.panel:alive() and btn.level then
					local is_unlocked = (btn.level == 0) or (highest_for_difficulty >= (btn.level * 4))
					btn.is_unlocked = is_unlocked

					-- Update background color
					local bg = btn.panel:child("background")
					if bg and bg:alive() then
						local bg_color = is_unlocked and Color.black or Color(0.3, 0.3, 0.3)
						bg:set_color(bg_color)
					end

					-- Update level text color
					local level_text = btn.panel:child("level_text")
					if level_text and level_text:alive() then
						local text_color = is_unlocked and Color.yellow or Color(0.5, 0.5, 0.5)
						level_text:set_color(text_color)
					end

					-- Update cost text
					local cost_text = btn.panel:child("cost_text")
					if cost_text and cost_text:alive() then
						local is_max_button = (btn == _G.CSR_MaxButton)
						local cost_display
						if is_max_button then
							cost_display = tostring(btn.cost) .. " \xEE\x80\x9D"
						elseif not is_unlocked then
							local required = btn.level * 4
							cost_display = "Reach " .. required
						else
							cost_display = ""
						end
						cost_text:set_text(cost_display)
					end
				end
			end
		end

		-- Update visible (scrollable) buttons
		if _G.CSR_VisibleButtons then
			for _, slot in ipairs(_G.CSR_VisibleButtons) do
				if slot.panel and slot.panel:alive() and slot.level then
					local is_unlocked = highest_for_difficulty >= (slot.level * 4)
					slot.is_unlocked = is_unlocked

					-- Update background color
					local bg = slot.panel:child("background")
					if bg and bg:alive() then
						local bg_color = is_unlocked and Color.black or Color(0.3, 0.3, 0.3)
						bg:set_color(bg_color)
					end

					-- Update level text color
					local level_text = slot.panel:child("level_text")
					if level_text and level_text:alive() then
						local text_color = is_unlocked and Color.yellow or Color(0.5, 0.5, 0.5)
						level_text:set_color(text_color)
					end

					-- Update cost text
					local cost_text = slot.panel:child("cost_text")
					if cost_text and cost_text:alive() then
						local cost_display
						if not is_unlocked then
							local required = slot.level * 4
							cost_display = "Reach " .. required
						else
							cost_display = ""
						end
						cost_text:set_text(cost_display)
					end
				end
			end
		end

		-- Recreate MAX button if needed (highest_level changed)
		if _G.CSR_MaxButton then
			-- Remove old MAX button
			if _G.CSR_MaxButton.panel and _G.CSR_MaxButton.panel:alive() then
				self._levels_panel:remove(_G.CSR_MaxButton.panel)
			end
			-- Remove from button list
			for i, btn in ipairs(_G.CSR_LevelButtons) do
				if btn == _G.CSR_MaxButton then
					table.remove(_G.CSR_LevelButtons, i)
					break
				end
			end
			_G.CSR_MaxButton = nil
		end

		-- Create new MAX button if there is progress
		if highest_for_difficulty > 0 then
			local max_btn = create_level_button(highest_for_difficulty, max_button_x, false, true)
			table.insert(_G.CSR_LevelButtons, max_btn)
			_G.CSR_MaxButton = max_btn
		end

	end

	-- Store globally to call on difficulty change
	_G.CSR_UpdateLevelButtonsUnlockStatus = update_level_buttons_unlock_status


	-- Update reward text for the currently selected difficulty
	local function update_reward_display(difficulty_id)
		if not reward_display or not reward_display:alive() then
			return
		end

		-- Find difficulty data
		local reward_ui = "STANDARD REWARDS"
		for _, diff in ipairs(difficulties) do
			if diff.id == difficulty_id then
				reward_ui = diff.reward_ui
				break
			end
		end

		reward_display:set_text(reward_ui)
	end

	-- Initialize reward text for the current difficulty
	update_reward_display(_G.CSR_SelectedDifficulty)

	-- Store function globally for updating
	_G.CSR_UpdateRewardDisplay = update_reward_display

end)

-- Hook on mouse move to set the selected state (WITH parameter o!)
Hooks:PostHook(CrimeSpreeContractMenuComponent, "mouse_moved", "CSR_DifficultyButtonHover", function(self, o, x, y)
	if not x or not y then
		return
	end

	local any_selected = false

	-- Check hover over DIFFICULTY buttons
	if CSR_DifficultyButtons then
		for idx, btn in ipairs(CSR_DifficultyButtons) do
			if btn.panel and btn.panel:alive() then
				local panel_x, panel_y = btn.panel:world_position()
				local panel_w = btn.panel:w()
				local panel_h = btn.panel:h()

				local inside = x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h
				btn.selected = inside

				if inside then
					any_selected = true
				end

				if btn.highlight and btn.highlight:alive() then
					btn.highlight:set_alpha(inside and 0.2 or 0)
				end
			end
		end
	end

	-- Check hover over LEVEL buttons
	if CSR_LevelButtons then
		for idx, btn in ipairs(CSR_LevelButtons) do
			if btn.panel and btn.panel:alive() then
				local panel_x, panel_y = btn.panel:world_position()
				local panel_w = btn.panel:w()
				local panel_h = btn.panel:h()

				local inside = x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h
				btn.selected = inside

				if inside then
					any_selected = true
				end

				if btn.highlight and btn.highlight:alive() then
					btn.highlight:set_alpha(inside and 0.2 or 0)
				end
			end
		end
	end

	-- Check hover over ARROW buttons
	if _G.CSR_LeftArrow and _G.CSR_LeftArrow.panel and _G.CSR_LeftArrow.panel:alive() then
		local panel_x, panel_y = _G.CSR_LeftArrow.panel:world_position()
		local panel_w = _G.CSR_LeftArrow.panel:w()
		local panel_h = _G.CSR_LeftArrow.panel:h()
		local inside = x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h
		_G.CSR_LeftArrow.selected = inside
		if inside then any_selected = true end
		if _G.CSR_LeftArrow.highlight and _G.CSR_LeftArrow.highlight:alive() then
			_G.CSR_LeftArrow.highlight:set_alpha(inside and 0.2 or 0)
		end
	end

	if _G.CSR_RightArrow and _G.CSR_RightArrow.panel and _G.CSR_RightArrow.panel:alive() then
		local panel_x, panel_y = _G.CSR_RightArrow.panel:world_position()
		local panel_w = _G.CSR_RightArrow.panel:w()
		local panel_h = _G.CSR_RightArrow.panel:h()
		local inside = x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h
		_G.CSR_RightArrow.selected = inside
		if inside then any_selected = true end
		if _G.CSR_RightArrow.highlight and _G.CSR_RightArrow.highlight:alive() then
			_G.CSR_RightArrow.highlight:set_alpha(inside and 0.2 or 0)
		end
	end

	-- Check hover over VISIBLE (scrollable) BUTTONS
	if _G.CSR_VisibleButtons then
		for _, slot in ipairs(_G.CSR_VisibleButtons) do
			if slot.panel and slot.panel:alive() then
				local panel_x, panel_y = slot.panel:world_position()
				local panel_w = slot.panel:w()
				local panel_h = slot.panel:h()
				local inside = x >= panel_x and x <= panel_x + panel_w and y >= panel_y and y <= panel_y + panel_h
				slot.selected = inside
				if inside then any_selected = true end
				if slot.highlight and slot.highlight:alive() then
					slot.highlight:set_alpha(inside and 0.2 or 0)
				end
			end
		end
	end

	-- Return true and "link" to change cursor to pointer
	if any_selected then
		return true, "link"
	end
end)

-- Hook on mouse click (WITHOUT parameter o!)
Hooks:PostHook(CrimeSpreeContractMenuComponent, "mouse_pressed", "CSR_DifficultyButtonClick", function(self, button, x, y)
	if button ~= Idstring("0") then  -- Left mouse button
		return
	end

	-- Handle clicks on DIFFICULTY buttons
	if CSR_DifficultyButtons then
		for _, btn in ipairs(CSR_DifficultyButtons) do
			if btn.selected and btn.panel and btn.panel:alive() then
				-- Deselect all buttons
				for _, other_btn in ipairs(CSR_DifficultyButtons) do
					if other_btn.active_bg and other_btn.active_bg:alive() then
						other_btn.active_bg:set_visible(false)
					end
				end

				-- Highlight selected button
				if btn.active_bg and btn.active_bg:alive() then
					btn.active_bg:set_visible(true)
				end

				-- Store selected difficulty
				_G.CSR_SelectedDifficulty = btn.difficulty

				-- CRITICAL: Save to Crime Spree Global (in BOTH places!)
				if managers.crime_spree and managers.crime_spree._global then
					managers.crime_spree._global.selected_difficulty = btn.difficulty
				end

				-- CRITICAL: Also save to Global.crime_spree (for _setup_global_from_mission_id)
				if Global and Global.crime_spree then
					Global.crime_spree.selected_difficulty = btn.difficulty
				end

				-- CRITICAL: Update seed file with difficulty
				if CSR_CurrentSeed and CSR_SaveSeed then
					CSR_SaveSeed(CSR_CurrentSeed, btn.difficulty)

					-- REGENERATE modifiers with new difficulty!
					if CSR_RegenerateForcedModifiers then
						CSR_RegenerateForcedModifiers(CSR_CurrentSeed, btn.difficulty)
					end
				end

				-- Update reward text
				if _G.CSR_UpdateRewardDisplay then
					_G.CSR_UpdateRewardDisplay(btn.difficulty)
				end

				-- CRITICAL: Update unlock status for level buttons
				if _G.CSR_UpdateLevelButtonsUnlockStatus then
					_G.CSR_UpdateLevelButtonsUnlockStatus()
				end

				-- CRITICAL FIX: Restore the selected starting level after difficulty change
				-- Without this, vanilla sets wrong values (100 on Overkill, 200 on Mayhem, etc.)
				-- Also reset to 0 if the selected level is not unlocked for the new difficulty
				if managers.crime_spree then
					local restore_level = _G.CSR_SelectedStartLevel or 0
					if restore_level > 0 then
						local highest = 0
						if _G.CSR_MetaProgress and _G.CSR_MetaProgress.GetHighestLevelForDifficulty then
							highest = _G.CSR_MetaProgress:GetHighestLevelForDifficulty(btn.difficulty)
						end
						if highest < (restore_level * 4) then
							restore_level = 0
							_G.CSR_SelectedStartLevel = 0
							-- Update UI: deselect all level buttons, re-highlight level 0
							if CSR_LevelButtons then
								for _, other_btn in ipairs(CSR_LevelButtons) do
									if other_btn.active_bg and other_btn.active_bg:alive() then
										other_btn.active_bg:set_visible(other_btn.level == 0)
									end
								end
							end
							if _G.CSR_VisibleButtons then
								for _, other_slot in ipairs(_G.CSR_VisibleButtons) do
									if other_slot.active_bg and other_slot.active_bg:alive() then
										other_slot.active_bg:set_visible(false)
									end
								end
							end
						end
					end
					managers.crime_spree:set_starting_level(restore_level)
				end

				-- Sound
				managers.menu_component:post_event("menu_enter")
				return true
			end
		end
	end

	-- Handle clicks on ARROW buttons
	if _G.CSR_LeftArrow and _G.CSR_LeftArrow.selected and _G.CSR_LeftArrow.panel and _G.CSR_LeftArrow.panel:alive() then
		-- Set held flag
		_G.CSR_ArrowHeld = "left"
		_G.CSR_ArrowHoldTime = 0
		_G.CSR_ArrowLastScroll = 0

		-- Scroll back immediately (first click)
		if _G.CSR_CurrentScroll > 1 then
			_G.CSR_CurrentScroll = _G.CSR_CurrentScroll - 1
			if _G.CSR_UpdateVisibleButtons then
				_G.CSR_UpdateVisibleButtons()
			end
			managers.menu_component:post_event("menu_enter")
		else
			managers.menu_component:post_event("menu_error")
		end
		return true
	end

	if _G.CSR_RightArrow and _G.CSR_RightArrow.selected and _G.CSR_RightArrow.panel and _G.CSR_RightArrow.panel:alive() then
		-- Set held flag
		_G.CSR_ArrowHeld = "right"
		_G.CSR_ArrowHoldTime = 0
		_G.CSR_ArrowLastScroll = 0

		-- Scroll forward immediately (first click)
		local max_scroll = math.max(1, #_G.CSR_AllStartLevels - 2)
		if _G.CSR_CurrentScroll < max_scroll then
			_G.CSR_CurrentScroll = _G.CSR_CurrentScroll + 1
			if _G.CSR_UpdateVisibleButtons then
				_G.CSR_UpdateVisibleButtons()
			end
			managers.menu_component:post_event("menu_enter")
		else
			managers.menu_component:post_event("menu_error")
		end
		return true
	end

	-- Handle clicks on LEVEL buttons
	if CSR_LevelButtons then
		for _, btn in ipairs(CSR_LevelButtons) do
			if btn.selected and btn.panel and btn.panel:alive() then

				-- Guard: check if level is unlocked
				if not btn.is_unlocked then
					managers.menu_component:post_event("menu_error")
					return true
				end

				local is_max_button = (btn == _G.CSR_MaxButton)

				if is_max_button then
					-- Restore vanilla costs so the lobby creation deducts correctly
					-- (costs stay restored until enable_crime_spree fires and resets them)
					tweak_data.crime_spree.initial_cost = 6
					tweak_data.crime_spree.cost_per_level = 0.75
				else
					-- Ensure costs are zeroed for free levels
					tweak_data.crime_spree.initial_cost = 0
					tweak_data.crime_spree.cost_per_level = 0
				end

				if managers.crime_spree then
					managers.crime_spree:set_starting_level(btn.level)
					_G.CSR_SelectedStartLevel = btn.level
				end

				-- Sound
				managers.menu_component:post_event("menu_enter")

				-- Deselect all static buttons
				for _, other_btn in ipairs(CSR_LevelButtons) do
					if other_btn.active_bg and other_btn.active_bg:alive() then
						other_btn.active_bg:set_visible(false)
					end
				end

				-- Deselect all visible buttons
				if _G.CSR_VisibleButtons then
					for _, other_slot in ipairs(_G.CSR_VisibleButtons) do
						if other_slot.active_bg and other_slot.active_bg:alive() then
							other_slot.active_bg:set_visible(false)
						end
					end
				end

				-- Highlight the selected button
				if btn.active_bg and btn.active_bg:alive() then
					btn.active_bg:set_visible(true)
				end

				return true
			end
		end
	end

	-- Handle clicks on VISIBLE (scrollable) BUTTONS (center 3)
	if _G.CSR_VisibleButtons then
		for _, slot in ipairs(_G.CSR_VisibleButtons) do
			if slot.selected and slot.panel and slot.panel:alive() and slot.level then

				-- Guard: check if level is unlocked
				if not slot.is_unlocked then
					managers.menu_component:post_event("menu_error")
					return true
				end

				-- Explicitly zero costs -- if MAX was previously selected, tweakdata may still be at vanilla values
				tweak_data.crime_spree.initial_cost = 0
				tweak_data.crime_spree.cost_per_level = 0

				if managers.crime_spree then
					managers.crime_spree:set_starting_level(slot.level)
					_G.CSR_SelectedStartLevel = slot.level  -- Store for restoration on difficulty change
				end

				-- Deselect all static buttons (0, MAX)
				if CSR_LevelButtons then
					for _, other_btn in ipairs(CSR_LevelButtons) do
						if other_btn.active_bg and other_btn.active_bg:alive() then
							other_btn.active_bg:set_visible(false)
						end
					end
				end

				-- Deselect all visible buttons
				for _, other_slot in ipairs(_G.CSR_VisibleButtons) do
					if other_slot.active_bg and other_slot.active_bg:alive() then
						other_slot.active_bg:set_visible(false)
					end
				end

				-- Highlight selected button
				if slot.active_bg and slot.active_bg:alive() then
					slot.active_bg:set_visible(true)
				end

				managers.menu_component:post_event("menu_enter")
				return true
			end
		end
	end
end)

-- Hook on mouse button release - stop auto-scroll
Hooks:PostHook(CrimeSpreeContractMenuComponent, "mouse_released", "CSR_ArrowReleased", function(self, button, x, y)
	if button == Idstring("0") then  -- Left mouse button
		-- Reset held flag
		_G.CSR_ArrowHeld = nil
		_G.CSR_ArrowHoldTime = 0
		_G.CSR_ArrowLastScroll = 0
	end
end)

-- Hook on update for auto-scrolling while arrow is held
Hooks:PostHook(CrimeSpreeContractMenuComponent, "update", "CSR_ArrowAutoScroll", function(self, t, dt)
	if not _G.CSR_ArrowHeld then
		return
	end

	-- CRITICAL: Check that panel still exists
	if not self._levels_panel or not alive(self._levels_panel) then
		_G.CSR_ArrowHeld = nil
		return
	end

	-- CRITICAL: Check that mouse button is STILL held
	local is_mouse_down = false

	-- Check left mouse button state via Input (down = held, not pressed = moment of press)
	if Input and Input.mouse then
		local mouse = Input:mouse()
		if mouse and mouse.down then
			is_mouse_down = mouse:down(Idstring("0"))  -- 0 = LMB
		end
	end

	-- If button was released, reset flag
	if not is_mouse_down then
		_G.CSR_ArrowHeld = nil
		_G.CSR_ArrowHoldTime = 0
		_G.CSR_ArrowLastScroll = 0
		return
	end

	-- Check that arrow is still under the cursor
	local arrow = _G.CSR_ArrowHeld == "left" and _G.CSR_LeftArrow or _G.CSR_RightArrow
	if not arrow or not arrow.selected then
		_G.CSR_ArrowHeld = nil
		_G.CSR_ArrowHoldTime = 0
		_G.CSR_ArrowLastScroll = 0
		return
	end

	-- Increment hold time
	_G.CSR_ArrowHoldTime = _G.CSR_ArrowHoldTime + dt

	-- Delay before auto-scroll starts (0.3 seconds)
	local initial_delay = 0.3
	if _G.CSR_ArrowHoldTime < initial_delay then
		return
	end

	-- Interval between auto-scroll ticks (0.1 seconds)
	local scroll_interval = 0.1
	if _G.CSR_ArrowHoldTime - _G.CSR_ArrowLastScroll < scroll_interval then
		return
	end

	-- Update last scroll timestamp
	_G.CSR_ArrowLastScroll = _G.CSR_ArrowHoldTime

	-- Perform scroll in the held direction
	if _G.CSR_ArrowHeld == "left" then
		if _G.CSR_CurrentScroll > 1 then
			_G.CSR_CurrentScroll = _G.CSR_CurrentScroll - 1
			if _G.CSR_UpdateVisibleButtons then
				_G.CSR_UpdateVisibleButtons()
			end
			managers.menu_component:post_event("menu_enter")
		end
	elseif _G.CSR_ArrowHeld == "right" then
		local max_scroll = math.max(1, #_G.CSR_AllStartLevels - 2)
		if _G.CSR_CurrentScroll < max_scroll then
			_G.CSR_CurrentScroll = _G.CSR_CurrentScroll + 1
			if _G.CSR_UpdateVisibleButtons then
				_G.CSR_UpdateVisibleButtons()
			end
			managers.menu_component:post_event("menu_enter")
		end
	end
end)

-- Hook on menu close - reset auto-scroll state
Hooks:PostHook(CrimeSpreeContractMenuComponent, "close", "CSR_CleanupAutoScroll", function(self)
	-- Reset auto-scroll flag to avoid crashes after menu closes
	_G.CSR_ArrowHeld = nil
	_G.CSR_ArrowHoldTime = 0
	_G.CSR_ArrowLastScroll = 0
end)

