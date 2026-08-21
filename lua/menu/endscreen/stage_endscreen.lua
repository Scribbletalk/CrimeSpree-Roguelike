-- Fork of vanilla StageEndScreenGui + CrimeSpreeResultTabItem.
-- 6 is_active() gates forced unconditional; reward/timeline panels dropped; rank gain replaces spree-level gain.

local padding = 10

-- =====================================================================
-- CSRCrimeSpreeResultTabItem — rank-gain panel only; reward-card and timeline dropped.
-- =====================================================================

CSRCrimeSpreeResultTabItem = CSRCrimeSpreeResultTabItem or class(StatsTabItem)

-- Verbatim vanilla init; calls our trimmed _setup() instead of vanilla's.
function CSRCrimeSpreeResultTabItem:init(panel, tab_panel, text, i)
	self._main_panel = panel
	self._tab_panel = tab_panel
	self._panel = self._main_panel:panel({
		h = self._main_panel:h() - 70,
	})
	self._index = i
	local prev_item_title_text = tab_panel:child("tab_text_" .. tostring(i - 1))
	local offset = prev_item_title_text and prev_item_title_text:right() or 0
	self._tab_text = tab_panel:text({
		vertical = "center",
		h = 32,
		blend_mode = "add",
		align = "center",
		layer = 1,
		name = "tab_text_" .. tostring(self._index),
		text = text,
		x = offset + 5,
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		color = tweak_data.screen_colors.button_stage_3,
	})
	local x, y, w, h = self._tab_text:text_rect()

	self._tab_text:set_size(w + 15, h + 10)

	self._select_rect = tab_panel:bitmap({
		texture = "guis/textures/pd2/shared_tab_box",
		visible = false,
		layer = 0,
		name = "tab_select_rect_" .. tostring(self._index),
		color = tweak_data.screen_colors.text,
	})

	self._select_rect:set_shape(self._tab_text:shape())
	self._panel:set_top(self._tab_text:bottom() - 2)
	self._panel:grow(0, -self._panel:y())
	self:deselect()
	self:_setup()
end

function CSRCrimeSpreeResultTabItem:_setup()
	self._cs_panel = self._panel:panel({
		w = self._panel:w() - padding * 2,
		h = self._panel:h() - padding * 2,
		x = padding,
		y = padding,
	})

	-- Gain display disabled (kept): reward panel owns the count-up. Re-enable: _update_gain_calculate.
	-- self:_create_level(0.75)
	self:_create_reward_panel()
	-- Reward cards disabled (kept). Re-enable here + in the stages table below.
	-- self:_create_rewards(0.75)
end

-- Failure branches kept as defensive mirror of vanilla (kicked / server left edge case).
function CSRCrimeSpreeResultTabItem:success()
	return managers.job:stage_success()
end

function CSRCrimeSpreeResultTabItem:make_fine_text(text)
	local x, y, w, h = text:text_rect()

	text:set_size(w, h)
	text:set_position(math.round(text:x()), math.round(text:y()))

	return x, y, w, h
end

-- Animates length-scaled rank gain (short=1, medium=2, long=3) instead of vanilla spree-level gain.
function CSRCrimeSpreeResultTabItem:_create_level(total_w)
	self._level_panel = self._cs_panel:panel({})

	local rank_gain = 0
	if managers.csr and managers.csr.rank_for_current_level then
		rank_gain = managers.csr:rank_for_current_level() or 1
	end

	local gain_x = self._level_panel:w() * (1 - total_w) * 0.5
	local gain_y = self._level_panel:h() * 0.25
	local gain_text = "+"
		.. managers.localization:text("menu_cs_level", {
			level = managers.experience:cash_string(0, ""),
		})
	local gain_color = self:success() and tweak_data.screen_colors.crime_spree_risk
		or tweak_data.screen_colors.important_1

	if not self:success() then
		gain_text = managers.localization:get_default_macro("BTN_SKULL")
	end

	local gain = self._level_panel:text({
		w = 200,
		vertical = "center",
		name = "gain",
		align = "center",
		blend_mode = "add",
		alpha = 0,
		layer = 10,
		text = gain_text,
		h = tweak_data.menu.pd2_large_font_size,
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = gain_color,
	})

	gain:set_center_x(gain_x)
	gain:set_center_y(gain_y)

	self._levels = {
		gain = gain,
		bonuses = {},
	}

	local function add_bonus(text, level, color)
		local font = tweak_data.menu.pd2_small_font
		local font_size = tweak_data.menu.pd2_small_font_size
		local bonus = self._level_panel:text({
			blend_mode = "add",
			vertical = "center",
			alpha = 0,
			align = "center",
			layer = 10,
			text = text or "",
			h = font_size,
			font_size = font_size,
			font = font,
			color = color or tweak_data.screen_colors.crime_spree_risk,
		})

		self:make_fine_text(bonus)
		bonus:set_center_x(gain_x)
		bonus:set_top(gain:bottom() + 10)

		-- Tuple is { label_text, level }; nil level on failure skips the count-up.
		table.insert(self._levels.bonuses, {
			bonus,
			level,
		})
	end

	if not self:success() then
		add_bonus(managers.localization:text("menu_cs_mission_failed"), nil, tweak_data.screen_colors.important_1)
	end

	if rank_gain > 0 and self:success() then
		add_bonus(managers.localization:text("menu_cs_mission_complete"), rank_gain)
	end

	-- Rank/missions totals are in the status bar strip; this tab owns only the gain animation.
end

