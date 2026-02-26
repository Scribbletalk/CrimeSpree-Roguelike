-- Enable Medics - unlocks medic spawning on lower difficulties
-- Only useful on Normal/Hard/Very Hard (on Overkill+ they already spawn)

if not RequiredScript then
	return
end



-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierEnableMedics = ModifierEnableMedics or class(CSRBaseModifier)

-- Custom desc_id for localization
ModifierEnableMedics.desc_id = "csr_enable_medics_desc"

-- Custom icon
ModifierEnableMedics.icon = "crime_spree_more_medics"

-- Raise medic spawn limit on Normal/Hard/Very Hard
-- On Overkill+ there are already enough (medic = 3+)
function ModifierEnableMedics:init(data)
	ModifierEnableMedics.super.init(self, data)

	-- Get current spawn limits
	local spawn_limits = tweak_data.group_ai.special_unit_spawn_limits

	if spawn_limits then
		-- If medic count is too low, raise limit to 4
		if spawn_limits.medic < 4 then
			local old_value = spawn_limits.medic
			spawn_limits.medic = 4  -- Raise the spawn limit
		else
		end
	else
	end
end

