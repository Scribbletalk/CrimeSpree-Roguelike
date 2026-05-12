-- Crime Spree Roguelike - Mission completion bonuses
-- Cash-to-ranks conversion and MP difficulty catchup/penalty

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

-- Helper: calculate current cumulative engine cash (large bags + small loot + kill cash).
-- Large bags are read from _global.secured (populated by LootManager:sync_secure_loot) PLUS
-- each VehicleDrivingExt._loot (populated by server_store_loot_in_vehicle, e.g. boats).
-- Vanilla multi-day "stage 1 of 2" heists (RVD Day 1, Hoxton Breakout Day 1, etc.) used
-- to deliver bags via ElementCarry operation="remove", silently vanishing them without
-- ever touching _global.secured. crimespree_carry_tracker.lua now PreHooks that path and
-- promotes remove -> managers.loot:secure(...) in CS mode, so those bags now flow through
-- the standard secure pipeline (HUD update, stinger sound, _global.secured entry).
-- Small loot and kill cash come from get_real_total_small_loot_value (which CSR_SafeOverride
-- in crimespree_kill_cash.lua injects CSR_MissionKillCash into).
local function CSR_CalcEngineCash()
	local bag_value = 0

	local secured = managers.loot and managers.loot._global and managers.loot._global.secured or {}
	for _, data in ipairs(secured) do
		local carry_data = tweak_data.carry[data.carry_id]
		if carry_data and not tweak_data.carry.small_loot[data.carry_id] and not carry_data.is_vehicle then
			bag_value = bag_value + managers.money:get_secured_bonus_bag_value(data.carry_id, data.multiplier)
		end
	end

	if managers.vehicle and managers.vehicle.get_all_vehicles then
		for _, vehicle in ipairs(managers.vehicle:get_all_vehicles() or {}) do
			if alive(vehicle) and vehicle.vehicle_driving then
				local ext = vehicle:vehicle_driving()
				local loot = ext and ext._loot
				if loot then
					for _, entry in ipairs(loot) do
						local carry_data = tweak_data.carry[entry.carry_id]
						if
							carry_data
							and not tweak_data.carry.small_loot[entry.carry_id]
							and not carry_data.is_vehicle
						then
							bag_value = bag_value
								+ managers.money:get_secured_bonus_bag_value(entry.carry_id, entry.multiplier)
						end
					end
				end
			end
		end
	end

	return bag_value + managers.loot:get_real_total_small_loot_value()
end

