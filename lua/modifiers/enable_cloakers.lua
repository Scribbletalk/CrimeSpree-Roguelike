-- Enable Cloakers - unlocks cloaker spawning on lower difficulties
-- Only useful on Normal/Hard (on Very Hard+ they already spawn)

if not RequiredScript then
	return
end



-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierEnableCloakers = ModifierEnableCloakers or class(CSRBaseModifier)

-- Custom desc_id for localization
ModifierEnableCloakers.desc_id = "csr_enable_cloakers_desc"

-- Custom icon
ModifierEnableCloakers.icon = "crime_spree_cloaker_smoke"

-- Enable cloaker spawning on lower difficulties (Normal/Hard)
-- On Very Hard+ they already exist (spooc = 2); on Normal/Hard spooc = 0
function ModifierEnableCloakers:init(data)
	ModifierEnableCloakers.super.init(self, data)

	-- Get current spawn limits
	local spawn_limits = tweak_data.group_ai.special_unit_spawn_limits

	if spawn_limits then
		-- If cloakers are disabled (spooc = 0), enable them
		if spawn_limits.spooc == 0 then
			spawn_limits.spooc = 2  -- Set to the same value as Very Hard
		else
		end
	else
	end
end

