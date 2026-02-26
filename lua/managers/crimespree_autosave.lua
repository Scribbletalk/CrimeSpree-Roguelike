-- Crime Spree Roguelike - Auto-save modifiers to seed file
-- Saves the current modifier list whenever the player picks a new modifier

if not RequiredScript then
	return
end



-- Hook on add_modifiers — fires when the player confirms an item choice in the popup
Hooks:PostHook(CrimeSpreeManager, "add_modifiers", "CSR_AutoSaveModifiers", function(self, mods, skip_popup)

	-- Only save while Crime Spree is active
	if not self._global or not self._global.is_active then
		return
	end

	-- Nothing to save if the modifier list is empty
	if not self._global.modifiers or #self._global.modifiers == 0 then
		return
	end

	local current_seed = _G.CSR_CurrentSeed
	local current_difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"

	if not current_seed then
		return
	end

	-- Write modifiers to the seed file and update the in-memory cache
	if CSR_SaveSeed then
		CSR_SaveSeed(current_seed, current_difficulty, self._global.modifiers)

		_G.CSR_SavedModifiers = {}
		for _, mod in ipairs(self._global.modifiers) do
			table.insert(_G.CSR_SavedModifiers, {id = mod.id, level = mod.level})
		end
	end
end)
