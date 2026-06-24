-- Post-heist: rank gain, loot→token accrual, shop restock, new mission set; failure locks the run.

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

local function csr_heist_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

Hooks:PostHook(MissionEndState, "at_enter", "CSR_MissionLifecycle_AtEnter", function(self)
	if self._server_left or self._kicked then
		return
	end
	if not managers.csr or not csr_heist_active() then
		return
	end

	-- Idempotency guard: _completion_bonus_done is set below; re-entry of the end state skips re-award.
	if self._completion_bonus_done then
		return
	end

	-- Suppress vanilla XP; cash is suppressed in endscreen_economy.lua.
	self._total_xp_bonus = false
	self._completion_bonus_done = true

	-- Capture the result-screen music event now; on_mission_end() overwrites current_event with a
	-- fade-reset so we can't recover the track name from it later. See pd2_music_current_event_not_playing_track.md.
	if managers.music and managers.music.jukebox_menu_track then
		_G.CSR_post_mission_music = managers.music:jukebox_menu_track(self._success and "heistresult" or "heistlost")
	end

	if self._success then
		-- Guest progress banks separately, paid out at the guest's own End Spree.
		local guesting = managers.csr.is_guesting and managers.csr:is_guesting()
		local played_id = managers.csr:current_mission()
		local gain
		if guesting then
			gain = managers.csr:rank_for_current_level()
		else
			gain = managers.csr:rank_for_mission(played_id)
		end
		-- guest_coin_mult/guest_p: computed once, reused for loot-rank below.
		local guest_coin_mult, guest_p
		if guesting then
			local host_n = managers.csr:mp_host_missions_completed() or 0
			guest_coin_mult = managers.csr:coin_streak_mult(host_n)
			guest_p = managers.csr:heist_participation()
			managers.csr:accrue_mp_earnings(gain, guest_coin_mult, guest_p)
			-- note_guest_present_mission: lets this mission's rank pick surface as a normal choice;
			-- HANDSHAKE_OK catch-up only auto-grants missions the guest was absent for.
			managers.csr:note_guest_present_mission()
		else
			managers.csr:progress_rank(gain)
			managers.csr:record_mission_completed()
			-- Career peak rank: host/SP only (guest rank is paused while guesting).
			managers.csr:record_career_max("highest_rank", managers.csr:rank())
			-- Career peak spree depth (host/SP).
			managers.csr:record_career_max("longest_spree", managers.csr:missions_completed())
		end

		-- Career lifetime mission count: host/SP AND guest.
		managers.csr:add_career_stat("total_missions", 1)
		-- Tally toward held wildcard progress (nil held = no-op).
		managers.csr:record_wildcard_mission(managers.csr:held_wildcard(managers.csr:local_peer_id()))

		local loot_cash = 0
		pcall(function()
			if managers.money and managers.loot then
				loot_cash = (managers.money:get_secured_bonus_bags_money() or 0)
					+ (managers.money:get_secured_mandatory_bags_money() or 0)
					+ (managers.loot:get_real_total_small_loot_value() or 0)
					+ (managers.loot:get_real_total_postponed_small_loot_value() or 0)
			end
		end)

		local pid = managers.csr:local_peer_id()
		-- Snapshot carry BEFORE accrual; accrue_* mutates in place so read these now for end-screen bars.
		local start_carry = managers.csr:loot_rank_carry()
		local _pre_entry = managers.csr:peer_entry(pid)
		local start_carry_tok = (_pre_entry and _pre_entry.loot_token_cash) or 0
		local completion_tokens, loot_tokens = 0, 0
		if _G.CSR_Shop then
			completion_tokens = CSR_Shop.award_completion_tokens(pid, gain)
			loot_tokens = CSR_Shop.accrue_loot_tokens(pid, loot_cash)
		end
		local loot_ranks
		local escalated_add = 0
		if guesting then
			loot_ranks = managers.csr:accrue_guest_loot_rank(loot_cash, guest_coin_mult, guest_p)
		else
			loot_ranks = managers.csr:accrue_loot_rank(loot_cash)
			-- Bank escalated coins (host/SP); missions_completed already incremented above.
			escalated_add = managers.csr:accrue_escalated_coins(gain + (loot_ranks or 0))
		end

		-- Reward card values (display only; payout already accrued above).
		-- Host shows escalated coins; guest scales by participation + streak at host difficulty.
		local total_rank = (gain or 0) + (loot_ranks or 0)
		local heist_cards
		if guesting then
			local r = managers.csr:_rewards_for(total_rank, managers.csr:host_reward_difficulty_index())
			heist_cards = {
				experience = math.round(r.experience * (guest_p or 1)),
				cash = math.round(r.cash * (guest_p or 1)),
				continental_coins = math.round(r.continental_coins * (guest_coin_mult or 1) * (guest_p or 1)),
				loot_drop = math.round(r.loot_drop * (guest_p or 1)),
			}
		else
			local r = managers.csr:_rewards_for(total_rank, managers.csr:reward_difficulty_index())
			heist_cards = {
				experience = r.experience,
				cash = r.cash,
				continental_coins = math.round(escalated_add or 0),
				loot_drop = r.loot_drop,
			}
		end

		-- Runtime stash for stage_endscreen.lua conversion animation; not serialized.
		local per_token = managers.csr:reward_per_rank_cash() / ((_G.CSR_Shop and CSR_Shop.TOKENS_PER_RANK) or 5)
		local reward_entry = managers.csr:peer_entry(pid)
		managers.csr._last_heist_rewards = {
			completion_tokens = completion_tokens,
			loot_tokens = loot_tokens,
			loot_cash = loot_cash,
			per_token = per_token,
			remainder = (reward_entry and reward_entry.loot_token_cash) or 0,
			heist_cards = heist_cards,
			mission_rank = gain,
			per_rank = managers.csr:reward_per_rank_cash(),
			start_carry = start_carry,
			start_carry_tok = start_carry_tok,
		}

		-- Shop restock: completing a heist is the shop's refresh boundary. Per-peer + local.
		if _G.CSR_Shop and CSR_Shop.roll_lineup then
			CSR_Shop.roll_lineup(pid)
		end

		-- New mission set (host/SP only). Exclude the just-played heist from the auto-roll;
		-- paid rerolls don't carry this exclusion.
		if not guesting then
			managers.csr:generate_mission_set(played_id)
			-- Flag newly-unlocked modifiers for the panel's blue tint + siren.
			managers.csr:refresh_modifier_highlight()
		end
		log_csr(
			"mission completed: +"
				.. tostring(gain)
				.. " rank (mission "
				.. tostring(played_id)
				.. "); loot="
				.. tostring(loot_cash)
				.. "; tokens +"
				.. tostring(completion_tokens + loot_tokens)
				.. " ("
				.. tostring(completion_tokens)
				.. " heist + "
				.. tostring(loot_tokens)
				.. " loot); loot ranks +"
				.. tostring(loot_ranks)
				.. "; new set rolled"
		)
	else
		-- Run locked until Continue (paid) or End Spree.
		managers.csr:mark_failed()
		log("[CSR] mission FAILED: run marked failed (locked until Continue/End Spree)")
	end

	-- Flush combat tally into career totals (win or loss).
	managers.csr:flush_heist_tally()

	-- Clear the in-flight flag so the grace timer / crash-detect don't fire for a finished heist.
	if managers.csr.clear_in_heist and not (managers.csr.is_guesting and managers.csr:is_guesting()) then
		managers.csr:clear_in_heist()
	end
end)