-- Three-column reward readout: rank+glyph (left, yellow), loot money (center), tokens+coin (right).
-- Both bars fill from loot_cash; center fades after drain. Reads _last_heist_rewards.
function CSRCrimeSpreeResultTabItem:_create_reward_panel()
	if not self:success() then
		return
	end
	local r = managers.csr and managers.csr._last_heist_rewards
	if not r then
		return
	end
	local mission_rank = math.max(0, math.floor(r.mission_rank or 0))
	local completion_tokens = math.max(0, math.floor(r.completion_tokens or 0))
	local loot_cash = math.max(0, r.loot_cash or 0)
	local loot_tokens = math.max(0, math.floor(r.loot_tokens or 0))
	local per_token = math.max(1, r.per_token or 1)
	local per_rank = math.max(1, r.per_rank or 200000)
	local start_carry = math.max(0, r.start_carry or 0)
	local start_carry_tok = math.max(0, r.start_carry_tok or 0)
	local remainder = math.max(0, r.remainder or 0)

	if mission_rank <= 0 and completion_tokens <= 0 and loot_cash <= 0 then
		return
	end

	local cs_panel = self._cs_panel
	if not cs_panel or not alive(cs_panel) then
		return
	end

	local panel_w = cs_panel:w()

	-- Yellow rank matches the Crime Spree glyph (crime_spree_risk == Color(1,1,0)); white tokens.
	local rank_color = tweak_data.screen_colors.crime_spree_risk
	local token_color = Color.white
	local num_font = tweak_data.menu.pd2_large_font
	local num_size = tweak_data.menu.pd2_large_font_size
	local money_font = tweak_data.menu.pd2_medium_font
	local money_size = tweak_data.menu.pd2_medium_font_size
	local small_font = tweak_data.menu.pd2_small_font
	local small_size = tweak_data.menu.pd2_small_font_size

	local zone_w = math.floor(panel_w / 3)
	local bar_w = 110
	local bar_h = 8
	local num_box_w = 80
	local icon_size = math.floor(num_size * 0.45)
	local gap = 6

	-- Layout: number row -> label -> bar, vertically centered in the panel.
	local panel_h = 100
	local stack_h = num_size + 6 + small_size + 10 + bar_h
	local row_y = math.floor((panel_h - stack_h) / 2)
	local label_y = row_y + num_size + 6
	local bar_y = label_y + small_size + 10

	local panel = cs_panel:panel({
		name = "csr_reward_panel",
		w = panel_w,
		h = panel_h,
		x = 0,
		alpha = 0,
		layer = 15,
	})
	panel:set_y(math.floor(cs_panel:h() * 0.16))

	-- Build one reward column: number, label, progress bar. suffix = glyph baked in text; icon_tex = bitmap after number.
	local function build_side(cx, color, label_key, suffix, icon_tex)
		local gain
		if icon_tex then
			-- number (right-aligned) + coin bitmap, centered on cx
			local group_w = num_box_w + gap + icon_size
			local group_x = math.floor(cx - group_w / 2)
			gain = panel:text({
				text = "+0",
				font = num_font,
				font_size = num_size,
				color = color,
				align = "right",
				vertical = "top",
				blend_mode = "add",
				layer = 1,
				x = group_x,
				y = row_y,
				w = num_box_w,
				h = num_size,
			})
			panel:bitmap({
				texture = icon_tex,
				color = color,
				layer = 1,
				w = icon_size,
				h = icon_size,
				x = group_x + num_box_w + gap,
				y = row_y + math.floor((num_size - icon_size) / 2),
			})
		else
			-- glyph baked into number text, centered across zone width
			gain = panel:text({
				text = "+0" .. (suffix or ""),
				font = num_font,
				font_size = num_size,
				color = color,
				align = "center",
				vertical = "top",
				blend_mode = "add",
				layer = 1,
				x = math.floor(cx - zone_w / 2),
				y = row_y,
				w = zone_w,
				h = num_size,
			})
		end
		panel:text({
			text = managers.localization:text(label_key),
			font = small_font,
			font_size = small_size,
			color = color,
			align = "center",
			vertical = "top",
			blend_mode = "add",
			layer = 1,
			x = math.floor(cx - zone_w / 2),
			y = label_y,
			w = zone_w,
			h = small_size,
		})
		panel:rect({
			color = Color(0.25, 0.2, 0.2, 0.2),
			layer = 2,
			x = math.floor(cx - bar_w / 2),
			y = bar_y,
			w = bar_w,
			h = bar_h,
		})
		local bar = panel:rect({
			color = color,
			layer = 3,
			x = math.floor(cx - bar_w / 2),
			y = bar_y,
			w = 0,
			h = bar_h,
		})
		return gain, bar
	end

	-- Rank: CS glyph (0xE018) baked in text. Tokens: gage-coin bitmap after the number.
	local rank_suffix = " " .. utf8.char(0xE018)
	local rank_gain, rank_bar = build_side(zone_w * 0.5, rank_color, "csr_reward_rank_label", rank_suffix, nil)
	local tok_gain, tok_bar = build_side(
		zone_w * 2.5,
		token_color,
		"csr_reward_tokens_label",
		nil,
		"guis/textures/pd2/crime_spree/csr_gage_token"
	)

	-- Center: loot money (feeds both bars, fades after drain). No bar.
	local money_h = small_size + 4 + money_size
	local money_top = math.floor((panel_h - money_h) / 2)
	local money_label = panel:text({
		name = "money_label",
		text = managers.localization:to_upper_text("csr_reward_loot_label"),
		font = small_font,
		font_size = small_size,
		color = Color(0.7, 0.6, 0.6, 0.6),
		align = "center",
		vertical = "top",
		blend_mode = "add",
		layer = 1,
		x = zone_w,
		y = money_top,
		w = zone_w,
		h = small_size,
	})
	local money_num = panel:text({
		name = "money_num",
		text = "$0",
		font = money_font,
		font_size = money_size,
		color = Color.white,
		align = "center",
		vertical = "top",
		blend_mode = "add",
		layer = 1,
		x = zone_w,
		y = money_top + small_size + 4,
		w = zone_w,
		h = money_size,
	})
	money_label:set_alpha(0)
	money_num:set_alpha(0)

	-- Pre-fill bars from last mission's carry (shows leftover cash did not vanish).
	rank_bar:set_w(math.floor((start_carry / per_rank) * bar_w))
	tok_bar:set_w(math.floor((start_carry_tok / per_token) * bar_w))

	-- Fractional bar fill ranges for the converting phase (both pools equal loot_cash by construction).
	local r_acc_from = start_carry / per_rank
	local r_acc_to = (start_carry + loot_cash) / per_rank
	local tok_pool = math.max(0, loot_tokens * per_token + remainder - start_carry_tok)
	local t_acc_from = start_carry_tok / per_token
	local t_acc_to = (start_carry_tok + tok_pool) / per_token

	self._csr_reward = {
		panel = panel,
		rank_gain = rank_gain,
		tok_gain = tok_gain,
		money_label = money_label,
		money_num = money_num,
		rank_bar = rank_bar,
		tok_bar = tok_bar,
		bar_w = bar_w,
		r_suffix = rank_suffix,
		t_suffix = "",
		mission_rank = mission_rank,
		completion_tokens = completion_tokens,
		pool_cash = loot_cash,
		r_acc_from = r_acc_from,
		r_acc_to = r_acc_to,
		r_base = mission_rank,
		t_acc_from = t_acc_from,
		t_acc_to = t_acc_to,
		t_base = completion_tokens,
		r_last_int = math.floor(r_acc_from),
		t_last_int = math.floor(t_acc_from),
	}
