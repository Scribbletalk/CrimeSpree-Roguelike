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

		local hp_bonus, _ = CSR_GetTotalHPDamageBonus()

		if hp_bonus > 0 then
			-- Multiply current _HEALTH_INIT so other mods' HP changes are respected
			local new_health = math.ceil(self._HEALTH_INIT * (1 + hp_bonus))
			self._HEALTH_INIT = new_health
			self._health = new_health
		end
	end)

	-- Re-apply HP scaling when enemy changes tweak table (e.g. marshal shield break).
	-- Vanilla _clbk_tweak_data_changed resets _HEALTH_INIT and _health from new tweakdata,
	-- overwriting our init-time scaling. This PostHook restores it.
	Hooks:PostHook(
		CopDamage,
		"_clbk_tweak_data_changed",
		"CSR_ReapplyHPOnTweakChange",
		function(self, old_tweak_data, new_tweak_data)
			if not managers.crime_spree or not managers.crime_spree:is_active() then
				return
			end

			if not new_tweak_data or not new_tweak_data.modify_health_on_tweak_change then
				return
			end

			local hp_bonus, _ = CSR_GetTotalHPDamageBonus()

			if hp_bonus > 0 then
				local new_health = math.ceil(self._HEALTH_INIT * (1 + hp_bonus))
				self._HEALTH_INIT = new_health
				self._health = new_health
			end
		end
	)
end
