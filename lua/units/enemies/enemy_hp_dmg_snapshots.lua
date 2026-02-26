-- Crime Spree Roguelike - Apply HP/DMG Snapshots to Enemies
-- Increase enemy HP on spawn

if not RequiredScript then
	return
end



-- === ENEMY HP (via CopDamage:init) ===
if CopDamage then
	Hooks:PostHook(CopDamage, "init", "CSR_IncreaseEnemyHealth", function(self, unit)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end

		-- Get HP bonus
		local hp_bonus, _ = CSR_GetTotalHPDamageBonus()

		if hp_bonus > 0 then
			-- Multiply current _HEALTH_INIT so other mods' HP changes are respected
			local new_health = math.ceil(self._HEALTH_INIT * (1 + hp_bonus))
			self._HEALTH_INIT = new_health
			self._health = new_health

		end
	end)

end