-- Snapshot engine cash at mission START so we can compute the delta at mission END.
-- This avoids the stale-global bug where CSR_ProcessedCash (set at previous heist's END)
-- is compared against values re-evaluated under a different game context.
-- Gate strictly on is_active() — vanilla's own on_mission_started early-returns on
-- not is_active() (PD2 source crimespreemanager.lua:1196), so any heist where vanilla
-- skips its body is NOT a CS heist and we must not snapshot for it. The previous OR
-- pattern fired this hook for any player with an in-progress CS run, which combined
-- with the on_mission_completed OR gate caused rank to tick up in vanilla heists.
-- TaheyaKinnie 2026-05-10.
Hooks:PostHook(CrimeSpreeManager, "on_mission_started", "CSR_SnapshotEngineCash", function(self)
	if not self:is_active() then
		return
	end
	self._csr_engine_cash_at_start = CSR_CalcEngineCash()
	CSR_log("[CSR Cash] Mission start snapshot: engine_cash=" .. tostring(self._csr_engine_cash_at_start))
end)

-- Override server_spree_level to return the HOST's rank when we have it.
-- CSR_MP_HostRank is set by _handle_handshake_ok (on join) and apply_rank_up (on level up),
-- and cleared by on_left_lobby. Checking the global directly instead of is_client()
-- avoids false negatives during mission loading when Network:session() may be nil.
local _original_server_spree_level = CrimeSpreeManager.server_spree_level
function CrimeSpreeManager:server_spree_level()
	if _G.CSR_MP_HostRank then
		return _G.CSR_MP_HostRank
	end
	return _original_server_spree_level(self)
end

-- PreHook: save current level and raw mission gain BEFORE vanilla runs.
-- Snapshot is_active() here (BEFORE vanilla's heist→endscreen transition can
-- cause is_active() to flicker on clients) and stash it on the manager. The
-- PostHook below reads the snapshot instead of calling is_active() directly,
-- which preserves the flicker protection without using the OR-with-in_progress()
-- pattern that leaked rank progression into vanilla heists for any player with
-- a CS run going. TaheyaKinnie 2026-05-10.
Hooks:PreHook(CrimeSpreeManager, "on_mission_completed", "CSR_SaveOldLevel", function(self, mission_id)
	self._csr_completed_was_cs = self:is_active() and true or false
	if not self._csr_completed_was_cs then
		return
	end

	-- Store old levels so we can revert vanilla's changes and apply our own
	self._csr_old_level = self._global.spree_level or 0
	self._csr_old_reward_level = self._global.reward_level or 0

	-- Save raw mission gain before vanilla's catchup/penalty modifies it
	local mission_data = self:get_mission(mission_id)
	self._csr_raw_mission_add = mission_data and mission_data.add or 0
end)

-- Streamlined Heisting compat. SH overrides on_mission_completed and adds
-- math.min(get_secured_bags_amount(), 20) to spree_add — bags-as-ranks on top
-- of vanilla mission gain. CSR already converts secured cash (which includes
-- bag value) to rank via cash_per_rank; SH's addition double-counts the bags
-- portion and inflates spree_level relative to host_earned, which fed the
-- late-join catchup bug (joiners receiving way too many items).
--
-- Neutralize by stubbing managers.loot:get_secured_bags_amount to 0 for the
-- duration of on_mission_completed. Vanilla's body of this function never
-- calls it (vanilla uses mission_data.add only), so this is a true no-op
-- without SH and a clean cancel of SH's bag-rank bonus when SH is present.
-- Restored unconditionally in the matching PostHook below.
Hooks:PreHook(CrimeSpreeManager, "on_mission_completed", "CSR_StripSHBagRankBonus", function(self)
	if not self._csr_completed_was_cs then
		return
	end
	if managers.loot and managers.loot.get_secured_bags_amount then
		self._csr_orig_get_secured_bags_amount = managers.loot.get_secured_bags_amount
		managers.loot.get_secured_bags_amount = function()
			return 0
		end
	end
end)

-- PostHook: add bonus levels for bags and kills AFTER vanilla runs
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_BagsKillsBonus", function(self, mission_id)
	-- Read the is_active() snapshot taken in the PreHook above. This preserves
	-- the original flicker protection (PreHook fires before any heist→endscreen
	-- transition flicker) without falling back to in_progress(), which used to
	-- let rank tick up in vanilla heists for any player with an in-progress CS
	-- run from before. TaheyaKinnie 2026-05-10.
	if not self._csr_completed_was_cs or self:has_failed() then
		return
	end

	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()

	-- Unconditional diagnostic log: tracks the rank-inflation bug ("164 -> 1000+")
	-- reported by MaoMao + The Jugger-Cat. Capture the inputs feeding cash_bonus and
	-- the spree_level reset path before any of them mutate. Strip after confirmed.
	log(
		"[CSR Rank Diag] mission_completed PRE: is_client="
			.. tostring(is_client)
			.. " spree_level="
			.. tostring(self._global.spree_level)
			.. " _csr_old_level="
			.. tostring(self._csr_old_level)
			.. " _csr_raw_mission_add="
			.. tostring(self._csr_raw_mission_add)
			.. " _csr_engine_cash_at_start="
			.. tostring(self._csr_engine_cash_at_start)
			.. " engine_cash_now="
			.. tostring(CSR_CalcEngineCash())
			.. " carried_cash="
			.. tostring(_G.CSR_CarriedCash)
			.. " mission_id="
			.. tostring(mission_id)
	)

	-- Client in multiplayer: revert ALL vanilla changes and use raw mission gain.
	-- Vanilla applies its own catchup/penalty (subtracts level difference) which can reduce
	-- the gain to 0 when client is far ahead. We replace that with our own rank scaling formula.
	local base_gain = 0
	if is_client and self._csr_old_level then
		self._global.spree_level = self._csr_old_level
		self._global.reward_level = self._csr_old_reward_level or self._csr_old_level
		-- Use raw mission gain (before vanilla penalty), not the penalized result
		base_gain = self._csr_raw_mission_add or 0
		CSR_log("[CSR MP] Client: reverted vanilla changes, using raw mission_add=" .. base_gain)

		-- Note: do NOT read get_peer_spree_level(1) here — that returns vanilla rank only
		-- (without our bags/kills bonus) and would overwrite the correct CSR_MP_HostRank.
		-- broadcast_rank_up from the host sends the correct value.
	end

	CSR_log(
		"[CSR Mission] on_mission_completed PostHook: is_client="
			.. tostring(is_client)
			.. " base_gain="
			.. base_gain
			.. " CSR_MP_HostRank="
			.. tostring(_G.CSR_MP_HostRank)
	)

	local bonus = base_gain

	-- === CASH-TO-RANKS CONVERSION ===
	-- Total cash earned (bags + loose loot + kill cash) is converted to bonus ranks.
	-- Conversion rate = value of one money bag at current difficulty.
	-- Table lives in base_modifier.lua (_G.CSR_ItemConstants.cash_per_rank) so both
	-- the math here and the UI in cash_convert_animation.lua read the same source.
	local CASH_PER_RANK = (_G.CSR_ItemConstants and _G.CSR_ItemConstants.cash_per_rank)
		or {
			normal = 7500,
			hard = 37500,
			very_hard = 75000,
			overkill = 157500,
			mayhem = 270000,
			death_wish = 307500,
			death_sentence = 345000,
		}

	-- Cash-to-rank scale must match the heist's actual payout difficulty. On a client,
	-- vanilla never overwrites _global.selected_difficulty with the host's value
	-- (see pd2_client_difficulty_engine_only memory), so the client's stored value
	-- can be wildly different from what the heist actually paid out at. Reading it
	-- here caused massive inflation: client_diff=normal (cash_per_rank=7500) vs.
	-- DS heist payout ($3M+) produced 400+ ranks per heist before the difficulty
	-- multiplier below compounded it 14x. Use the host's CSR difficulty instead.
	local current_diff
	if is_client then
		current_diff = _G.CSR_MP_HostDifficulty or "overkill"
	else
		current_diff = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "overkill"
	end
	local cash_per_rank = CASH_PER_RANK[current_diff] or 157500

	-- Unconditional diag (rare event, once per heist) — confirms which difficulty
	-- the cash-to-rank converter is using. Catches a client falling back to its
	-- own stored difficulty if CSR_MP_HostDifficulty was never received.
	log(
		"[CSR Cash] current_diff="
			.. tostring(current_diff)
			.. " (is_client="
			.. tostring(is_client)
			.. " host_diff="
			.. tostring(_G.CSR_MP_HostDifficulty)
			.. " client_stored_diff="
			.. tostring(self._global.selected_difficulty)
			.. ") cash_per_rank="
			.. tostring(cash_per_rank)
	)

	-- Compute cash earned THIS mission only by subtracting the snapshot taken
	-- at mission start.  Both values use the same evaluation context (same job,
	-- same difficulty stars), so bag re-valuation drift is impossible.
	--
	-- NIL-SNAPSHOT GUARD: if the start-of-mission snapshot is missing (client joined
	-- mid-run after on_mission_started already fired, or hot-reload between hooks),
	-- `engine_cash_now` includes the entire CS-cumulative `_global.secured` from
	-- prior heists. Falling through with `or 0` would make new_cash = total cumulative
	-- = 100s of bonus ranks. Treat missing snapshot as "no measurable delta" instead.
	local engine_cash_now = CSR_CalcEngineCash()
	local engine_cash_start = self._csr_engine_cash_at_start
	local new_cash
	if engine_cash_start == nil then
		new_cash = 0
		log(
			"[CSR Cash] WARN: missing on_mission_started snapshot — skipping cash bonus this heist (engine_cash_now="
				.. tostring(engine_cash_now)
				.. ")"
		)
	else
		new_cash = math.max(0, engine_cash_now - engine_cash_start)
	end

	-- Add leftover cash carried over from previous conversion
	local carried_cash = _G.CSR_CarriedCash or 0
	local total_cash = new_cash + carried_cash

	-- Escalating cost ladder: each subsequent rank within THIS mission costs
	-- +step*base more than the previous (additive of base, NOT compounding).
	-- Escalation resets next mission; only dollars carry over via _G.CSR_CarriedCash.
	local cash_step = (_G.CSR_ItemConstants and _G.CSR_ItemConstants.cash_per_rank_step) or 0.10

	local rank_costs = {}
	local cash_bonus = 0
	local consumed = 0
	while true do
		local next_cost = math.floor(cash_per_rank * (1 + cash_step * cash_bonus))
		if consumed + next_cost > total_cash then
			break
		end
		consumed = consumed + next_cost
		cash_bonus = cash_bonus + 1
		rank_costs[cash_bonus] = next_cost
	end

	local leftover_cash = total_cash - consumed
	_G.CSR_CarriedCash = leftover_cash

	if cash_bonus > 0 then
		bonus = bonus + cash_bonus
	end

	-- Gage Tokens — host-authoritative award.
	-- Formula: math.floor((mission_ranks + cash_ranks + 1) / 2) — round-half-up integer math.
	-- Host computes from its own (uncatchup'd) bonus and broadcasts the exact amount
	-- to all peers so wallets stay in lockstep regardless of MP catchup/penalty math below.
	-- Note: on the host, `bonus` here only contains cash_bonus — vanilla already added
	-- mission_data.add to spree_level between the PreHook and this PostHook. We re-add
	-- _csr_raw_mission_add for the token formula so it reflects the TOTAL ranks gained.
	if Network and Network:is_server() and CSR_TokensManager then
		local total_ranks = bonus + (self._csr_raw_mission_add or 0)
		local award = math.floor((total_ranks + 1) / 2)
		if award > 0 then
			CSR_TokensManager.credit(CSR_TokensManager.local_peer_id(), award)
			CSR_TokensManager.add_host_earned(award)
			local host_earned_now = CSR_TokensManager.get_host_earned()
			local payload = tostring(award) .. "|" .. tostring(host_earned_now)
			if LuaNetworking and CSR_MP and CSR_MP.MSG and CSR_MP.MSG.TOKEN_AWARD then
				LuaNetworking:SendToPeers(CSR_MP.MSG.TOKEN_AWARD, payload)
			end

			-- Advance the late-join catchup snapshot for every currently-connected
			-- peer to host_earned_now. Each handshake (on_entered_lobby /
			-- on_mission_started fallback) triggers run_for_peer; without this, it
			-- would re-grant items+leftover tokens for the heist we just paid out
			-- via TOKEN_AWARD. Peers who join later still see a real
			-- (host_earned - their_initial_snapshot) delta because we only touch
			-- snapshots for peers who were here for this broadcast.
			_G.CSR_HostCatchupSnapshots = _G.CSR_HostCatchupSnapshots or {}
			local sess = managers and managers.network and managers.network:session()
			if sess and sess.peers then
				for _, peer in pairs(sess:peers() or {}) do
					local pid = peer and peer:id()
					if pid and pid ~= 1 then
						local key
						if peer.user_id then
							local uid = peer:user_id()
							if uid and uid ~= "" then
								key = uid
							end
						end
						key = key or ("peer_" .. tostring(pid))
						_G.CSR_HostCatchupSnapshots[key] = host_earned_now
						log(
							"[CSR TOK] advanced host_catchup_snapshot for key="
								.. tostring(key)
								.. " (peer="
								.. tostring(pid)
								.. ") to "
								.. tostring(host_earned_now)
						)
					end
				end
			end

			log(
				"[CSR TOK] award="
					.. award
					.. " host_earned="
					.. tostring(host_earned_now)
					.. " total_ranks="
					.. tostring(total_ranks)
					.. " raw_mission_add="
					.. tostring(self._csr_raw_mission_add)
					.. " cash_bonus="
					.. tostring(cash_bonus)
			)
			-- Persist host-side state immediately after the host-earned counter is updated,
			-- so a quit before the next modifier-pick doesn't lose this heist's tokens.
			if CSR_SaveSeed then
				local current_seed = _G.CSR_CurrentSeed
				local current_difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"
				if current_seed then
					CSR_SaveSeed(current_seed, current_difficulty, self._global.modifiers)
				end
			end

			-- Persist the advanced host_catchup_snapshots to the session JSON. Without
			-- this, a host quit/restart between heists would lose the advancement and
			-- the next handshake from the same peer would re-grant.
			if CSR_SaveSession and _G.CSR_CurrentSeed then
				local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
				CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, _G.CSR_MP_TotalDrops)
			end
		end
	end

	-- Fresh shop lineup rolls per-peer at heist completion (each peer rolls their own).
	if CSR_ShopManager and CSR_ShopManager.on_heist_complete then
		CSR_ShopManager.on_heist_complete()
	end

	CSR_log(
		"[CSR Cash] total_cash="
			.. total_cash
			.. " carried_over="
			.. carried_cash
			.. " cash_per_rank="
			.. cash_per_rank
			.. " cash_bonus="
			.. cash_bonus
			.. " leftover="
			.. leftover_cash
			.. " total_bonus="
			.. bonus
	)

	-- === MULTIPLAYER DIFFICULTY SCALING ===
	-- Compare host vs client difficulty using reward multiplier ratio.
	-- Higher-difficulty host → catchup (ratio > 1, uncapped).
	-- Lower-difficulty host → penalty (ratio < 1, minimum 1 point).
	local DIFFICULTY_REWARD_MULT = {
		normal = 0.12,
		hard = 0.25,
		very_hard = 0.52,
		overkill = 1.0,
		mayhem = 1.28,
		death_wish = 1.41,
		death_sentence = 1.68,
	}

	-- Apply difficulty scaling ONLY to the base mission gain (mission_data.add).
	-- cash_bonus is already in the host's frame (cash_per_rank above looks up the
	-- host's difficulty), so multiplying it again would double-apply the scaling
	-- and produce thousand-rank inflations on big heists.
	local difficulty_multiplier = 1
	if base_gain > 0 and is_client and _G.CSR_MP_HostDifficulty then
		local host_diff = _G.CSR_MP_HostDifficulty
		local client_diff = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "overkill"
		local host_mult = DIFFICULTY_REWARD_MULT[host_diff] or 1.0
		local client_mult = DIFFICULTY_REWARD_MULT[client_diff] or 1.0
		if client_mult > 0 then
			difficulty_multiplier = host_mult / client_mult
			local raw_bonus = bonus
			local scaled_base = math.max(1, math.floor(base_gain * difficulty_multiplier))
			bonus = scaled_base + cash_bonus
			CSR_log(
				"[CSR MP] Client difficulty scaling (base_gain only): host="
					.. host_diff
					.. "("
					.. host_mult
					.. ") client="
					.. client_diff
					.. "("
					.. client_mult
					.. ") mult="
					.. string.format("%.2f", difficulty_multiplier)
					.. " base_gain "
					.. base_gain
					.. " -> "
					.. scaled_base
					.. " bonus "
					.. raw_bonus
					.. " -> "
					.. bonus
			)
		end
	end

	-- Vanilla already set _mission_completion_gain = mission_data.add (raw gain).
	-- We keep it as-is: bags, kills, and rank adjustment show as separate UI entries.

	-- === APPLY BONUS ===
	if bonus > 0 then
		self._global.spree_level = self._global.spree_level + bonus

		-- highest_level is intentionally NOT bumped here. We only update the all-time
		-- peak when the player CLAIMS rewards on the end-screen — see flush_reward_amount
		-- PostHook below. A heist that inflates rank but is never claimed (player quits
		-- before end-screen) leaves the prior highest intact.

		-- Update reward_level (drives experience/coins calculation)
		self._global.reward_level = self._global.reward_level + bonus

		-- Update rewards (experience, continental_coins, cash)
		self._global.unshown_rewards = self._global.unshown_rewards or {}
		for _, reward in ipairs(tweak_data.crime_spree.rewards) do
			self._global.unshown_rewards[reward.id] = (self._global.unshown_rewards[reward.id] or 0)
				+ bonus * reward.amount
		end
	end

	-- Host: always broadcast current rank to clients after mission completion.
	-- Must be OUTSIDE the bonus block — vanilla already increased spree_level by the
	-- base mission gain, and clients need to know the new total for item drop tracking.
	if not is_client and _G.CSR_MP and CSR_MP.broadcast_rank_up then
		CSR_MP.broadcast_rank_up(self._global.spree_level)
	end

	-- Store difficulty adjustment for UI (positive = catchup, negative = penalty)
	if difficulty_multiplier ~= 1 then
		self._csr_rank_adjustment = bonus - (base_gain + cash_bonus)
	else
		self._csr_rank_adjustment = 0
	end

	-- Store for UI display (bags_ui.lua reads cash_bonus, rank_ui.lua reads rank_adjustment)
	self._csr_bonus_bags = cash_bonus
	self._csr_total_cash = total_cash
	self._csr_rank_costs = rank_costs
end)