end

-- Stage-3 reward cards (ported verbatim): display-only; values already credited in gm_rewards.lua.
function CSRCrimeSpreeResultTabItem:_create_rewards(total_w)
	local r = managers.csr and managers.csr._last_heist_rewards
	local amounts = r and r.heist_cards
	if not amounts then
		return
	end

	self._reward_panel = self._cs_panel:panel({
		x = self._cs_panel:w() * (1 - total_w),
		y = padding,
		w = self._cs_panel:w() * total_w - padding * 2,
		h = self._cs_panel:h() * 0.5,
	})
	local w = self._reward_panel:w() / #tweak_data.crime_spree.rewards

	local function create_card(idx, panel, icon, rotation)
		local scale = 0.65
		local texture, rect, coords = tweak_data.hud_icons:get_icon_data(
			idx == 1 and (icon or tweak_data.lootdrop.type_to_card_fallback)
				or tweak_data.lootdrop.type_to_card_fallback
		)
		local upcard = panel:bitmap({
			name = "upcard",
			halign = "scale",
			valign = "scale",
			texture = texture,
			w = math.round(0.7111111111111111 * panel:h() * scale),
			h = panel:h() * scale,
			layer = 20 - idx,
		})

		upcard:set_center_x(panel:w() * 0.5)
		upcard:set_rotation(rotation)

		if coords then
			local tl = Vector3(coords[1][1], coords[1][2], 0)
			local tr = Vector3(coords[2][1], coords[2][2], 0)
			local bl = Vector3(coords[3][1], coords[3][2], 0)
			local br = Vector3(coords[4][1], coords[4][2], 0)

			upcard:set_texture_coordinates(tl, tr, bl, br)
		else
			upcard:set_texture_rect(unpack(rect))
		end

		return upcard
	end

	self._rewards = {}
	local count = 0

	for i, data in ipairs(tweak_data.crime_spree.rewards) do
		local amount = math.floor(amounts[data.id] or 0)

		if amount > 0 then
			local cards = {}
			local panel = self._reward_panel:panel({
				alpha = 0,
				w = w,
				x = count * w,
			})
			local first_card_panel = self._reward_panel:panel({
				w = w,
				x = count * w,
			})
			local card = nil
			local rotation = math.rand(-10, 10)
			local num_cards = 1

			for j = 1, num_cards do
				card = create_card(j, j == 1 and first_card_panel or panel, data.icon, rotation)

				card:hide()
				table.insert(cards, card)
			end

			local reward_amount = panel:text({
				vertical = "center",
				h = 32,
				wrap = true,
				align = "center",
				word_wrap = true,
				blend_mode = "add",
				layer = 11,
				name = "reward" .. tostring(i),
				text = managers.experience:cash_string(amount, data.cash_string or ""),
				w = panel:w(),
				font_size = tweak_data.menu.pd2_small_font_size,
				font = tweak_data.menu.pd2_small_font,
				color = Color.white,
			})

			reward_amount:set_top(card:bottom() + padding)

			local _x, _y, _w, txt_h = reward_amount:text_rect()

			reward_amount:set_h(txt_h)
			table.insert(self._rewards, {
				cards = cards,
				first_card_panel = first_card_panel,
				panel = panel,
			})

			count = count + 1
		end
	end
end

function CSRCrimeSpreeResultTabItem:set_stats(stats_data) end

function CSRCrimeSpreeResultTabItem:feed_statistics(stats_data) end

-- Reward panel is the sole active stage. Vanilla gain count-up + reward-cards both disabled (kept).
CSRCrimeSpreeResultTabItem.stages = {
	-- Vanilla gain count-up disabled (kept): { delay = 1, func = "_update_gain_calculate" },
	{
		delay = 0.5,
		func = "_update_reward_panel",
	},
	-- Reward cards stage disabled (kept for possible return); re-enable with _create_rewards in _setup:
	-- {
	-- 	delay = 0.3,
	-- 	func = "_update_reward_gain",
	-- },
}

function CSRCrimeSpreeResultTabItem:_advance_stage(delay)
	local idx = (self._update and self._update.idx or 0) + 1

	if not CSRCrimeSpreeResultTabItem.stages[idx] then
		self._update = {
			done = true,
		}

		return
	end

	self._update = {
		idx = idx,
		t = delay or CSRCrimeSpreeResultTabItem.stages[idx].delay,
		func = CSRCrimeSpreeResultTabItem.stages[idx].func,
	}
end

function CSRCrimeSpreeResultTabItem:update(t, dt)
	if not self._update then
		self:_advance_stage()
	end

	if self._update.done then
		return
	end

	self._update.t = self._update.t - dt

	if self._update.t <= 0 then
		self[self._update.func](self, t, dt)
	end
end

function CSRCrimeSpreeResultTabItem:fade_in(element, duration, delay)
	if delay then
		wait(delay)
	end

	over(duration, function(p)
		element:set_alpha(math.lerp(0, 1, p))
	end)
end

function CSRCrimeSpreeResultTabItem:fade_out(element, duration, delay)
	if delay then
		wait(delay)
	end

	over(duration, function(p)
		element:set_alpha(math.lerp(1, 0, p))
	end)
end

