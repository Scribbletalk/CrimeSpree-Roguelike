-- CSRMissionsMenuComponent — Rewards feature-panel (extracted from missions_menu.lua).
-- Loads on lib/managers/menu/menucomponentmanager AFTER missions_menu.lua (mod.txt
-- order), so the class table already exists; this file just adds the panel method
-- to it. Self-contained: its own layout constants live here.
if not RequiredScript then
	return
end

-- Defensive: missions_menu.lua defines the class. If load order ever regresses so
-- this file runs first, skip rather than index a nil class (the panel would be
-- empty, not a crash). With the correct mod.txt order this never triggers.
if not CSRMissionsMenuComponent then
	return
end

-- Rewards feature-panel layout. Four compact rows (one per run-completion reward):
-- a vanilla loot-card thumbnail on the left + title/amount on the right. The card
-- keeps its 128x180 portrait aspect and fills the row height; the row height is
-- derived from the panel height (4 rows + gaps), capped so tall panels don't
-- balloon the cards. The whole block is centred vertically in the panel.
local rewards_panel_row_gap = 12
local rewards_panel_max_row_h = 96
local rewards_panel_card_aspect = 128 / 180 -- loot-card art is portrait (w/h)
local rewards_panel_text_gap = 12 -- card right edge -> title/amount column

-- Shared feature-panel inner padding (declared locally in each sidebar file; matches
-- the value used by every feature panel in missions_menu.lua).
local items_panel_padding = 16

-- Build / rebuild the Rewards feature-panel: the four run-completion rewards
-- (cash, XP, Continental Coins, Loot Cards) as compact rows -- a vanilla loot-card
-- thumbnail on the left + title/amount on the right. The amounts are the PROJECTED
-- run-end payout at the current rank + difficulty: CSR pays out FROM RANK at the
-- end of a spree (not per heist), so the panel answers "what do I get if I end the
-- spree now?". Formulas + per-rank tables are locked in
-- project_csr_reward_system_design.
--
-- Read-only and local-state-only (rank is the run's; the skill/infamy XP mults are
-- THIS player's), so MP-safe with no packet. A client whose rank hasn't synced yet
-- just shows its local value -- same deferred-sync caveat as the items panel.
function CSRMissionsMenuComponent:_populate_rewards_panel()
	if not self._feature_panels or not alive(self._feature_panels.rewards) then
		return
	end
	local panel = self._feature_panels.rewards

	if self._rewards_content and alive(self._rewards_content) then
		panel:remove(self._rewards_content)
	end
	self._rewards_content = nil

	local content = panel:panel({
		layer = 5,
	})
	self._rewards_content = content

	-- Projected run-end payout from the single source of truth (managers.csr:
	-- projected_rewards -- the SAME numeric table End Spree awards). cash_string
	-- prefixes the locale cash sign ("$"); experience_string is the bare grouped
	-- number (we add the "+"). pcall-isolated -- a display must never crash the lobby.
	local mgr = managers and managers.csr
	local r = (mgr and mgr.projected_rewards and mgr:projected_rewards()) or {}
	-- Bucket B = guest earnings banked while playing in hosts' lobbies (own run
	-- paused). Shown as a SECOND value column ("MP SESSIONS") beside the own-run
	-- projection whenever anything is banked; a host/SP player who never guested has
	-- B=0 and sees the unchanged single column. End Spree pays A + B
	-- (project_csr_mp_reward_model).
	local b = (mgr and mgr.mp_earnings and mgr:mp_earnings()) or {}
	local show_mp = mgr and mgr.has_mp_earnings and mgr:has_mp_earnings() or false

	-- Format one component identically for both columns (cash sign / grouped XP).
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
		{ icon = "upcard_cash", title = "CASH", own = cash_fmt(r.cash), mp = cash_fmt(b.cash) },
		{ icon = "upcard_xp", title = "EXPERIENCE", own = xp_fmt(r.experience), mp = xp_fmt(b.experience) },
		{
			icon = "upcard_coins",
			title = "CONTINENTAL COINS",
			own = tostring(r.continental_coins or 0),
			mp = tostring(b.continental_coins or 0),
		},
		{
			icon = "upcard_random",
			title = "LOOT CARDS",
			own = tostring(r.loot_drop or 0),
			mp = tostring(b.loot_drop or 0),
		},
	}

	-- Row height fits 4 rows + 3 gaps (plus a header row when the MP column shows)
	-- into the panel, capped so tall panels keep sane card sizes; block centred.
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

	-- Value column geometry: single column fills the text area (legacy look); with the
	-- MP column present, split into own (left) | mp (right) halves.
	local col_gap = show_mp and rewards_panel_text_gap or 0
	local col_w = show_mp and math.floor((total_text_w - col_gap) / 2) or total_text_w
	local own_x = text_x
	local mp_x = text_x + col_w + col_gap

	-- Column headers (only when the MP column is present).
	if show_mp then
		content:text({
			name = "reward_hdr_own",
			text = "THIS RUN",
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
			text = "MP SESSIONS",
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

		-- Loot-card thumbnail (vanilla atlas; get_icon_data returns texture + rect,
		-- nil-safe). Fills the row height at the portrait aspect.
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

		-- Title (dim) above the amount(s), the pair vertically centred against the
		-- card so a short row still reads as a unit.
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