-- PostHook: update meta-progress stats
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_UpdateMetaProgress", function(self)
	if not self:is_active() or self:has_failed() then
		return
	end

	if CSR_MetaProgress then
		CSR_MetaProgress:AddMission()
		CSR_MetaProgress:AddKills(self._csr_total_kills or 0)
		CSR_MetaProgress:AddBags(self._csr_bonus_bags or 0)

		-- Per-difficulty highest is intentionally NOT updated here. Like vanilla highest_level,
		-- it now claim-gates via flush_reward_amount PostHook below.

		-- Record cash and coins earned
		if self._global.unshown_rewards then
			if self._global.unshown_rewards.cash then
				CSR_MetaProgress:AddCash(self._global.unshown_rewards.cash)
			end
			if self._global.unshown_rewards.continental_coins then
				CSR_MetaProgress:AddCoins(self._global.unshown_rewards.continental_coins)
			end
		end

		CSR_MetaProgress:Save()
	end
end)

-- Pair to CSR_StripSHBagRankBonus PreHook above. Always runs (even if PreHook
-- bailed) so a swapped-in stub is guaranteed to be reverted before any other
-- code path could read get_secured_bags_amount.
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_RestoreSecuredBagsAmount", function(self)
	if self._csr_orig_get_secured_bags_amount then
		managers.loot.get_secured_bags_amount = self._csr_orig_get_secured_bags_amount
		self._csr_orig_get_secured_bags_amount = nil
	end
