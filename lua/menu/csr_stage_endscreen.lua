-- CSRStageEndScreenGui / CSRCrimeSpreeResultTabItem — fork of the vanilla
-- end-screen GUI pair.
--
-- Origin:
--   pd2_source_code/lib/managers/menu/stageendscreengui.lua
--     (StageEndScreenGui, lines 511-1241; StatsTabItem 1-509 is NOT forked)
--   pd2_source_code/lib/managers/menu/stageendscreentabcrimespree.lua
--     (CrimeSpreeResultTabItem, 749 lines)
--
-- Strategy: byte-for-byte copy of StageEndScreenGui with the class renamed and
-- a SMALL, surgical diff (the 6 `managers.crime_spree:is_active()` sites made
-- unconditional, plus two class-reference swaps). Every other method (tabs,
-- scrolling, mouse/input, bain debrief, console subtitles, update loop, close)
-- is byte-identical to vanilla — those drive the generic StatsTabItem stat
-- pages which are vanilla-correct and read managers.statistics, NOT crime_spree.
--
-- The base StatsTabItem class is REUSED, never redefined: CSRCrimeSpreeResultTabItem
-- subclasses the vanilla global StatsTabItem exactly as vanilla
-- CrimeSpreeResultTabItem does. Redefining StatsTabItem here would leak into
-- every vanilla end screen (feedback_csr_only_no_vanilla_leak).
--
-- Class renames:
--   StageEndScreenGui       -> CSRStageEndScreenGui
--   CrimeSpreeResultTabItem -> CSRCrimeSpreeResultTabItem
--   CrimeSpreeMissionsMenuComponent.get_height() -> CSRMissionsMenuComponent.get_height()
--
-- The 6 surgical gate flips in CSRStageEndScreenGui:init (all forced to the
-- CS-style branch, since this class is only ever instantiated for a CSR heist
-- by csr_endscreen_wiring.lua):
--   1. panel width  : the CS `w = w - padding + 1` shrink, unconditional
--   2. panel bottom  : reserve CSRMissionsMenuComponent.get_height() like CS
--   3. continue_text : blanked ("") like CS — the real continue/cash-out flow
--                      is the post-heist options node (Slice B), not this button
--   4. result tab    : build CSRCrimeSpreeResultTabItem, skip the cash summary
--   5. small font    : reduced like CS (the CS result tab is wide)
--   6. set_continue_button_text : no-op like CS
--
-- Backend swaps (CSRCrimeSpreeResultTabItem only):
--   managers.crime_spree:mission_completion_gain() -> managers.csr:constant("rank_per_heist")
--   managers.crime_spree:has_failed()              -> (dropped; CSR failure
--                                                     state is Slice B)
--   missions_completed counter sourced from managers.csr:missions_completed()
--
-- Dropped (vanilla-CS spree economy with no CSR backend, per the locked
-- end-screen design — rank-gain animation + missions counter only):
--   _create_rewards / _update_reward_gain   (spree reward-tier cards)
--   _create_timeline / _update_level_gain   (modifier-unlock timeline)
--   catchup_bonus / spree_level / mission_start_spree_level / modifiers_to_select
--
-- Routing (which class instantiates) lives in csr_endscreen_wiring.lua, gated
-- on the run-scoped no-leak signal (job == "crime_spree" AND vanilla CS NOT
-- active) so vanilla / vanilla CS / Skirmish are byte-for-byte untouched.

local padding = 10

-- =====================================================================
-- CSRCrimeSpreeResultTabItem — simplified fork of CrimeSpreeResultTabItem.
-- Only the rank-gain panel + a missions-completed line; the reward-card and
-- modifier-timeline panels are dropped (no CSR backend, per locked design).
-- The gain count-up animation machinery (stages / _advance_stage / update /
-- fade_in / count_text / _update_gain_calculate) is reused verbatim from
-- vanilla — it is generic and not spree-coupled.
-- =====================================================================

CSRCrimeSpreeResultTabItem = CSRCrimeSpreeResultTabItem or class(StatsTabItem)

-- Verbatim vanilla CrimeSpreeResultTabItem:init (tab text + select rect),
-- then our trimmed :_setup().
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

	self:_create_level(0.75)
end

-- CSR has no per-mission failure state yet (Slice B). Success is purely the
-- vanilla stage-success flag here; the failure branches below stay only as a
-- defensive mirror of vanilla so the layout never errors if stage_success() is
-- false for some non-CSR-failure reason (kicked / server left).
function CSRCrimeSpreeResultTabItem:success()
	return managers.job:stage_success()
end

function CSRCrimeSpreeResultTabItem:make_fine_text(text)
	local x, y, w, h = text:text_rect()

	text:set_size(w, h)
	text:set_position(math.round(text:x()), math.round(text:y()))

	return x, y, w, h
end

