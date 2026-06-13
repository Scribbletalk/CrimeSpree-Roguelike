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

-- Heal a leftover vanilla Crime Spree on load. CSR runs the STANDARD gamemode and keeps its own state
-- in csr_save.json; it never populates vanilla in_progress/spree_level/modifiers. So an in-progress
-- spree here is a pre-existing vanilla CS one (e.g. the player never ended it before installing this
-- mod). It corrupts CSR's menu: vanilla nodes render alongside ours (doubled Reroll/Start) and
-- modifiers_to_select() > 0 forces the modifier-select panel. We capture the unclaimed rewards into
-- CSR's _meta (so they survive a relaunch and aren't lost), then reset_crime_spree() to un-double the
-- menu (preserving highest_level). The captured rewards are claimed later via the vanilla reward
-- screen (contract_difficulty.lua prompts; _pending_end_rewards path grants them). Runs at game start,
-- after managers.csr:init(), before any menu builds -> self-healing for users who never reset vanilla CS.
local orig_load = CrimeSpreeManager.load
function CrimeSpreeManager:load(data, version)
	orig_load(self, data, version)
	if not (self._global and self._global.in_progress) then
		return
	end

	-- calculate_rewards() = amount * reward_level, keyed by reward id (experience/cash/
	-- continental_coins/loot_drop/random_cosmetic); needs in_progress true (still is here).
	local rewards = self:calculate_rewards()
	local has_rewards = false
	for _, amt in pairs(rewards) do
		if (amt or 0) > 0 then
			has_rewards = true
			break
		end
	end

	if has_rewards and managers and managers.csr and managers.csr.set_pending_vanilla_rewards then
		managers.csr:set_pending_vanilla_rewards(rewards)
		csr_log("[CSR] end_spree_rewards: captured leftover vanilla CS rewards for later claim")
	end

	csr_log(
		"[CSR] end_spree_rewards: healing leftover vanilla CS spree (level="
			.. tostring(self._global.spree_level)
			.. ")"
	)
	self:reset_crime_spree()
end

csr_log("[CSR] end_spree_rewards.lua loaded")
