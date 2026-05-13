-- DOG TAGS — max HP bump.
--
-- Reads stack count from managers.csr and adds (dog_tags_hp_bonus * stacks) to
-- vanilla's health_skill_multiplier return value. Additive per the project
-- convention that all buffs stack additively (Glass Pistol is the lone
-- multiplicative exception, applied last).
--
-- Critical Rule #1 exception: health_skill_multiplier returns a value, which
-- Hooks:PostHook can't carry through. Per feedback_rule1_return_value_exception,
-- raw chain wrapping is the established CSR convention for return-value hooks.
-- The _G guard prevents re-wrapping on hot-reload (each load would otherwise
-- close over the already-wrapped function and compound the bonus).

if not RequiredScript then
	return
end

if PlayerManager and not _G._CSR_DOG_TAGS_HEALTH_MULT_HOOKED then
	_G._CSR_DOG_TAGS_HEALTH_MULT_HOOKED = true
	local original_health_skill_multiplier = PlayerManager.health_skill_multiplier
	if original_health_skill_multiplier then
		function PlayerManager:health_skill_multiplier()
			local mul = original_health_skill_multiplier(self)
			if not managers or not managers.csr then
				return mul
			end
			if not managers.csr:is_run_active() then
				return mul
			end
			local pid = managers.csr:local_peer_id()
			local stacks = managers.csr:item_count(pid, "player_health_boost_")
			if stacks <= 0 then
				return mul
			end
			local bonus_per_stack = managers.csr:constant("dog_tags_hp_bonus") or 0.10
			return mul + bonus_per_stack * stacks
		end
	end
end
