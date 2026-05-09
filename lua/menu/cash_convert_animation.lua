-- Crime Spree Roguelike - End screen cash-to-rank conversion animation (stage 2)
-- Injects a new stage into CrimeSpreeResultTabItem.stages between the vanilla
-- bonus count-up and the timeline fill. Shows an RoR2-style refilling bar as
-- the player's earned cash converts into rank points, bumping the main gain
-- counter on each rank tick.

if not RequiredScript then
	return
end

local key = ModPath .. "\t" .. RequiredScript .. "\tcash_convert_animation"
if _G[key] then
	return
end
_G[key] = true

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR CashConvert] " .. tostring(msg))
	end
end

if not CrimeSpreeResultTabItem then
	CSR_log("CrimeSpreeResultTabItem not found, skipping")
	return
end

local function csr_cash_per_rank()
	return (_G.CSR_ItemConstants and _G.CSR_ItemConstants.cash_per_rank)
		or {
			normal = 7500,
			hard = 37500,
			very_hard = 75000,
			overkill = 157500,
			mayhem = 270000,
			death_wish = 307500,
			death_sentence = 345000,
		}
end

Hooks:PostHook(CrimeSpreeResultTabItem, "_setup", "CSR_BuildCashConvert", function(self)
	CSR_log("_setup PostHook fired, success=" .. tostring(self:success()))
	if not self:success() then
		return
	end
	-- Use is_active() OR in_progress() — is_active() flickers on clients during
	-- the heist→endscreen transition. A strict is_active() check here suppresses
	-- the cash-convert animation entirely for clients.
	local cs_mgr = managers.crime_spree
	local cs_running = cs_mgr
		and ((cs_mgr.is_active and cs_mgr:is_active()) or (cs_mgr.in_progress and cs_mgr:in_progress()))
	if not cs_running then
		CSR_log("not in CS — skipping")
		return
	end

	local cash_bonus = managers.crime_spree._csr_bonus_bags
	local total_cash = managers.crime_spree._csr_total_cash
	local rank_costs = managers.crime_spree._csr_rank_costs or {}
	CSR_log("data: cash_bonus=" .. tostring(cash_bonus) .. " total_cash=" .. tostring(total_cash))
	if not cash_bonus or not total_cash then
		CSR_log("no bonus data — skipping")
		return
	end

	local leftover_cash = _G.CSR_CarriedCash or 0
	if cash_bonus == 0 and leftover_cash == 0 then
		CSR_log("E2: zero everything — skipping")
		return
	end

	local diff = (managers.crime_spree._global and managers.crime_spree._global.selected_difficulty)
		or _G.CSR_CurrentDifficulty
		or "overkill"
	-- Base = next mission's rank-1 cost. Used only for carry_target_w (escalation
	-- resets next mission, so leftover is shown as fraction of rank-1 base).
	local cash_per_rank = csr_cash_per_rank()[diff] or 157500

	local cs_panel = self._cs_panel
	if not cs_panel or not alive(cs_panel) then
		return
	end

	local panel_w = math.floor(cs_panel:w() * 0.60)
	local panel_h = 80
	local convert_panel = cs_panel:panel({
		w = panel_w,
		h = panel_h,
		alpha = 0,
		layer = 15,
	})
	convert_panel:set_center_x(cs_panel:w() * 0.5)
	convert_panel:set_y(math.floor(cs_panel:h() * 0.30))

	local title = convert_panel:text({
		name = "csr_cc_title",
		text = managers.localization:to_upper_text("csr_cash_convert_title"),
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = Color(1, 0.4, 1, 0.4),
		align = "center",
		vertical = "top",
		blend_mode = "add",
		layer = 1,
		w = panel_w,
		h = tweak_data.menu.pd2_small_font_size,
	})
	title:set_top(0)

	local money = convert_panel:text({
		name = "csr_cc_money",
		text = "$" .. managers.experience:cash_string(total_cash, ""),
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color.white,
		align = "left",
		vertical = "center",
		blend_mode = "add",
		layer = 1,
		w = panel_w * 0.5,
		h = tweak_data.menu.pd2_medium_font_size,
	})
	money:set_left(10)
	money:set_top(title:bottom() + 4)

	local rank = convert_panel:text({
		name = "csr_cc_rank",
		text = "+" .. managers.localization:text("menu_cs_level", { level = 0 }),
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color(1, 0.4, 1, 0.4),
		align = "right",
		vertical = "center",
		blend_mode = "add",
		layer = 1,
		w = panel_w * 0.5,
		h = tweak_data.menu.pd2_medium_font_size,
	})
	rank:set_right(panel_w - 10)
	rank:set_top(money:top())

	local bar_w = math.min(400, panel_w - 20)
	local bar_h = 16
	local bar_x = math.floor((panel_w - bar_w) * 0.5)
	local bar_y = money:bottom() + 6

	local carry_target_w = 0
	if leftover_cash > 0 then
		carry_target_w = math.floor((leftover_cash / cash_per_rank) * bar_w)
	end

	local bg = convert_panel:rect({
		name = "csr_cc_bg",
		color = Color.black,
		alpha = 0.4,
		layer = 2,
		w = bar_w,
		h = bar_h,
		x = bar_x,
		y = bar_y,
	})

	local fg = convert_panel:rect({
		name = "csr_cc_fg",
		color = Color(1, 0.4, 1, 0.4),
		layer = 3,
		w = 0,
		h = bar_h,
		x = bar_x,
		y = bar_y,
	})

	local tick = convert_panel:text({
		name = "csr_cc_tick",
		text = "|",
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color.white,
		alpha = 0.4,
		align = "center",
		vertical = "center",
		blend_mode = "add",
		layer = 4,
		w = 8,
		h = bar_h + 8,
	})
	tick:set_center_x(bar_x + bar_w)
	tick:set_center_y(bar_y + bar_h * 0.5)

	self._csr_convert = {
		cash_bonus = cash_bonus,
		total_cash = total_cash,
		leftover_cash = leftover_cash,
		cash_per_rank = cash_per_rank,
		rank_costs = rank_costs,
		diff = diff,
		panel = convert_panel,
		title = title,
		money = money,
		rank = rank,
		bg = bg,
		fg = fg,
		tick = tick,
		carry_target_w = carry_target_w,
		bar_w = bar_w,
	}

	CSR_log(
		"built: cash_bonus="
			.. cash_bonus
			.. " total_cash="
			.. total_cash
			.. " leftover="
			.. leftover_cash
			.. " cash_per_rank="
			.. cash_per_rank
			.. " bar_w="
			.. bar_w
	)
