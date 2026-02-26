-- Crime Spree Roguelike - Level Field Fix
-- Adds level = 0 for all modifiers that don't have it set
-- Prevents crash: "attempt to perform arithmetic on field 'level' (a nil value)"

if not RequiredScript then
	return
end



-- Hook on modifier retrieval - ensure level = 0 is set if missing
Hooks:PostHook(CrimeSpreeManager, "_get_modifiers", "CSR_FixMissingLevel", function(self)
	-- Check all modifier types
	local modifier_types = {"loud", "stealth", "forced"}

	for _, mod_type in ipairs(modifier_types) do
		local modifiers = tweak_data.crime_spree.modifiers[mod_type]
		if modifiers then
			for _, mod_data in ipairs(modifiers) do
				-- If level is missing, default it to 0
				if mod_data.level == nil then
					mod_data.level = 0
				end
			end
		end
	end
end)

