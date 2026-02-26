-- Crime Spree Roguelike - One-Time Modifier Reset
-- Simulates starting a new Crime Spree from the current level

if not RequiredScript then
	return
end



Hooks:PostHook(CrimeSpreeManager, "_setup", "CSR_OneTimeModifierReset", function(self)
	if not self._global or not self._global.spree_level or self._global.spree_level <= 0 then
		return
	end

	if _G.CSR_ModifiersAlreadyReset then
		return
	end

	local current_level = self._global.spree_level
	local current_rewards = self._global.total_rewards or 0
	local current_coins = self._global.total_continental_coins or 0


	-- Call vanilla set_starting_level
	-- It automatically adds all forced modifiers!
	self:set_starting_level(current_level)

	-- Restore rewards (set_starting_level resets them to zero)
	self._global.total_rewards = current_rewards
	self._global.total_continental_coins = current_coins


	_G.CSR_ModifiersAlreadyReset = true
end)