-- Repurposed vanilla _create_level: the animated "gain" number now counts the
-- run's rank gain (flat managers.csr:constant("rank_per_heist")) instead of the
-- spree level gain, and a static missions-completed line is added below it
-- using the same loc keys the lobby/briefing forks use (csr_lobby_rank /
-- csr_lobby_missions_completed) so all three CSR surfaces read identically.
function CSRCrimeSpreeResultTabItem:_create_level(total_w)
	self._level_panel = self._cs_panel:panel({})

	local rank_gain = 0
	if managers.csr and managers.csr.constant then
		rank_gain = managers.csr:constant("rank_per_heist") or 1
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

		local bonus_amt = nil

		if level ~= nil then
			bonus_amt = self._level_panel:text({
				vertical = "center",
				blend_mode = "add",
				w = 200,
				align = "center",
				alpha = 0,
				layer = 10,
				text = "+" .. managers.localization:text("menu_cs_level", {
					level = level or 0,
				}),
				h = font_size,
				font_size = font_size,
				font = font,
				color = color or tweak_data.screen_colors.crime_spree_risk,
			})

			bonus_amt:set_center_x(gain_x)
			bonus_amt:set_top(bonus:bottom())
		end

		table.insert(self._levels.bonuses, {
			bonus,
			bonus_amt,
			level,
		})
	end

	if not self:success() then
		add_bonus(managers.localization:text("menu_cs_mission_failed"), nil, tweak_data.screen_colors.important_1)
	end

	if rank_gain > 0 and self:success() then
		add_bonus(managers.localization:text("menu_cs_mission_complete"), rank_gain)
	end

	-- Rank/missions counters are NOT repeated here: the status bar above the
	-- mission-cards strip (csr_missions_menu.lua:_create_status_bar, now also
	-- on the end screen via the fix-#3 wiring) already shows RANK + MISSIONS.
	-- This tab only owns the animated rank-GAIN number.
end

function CSRCrimeSpreeResultTabItem:set_stats(stats_data) end

function CSRCrimeSpreeResultTabItem:feed_statistics(stats_data) end

-- Only the gain count-up stage survives; the level-timeline and reward-card
-- stages are dropped (their panels do not exist in this fork).
CSRCrimeSpreeResultTabItem.stages = {
	{
		delay = 1,
		func = "_update_gain_calculate",
	},
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

-- Verbatim vanilla _update_gain_calculate: fades each bonus in and counts the
-- gain number up by the bonus amount. With our single "mission complete" bonus
-- this animates the rank gain from 0 to rank_per_heist.
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
			bonus[2]:animate(callback(self, self, "fade_in"), fade_t, t)

			t = t + fade_t + 0.5

			self._levels.gain:animate(
				callback(self, self, "count_text"),
				"+",
				gain_amt,
				gain_amt + bonus[3],
				count_bonus_t,
				t
			)

			gain_amt = gain_amt + bonus[3]
		end

		t = t + count_bonus_t + 1

		if self:success() then
			if i ~= #self._levels.bonuses then
				bonus[1]:animate(callback(self, self, "fade_out"), fade_t * 0.66, t)
			end

			if bonus[2] then
				bonus[2]:animate(callback(self, self, "fade_out"), fade_t * 0.66, t)
			end

			t = t + 0.4
		end
	end

	self:_advance_stage(t)
end

-- =====================================================================
-- CSRStageEndScreenGui — fork of StageEndScreenGui (the 6 gate flips marked
-- inline with `CSR:`). Everything else is verbatim vanilla.
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

	-- CSR gate 2: reserve the forked missions-strip height like vanilla CS.
	self._panel:set_bottom(self._safe_workspace:panel():h() - (CSRMissionsMenuComponent.get_height() + padding))

	local continue_button = managers.menu:is_pc_controller() and "[ENTER]" or nil
	local continue_text = utf8.to_upper(managers.localization:text("menu_es_calculating_experience", {
		CONTINUE = continue_button,
	}))

	-- CSR gate 3: the CS end screen blanks the inline continue text; the real
	-- continue/cash-out flow is the post-heist options node (Slice B).
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

	-- CSR gate 4: build the forked result tab; never show the cash summary
	-- (vanilla CS skips it too — CSR has no per-heist cash payout screen).
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

	-- The vanilla stats-box frame (BoxGuiObject around the selected tab) is
	-- intentionally NOT drawn for the CSR fork. It framed the cash/XP summary
	-- area; with per-heist cash/XP suppressed (fix #2) and the cash summary
	-- skipped (gate 4), that frame is left as stray empty corners next to the
	-- mission cards (user report 2026-05-18). box_panel was a throwaway local
	-- (never stored on self / referenced again), so dropping it is inert.

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

-- CSR gate 6: the CS end screen ignores inline continue-button-text updates
-- (the continue flow is the post-heist options node, Slice B). No-op.
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

log("[CSR] csr_stage_endscreen.lua loaded (CSRStageEndScreenGui + CSRCrimeSpreeResultTabItem fork)")