function CSRCrimeSpreeResultTabItem:count_text(element, cash_string, start_val, end_val, duration, delay)
	if delay then
		wait(delay)
	end

	local v = start_val

	managers.menu_component:post_event("count_1")
	over(duration, function(p)
		v = math.lerp(start_val, end_val, p)

		element:set_text(managers.localization:text("menu_cs_level", {
			level = managers.experience:cash_string(v, cash_string),
		}))
	end)
	managers.menu_component:post_event("count_1_finished")
end

-- Verbatim vanilla: fades bonuses in and counts the gain up by each bonus amount.
function CSRCrimeSpreeResultTabItem:_update_gain_calculate(t, dt)
	local t = 0
	local fade_t = 0.5
	local count_bonus_t = 0.75
	local gain_amt = 0

	self._levels.gain:animate(callback(self, self, "fade_in"), 0.5, t)

	t = t + 0.5

	for i, bonus in ipairs(self._levels.bonuses) do
		bonus[1]:animate(callback(self, self, "fade_in"), fade_t, t)

		t = t + 0.25

		if bonus[2] then
			t = t + fade_t + 0.5

			self._levels.gain:animate(
				callback(self, self, "count_text"),
				"+",
				gain_amt,
				gain_amt + bonus[2],
				count_bonus_t,
				t
			)

			gain_amt = gain_amt + bonus[2]
		end

		t = t + count_bonus_t + 1

		if self:success() then
			if i ~= #self._levels.bonuses then
				bonus[1]:animate(callback(self, self, "fade_out"), fade_t * 0.66, t)
			end

			t = t + 0.4
		end
	end

	self:_advance_stage(t)
end

-- Reward panel animation state machine. Sub-state in _csr_rp_state.
function CSRCrimeSpreeResultTabItem:_update_reward_panel(t, dt)
	local cc = self._csr_reward
	if not cc then
		self:_advance_stage()
		return
	end

	local st = self._csr_rp_state
	if not st then
		st = { phase = "fade_in", elapsed = 0 }
		self._csr_rp_state = st
	end

	st.elapsed = st.elapsed + dt

	if st.phase == "fade_in" then
		cc.panel:set_alpha(math.min(st.elapsed / 0.4, 1))
		if st.elapsed >= 0.4 then
			cc.panel:set_alpha(1)
			st.phase = "flat_show"
			st.elapsed = 0
		end
		return
	end

	-- Both flat mission bonuses count up at once.
	if st.phase == "flat_show" then
		local p = math.min(st.elapsed / 0.5, 1)
		cc.rank_gain:set_text("+" .. math.round(cc.mission_rank * p) .. cc.r_suffix)
		cc.tok_gain:set_text("+" .. math.round(cc.completion_tokens * p) .. cc.t_suffix)
		if p >= 1 then
			cc.rank_gain:set_text("+" .. cc.mission_rank .. cc.r_suffix)
			cc.tok_gain:set_text("+" .. cc.completion_tokens .. cc.t_suffix)
			st.phase = "flat_hold"
			st.elapsed = 0
		end
		return
	end

	if st.phase == "flat_hold" then
		if st.elapsed >= 0.7 then
			if cc.pool_cash > 0 then
				cc.money_num:set_text("$" .. managers.experience:cash_string(math.floor(cc.pool_cash), ""))
				st.phase = "money_in"
				st.elapsed = 0
			else
				st.phase = "hold"
				st.elapsed = 0
			end
		end
		return
	end

	if st.phase == "money_in" then
		local p = math.min(st.elapsed / 0.4, 1)
		cc.money_label:set_alpha(p)
		cc.money_num:set_alpha(p)
		if p >= 1 then
			cc.money_label:set_alpha(1)
			cc.money_num:set_alpha(1)
			st.phase = "money_hold"
			st.elapsed = 0
		end
		return
	end

	if st.phase == "money_hold" then
		if st.elapsed >= 0.5 then
			st.phase = "converting"
			st.elapsed = 0
			if managers.menu_component then
				managers.menu_component:post_event("count_1")
			end
		end
		return
	end

	-- Money drains to $0 while both bars fill off the same eased progress (one source, two effects).
	if st.phase == "converting" then
		local CONV_DUR = 2.8
		local p = math.min(st.elapsed / CONV_DUR, 1)
		local e = p < 0.5 and (2 * p * p) or (1 - (-2 * p + 2) ^ 2 / 2)

		cc.money_num:set_text(
			"$" .. managers.experience:cash_string(math.max(0, math.floor(cc.pool_cash * (1 - e))), "")
		)

		local rval = cc.r_acc_from + (cc.r_acc_to - cc.r_acc_from) * e
		local r_int = math.floor(rval)
		cc.rank_bar:set_w(math.floor((rval - r_int) * cc.bar_w))
		cc.rank_gain:set_text("+" .. (cc.r_base + r_int) .. cc.r_suffix)
		cc.r_last_int = r_int

		local tval = cc.t_acc_from + (cc.t_acc_to - cc.t_acc_from) * e
		local t_int = math.floor(tval)
		cc.tok_bar:set_w(math.floor((tval - t_int) * cc.bar_w))
		cc.tok_gain:set_text("+" .. (cc.t_base + t_int) .. cc.t_suffix)
		cc.t_last_int = t_int

		if p >= 1 then
			cc.money_num:set_text("$0")
			cc.rank_gain:set_text("+" .. (cc.r_base + math.floor(cc.r_acc_to)) .. cc.r_suffix)
			cc.rank_bar:set_w(math.floor((cc.r_acc_to - math.floor(cc.r_acc_to)) * cc.bar_w))
			cc.tok_gain:set_text("+" .. (cc.t_base + math.floor(cc.t_acc_to)) .. cc.t_suffix)
			cc.tok_bar:set_w(math.floor((cc.t_acc_to - math.floor(cc.t_acc_to)) * cc.bar_w))
			if managers.menu_component then
				managers.menu_component:post_event("count_1_finished")
			end
			st.phase = "money_out"
			st.elapsed = 0
		end
		return
	end

	-- Center money lingers 3s at full $0, then fades; rank/token columns stay.
	if st.phase == "money_out" then
		local MONEY_LINGER = 3.0
		if st.elapsed >= MONEY_LINGER then
			local a = 1 - math.min((st.elapsed - MONEY_LINGER) / 0.4, 1)
			cc.money_label:set_alpha(a)
			cc.money_num:set_alpha(a)
			if st.elapsed >= MONEY_LINGER + 0.4 then
				cc.money_label:set_alpha(0)
				cc.money_num:set_alpha(0)
				st.phase = "hold"
				st.elapsed = 0
			end
		end
		return
	end

	-- Panel persists (never fades). Advance once to stop the update loop while leaving it on screen.
	if st.phase == "hold" then
		if st.elapsed >= 1.0 then
			st.phase = "done"
			self:_advance_stage()
		end
		return
	end
