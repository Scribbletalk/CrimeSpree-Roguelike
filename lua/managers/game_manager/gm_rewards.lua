-- CSRGameManager end-of-run rewards, guest earnings & MP host-state mirror (Tier 1 split from game_manager.lua).
if not CSRGameManager then
	return
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

-- =====================================================
-- End-of-run rewards (projection + award source of truth)
-- =====================================================

-- Per-rank cash multiplier by CSR difficulty index (1=normal..7=death_sentence). Mirrors moneytweakdata.
local REWARD_PAYOUT_MULT = { 1, 2, 5, 10, 11, 13, 14 }

-- tweak_data.difficulties leads with "easy" (index 1), so CSR index = difficulty_to_index - 1.
function CSRGameManager:reward_difficulty_index()
	local di = (tweak_data and tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(self:difficulty()))
		or 2
	return math.max(1, math.min(7, di - 1))
end

-- Reward components for `rank` ranks at CSR difficulty index `idx`.
-- Shared by projected_rewards (bucket A) and accrue_mp_earnings (bucket B).
function CSRGameManager:_rewards_for(rank, idx)
	rank = tonumber(rank) or 0
	local XP_MULT = { 0, 2, 5, 10, 11.5, 13, 14 }

	local cash = 200000 * (REWARD_PAYOUT_MULT[idx] or 1) * rank
	local xp = 12000 * (1 + (XP_MULT[idx] or 0)) * rank
	-- pcall-isolated so a menu projection never errors.
	local skill_mult, infamy_mult = 1, 1
	pcall(function()
		skill_mult = (managers.player and managers.player:get_skill_exp_multiplier()) or 1
	end)
	pcall(function()
		infamy_mult = (managers.player and managers.player:get_infamy_exp_multiplier()) or 1
	end)
	xp = xp * skill_mult * infamy_mult

	return {
		cash = math.round(cash),
		experience = math.round(xp),
		continental_coins = rank * 2,
		loot_drop = rank,
	}
end

function CSRGameManager:projected_rewards()
	-- Bucket A: own rank/difficulty (guest bucket B is summed in separately at End Spree).
	return self:_rewards_for(self:rank(), self:reward_difficulty_index())
end

-- CSR difficulty index for the host's synced difficulty (bucket B). Falls back to own when not guesting.
function CSRGameManager:host_reward_difficulty_index()
	local hd = self:mp_host_difficulty()
	if type(hd) ~= "string" then
		return self:reward_difficulty_index()
	end
	local di = (tweak_data and tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(hd)) or 2
	return math.max(1, math.min(7, di - 1))
end

-- =====================================================
-- Guest earnings bucket B
-- =====================================================

-- Bank one guest heist's reward into _meta.mp_earnings at host difficulty. Called only from the guest fork.
function CSRGameManager:accrue_mp_earnings(rank_gained)
	rank_gained = tonumber(rank_gained) or 0
	if rank_gained <= 0 then
		return nil
	end
	local r = self:_rewards_for(rank_gained, self:host_reward_difficulty_index())
	local b = self._meta.mp_earnings or { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 }
	b.cash = (b.cash or 0) + r.cash
	b.experience = (b.experience or 0) + r.experience
	b.continental_coins = (b.continental_coins or 0) + r.continental_coins
	b.loot_drop = (b.loot_drop or 0) + r.loot_drop
	self._meta.mp_earnings = b
	self:save()
	log_csr(
		"accrue_mp_earnings: +"
			.. tostring(r.cash)
			.. " cash / +"
			.. tostring(r.experience)
			.. " xp (bucket B now "
			.. tostring(b.cash)
			.. " cash)"
	)
	return r
end

-- Guest analogue of accrue_loot_rank: converts looted cash to bucket B ranks at host difficulty.
function CSRGameManager:accrue_guest_loot_rank(loot_cash)
	loot_cash = tonumber(loot_cash) or 0
	if loot_cash <= 0 then
		return 0
	end
	local per_rank = self:reward_per_rank_cash()
	if per_rank <= 0 then
		return 0
	end
	local entry = self:_guest_session_entry(true)
	if not entry then
		return 0
	end
	local acc = (entry.loot_rank_cash or 0) + loot_cash
	local ranks = math.floor(acc / per_rank)
	entry.loot_rank_cash = acc - ranks * per_rank
	if ranks > 0 then
		self:accrue_mp_earnings(ranks) -- accrue_mp_earnings saves
	else
		self:save() -- persist the carried remainder
	end
	return ranks
end

-- Read-only copy of bucket B; always a full table (zeros when empty).
function CSRGameManager:mp_earnings()
	local b = self._meta.mp_earnings or {}
	return {
		cash = b.cash or 0,
		experience = b.experience or 0,
		continental_coins = b.continental_coins or 0,
		loot_drop = b.loot_drop or 0,
	}
end

