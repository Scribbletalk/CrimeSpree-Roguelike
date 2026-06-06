-- CSRMissionsMenuComponent — Rewards feature-panel (extends class from missions_menu.lua).
-- Four rows (cash / XP / coins / loot cards) showing projected run-end payout.
-- Second "MP SESSIONS" column appears when bucket B (guest earnings) is non-empty.
-- See project_csr_reward_system_design + project_csr_mp_reward_model.

if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

local rewards_panel_row_gap = 12
local rewards_panel_max_row_h = 96
local rewards_panel_card_aspect = 128 / 180
local rewards_panel_text_gap = 12

local items_panel_padding = 16

function CSRMissionsMenuComponent:_populate_rewards_panel()
	if not self._feature_panels or not alive(self._feature_panels.rewards) then
		return
	end
	local panel = self._feature_panels.rewards

	if self._rewards_content and alive(self._rewards_content) then
		panel:remove(self._rewards_content)
	end
	self._rewards_content = nil

	local content = panel:panel({ layer = 5 })
	self._rewards_content = content

	-- Bucket A = own run; Bucket B = guest earnings banked while guesting in hosts' lobbies.
	-- End Spree pays A + B.
	local mgr = managers and managers.csr
	local r = (mgr and mgr.projected_rewards and mgr:projected_rewards()) or {}
	local b = (mgr and mgr.mp_earnings and mgr:mp_earnings()) or {}
	local show_mp = mgr and mgr.has_mp_earnings and mgr:has_mp_earnings() or false

	local function cash_fmt(v)
		local s = "$0"
		pcall(function()
			s = managers.experience:cash_string(v or 0)
		end)
		return s
	end
	local function xp_fmt(v)
		local s = "0"
		pcall(function()
			s = managers.experience:experience_string(v or 0)
		end)
		return "+" .. s
	end

	local rows = {
		{
			icon = "upcard_cash",
			title = managers.localization:text("csr_rewards_cash"),
			own = cash_fmt(r.cash),
			mp = cash_fmt(b.cash),
		},
		{
			icon = "upcard_xp",
			title = managers.localization:text("csr_rewards_experience"),
			own = xp_fmt(r.experience),
			mp = xp_fmt(b.experience),
		},
		{
			icon = "upcard_coins",
			title = managers.localization:text("csr_rewards_continental_coins"),
			own = tostring(r.continental_coins or 0),
			mp = tostring(b.continental_coins or 0),
		},
		{
			icon = "upcard_random",
			title = managers.localization:text("csr_rewards_loot_cards"),
			own = tostring(r.loot_drop or 0),
			mp = tostring(b.loot_drop or 0),
		},
	}

	-- Row height fits 4 rows + 3 gaps (plus header when MP column shows).
	local pad = items_panel_padding
	local small = tweak_data.menu.pd2_small_font_size
	local avail_h = panel:h() - pad * 2
	local header_h = show_mp and small or 0
	local header_gap = show_mp and rewards_panel_row_gap or 0
	local rows_avail = avail_h - header_h - header_gap
	local row_h = math.min(rewards_panel_max_row_h, math.floor((rows_avail - rewards_panel_row_gap * 3) / 4))
	row_h = math.max(row_h, tweak_data.menu.pd2_medium_font_size + small)
	local card_w = math.floor(row_h * rewards_panel_card_aspect)
	local block_h = header_h + header_gap + row_h * 4 + rewards_panel_row_gap * 3
	local start_y = pad + math.max(0, math.floor((avail_h - block_h) / 2))
	local text_x = pad + card_w + rewards_panel_text_gap
	local total_text_w = math.max(0, panel:w() - pad - text_x)

	local col_gap = show_mp and rewards_panel_text_gap or 0
	local col_w = show_mp and math.floor((total_text_w - col_gap) / 2) or total_text_w
	local own_x = text_x
	local mp_x = text_x + col_w + col_gap

	if show_mp then
		content:text({
			name = "reward_hdr_own",
			text = managers.localization:text("csr_rewards_this_run"),
			font = tweak_data.menu.pd2_small_font,
			font_size = small,
			color = Color.white:with_alpha(0.6),
			x = own_x,
			y = start_y,
			w = col_w,
			h = header_h,
			vertical = "center",
			layer = 10,
		})
		content:text({
			name = "reward_hdr_mp",
			text = managers.localization:text("csr_rewards_mp_sessions"),
			font = tweak_data.menu.pd2_small_font,
			font_size = small,
			color = Color.white:with_alpha(0.6),
			x = mp_x,
			y = start_y,
			w = col_w,
			h = header_h,
			vertical = "center",
			layer = 10,
		})
	end

	local rows_y0 = start_y + header_h + header_gap

	for i, row in ipairs(rows) do
		local ry = rows_y0 + (i - 1) * (row_h + rewards_panel_row_gap)

		local tex, rect = tweak_data.hud_icons:get_icon_data(row.icon)
		content:bitmap({
			name = "reward_card",
			texture = tex,
			texture_rect = rect,
			x = pad,
			y = ry,
			w = card_w,
			h = row_h,
			layer = 10,
		})

		local title_h = small
		local amount_h = tweak_data.menu.pd2_medium_font_size
		local tb_y = ry + math.floor((row_h - (title_h + amount_h)) / 2)

		content:text({
			name = "reward_title",
			text = row.title,
			font = tweak_data.menu.pd2_small_font,
			font_size = small,
			color = Color.white:with_alpha(0.6),
			x = text_x,
			y = tb_y,
			w = total_text_w,
			h = title_h,
			vertical = "center",
			layer = 10,
		})
		content:text({
			name = "reward_own",
			text = row.own,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = tweak_data.screen_colors.text,
			x = own_x,
			y = tb_y + title_h,
			w = col_w,
			h = amount_h,
			vertical = "center",
			layer = 10,
		})
		if show_mp then
			content:text({
				name = "reward_mp",
				text = row.mp,
				font = tweak_data.menu.pd2_medium_font,
				font_size = tweak_data.menu.pd2_medium_font_size,
				color = tweak_data.screen_colors.text,
				x = mp_x,
				y = tb_y + title_h,
				w = col_w,
				h = amount_h,
				vertical = "center",
				layer = 10,
			})
		end
	end
end
