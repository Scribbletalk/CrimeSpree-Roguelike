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
		if guesting then
			managers.csr:accrue_mp_earnings(gain)
		else
			managers.csr:progress_rank(gain)
			managers.csr:record_mission_completed()
		end

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

		-- Runtime stash for end-screen conversion animation (stage_endscreen.lua), not serialized.
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

log_csr("mission_lifecycle.lua loaded")
