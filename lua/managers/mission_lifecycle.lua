-- Post-heist orchestration on MissionEndState:at_enter — rank gain, loot→token
-- accrual, shop restock, new mission set. Failure → mark_failed (run stays active
-- but locked). See csr_vanilla_intercepts.md.

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

	-- Suppress vanilla's end-screen XP. Vanilla's own CS guard in :update is false
	-- for CSR. Force _completion_bonus_done so the continue button doesn't stay
	-- _continue_blocked (skipping the XP block also skips set_completion_bonus_done).
	-- Set the field directly — the setter's _set_continue_button_text fires too early.
	-- Cash is suppressed separately in endscreen_economy.lua (must be at the source).
	self._total_xp_bonus = false
	self._completion_bonus_done = true

	if self._success then
		-- Guest playing in a host's lobby PAUSES its own run: rank, mission count,
		-- loot→rank and mission set do NOT advance. Heist reward banks into bucket B
		-- (valued at HOST difficulty), paid at the guest's own End Spree as A + B.
		local guesting = managers.csr.is_guesting and managers.csr:is_guesting()
		local played_id = managers.csr:current_mission()
		local gain
		if guesting then
			gain = managers.csr:rank_for_current_level()
		else
			gain = managers.csr:rank_for_mission(played_id)
		end
		if guesting then
			managers.csr:accrue_mp_earnings(gain)
		else
			managers.csr:progress_rank(gain)
			managers.csr:record_mission_completed()
		end

		-- Looted cash drives BOTH a token stream AND extra rank progress.
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
		local completion_tokens, loot_tokens = 0, 0
		if _G.CSR_Shop then
			completion_tokens = CSR_Shop.award_completion_tokens(pid, gain)
			loot_tokens = CSR_Shop.accrue_loot_tokens(pid, loot_cash)
		end
		local loot_ranks
		if guesting then
			loot_ranks = managers.csr:accrue_guest_loot_rank(loot_cash)
		else
			loot_ranks = managers.csr:accrue_loot_rank(loot_cash)
		end

		-- Stash for the end-screen conversion animation (stage_endscreen.lua reads this).
		-- Runtime field, not serialized.
		local per_token = managers.csr:reward_per_rank_cash() / ((_G.CSR_Shop and CSR_Shop.TOKENS_PER_RANK) or 5)
		local reward_entry = managers.csr:peer_entry(pid)
		managers.csr._last_heist_rewards = {
			completion_tokens = completion_tokens,
			loot_tokens = loot_tokens,
			loot_cash = loot_cash,
			per_token = per_token,
			remainder = (reward_entry and reward_entry.loot_token_cash) or 0,
		}

		-- Shop restock: completing a heist is the shop's refresh boundary. Per-peer + local.
		if _G.CSR_Shop and CSR_Shop.roll_lineup then
			CSR_Shop.roll_lineup(pid)
		end

		-- New mission set — host/SP only (guest's lobby is driven by host).
		if not guesting then
			managers.csr:generate_mission_set()
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
end)

log_csr("mission_lifecycle.lua loaded")