end)

-- ===================================================================
-- HIGHEST_LEVEL CLAIM-GATING
-- ===================================================================
-- Vanilla calls _check_highest_level on every rank-up (give_progress, complete_crime_spree),
-- which means a buggy rank inflation immediately persisted to highest_level too.
-- We want highest_level to only update when the player actually CLAIMS rewards on the
-- end-screen — quitting before claiming preserves prior highest. Implementation:
--   1. PreHook _check_highest_level: temporarily set highest_level above `value` so
--      vanilla's `if value > highest_level then` check fails; vanilla skips the bump
--      AND skips the OnHighestCrimeSpree event.
--   2. PostHook _check_highest_level: restore the original highest_level.
--   3. PostHook flush_reward_amount (fires per reward type on end-screen): bump
--      highest_level to the current spree_level if higher. This is the moment the
--      player "locks in" their progress.
Hooks:PreHook(CrimeSpreeManager, "_check_highest_level", "CSR_BlockVanillaHighestBump", function(self, value)
	self._csr_pre_check_highest = self._global.highest_level or 0
	self._global.highest_level = math.max(self._csr_pre_check_highest, (value or 0) + 1)
end)

Hooks:PostHook(CrimeSpreeManager, "_check_highest_level", "CSR_RestoreHighestAfterBlock", function(self, value)
	if self._csr_pre_check_highest ~= nil then
		self._global.highest_level = self._csr_pre_check_highest
		self._csr_pre_check_highest = nil
	end
end)

Hooks:PostHook(CrimeSpreeManager, "flush_reward_amount", "CSR_BumpHighestOnClaim", function(self, reward_id)
	local current = self._global.spree_level or 0

	-- Vanilla all-time highest. Vanilla's own save mechanism picks up the field write.
	if current > (self._global.highest_level or 0) then
		self._global.highest_level = current
	end

	-- CSR per-difficulty highest (claim-gated alongside vanilla highest).
	-- flush fires up to ~5x per end-screen (one per reward type), but the JSON write is
	-- small and end-screen isn't a hot path. Saving every call avoids losing the update
	-- if the player quits between end-screen and the next mission_completed.
	if CSR_MetaProgress and CSR_MetaProgress.UpdateHighestLevelForDifficulty then
		local current_difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"
		CSR_MetaProgress:UpdateHighestLevelForDifficulty(current_difficulty, current)
		if CSR_MetaProgress.Save then
			CSR_MetaProgress:Save()
		end
	end
end)
