-- CSR mission lifecycle (Slice 7 wiring).
--
-- Hooks MissionEndState:at_enter so a CSR run progresses rank when the player
-- completes a heist. Mirrors the vanilla call site at
-- lib/states/missionendstate.lua:95-101 (success -> on_mission_completed,
-- failure -> on_mission_failed), but routes into managers.csr instead.
--
-- Rank gain on success scales with the mission's LENGTH category -- the clock
-- icon on the lobby card (user balance spec 2026-05-23): short = 1, medium = 2,
-- long = 3. The category + mapping live in managers.csr:rank_for_mission (it
-- mirrors vanilla's add-value thresholds so the rank matches the displayed
-- clock). rank_per_heist remains only as the fallback for an unresolved mission.
--
-- Failure path is a log-only stub for this slice. Roguelike end-on-death and
-- vanilla-style rank-regression are both deferred.

local function log_csr(msg)
	log("[CSR] " .. tostring(msg))
end

-- No-leak gate (feedback_csr_only_no_vanilla_leak). managers.csr:is_active() is
-- a persisted csr_save.json flag and end_run() is never driven in U1, so after
-- the first start_run() it stays true across sessions. Gating ONLY on it meant
-- completing a VANILLA heist after a CSR run granted rank, counted a mission and
-- rerolled the mission set for that vanilla heist (user report 2026-05-18).
--
-- The correctly-scoped signal is the active job, not the flag: a CSR-launched
-- heist runs the temporary "crime_spree" job (activate_temporary_job on launch)
-- with vanilla Crime Spree NOT enabled; a vanilla heist carries its real job id.
-- This is byte-identical to briefing_wiring.lua:csr_briefing_active() — the
-- already-verified run-scoped CSR-exclusive signal. The job is still set at
-- MissionEndState:at_enter (vanilla calls on_mission_completed here, which reads
-- job/level), so the signal is valid at this hook point.
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

	-- CSR grants NO per-heist XP or cash: rewards accrue only at run
	-- completion. Vanilla Crime Spree suppresses end-screen XP via
	-- MissionEndState:update's
	--   `if managers.crime_spree:is_active() then self._total_xp_bonus = false end`
	-- (missionendstate.lua:864) — that guard is false for a CSR heist (CSR
	-- never enables vanilla CS), so the XP would otherwise be given. Mirror
	-- the suppression here (this PostHook runs after at_enter has set
	-- _total_xp_bonus via completion_bonus_done() at :238).
	--
	-- _completion_bonus_done must be forced true: skipping the XP block in
	-- :update also skips its set_completion_bonus_done() call, which would
	-- otherwise leave the inline continue button permanently _continue_blocked
	-- (:783). Set the field directly rather than via the setter to avoid its
	-- _set_continue_button_text() side effect firing before the endscreen GUI
	-- exists; our forked continue button is a no-op anyway, and :update
	-- refreshes the text later when the block timer clears. Vanilla CS does
	-- not get stuck because its continue is the separate post-heist options
	-- node (Slice B), not the inline button — revisit when that lands.
	--
	-- Cash is suppressed separately in endscreen_economy.lua: the payout
	-- is added inside at_enter (:134) BEFORE this PostHook fires, so it must
	-- be gated in MoneyManager, it cannot be undone here.
	self._total_xp_bonus = false
	self._completion_bonus_done = true

	if self._success then
		-- Rank gain scales with the mission's length category -- the clock icon on
		-- the lobby card (short = 1, medium = 2, long = 3; see rank_for_mission).
		-- Read the played mission id BEFORE generate_mission_set clears
		-- current_mission below.
		local played_id = managers.csr:current_mission()
		local gain = managers.csr:rank_for_mission(played_id)
		managers.csr:progress_rank(gain)
		-- Track completed-heist count for the run independently of rank (the
		-- lobby header shows it next to RANK; the two are distinct concepts).
		managers.csr:record_mission_completed()

		-- Looted cash this heist = full secured value (bags + small loot). It drives
		-- TWO independent rewards, both measured against the run's per-rank payout
		-- (project_csr_token_earning):
		--   * Gage Tokens (shop): 5 per completion rank + 1 per (per_rank/5) of loot.
		--   * extra rank progress: every full per_rank of loot grants +1 rank.
		-- pcall-isolated: the CSR temp "crime_spree" job is unusual and a mission-end
		-- hook must never error. These are host-local loot reads; MP token sync (at
		-- host difficulty) is deferred with the rest of the MP slice.
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
		local loot_ranks = managers.csr:accrue_loot_rank(loot_cash)

		-- Mirror vanilla on_mission_completed: clear the played mission and roll
		-- a fresh set so the lobby shows new cards on return.
		managers.csr:generate_mission_set()
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
		-- Slice B: a lost heist FAILS the run (does not end it). The run stays
		-- active but locked — the lobby gates Start/Reroll/select on
		-- managers.csr:has_failed() until the player pays Continue
		-- (clear_failed) or gives up via End Spree (end_run). mark_failed is a
		-- no-op if no run is active, so this is safe on any non-CSR failure
		-- that slipped past csr_heist_active() (it cannot — but defensive).
		managers.csr:mark_failed()
		log_csr("mission FAILED: run marked failed (locked until Continue/End Spree)")
	end
end)

log_csr("mission_lifecycle.lua loaded (Slice 7 wiring)")
