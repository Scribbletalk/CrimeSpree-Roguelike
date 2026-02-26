-- Crime Spree Roguelike - Remove Damage Cap (Direct Override)
-- Raises the vanilla damage clamp just before each hit so one-shot kills work at high CS levels

if not RequiredScript then
	return
end



if CopDamage then
	-- Track original _HEALTH_INIT per unit so we can restore it after the bullet hook
	local saved_health_init = {}

	-- PreHook: raise _HEALTH_INIT and clamp values before damage is applied
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_RemoveDamageCap_Bullet", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then return end
		if not attack_data then return end

		local unit_key = tostring(self._unit:key())

		-- Temporarily inflate _HEALTH_INIT by 20% so the vanilla minimum-health limiter
		-- doesn't leave the enemy alive at 1 HP after an otherwise-lethal shot
		saved_health_init[unit_key] = self._HEALTH_INIT
		self._HEALTH_INIT = self._HEALTH_INIT * 1.2
		self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100

		-- Set the damage clamp just above current HP so any single hit can kill
		local smart_cap = math.ceil(self._health) + 1
		self._char_tweak.DAMAGE_CLAMP_BULLET = smart_cap
		self._char_tweak.DAMAGE_CLAMP_SHOCK  = smart_cap

		-- Disable the headshot damage reduction on specials that normally cap it below 1
		if self._char_tweak.headshot_dmg_mul and self._char_tweak.headshot_dmg_mul < 1 then
			self._char_tweak.headshot_dmg_mul = 1
		end
	end)

	-- PostHook: restore original _HEALTH_INIT so other systems aren't affected
	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_RestoreHealthInit", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then return end

		local unit_key = tostring(self._unit:key())
		if saved_health_init[unit_key] then
			self._HEALTH_INIT = saved_health_init[unit_key]
			self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100
			saved_health_init[unit_key] = nil
		end
	end)

	-- Raise explosion clamp before each explosion hit
	Hooks:PreHook(CopDamage, "damage_explosion", "CSR_RemoveDamageCap_Explosion", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then return end
		local smart_cap = math.ceil(self._health) + 1
		self._char_tweak.DAMAGE_CLAMP_EXPLOSION = smart_cap
	end)

	-- Raise melee clamp before each melee hit
	Hooks:PreHook(CopDamage, "damage_melee", "CSR_RemoveDamageCap_Melee", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then return end
		local smart_cap = math.ceil(self._health) + 1
		self._char_tweak.DAMAGE_CLAMP_MELEE = smart_cap
	end)

	-- Raise fire/DOT clamp before each fire tick
	Hooks:PreHook(CopDamage, "damage_fire", "CSR_RemoveDamageCap_Fire", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then return end
		local smart_cap = math.ceil(self._health) + 1
		self._char_tweak.DAMAGE_CLAMP_FIRE = smart_cap
		self._char_tweak.DAMAGE_CLAMP_DOT  = smart_cap
	end)
end
