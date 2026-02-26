-- Crime Spree Roguelike - HUD Refresh Fix
-- Force a HUD refresh on player spawn — vanilla doesn't update HP/armor bars when our modifiers change the values

if not RequiredScript then
	return
end



-- Hook on init — fires when the player spawns
if PlayerDamage then
	Hooks:PostHook(PlayerDamage, "init", "CSR_RefreshHUDOnSpawn", function(self, unit)
		-- Only run during Crime Spree
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end

		-- Wait 1 second so the HUD has time to fully load before we push values to it
		DelayedCalls:Add("csr_refresh_hud_fix", 1.0, function()
			-- Guard: player must still be alive
			if not self or not alive(unit) or self:dead() or self:is_downed() then
				return
			end

			if not managers.hud then
				return
			end

			-- Force a HUD refresh directly with current HP/armor values
			local current_health = self:get_real_health()
			local max_health = self:_max_health()
			local current_armor = self:get_real_armor()
			local max_armor = self:_max_armor()

			-- Push updated values to each HUD panel
			if managers.hud.set_player_health then
				managers.hud:set_player_health({
					current = current_health,
					total = max_health
				})
			end

			if managers.hud.set_player_armor then
				managers.hud:set_player_armor({
					current = current_armor,
					total = max_armor
				})
			end

			-- Also trigger the internal sync method if available
			if self._send_set_health then
				self:_send_set_health()
			end
		end)
	end)

end