end)

function CrimeSpreeResultTabItem:_csr_update_cash_convert(t, dt)
	if not self._update._csr then
		CSR_log("_csr_update_cash_convert FIRED (first frame); _csr_convert=" .. tostring(self._csr_convert ~= nil))
	end
	if not self._csr_convert then
		self:_advance_stage()
		return
	end

	local cc = self._csr_convert
	local st = self._update._csr

	if not st then
		local base_main_gain = 0
		if self._levels and self._levels.bonuses then
			for _, b in ipairs(self._levels.bonuses) do
				if b[3] then
					base_main_gain = base_main_gain + b[3]
				end
			end
		end

		st = {
			phase = "fade_in",
			phase_elapsed = 0,
			rank_idx = 0,
			fill_duration = 1.2,
			fill_elapsed = 0,
			base_cash = cc.total_cash,
			base_rank = 0,
			base_main_gain = base_main_gain,
		}
		self._update._csr = st
		CSR_log("stage 2 start: base_main_gain=" .. base_main_gain .. " cash_bonus=" .. cc.cash_bonus)
	end

	st.phase_elapsed = st.phase_elapsed + dt

	if st.phase == "fade_in" then
		local p = math.min(st.phase_elapsed / 0.5, 1)
		cc.panel:set_alpha(p)
		if p >= 1 then
			st.phase = "filling"
			st.phase_elapsed = 0
			st.rank_idx = 1
			st.fill_elapsed = 0
			if cc.cash_bonus > 0 and managers.menu then
				managers.menu:post_event("count_1")
			end
		end
		return
	end

	if st.phase == "filling" then
		-- E1: cash_bonus == 0 but leftover_cash > 0 — single partial fill, no rank tick, no SFX
		if cc.cash_bonus <= 0 then
			if cc.carry_target_w <= 0 then
				st.phase = "fade_out"
				st.phase_elapsed = 0
				return
			end
			st.fill_elapsed = st.fill_elapsed + dt
			local duration = 0.6
			local p = math.min(st.fill_elapsed / duration, 1)
			local target_w = cc.carry_target_w
			cc.fg:set_w(math.floor(target_w * p))
			cc.money:set_text("$" .. managers.experience:cash_string(math.floor(math.lerp(cc.total_cash, 0, p)), ""))
			if p >= 1 then
				cc.fg:set_w(target_w)
				cc.money:set_text("$0")
				st.phase = "hold"
				st.phase_elapsed = 0
			end
			return
		end

		st.fill_elapsed = st.fill_elapsed + dt
		local p = math.min(st.fill_elapsed / st.fill_duration, 1)

		-- Per-rank cost (escalates within mission). Falls back to base if the
		-- mission-bonus side didn't populate the array (defensive).
		local cur_cost = (cc.rank_costs and cc.rank_costs[st.rank_idx]) or cc.cash_per_rank

		cc.fg:set_w(math.floor(cc.bar_w * p))
		local money_now = math.floor(math.lerp(st.base_cash, st.base_cash - cur_cost, p))
		cc.money:set_text("$" .. managers.experience:cash_string(money_now, ""))

		if st.fill_elapsed >= st.fill_duration then
			cc.fg:set_w(cc.bar_w)
			cc.money:set_text("$" .. managers.experience:cash_string(st.base_cash - cur_cost, ""))
			cc.rank:set_text("+" .. managers.localization:text("menu_cs_level", { level = st.base_rank + 1 }))

			if self._levels and self._levels.gain then
				self._levels.gain:set_text("+" .. managers.localization:text("menu_cs_level", {
					level = managers.experience:cash_string(st.base_main_gain + st.rank_idx, ""),
				}))
			end

			if managers.menu then
				managers.menu:post_event("count_1_finished")
			end
			if cc.tick and cc.tick.animate then
				cc.tick:animate(CrimeSpreeResultTabItem.animate_modifier_unlock)
			end

			if st.rank_idx < cc.cash_bonus then
				st.base_cash = st.base_cash - cur_cost
				st.base_rank = st.base_rank + 1
				st.rank_idx = st.rank_idx + 1
				st.fill_duration = math.max(0.30, st.fill_duration * 0.88)
				st.fill_elapsed = 0
				cc.fg:set_w(0)
				if managers.menu then
					managers.menu:post_event("count_1")
				end
			else
				if managers.menu_component then
					managers.menu_component:post_event("stinger_new_weapon")
				end
				if cc.leftover_cash > 0 then
					st.base_cash = st.base_cash - cur_cost
					cc.fg:set_w(0)
					st.phase = "carry_reveal"
					st.phase_elapsed = 0
				else
					st.phase = "hold"
					st.phase_elapsed = 0
				end
			end
		end
		return
	end

	if st.phase == "carry_reveal" then
		local duration = math.max(0.30, st.fill_duration)
		local p = math.min(st.phase_elapsed / duration, 1)
		local end_w = cc.carry_target_w
		cc.fg:set_w(math.floor(math.lerp(0, end_w, p)))

		cc.money:set_text("$" .. managers.experience:cash_string(math.floor(math.lerp(cc.leftover_cash, 0, p)), ""))

		if p >= 1 then
			cc.fg:set_w(end_w)
			cc.money:set_text("$0")
			st.phase = "hold"
			st.phase_elapsed = 0
		end
		return
	end

	if st.phase == "hold" then
		if st.phase_elapsed >= 0.8 then
			st.phase = "fade_out"
			st.phase_elapsed = 0
		end
		return
	end

	if st.phase == "fade_out" then
		local p = math.min(st.phase_elapsed / 0.5, 1)
		cc.panel:set_alpha(1 - p)
		if p >= 1 then
			st.phase = "done"
			self._update._csr = nil
			self:_advance_stage()
		end
		return
	end
end

if CrimeSpreeResultTabItem.stages then
	local already_injected = false
	for _, s in ipairs(CrimeSpreeResultTabItem.stages) do
		if s.func == "_csr_update_cash_convert" then
			already_injected = true
			break
		end
	end
	if not already_injected then
		table.insert(CrimeSpreeResultTabItem.stages, 2, {
			delay = 0.3,
			func = "_csr_update_cash_convert",
		})
		CSR_log("injected stage at index 2")
	end
end
