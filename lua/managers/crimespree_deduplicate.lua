-- Crime Spree Roguelike - Duplicate Modifier Guard

if not RequiredScript then
	return
end



-- Hook on add_modifiers - strip any entries already present in the active list
if CrimeSpreeManager then
	local original_add_modifiers = CrimeSpreeManager.add_modifiers

	function CrimeSpreeManager:add_modifiers(modifiers, ...)
		if not modifiers or #modifiers == 0 then
			return original_add_modifiers(self, modifiers, ...)
		end

		-- Filter out any modifier whose ID is already active
		local active_mods = self:active_modifiers() or {}
		local filtered_modifiers = {}

		for _, mod in ipairs(modifiers) do
			local is_duplicate = false

			-- Check whether this modifier ID is already active
			for _, active_mod in ipairs(active_mods) do
				if active_mod.id == mod.id then
					is_duplicate = true
					break
				end
			end

			-- Keep only non-duplicate entries
			if not is_duplicate then
				table.insert(filtered_modifiers, mod)
			end
		end

		-- If everything was filtered out, skip the original call entirely
		if #filtered_modifiers == 0 then
			return
		end

		-- Log how many duplicates were filtered
		if #filtered_modifiers ~= #modifiers then
		end

		-- Call the original with the deduplicated list
		return original_add_modifiers(self, filtered_modifiers, ...)
	end

else
end
