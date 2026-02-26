-- Crime Spree Roguelike - Force Update Active Crime Spree
-- Rebuilds active Crime Spree modifiers when the seed or difficulty changes

if not RequiredScript then
	return
end



-- Hook on _setup - fires when the CrimeSpreeManager initialises
Hooks:PostHook(CrimeSpreeManager, "_setup", "CSR_ForceUpdateModifiers", function(self)
	-- Guard: only proceed if a saved Crime Spree exists (level > 0)
	if not self._global or not self._global.spree_level or self._global.spree_level <= 0 then
		return
	end

	-- Guard: skip unless the regeneration flag was set (set in crimespree.lua)
	if not _G.CSR_NeedsRegenerationFlag then
		return
	end


	-- Run the regeneration function (defined in crimespree.lua)
	if _G.CSR_RegenerateForcedMods then
		local seed = _G.CSR_CurrentSeed or os.time()
		local difficulty = _G.CSR_CurrentDifficulty or "normal"

		_G.CSR_RegenerateForcedMods(seed, difficulty)

		-- CRITICAL: Push the newly generated modifiers into the active Crime Spree
		-- Source: repeating_modifiers (freshly generated)
		local new_forced_mods = tweak_data.crime_spree.repeating_modifiers.forced or {}
		local new_stealth_mods = tweak_data.crime_spree.repeating_modifiers.stealth or {}


		-- Clear old modifiers and repopulate up to the current level
		self._global.active_modifiers = {}

		local current_level = self._global.spree_level or 0

		-- Add all modifiers whose assigned level is at or below the current level
		for _, mod in ipairs(new_forced_mods) do
			if mod.level and mod.level <= current_level then
				table.insert(self._global.active_modifiers, {
					id = mod.id,
					class = mod.class,
					level = mod.level
				})
			end
		end

		for _, mod in ipairs(new_stealth_mods) do
			if mod.level and mod.level <= current_level then
				table.insert(self._global.active_modifiers, {
					id = mod.id,
					class = mod.class,
					level = mod.level
				})
			end
		end


		-- Clear the flag so this update only runs once
		_G.CSR_NeedsRegenerationFlag = false
	else
	end
end)

