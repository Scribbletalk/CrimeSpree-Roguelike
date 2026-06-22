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

	-- Idempotency: we set _completion_bonus_done = true just below; on a re-entry of the end state
	-- it's already true, so don't re-award rank/tokens/loot. Resets per heist (MissionEndState:init).
	if self._completion_bonus_done then
		return
	end

	-- Suppress vanilla XP and unblock the continue button; cash suppressed in endscreen_economy.lua.
	self._total_xp_bonus = false
	self._completion_bonus_done = true

	-- Record the result-screen music event so the Black Market can resume it on close. The state
	-- posts this track then on_mission_end() overwrites Global.current_event with a fade-reset that
	-- names no track, so the menu can't read the audible track back from current_event.
	if managers.music and managers.music.jukebox_menu_track then
		_G.CSR_post_mission_music = managers.music:jukebox_menu_track(self._success and "heistresult" or "heistlost")
	end

	if self._success then
		-- Guest run is paused: progress banks into bucket B, paid out at guest's own End Spree.
		local guesting = managers.csr.is_guesting and managers.csr:is_guesting()
		local played_id = managers.csr:current_mission()
		local gain
		if guesting then
			gain = managers.csr:rank_for_current_level()
		else
			gain = managers.csr:rank_for_mission(played_id)
		end
		-- guest_coin_mult/guest_p are computed once in the guest branch and reused for loot-rank.
		local guest_coin_mult, guest_p
		if guesting then
			local host_n = managers.csr:mp_host_missions_completed() or 0
			guest_coin_mult = managers.csr:coin_streak_mult(host_n)
			guest_p = managers.csr:heist_participation()
			managers.csr:accrue_mp_earnings(gain, guest_coin_mult, guest_p)
			-- Account this present mission so its rank pick surfaces as a normal choice the guest makes;
			-- the HANDSHAKE_OK catch-up only auto-grants host missions the guest was ABSENT for.
			managers.csr:note_guest_present_mission()
		else
			managers.csr:progress_rank(gain)
			managers.csr:record_mission_completed()
			-- Career peak rank (host/SP only; a guest's own rank is paused while guesting).
			managers.csr:record_career_max("highest_rank", managers.csr:rank())
			-- Career peak spree depth: most missions completed in a single spree (host/SP).
			managers.csr:record_career_max("longest_spree", managers.csr:missions_completed())
		end

		-- Career lifetime mission count: every completed CSR heist, host/SP AND guest.
		managers.csr:add_career_stat("total_missions", 1)
		-- Tally this heist toward the local player's held wildcard (carry-1; nil held = skipped).
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
		-- Snapshot loot carry BEFORE accrual so the endscreen can pre-fill the rank/token bars.
		-- accrue_* mutates these in place to the post-heist remainder, so read them now.
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
			-- Bank this heist's escalated coins (host/SP). Total rank = mission-length gain + loot
			-- ranks; multiplier uses missions_completed, already incremented above.
			escalated_add = managers.csr:accrue_escalated_coins(gain + (loot_ranks or 0))
		end

		-- Per-heist reward components for the end-screen reward cards (display only; these already
		-- accrued toward the run payout above). Mirrors the banked values per role: host shows the
		-- escalated coins it banked; guest scales by participation + streak at host difficulty.
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

		-- Runtime stash for end-screen conversion animation (stage_endscreen.lua), not serialized.
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

		-- New mission set — host/SP only (guest's lobby is driven by host).
		-- Exclude the just-completed heist so it can't reappear in the auto-roll; a paid
		-- reroll omits the exclusion, so the mission can still come back if rerolled.
		if not guesting then
			managers.csr:generate_mission_set(played_id)
			-- Flag the modifiers THIS mission unlocked for the panel's blue tint + siren (per-mission
			-- precision; guests detect lazily on panel build once the host's rank syncs).
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
		-- Failed: run stays active but LOCKED until Continue (paid) or End Spree.
		managers.csr:mark_failed()
		log("[CSR] mission FAILED: run marked failed (locked until Continue/End Spree)")
	end

	-- Bank this heist's combat tally (kills / damage dealt / taken) into career totals. Runs for
	-- both win and loss — the kills/damage happened either way. CSR-gated by the hook's early return.
	managers.csr:flush_heist_tally()

	-- Heist resolved cleanly (win or wipe) -> clear the loss-penalty in-flight flag so the grace
	-- timer and crash-detect can't fire for a finished heist. Host/SP only (guest never set it).
	if managers.csr.clear_in_heist and not (managers.csr.is_guesting and managers.csr:is_guesting()) then
		managers.csr:clear_in_heist()
	end
end)

-- Destroy the CSR end-screen backdrop (mission-name ghost) while its Lua handle is still alive.
-- Returning to the menu runs Setup:load_start_menu -> init_managers, which rebuilds HUDManager
-- (so _hud_stage_endscreen goes nil) but leaves the MenuBackdropGUI panel orphaned on the C++
-- fullscreen_workspace. The lobby/on_enter_lobby teardowns run AFTER that reinit and find nil,
-- so the ghost bled under the "CRIME SPREE ROGUELIKE" header. at_exit fires pre-reinit. Gate on
-- our metatable so non-CSR endscreens are untouched.
Hooks:PostHook(MissionEndState, "at_exit", "CSR_MissionLifecycle_TeardownEndscreenBackdrop", function()
	local es = managers.hud and managers.hud._hud_stage_endscreen
	local is_csr = es ~= nil and CSRHUDStageEndScreen ~= nil and getmetatable(es) == CSRHUDStageEndScreen
	if is_csr and es.close then
		es:close()
		managers.hud._hud_stage_endscreen = nil
		log_csr("at_exit: CSR end-screen backdrop torn down (pre-reinit)")
	end
end)

-- Capture the heist timer at heist entry so heist_participation() can compute how much of the
-- mission the local player was present for: ~0 for a from-start player; the host's synced
-- elapsed time for a drop-in client. Mirrors the _G._CSR_*_Hooked guard used by the other
-- IngameWaitingForPlayersState hooks (apply_modifiers / quit_penalty / mp_session).
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
		-- Reset the per-heist combat tally so kills/damage count from zero this heist (CSR only).
		if managers.csr.in_csr_heist and managers.csr:in_csr_heist() then
			managers.csr:reset_heist_tally()
		end
		if _G.CSR_DEBUG then
			csr_log("[CSR] heist join captured: t_join=" .. tostring(t))
		end
	end)
end

log_csr("mission_lifecycle.lua loaded")