-- Destroy the CSR end-screen backdrop at at_exit (pre-reinit). Setup:load_start_menu rebuilds
-- HUDManager and nils _hud_stage_endscreen before lobby teardowns run, leaving the panel orphaned.
-- Gate on our metatable so non-CSR end-screens are untouched.
Hooks:PostHook(MissionEndState, "at_exit", "CSR_MissionLifecycle_TeardownEndscreenBackdrop", function()
	local es = managers.hud and managers.hud._hud_stage_endscreen
	local is_csr = es ~= nil and CSRHUDStageEndScreen ~= nil and getmetatable(es) == CSRHUDStageEndScreen
	if is_csr and es.close then
		es:close()
		managers.hud._hud_stage_endscreen = nil
		log_csr("at_exit: CSR end-screen backdrop torn down (pre-reinit)")
	end
end)

-- Capture heist join time so heist_participation() can scale guest rewards by how long they were present.
if IngameWaitingForPlayersState and not _G._CSR_HeistParticipation_Hooked then
	_G._CSR_HeistParticipation_Hooked = true
	Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_HeistParticipation_Join", function()
		if not managers.csr then
			return
		end
		local t = 0
		pcall(function()
			t = (managers.game_play_central and managers.game_play_central:get_heist_timer()) or 0
		end)
		managers.csr._heist_join_time = t
		-- Reset combat tally so this heist counts from zero.
		if managers.csr.in_csr_heist and managers.csr:in_csr_heist() then
			managers.csr:reset_heist_tally()
		end
		if _G.CSR_DEBUG then
			csr_log("[CSR] heist join captured: t_join=" .. tostring(t))
		end
	end)
end

log_csr("mission_lifecycle.lua loaded")