end

-- Reward-card animations (ported verbatim from vanilla CrimeSpreeResultTabItem).
function CSRCrimeSpreeResultTabItem.animate_card_panel(o, reward_num)
	wait(reward_num * 0.5)
	over(0.5, function(p)
		o:set_alpha(math.lerp(0, 1, p))
	end)
end

function CSRCrimeSpreeResultTabItem.flip_card(card, reward_num)
	wait(reward_num * 0.5)

	local start_w = card:w()
	local cx, cy = card:center()
	local start_rotation = card:rotation()
	local end_rotation = start_rotation * -1
	local diff = end_rotation - start_rotation

	card:set_valign("scale")
	card:set_halign("scale")
	card:show()
	card:set_w(0)
	managers.menu_component:post_event("loot_flip_card")
	over(0.25, function(p)
		card:set_rotation(start_rotation + math.sin(p * 45 + 45) * diff)

		if card:rotation() == 0 then
			card:set_rotation(360)
		end

		card:set_w(start_w * math.sin(p * 90))
		card:set_center(cx, cy)
	end)
end

function CSRCrimeSpreeResultTabItem.animate_card(o, reward_num, card_idx)
	wait(reward_num * 0.5 + 0.5)
	o:show()
	over(0.25, function(p)
		o:set_rotation(o:rotation() + 0.375 * card_idx * (1 - p * p))
	end)
end

-- Stage 3: fan the reward cards in once the token convert has faded out.
function CSRCrimeSpreeResultTabItem:_update_reward_gain(t, dt)
	if not self:success() then
		self:_advance_stage()
		return
	end

	for reward_num, data in ipairs(self._rewards or {}) do
		data.panel:animate(CSRCrimeSpreeResultTabItem.animate_card_panel, reward_num)

		for idx, card in ipairs(data.cards or {}) do
			if idx == 1 then
				card:animate(CSRCrimeSpreeResultTabItem.flip_card, reward_num)
			else
				card:animate(CSRCrimeSpreeResultTabItem.animate_card, reward_num, idx)
			end
		end
	end

	self:_advance_stage()
end

-- =====================================================================
-- CSRStageEndScreenGui — fork of StageEndScreenGui; 6 gate flips marked inline.
-- =====================================================================

CSRStageEndScreenGui = CSRStageEndScreenGui or class()

