-- Crime Spree Roguelike - Bonus Drop Bar (R6S Alpha Pack style)
-- Thin bar with a "drop zone" chunk proportional to the accumulated chance.
-- An arrow sweeps across and either lands inside the zone (item drop) or misses.
-- Shown on the stage-end screen after rank bonuses finish counting.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("[CSR BonusDrop] Bonus wheel popup module loaded")

-- Rarity colors
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 0.95, 0),
	rare = Color(0.3, 0.7, 1),
}

local RARITY_LABELS = {
	common = "COMMON",
	uncommon = "UNCOMMON",
	rare = "RARE",
}

-- === BAR POPUP CLASS ===
CSRBonusDropBar = CSRBonusDropBar or class()

-- @param won        boolean   — did the roll succeed?
-- @param chance     number    — total chance (0.0–1.0) at time of roll
-- @param winner     table|nil — registry item if won
function CSRBonusDropBar:init(won, chance, winner)
	self._won = won
	self._chance = math.min(chance or 0.01, 1.0)
	self._winner = winner
	self._closed = false

	-- Create fullscreen workspace
	self._ws = managers.gui_data:create_fullscreen_workspace()
	if not self._ws then
		return
	end

	local root = self._ws:panel()

	-- Backdrop (light dim)
	self._backdrop = root:rect({
		name = "csr_drop_backdrop",
		color = Color.black,
		alpha = 0,
		layer = 1100,
		w = root:w(),
		h = root:h(),
	})

	-- Main panel
	local panel_w = 500
	local panel_h = 200
	self._panel = root:panel({
		name = "csr_drop_panel",
		w = panel_w,
		h = panel_h,
		layer = 1200,
	})
	self._panel:set_center(root:center())
	self._panel:set_alpha(0)

	-- Background
	self._panel:rect({ color = Color.black, alpha = 0.92, layer = 0 })
	if BoxGuiObject then
		pcall(function()
			BoxGuiObject:new(self._panel, { sides = { 2, 2, 2, 2 } })
		end)
	end

	-- Title
	self._panel:text({
		text = "BONUS DROP",
		font = tweak_data.menu.pd2_large_font,
		font_size = 26,
		color = Color(1, 0.85, 0.1),
		align = "center",
		x = 0,
		y = 10,
		w = panel_w,
		h = 30,
		layer = 10,
	})

	-- Help "?" button (top-left corner)
	local help_btn = self._panel:text({
		name = "csr_drop_help_btn",
		text = "?",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = Color(0.5, 0.5, 0.5),
		align = "center",
		vertical = "center",
		x = 6,
		y = 6,
		w = 22,
		h = 22,
		layer = 15,
	})

	-- Tooltip panel (hidden by default)
	local tip_text =
		"Collect instant cash from loot and kills\nto increase your chance of a bonus item.\nChance carries over between missions."
	self._help_tip = self._panel:text({
		name = "csr_drop_help_tip",
		text = tip_text,
		font = tweak_data.menu.pd2_small_font,
		font_size = 14,
		color = Color(0.85, 0.85, 0.85),
		x = 6,
		y = 30,
		w = 260,
		h = 60,
		wrap = true,
		word_wrap = true,
		layer = 20,
		alpha = 0,
	})
	self._help_tip_bg = self._panel:rect({
		name = "csr_drop_help_tip_bg",
		x = 4,
		y = 28,
		w = 264,
		h = 64,
		color = Color.black,
		alpha = 0,
		layer = 19,
	})
	self._help_btn = help_btn

	-- Chance label (e.g. "11.5%")
	self._chance_text = self._panel:text({
		text = string.format("%.1f%%", self._chance * 100),
		font = tweak_data.menu.pd2_small_font,
		font_size = 16,
		color = Color(0.9, 0.9, 0.9),
		align = "center",
		x = 0,
		y = 36,
		w = panel_w,
		h = 18,
		layer = 10,
	})

	-- === THE BAR ===
	local bar_x = 40
	local bar_y = 62
	local bar_w = panel_w - 80
	local bar_h = 12

	-- Bar background (thin line)
	self._panel:rect({
		x = bar_x,
		y = bar_y,
		w = bar_w,
		h = bar_h,
		color = Color(0.15, 0.15, 0.15),
		layer = 2,
	})

	-- Bar outline
	self._panel:rect({ x = bar_x, y = bar_y, w = bar_w, h = 1, color = Color(0.3, 0.3, 0.3), layer = 3 })
	self._panel:rect({ x = bar_x, y = bar_y + bar_h - 1, w = bar_w, h = 1, color = Color(0.3, 0.3, 0.3), layer = 3 })

	-- Drop zone (thick bright chunk) — positioned randomly along the bar
	local zone_w = math.max(8, math.floor(bar_w * self._chance))
	local max_zone_x = bar_w - zone_w
	local zone_offset = math.random(0, math.max(0, max_zone_x))

	self._zone_start = bar_x + zone_offset
	self._zone_end = self._zone_start + zone_w

	-- The bright chunk
	self._panel:rect({
		x = self._zone_start,
		y = bar_y - 2,
		w = zone_w,
		h = bar_h + 4,
		color = Color(1, 0.85, 0.1),
		alpha = 0.9,
		layer = 4,
	})

	-- === ARROW / POINTER ===
	local arrow_h = bar_h + 16
	local arrow_y = bar_y - 8
	self._arrow = self._panel:rect({
		name = "csr_drop_arrow",
		x = bar_x,
		y = arrow_y,
		w = 3,
		h = arrow_h,
		color = Color.white,
		layer = 8,
	})

	-- Arrow glow
	self._arrow_glow = self._panel:rect({
		name = "csr_drop_arrow_glow",
		x = bar_x - 2,
		y = arrow_y,
		w = 7,
		h = arrow_h,
		color = Color.white,
		alpha = 0.3,
		layer = 7,
	})

	-- Store bar geometry for animation
	self._bar_x = bar_x
	self._bar_w = bar_w
	self._bar_y = bar_y

	-- Result: item name (rarity colored)
	self._result_text = self._panel:text({
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = Color.white,
		align = "center",
		x = 0,
		y = bar_y + bar_h + 14,
		w = panel_w,
		h = 28,
		layer = 10,
		alpha = 0,
	})

	-- Result: item description (white, below name)
	self._result_desc = self._panel:text({
		text = "",
		font = tweak_data.menu.pd2_small_font,
		font_size = 15,
		color = Color(0.75, 0.75, 0.75),
		align = "center",
		x = 20,
		y = bar_y + bar_h + 40,
		w = panel_w - 40,
		h = 50,
		wrap = true,
		word_wrap = true,
		layer = 10,
		alpha = 0,
	})

	-- Dismiss hint (hidden)
	self._dismiss_text = self._panel:text({
		text = "Click to continue",
		font = tweak_data.menu.pd2_small_font,
		font_size = 14,
		color = Color(0.4, 0.4, 0.4),
		align = "center",
		x = 0,
		y = panel_h - 26,
		w = panel_w,
		h = 18,
		layer = 10,
		alpha = 0,
	})

	-- Save global reference
	_G.CSR_BonusDropBarInstance = self

	-- Register input hook
	Hooks:Add("GameSetupUpdate", "CSR_BonusDropBar_Update", function(t, dt)
		local inst = _G.CSR_BonusDropBarInstance
		if not inst or inst._closed then
			return
		end

		-- Help tooltip hover check using panel:inside() with fullscreen 16:9 mouse coords
		if inst._help_btn and alive(inst._help_btn) and inst._help_tip then
			local hovering = false
			pcall(function()
				local mx, my = managers.mouse_pointer:modified_fullscreen_16_9_mouse_pos()
				hovering = inst._help_btn:inside(mx, my)
			end)
			inst._help_tip:set_alpha(hovering and 1 or 0)
			inst._help_tip_bg:set_alpha(hovering and 0.9 or 0)
		end

		if not inst._can_dismiss then
			return
		end

		local dismiss = false
		if Input:keyboard() and Input:keyboard():pressed(Idstring("esc")) then
			dismiss = true
			pcall(function()
				Input:keyboard():clear_key_state(Idstring("esc"))
			end)
		end
		if Input:mouse() and Input:mouse():pressed(Idstring("0")) then
			dismiss = true
		end

		if dismiss then
			inst:close()
		end
	end)

	-- Start animation
	self:_animate()
