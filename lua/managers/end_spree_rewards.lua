-- CSR End Spree reward award — drives the VANILLA Crime Spree reward screen with
-- CSR's own per-rank values.
--
-- The vanilla CrimeSpreeRewardsMenuComponent (opened by the crime_spree_claim_rewards
-- node) reads managers.crime_spree:calculate_rewards() for the cards and calls
-- on_spree_complete() to actually grant the rewards. Both are hard-wired to
-- managers.crime_spree, and on_spree_complete() early-returns unless vanilla CS is
-- in_progress() -- which CSR never is (we run a temp "crime_spree" job WITHOUT the
-- vanilla gamemode). So the stock award path is a no-op for us.
--
-- We intercept both, gated on a CSR-owned pending table
-- (managers.csr._pending_end_rewards) that _dialog_end_csr_yes sets right before the
-- node opens. When no claim is pending the table is nil and vanilla CS behaves
-- exactly as before -- no leak (a pure vanilla-CS player never walks the CSR End
-- Spree path, so the table is only ever set by us).
--
-- award_rewards itself needs no patch: it's a pure id->manager dispatch
-- (experience -> give_experience, cash -> money:add_to_total, continental_coins ->
-- custom_safehouse:add_coins, loot_drop -> generate_loot_drops) with no in_progress
-- dependency. Feeding it our table grants the real money / XP / coins and kicks off
-- the loot-card coroutine the screen animates. It is player-local (no RPC), so each
-- player who ends the spree grants their own rewards.
--
-- Raw method wraps (not PostHook): calculate_rewards must change the RETURN value and
-- on_spree_complete must bypass the original's in_progress gate -- neither is possible
-- via PostHook. This is the sanctioned CSR exception to Rule #1 for return-value /
-- gate-bypass intercepts (feedback_rule1_return_value_exception); each captures its
-- own original and the _G guard blocks a double-wrap on reload.

if not RequiredScript then
	return
end

if _G._CSR_END_SPREE_REWARDS_HOOKED then
	return
end
_G._CSR_END_SPREE_REWARDS_HOOKED = true

-- Display: return CSR's pending table so the reward cards show our numbers.
local orig_calculate_rewards = CrimeSpreeManager.calculate_rewards
function CrimeSpreeManager:calculate_rewards()
	local csr = managers and managers.csr
	if csr and csr._pending_end_rewards then
		return csr._pending_end_rewards
	end
	return orig_calculate_rewards(self)
end

-- Award: grant CSR's pending table directly (bypassing the in_progress gate that
-- blocks the vanilla path for CSR), then clear the pending state so a later vanilla
-- read falls through. update_previous_coins mirrors vanilla so the coins card's
-- "previous -> new" count-up reads correctly.
local orig_on_spree_complete = CrimeSpreeManager.on_spree_complete
function CrimeSpreeManager:on_spree_complete()
	local csr = managers and managers.csr
	if csr and csr._pending_end_rewards then
		local rewards = csr._pending_end_rewards
		csr._pending_end_rewards = nil

		if managers.custom_safehouse then
			managers.custom_safehouse:update_previous_coins()
		end
		self:award_rewards(rewards)
		if MenuCallbackHandler and MenuCallbackHandler.save_progress then
			MenuCallbackHandler:save_progress()
		end
		return
	end
	return orig_on_spree_complete(self)
end

csr_log("[CSR] end_spree_rewards.lua loaded (vanilla reward screen driven by CSR values)")