function CSRStageEndScreenGui:init(saferect_ws, fullrect_ws, statistics_data)
	self._safe_workspace = saferect_ws
	self._full_workspace = fullrect_ws
	self._fullscreen_panel = self._full_workspace:panel():panel({
		layer = 1,
	})
	-- CSR gate 1: the CS panel-width shrink, unconditional.
	local w = self._safe_workspace:panel():w() / 2 - padding
	w = w - padding + 1

	self._panel = self._safe_workspace:panel():panel({
		layer = 6,
		w = w,
		h = self._safe_workspace:panel():h() * 0.5 - padding,
	})

	self._panel:set_right(self._safe_workspace:panel():w())

	-- CSR gate 2: reserve missions-strip height + reminder-bar clearance above it.
	local reminder_clearance = tweak_data.menu.pd2_medium_font_size * 2
	self._panel:set_bottom(
		self._safe_workspace:panel():h() - (CSRMissionsMenuComponent.get_height() + padding) - reminder_clearance
	)

	local continue_button = managers.menu:is_pc_controller() and "[ENTER]" or nil
	local continue_text = utf8.to_upper(managers.localization:text("menu_es_calculating_experience", {
		CONTINUE = continue_button,
	}))

	-- CSR gate 3: blank inline continue text; actual flow is the post-heist options node.
	continue_text = ""

	self._continue_button = self._panel:text({
		name = "ready_button",
		vertical = "center",
		h = 32,
		align = "right",
		layer = 1,
		text = continue_text,
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.button_stage_3,
	})
	local _, _, w, h = self._continue_button:text_rect()

	self._continue_button:set_size(w, h)
	self._continue_button:set_bottom(self._panel:h())
	self._continue_button:set_right(self._panel:w())

	self._button_not_clickable = true

	self._continue_button:set_color(tweak_data.screen_colors.item_stage_1)

	self._scroll_panel = self._panel:panel({
		name = "scroll_panel",
	})
	self._tab_panel = self._scroll_panel:panel({
		name = "tab_panel",
	})
	local big_text = self._fullscreen_panel:text({
		name = "continue_big_text",
		vertical = "bottom",
		h = 90,
		alpha = 0.4,
		align = "right",
		text = continue_text,
		font_size = tweak_data.menu.pd2_massive_font_size,
		font = tweak_data.menu.pd2_massive_font,
		color = tweak_data.screen_colors.button_stage_3,
	})
	local x, y =
		managers.gui_data:safe_to_full_16_9(self._continue_button:world_right(), self._continue_button:world_center_y())

	big_text:set_world_right(x)
	big_text:set_world_center_y(y)
	big_text:move(13, -9)

	if MenuBackdropGUI then
		MenuBackdropGUI.animate_bg_text(self, big_text)
	end

	local text = managers.menu:is_pc_controller() and "" or managers.localization:get_default_macro("BTN_BOTTOM_L")
	local color = managers.menu:is_pc_controller() and tweak_data.screen_colors.button_stage_3 or Color.white
	local prev_page = self._panel:text({
		w = 0,
		name = "prev_page",
		vertical = "top",
		y = 0,
		layer = 2,
		h = tweak_data.menu.pd2_medium_font_size,
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		text = text,
		color = color,
	})
	local _, _, w, h = prev_page:text_rect()

	prev_page:set_size(w, h + 10)
	prev_page:set_left(0)

	self._prev_page = prev_page

	self._scroll_panel:move(w, 0)

	self._items = {}
	local item = nil

	-- CSR gate 4: build the forked result tab; skip vanilla cash summary.
	item = CSRCrimeSpreeResultTabItem:new(
		self._panel,
		self._tab_panel,
		utf8.to_upper(managers.localization:text("menu_es_crime_spree_summary")),
		#self._items + 1
	)

	table.insert(self._items, item)

	item = StatsTabItem:new(
		self._panel,
		self._tab_panel,
		utf8.to_upper(managers.localization:text("menu_es_stats_crew")),
		#self._items + 1
	)

	item:set_stats({
		"time_played",
		"most_downs",
		"best_accuracy",
		"best_killer",
		"best_special",
		"group_total_downed",
		"group_hit_accuracy",
		"criminals_finished",
	})
	table.insert(self._items, item)

	item = StatsTabItem:new(
		self._panel,
		self._tab_panel,
		utf8.to_upper(managers.localization:text("menu_es_stats_personal")),
		#self._items + 1
	)

	item:set_stats({
		"total_downed",
		"hit_accuracy",
		"total_kills",
		"total_specials_kills",
		"total_head_shots",
		"favourite_weapon",
		"civilians_killed_penalty",
	})
	table.insert(self._items, item)

	item = StatsTabItem:new(
		self._panel,
		self._tab_panel,
		utf8.to_upper(managers.localization:text("menu_es_stats_gage_assignment")),
		#self._items + 1
	)

	item:set_stats({
		"gage_assignment_summary",
	})
	table.insert(self._items, item)

	if managers.custom_safehouse:unlocked() then
		item = StatsTabItem:new(
			self._panel,
			self._tab_panel,
			utf8.to_upper(managers.localization:text("menu_es_safehouse_summary")),
			#self._items + 1
		)

		item:set_stats({
			"stage_safehouse_summary",
		})
		table.insert(self._items, item)
	end

	local scroll_w = self._panel:w() - self._scroll_panel:x()
	local text = managers.menu:is_pc_controller() and "" or managers.localization:get_default_macro("BTN_BOTTOM_R")
	local color = managers.menu:is_pc_controller() and tweak_data.screen_colors.button_stage_3 or Color.white
	local next_page = self._panel:text({
		w = 0,
		vertical = "top",
		y = 0,
		layer = 2,
		name = "tab_text_" .. tostring(#self._items + 1),
		h = tweak_data.menu.pd2_medium_font_size,
		font_size = tweak_data.menu.pd2_medium_font_size,
		font = tweak_data.menu.pd2_medium_font,
		text = text,
		color = color,
	})
	local _, _, w, h = next_page:text_rect()

	next_page:set_size(w, h + 10)
	next_page:set_right(self._panel:w())

	self._next_page = next_page
	scroll_w = scroll_w - next_page:w() - 5
	local ix, iy, iw, ih = self._items[#self._items]:tab_text_shape()

	self._tab_panel:set_w(ix + iw + 5)
	self._tab_panel:set_h(ih)
	self._scroll_panel:set_w(scroll_w)
	self._scroll_panel:set_h(ih)

	if self._console_subtitle_string_id then
		self:console_subtitle_callback(self._console_subtitle_string_id)
	end

	self:select_tab(1, true)
	self._items[self._selected_item]:select()

	-- Stats-box frame intentionally omitted: without the cash/XP summary it renders as stray empty corners.

	if statistics_data then
		self:feed_statistics(statistics_data)
	end

	self._enabled = true

	if managers.job:stage_success() then
		self._bain_debrief_t = TimerManager:main():time() + 2.5
	end

	-- CSR gate 5: the CS result tab is wide; reduce to small font like vanilla CS.
	self._reduced_to_small_font = true

	self:chk_reduce_to_small_font()
end

function CSRStageEndScreenGui:chk_reduce_to_small_font()
	local max_x = alive(self._next_page) and self._next_page:left() - 5 or self._panel:w()

	if
		self._reduced_to_small_font
		or self._items[#self._items]
			and alive(self._items[#self._items]._tab_text)
			and max_x < self._items[#self._items]._tab_text:right()
	then
		for i, tab in ipairs(self._items) do
			tab:reduce_to_small_font()
		end

		self._reduced_to_small_font = true
	end
end

function CSRStageEndScreenGui:hide()
	self._enabled = false

	self._panel:set_alpha(0.5)
	self._fullscreen_panel:set_alpha(0.5)
end

function CSRStageEndScreenGui:show()
	self._enabled = true

	self._panel:set_alpha(1)
	self._fullscreen_panel:set_alpha(1)
end

function CSRStageEndScreenGui:play_bain_debrief()
	local variant = managers.groupai:state():endscreen_variant() or 0
	local level_data = Global.level_data.level_id and tweak_data.levels[Global.level_data.level_id]
	local outro_event = level_data and (variant == 0 and level_data.outro_event or level_data.outro_event[variant])
	outro_event = managers.mutators:get_outro_event(outro_event)

	Application:debug("CSRStageEndScreenGui:play_bain_debrief()", outro_event)

	if outro_event then
		local snd_event = nil
		local tactic = managers.groupai:state():enemy_weapons_hot() and "loud" or "stealth"

		if type(outro_event) == "table" then
			if outro_event.loud or outro_event.stealth then
				snd_event = outro_event[tactic]
			else
				snd_event = outro_event[math.random(#outro_event)]
			end
		else
			snd_event = outro_event
		end

		if snd_event then
			print("[CSRStageEndScreenGui] ", snd_event)
			managers.briefing:post_event(snd_event, {
				show_subtitle = false,
				listener = {
					end_of_event = true,
					clbk = callback(self, self, "bain_debrief_end_callback"),
				},
			})
		else
			debug_pause(
				string.format(
					"[CSRStageEndScreenGui] Attempting to play outro_event that doesn't exist! %s",
					tostring(outro_event),
					tactic
				)
			)
		end

		if managers.menu:is_console() then
			managers.briefing:add_listener({
				marker = true,
				clbk = callback(self, self, "console_subtitle_callback"),
			})
		end
	else
		self:bain_debrief_end_callback()
	end
end

function CSRStageEndScreenGui:console_subtitle_callback(event, string_id, duration, cookie)
	if not self._console_subtitle_panel then
		self._console_subtitle_panel = self._safe_workspace:panel():panel()

		self._console_subtitle_panel:set_size(self._panel:x() - 10 - 10, self._panel:h() - 70)
		self._console_subtitle_panel:set_leftbottom(0, self._panel:bottom() - 70)
		self._console_subtitle_panel:text({
			text = "",
			name = "subtitle_text",
			wrap = true,
			align = "center",
			vertical = "bottom",
			word_wrap = true,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
		})
	end

	if duration then
		local text = self._console_subtitle_panel:child("subtitle_text")

		text:set_text(managers.localization:text(string_id))

		self._console_subtitle_string_id = string_id
		self._console_subtitle_duration = TimerManager:main():time() + duration
	end
end

function CSRStageEndScreenGui:bain_debrief_end_callback()
	self._contact_debrief_t = TimerManager:main():time() + 3.5
end

function CSRStageEndScreenGui:update(t, dt)
	if self._bain_debrief_t and self._bain_debrief_t < t then
		self._bain_debrief_t = nil

		self:play_bain_debrief()
	end

	if self._contact_debrief_t and self._contact_debrief_t < t then
		self._contact_debrief_t = nil

		if managers.job:on_last_stage() then
			local job_data = managers.job:current_job_data()

			if job_data and job_data.debrief_event then
				managers.briefing:post_event(job_data.debrief_event)

				if managers.menu:is_console() then
					managers.briefing:add_listener({
						marker = true,
						clbk = callback(self, self, "console_subtitle_callback"),
					})
				end
			end
		end
	end

	if self._console_subtitle_duration and self._console_subtitle_duration < t then
		local text = self._console_subtitle_panel:child("subtitle_text")

		text:set_text("")

		self._console_subtitle_string_id = nil
		self._console_subtitle_duration = nil
	end

	for index, tab in ipairs(self._items) do
		if tab.update then
			tab:update(t, dt)
		end
	end
end

function CSRStageEndScreenGui:feed_statistics(data)
	data = data or {}
	data.total_objectives = managers.objectives:total_objectives(Global.level_data and Global.level_data.level_id)
	data.completed_ratio = data.success and managers.statistics:started_session_from_beginning() and 100
		or data.total_objectives ~= 0 and math.round(
			managers.statistics:completed_objectives() / data.total_objectives * 100
		)
		or 0
	data.completed_objectives = managers.localization:text("menu_completed_objectives_of", {
		COMPLETED = managers.statistics:completed_objectives(),
		TOTAL = data.total_objectives,
		PERCENT = data.completed_ratio,
	})
	data.time_played = managers.statistics:session_time_played()
	data.total_downed = managers.statistics:total_downed()
	data.favourite_weapon = managers.statistics:session_favourite_weapon()
	data.hit_accuracy = managers.statistics:session_hit_accuracy() .. "%"
	data.total_kills = managers.statistics:session_total_kills()
	data.total_specials_kills = managers.statistics:session_total_specials_kills()
	data.total_head_shots = managers.statistics:session_total_head_shots()
	data.civilians_killed_penalty = managers.statistics:session_total_civilian_kills()
	self._data = data or {}

	for i, item in ipairs(self._items) do
		item:feed_statistics(data)
	end
end

function CSRStageEndScreenGui:show_cash_summary()
	self._items[1]._panel:set_alpha(1)
end

-- CSR gate 6: no-op; continue flow is the post-heist options node, not this button.
function CSRStageEndScreenGui:set_continue_button_text(text, not_clickable)
	return
end

function CSRStageEndScreenGui:next_tab(no_sound)
	return self:select_tab(math.min(self._selected_item + 1, #self._items), no_sound)
end

function CSRStageEndScreenGui:prev_tab(no_sound)
	return self:select_tab(math.max(self._selected_item - 1, 1), no_sound)
end

function CSRStageEndScreenGui:select_tab(selected_item, no_sound)
	if self._selected_item == selected_item then
		return
	end

	if self._selected_item then
		self._items[self._selected_item]:deselect()
	end

	self._selected_item = selected_item

	self._items[self._selected_item]:select()

	local ix, iy, iw, ih = self._items[self._selected_item]:tab_text_shape()
	local left = self._tab_panel:x() + ix
	local right = left + iw

	if left < 0 then
		self._tab_panel:move(-left, 0)
	elseif self._scroll_panel:w() < right then
		self._tab_panel:move(-(right - self._scroll_panel:w()), 0)
	end

	if not no_sound then
		managers.menu_component:post_event("menu_enter")
	end

	if self._prev_page then
		self._prev_page:set_visible(self._selected_item > 1)
	end

	if self._next_page then
		self._next_page:set_visible(self._selected_item < #self._items)
	end

	return self._selected_item
end

function CSRStageEndScreenGui:mouse_pressed(button, x, y)
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return
	end

	if button == Idstring("mouse wheel down") then
		self:next_page(true)

		return
	elseif button == Idstring("mouse wheel up") then
		self:previous_page(true)

		return
	end

	if button ~= Idstring("0") then
		return
	end

	if self._scroll_panel:inside(x, y) then
		for index, tab in ipairs(self._items) do
			local pressed = tab:mouse_pressed(button, x, y)

			if pressed == true then
				self:select_tab(index, false)
			end
		end
	end

	if
		not self._button_not_clickable
		and self._continue_button:inside(x, y)
		and game_state_machine:current_state()._continue_cb
	then
		managers.menu_component:post_event("menu_enter")
		game_state_machine:current_state()._continue_cb()
	end

	if alive(self._prev_page) and self._prev_page:visible() and self._prev_page:inside(x, y) then
		self:previous_page(false)
	end

	if alive(self._next_page) and self._next_page:visible() and self._next_page:inside(x, y) then
		self:next_page(false)
	end
end

-- Snap targets for the controller cursor: the tab strip, the paging arrows and Continue. Tabs are
-- hit-tested on their text (StatsTabItem:mouse_moved, stageendscreengui.lua:451), not a panel.
function CSRStageEndScreenGui:csr_magnet_targets(out)
	if not self._enabled then
		return
	end
	for _, tab in ipairs(self._items or {}) do
		CSR_ControllerNav.add_target(out, tab._tab_text)
	end
	CSR_ControllerNav.add_target(out, self._prev_page)
	CSR_ControllerNav.add_target(out, self._next_page)
	CSR_ControllerNav.add_target(out, self._continue_button)
end

function CSRStageEndScreenGui:mouse_moved(x, y)
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return false
	end

	local mouse_over_tab = false
	local mouse_over_scroll = self._scroll_panel:inside(x, y)

	for _, tab in ipairs(self._items) do
		local selected, highlighted = tab:mouse_moved(x, y, mouse_over_scroll)

		if highlighted and not selected then
			mouse_over_tab = true
		end
	end

	if mouse_over_tab then
		return true, "link"
	end

	if alive(self._prev_page) then
		if self._prev_page:visible() and self._prev_page:inside(x, y) then
			if not self._prev_page_highlighted then
				self._prev_page_highlighted = true

				self._prev_page:set_color(tweak_data.screen_colors.button_stage_2)
				managers.menu_component:post_event("highlight")
			end

			return true, "link"
		elseif self._prev_page_highlighted then
			self._prev_page_highlighted = false

			self._prev_page:set_color(tweak_data.screen_colors.button_stage_3)
		end
	end

	if alive(self._next_page) then
		if self._next_page:visible() and self._next_page:inside(x, y) then
			if not self._next_page_highlighted then
				self._next_page_highlighted = true

				self._next_page:set_color(tweak_data.screen_colors.button_stage_2)
				managers.menu_component:post_event("highlight")
			end

			return true, "link"
		elseif self._next_page_highlighted then
			self._next_page_highlighted = false

			self._next_page:set_color(tweak_data.screen_colors.button_stage_3)
		end
	end

	if self._button_not_clickable then
		self._continue_button:set_color(tweak_data.screen_colors.item_stage_1)
	elseif self._continue_button:inside(x, y) then
		if not self._continue_button_highlighted then
			self._continue_button_highlighted = true

			self._continue_button:set_color(tweak_data.screen_colors.button_stage_2)
			managers.menu_component:post_event("highlight")
		end

		return true, "link"
	elseif self._continue_button_highlighted then
		self._continue_button_highlighted = false

		self._continue_button:set_color(tweak_data.screen_colors.button_stage_3)
		managers.menu_component:post_event("highlight")
	end

	if managers.hud._hud_stage_endscreen and managers.hud._hud_stage_endscreen._backdrop then
		managers.hud._hud_stage_endscreen._backdrop:mouse_moved(x, y)
	end

	return false, "arrow"
end

function CSRStageEndScreenGui:input_focus()
	return self._enabled and 1 or nil
end

function CSRStageEndScreenGui:scroll_up()
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return
	end

	if self._items[self._selected_item] then
		self._items[self._selected_item]:move_right()
	end
end

function CSRStageEndScreenGui:scroll_down()
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return
	end

	if self._items[self._selected_item] then
		self._items[self._selected_item]:move_left()
	end
end

function CSRStageEndScreenGui:move_up() end

function CSRStageEndScreenGui:move_down() end

function CSRStageEndScreenGui:move_left()
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return
	end

	if self._items[self._selected_item] then
		self._items[self._selected_item]:move_left()
	end
end

function CSRStageEndScreenGui:move_right()
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return
	end

	if self._items[self._selected_item] then
		self._items[self._selected_item]:move_right()
	end
end

function CSRStageEndScreenGui:confirm_pressed()
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return
	end

	-- On a controller the endscreen shares the screen with the CSRMissionsMenuComponent (its sidebar
	-- and item reminders, docked below). MenuComponentManager checks this node-gui's confirm BEFORE
	-- live components, so A would fire continue and never reach the sidebar. Give the component the
	-- click first (it replays at the virtual cursor); only continue if the cursor is over nothing there.
	if not managers.menu:is_pc_controller() then
		local comp = managers.menu_component and managers.menu_component._crime_spree_missions
		if comp and CSRMissionsMenuComponent and getmetatable(comp) == CSRMissionsMenuComponent then
			if comp:confirm_pressed() then
				return true
			end
		end
	end

	if game_state_machine:current_state()._continue_cb() then
		game_state_machine:current_state()._continue_cb()

		return true
	end
end

function CSRStageEndScreenGui:back_pressed()
	if not alive(self._panel) or not alive(self._fullscreen_panel) or not self._enabled then
		return false
	end
end

function CSRStageEndScreenGui:special_btn_pressed(btn)
	if btn == Idstring("menu_challenge_claim") then
		managers.hud:set_speed_up_endscreen_hud(5)
	end
end

function CSRStageEndScreenGui:special_btn_released(btn)
	if btn == Idstring("menu_challenge_claim") then
		managers.hud:set_speed_up_endscreen_hud(nil)
	end
end

function CSRStageEndScreenGui:accept_input(accept)
	print("CSRStageEndScreenGui:accept_input", accept)
end

function CSRStageEndScreenGui:next_page(no_sound)
	if not self._enabled then
		return
	end

	self:next_tab(no_sound)
end

function CSRStageEndScreenGui:previous_page(no_sound)
	if not self._enabled then
		return
	end

	self:prev_tab(no_sound)
end

function CSRStageEndScreenGui:close()
	if self._panel and alive(self._panel) then
		self._panel:parent():remove(self._panel)
	end

	if self._fullscreen_panel and alive(self._fullscreen_panel) then
		self._fullscreen_panel:parent():remove(self._fullscreen_panel)
	end

	if alive(self._console_subtitle_panel) then
		self._console_subtitle_panel:parent():remove(self._console_subtitle_panel)
	end
end

function CSRStageEndScreenGui:reload()
	self:close()
	CSRStageEndScreenGui.init(self, self._safe_workspace, self._full_workspace, self._data)
end

csr_log("[CSR] stage_endscreen.lua loaded (CSRStageEndScreenGui + CSRCrimeSpreeResultTabItem fork)")
