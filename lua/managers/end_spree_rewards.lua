-- Drive the vanilla Crime Spree reward screen with CSR's own per-rank values.
-- Two raw method wraps intercept calculate_rewards (return value) and
-- on_spree_complete (in_progress gate bypass). See csr_vanilla_intercepts.md.

if not RequiredScript then
	return
end

if _G._CSR_END_SPREE_REWARDS_HOOKED then
	return
end
_G._CSR_END_SPREE_REWARDS_HOOKED = true

-- Display: vanilla reward cards now read CSR's pending table.
local orig_calculate_rewards = CrimeSpreeManager.calculate_rewards
function CrimeSpreeManager:calculate_rewards()
	local csr = managers and managers.csr
	if csr and csr._pending_end_rewards then
		return csr._pending_end_rewards
	end
	return orig_calculate_rewards(self)
end

-- Award: grant CSR's pending table directly (bypasses vanilla's in_progress gate).
-- update_previous_coins mirrors vanilla so the coins card's count-up reads correctly.
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

csr_log("[CSR] end_spree_rewards.lua loaded")