end

function CSRBonusDropBar:_animate()
	local panel = self._panel
	local backdrop = self._backdrop
	local arrow = self._arrow
	local arrow_glow = self._arrow_glow
	local result_text = self._result_text
	local result_desc = self._result_desc
	local dismiss_text = self._dismiss_text
	local self_ref = self

	local bar_x = self._bar_x
	local bar_w = self._bar_w
	local won = self._won
	local winner = self._winner

	-- Calculate target position as fraction of bar (0.0 = left edge, 1.0 = right edge)
	local target_frac
	if won then
		-- Land inside the drop zone
		local zone_left = self._zone_start - bar_x
		local zone_right = self._zone_end - bar_x
		local margin = math.min(4, (zone_right - zone_left) * 0.2)
		target_frac = (zone_left + margin + math.random() * math.max(0, zone_right - zone_left - margin * 2)) / bar_w
	else
		-- Land outside the drop zone
		local zone_left_frac = (self._zone_start - bar_x) / bar_w
		local zone_right_frac = (self._zone_end - bar_x) / bar_w
		local margin = 0.03
		-- Pick a random spot that's NOT inside the zone
		if zone_left_frac > margin * 2 and zone_right_frac < 1 - margin * 2 then
			-- Zone is in the middle — pick left or right randomly
			if math.random() < 0.5 then
				target_frac = math.random() * (zone_left_frac - margin)
			else
				target_frac = zone_right_frac + margin + math.random() * (1 - zone_right_frac - margin)
			end
		elseif zone_left_frac > margin * 2 then
			target_frac = math.random() * (zone_left_frac - margin)
		else
			target_frac = zone_right_frac + margin + math.random() * math.max(0, 1 - zone_right_frac - margin)
		end
		target_frac = math.max(0, math.min(1, target_frac))
	end

	-- Total distance in "bar widths" the arrow will travel (multiple full passes + final position)
	local full_passes = 2 + math.random(0, 1) -- 2-3 full left-to-right passes
	local total_distance = full_passes + target_frac

	panel:animate(function(o)
		-- Fade in
		over(0.4, function(p)
			backdrop:set_alpha(p * 0.5)
			panel:set_alpha(p)
		end)

		-- Arrow sweep: left-to-right spinner with deceleration
		-- Arrow starts at left edge, sweeps right, wraps to left, repeats, slows down, stops
		local duration = 4.0
		arrow:set_x(bar_x - 1)
		arrow_glow:set_x(bar_x - 3)

		over(duration, function(p)
			-- Cubic ease-out for deceleration (fast start, slow finish)
			local eased = 1 - math.pow(1 - p, 3)
			-- Current distance traveled (in bar widths)
			local dist = eased * total_distance
			-- Current position within bar (wrap around using modulo)
			local frac = dist % 1.0
			local x = bar_x + frac * bar_w
			arrow:set_x(x - 1)
			arrow_glow:set_x(x - 3)
		end)

		-- Brief pause before result
		wait(0.4)

		-- Show result
		if won and winner then
			local rarity_color = RARITY_COLORS[winner.rarity] or Color.white
			local rarity_label = RARITY_LABELS[winner.rarity] or "ITEM"

			-- Get name and description from localization (format: "NAME\nDESC")
			local item_name = winner.type
			local item_desc = ""
			if managers.localization then
				local full_text = managers.localization:text(winner.loc_key)
				local nl = full_text:find("\n")
				if nl then
					item_name = full_text:sub(1, nl - 1)
					item_desc = full_text:sub(nl + 1)
				else
					item_name = full_text
				end
			end

			result_text:set_text(rarity_label .. " - " .. item_name)
			result_text:set_color(rarity_color)

			if item_desc ~= "" then
				result_desc:set_text(item_desc)
			end

			-- Flash the arrow gold
			arrow:set_color(Color(1, 0.85, 0.1))
			arrow_glow:set_color(Color(1, 0.85, 0.1))
			arrow_glow:set_alpha(0.6)
		else
			result_text:set_text("No luck... chance saved!")
			result_text:set_color(Color(0.85, 0.85, 0.85))

			-- Dim the arrow
			arrow:set_color(Color(0.4, 0.4, 0.4))
			arrow_glow:set_alpha(0.1)
		end

		over(0.3, function(p)
			result_text:set_alpha(p)
			result_desc:set_alpha(p)
			dismiss_text:set_alpha(p * 0.5)
		end)

		self_ref._can_dismiss = true
	end)