-- True when bucket B has claimable earnings (lets a rank-0 guest still cash out at End Spree).
function CSRGameManager:has_mp_earnings()
	local b = self._meta.mp_earnings
	if not b then
		return false
	end
	return (b.cash or 0) > 0 or (b.experience or 0) > 0 or (b.continental_coins or 0) > 0 or (b.loot_drop or 0) > 0
end

-- Zero bucket B after it has been paid out (End Spree A + B). Persists.
function CSRGameManager:reset_mp_earnings()
	self._meta.mp_earnings = { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 }
	self:save()
end

-- True while the local player is a client in an announced CSR run.
function CSRGameManager:is_guesting()
	return self:_is_guesting()
end

-- Cash value of one rank at the current earning difficulty.
-- Returns host difficulty while guesting so shared loot converts at the same rate as the host.
function CSRGameManager:reward_per_rank_cash()
	local idx = self:_is_guesting() and self:host_reward_difficulty_index() or self:reward_difficulty_index()
	return 200000 * (REWARD_PAYOUT_MULT[idx] or 1)
end

-- Feed completed-heist loot into the rank accumulator; every full reward_per_rank_cash() grants +1 rank.
function CSRGameManager:accrue_loot_rank(loot_cash)
	loot_cash = tonumber(loot_cash) or 0
	if loot_cash <= 0 or not self._state.is_active then
		return 0
	end
	local per_rank = self:reward_per_rank_cash()
	if per_rank <= 0 then
		return 0
	end
	local acc = (self._state.loot_rank_cash or 0) + loot_cash
	local ranks = math.floor(acc / per_rank)
	self._state.loot_rank_cash = acc - ranks * per_rank
	if ranks > 0 then
		self:progress_rank(ranks) -- progress_rank saves
	else
		self:save() -- persist the carried remainder
	end
	return ranks
end

function CSRGameManager:seed()
	return self._state.seed
end

function CSRGameManager:host_rank()
	-- Returns host's synced rank while guesting (for enemy scaling + item quota); own rank otherwise.
	local mp = self._state.mp_session
	if mp and mp.host_rank then
		local mpnet = _G.CSR_MP
		local guesting = mpnet and mpnet.is_client and mpnet.is_client()
		if guesting then
			return mp.host_rank
		end
	end
	return self._state.rank or 0
end

-- Store host's synced rank/difficulty/seed from the MP host-state push (client only).
function CSRGameManager:set_mp_host_state(host_rank, host_difficulty, host_seed, host_missions)
	self._state.mp_session = self._state.mp_session or {}
	local mp = self._state.mp_session
	if type(host_rank) == "number" then
		mp.host_rank = host_rank
	end
	if type(host_difficulty) == "string" then
		mp.host_difficulty = host_difficulty
	end
	if type(host_seed) == "number" then
		mp.host_seed = host_seed
	end
	if type(host_missions) == "number" then
		mp.host_missions = host_missions
	end
end

-- Host's completed-heist count while guesting (nil on host/SP). Gated to prevent stale value leaking after leaving.
function CSRGameManager:mp_host_missions_completed()
	if not self:_is_guesting() then
		return nil
	end
	local mp = self._state.mp_session
	return mp and mp.host_missions or nil
end

-- Drop synced host state on leave/between heists; guest falls back to own _state during the load window.
function CSRGameManager:clear_mp_host_state()
	local mp = self._state.mp_session
	if not mp then
		return
	end
	mp.host_rank = nil
	mp.host_difficulty = nil
	mp.host_seed = nil
	mp.host_missions = nil
	-- Also clear so the guest re-pulls a fresh mission set on the next lobby open.
	mp.host_mission_set = nil
end

-- Host difficulty while guesting (nil otherwise). Gated to prevent stale value leaking into own-host lobby.
function CSRGameManager:mp_host_difficulty()
	if not self:_is_guesting() then
		return nil
	end
	local mp = self._state.mp_session
	return mp and mp.host_difficulty or nil
end

-- Late-join grant snapshot, keyed per host run in the session record. Re-joining the same host
-- triggers an INCREMENTAL grant only when the host's completed-mission count has changed since the
-- last grant. guest_grant_missions() returns nil until the first grant has run.
function CSRGameManager:guest_grant_missions()
	local key = self:_guest_session_key()
	if not key then
		return nil
	end
	local sess = self._meta.mp_sessions and self._meta.mp_sessions[key]
	return sess and sess.grant_missions
end

-- Host gross-tokens already converted at the last grant; the next grant only spends the delta above this.
function CSRGameManager:guest_grant_gross()
	local key = self:_guest_session_key()
	if not key then
		return 0
	end
	local sess = self._meta.mp_sessions and self._meta.mp_sessions[key]
	return (sess and sess.grant_gross) or 0
end

function CSRGameManager:mark_guest_grant(missions, gross)
	local key = self:_guest_session_key()
	if not key then
		return
	end
	self:_guest_session_entry(true)
	local sess = self._meta.mp_sessions and self._meta.mp_sessions[key]
	if sess then
		sess.grant_missions = tonumber(missions) or 0
		sess.grant_gross = tonumber(gross) or 0
		self:save()
	end
end
