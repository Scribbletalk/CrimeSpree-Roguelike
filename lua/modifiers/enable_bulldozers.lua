-- Enable Bulldozers - unlocks bulldozer spawning on lower difficulties
-- Only useful on Normal/Hard (on Overkill+ they already spawn)

if not RequiredScript then
	return
end



-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierEnableBulldozers = ModifierEnableBulldozers or class(CSRBaseModifier)

-- Custom desc_id for localization
ModifierEnableBulldozers.desc_id = "csr_enable_bulldozers_desc"

-- Custom icon
ModifierEnableBulldozers.icon = "crime_spree_more_dozers"

-- Raise bulldozer spawn limit on Normal/Hard
-- On Overkill+ there are already enough (tank = 4+)
function ModifierEnableBulldozers:init(data)
	ModifierEnableBulldozers.super.init(self, data)

	-- Get current spawn limits
	local spawn_limits = tweak_data.group_ai.special_unit_spawn_limits

	if spawn_limits then
		-- If bulldozer count is too low, raise limit to 3
		if spawn_limits.tank < 3 then
			local old_value = spawn_limits.tank
			spawn_limits.tank = 3  -- Raise the spawn limit
		else
		end
	else
	end
end

