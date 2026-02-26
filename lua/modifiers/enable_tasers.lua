-- Enable Tasers - unlocks taser spawning on lower difficulties
-- Only useful on Normal (on Hard+ they already spawn)

if not RequiredScript then
	return
end



-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierEnableTasers = ModifierEnableTasers or class(CSRBaseModifier)

-- Custom desc_id for localization
ModifierEnableTasers.desc_id = "csr_enable_tasers_desc"

-- Custom icon
ModifierEnableTasers.icon = "crime_spree_taser_overcharge"

-- Enable taser spawning on Normal (on Hard+ they already exist with taser = 1-2)
function ModifierEnableTasers:init(data)
	ModifierEnableTasers.super.init(self, data)

	-- Get current spawn limits
	local spawn_limits = tweak_data.group_ai.special_unit_spawn_limits

	if spawn_limits then
		-- If taser count is too low or absent, raise it
		if spawn_limits.taser < 2 then
			local old_value = spawn_limits.taser
			spawn_limits.taser = 2  -- Set to the same value as Hard
		else
		end
	else
	end
end

