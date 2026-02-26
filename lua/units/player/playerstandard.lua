-- Movement Speed Hook for DOZER GUIDE
if not RequiredScript then
	return
end



-- Save original function
local original_get_max_walk_speed = PlayerStandard._get_max_walk_speed

-- Override speed calculation function
function PlayerStandard:_get_max_walk_speed(t, force_run)
	local speed = original_get_max_walk_speed(self, t, force_run)

	-- Apply speed debuff from DOZER GUIDE
	if CSR_ActiveBuffs and CSR_ActiveBuffs.dozer_guide and CSR_ActiveBuffs.dozer_guide_speed_debuff then
		local debuff_multiplier = CSR_ActiveBuffs.dozer_guide_speed_multiplier or 1
		speed = speed * debuff_multiplier
	end

	-- Apply speed bonus from ESCAPE PLAN (multiplicative with Dozer Guide)
	if CSR_ActiveBuffs and CSR_ActiveBuffs.escape_plan and CSR_ActiveBuffs.escape_plan_speed_bonus then
		speed = speed * (1 + CSR_ActiveBuffs.escape_plan_speed_bonus)
	end

	return speed
end