end

function CSRBonusDropBar:close()
	if self._closed then
		return
	end
	self._closed = true

	_G.CSR_BonusDropBarInstance = nil
	_G.CSR_BonusDropResult = nil

	Hooks:Remove("CSR_BonusDropBar_Update")

	if self._ws then
		local panel = self._panel
		local backdrop = self._backdrop
		local ws = self._ws

		panel:animate(function(o)
			over(0.2, function(p)
				panel:set_alpha(1 - p)
				backdrop:set_alpha(0.5 * (1 - p))
			end)
			managers.gui_data:destroy_workspace(ws)
		end)
	end
end

-- === TRIGGER: Show bonus drop bar BEFORE rank animation ===
-- Bar appears immediately (after forced mods popup if any), rank animation waits for it.
-- NOTE: This PostHook fires EVERY FRAME (vanilla animate coroutine). Must only schedule once.
Hooks:PostHook(CrimeSpreeResultTabItem, "_update_gain_calculate", "CSR_ScheduleBonusDropBar", function(self)
	-- Only schedule once per result screen
	if self._csr_drop_scheduled then
		return
	end

	if not self:success() then
		return
	end
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end

	-- Read the roll result
	local won = _G.CSR_BonusDropResult ~= nil
	local chance = _G.CSR_LastDropChance or (_G.CSR_BonusDropChance or 0.01)
	local winner = _G.CSR_BonusDropResult

	-- Skip if no mission cash was collected (no roll happened)
	if not _G.CSR_LastDropChance then
		return
	end

	-- Mark as scheduled so we don't repeat every frame
	self._csr_drop_scheduled = true

	CSR_log("[CSR BonusDrop] Scheduling bar (before rank animation)")

	-- Signal that bonus drop is about to appear (so rank animation waits)
	_G.CSR_BonusDropPending = true

	-- Small delay for screen to settle, then show (or wait for forced mods first)
	DelayedCalls:Add("CSR_ShowBonusDropBar", 0.8, function()
		if _G.CSR_BonusDropBarInstance then
			return
		end

		-- Wait for forced mods popup to close first
		if _G.CSR_ForcedModsPending or _G.CSR_ForcedModsNotificationInstance then
			CSR_log("[CSR BonusDrop] Forced mods popup active, waiting...")
			local attempts = 0
			local function check_and_show()
				attempts = attempts + 1
				if (_G.CSR_ForcedModsPending or _G.CSR_ForcedModsNotificationInstance) and attempts < 120 then
					DelayedCalls:Add("CSR_WaitForForcedModsThenDrop", 0.5, check_and_show)
				else
					if _G.CSR_BonusDropBarInstance then
						return
					end
					_G.CSR_BonusDropPending = false
					CSRBonusDropBar:new(won, chance, winner)
					_G.CSR_LastDropChance = nil
				end
			end
			check_and_show()
			return
		end

		_G.CSR_BonusDropPending = false
		CSRBonusDropBar:new(won, chance, winner)
		_G.CSR_LastDropChance = nil
	end)
end)
