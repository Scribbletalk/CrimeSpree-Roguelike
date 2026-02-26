-- Crime Spree Roguelike - Damage from all sources (for Evidence Rounds)
-- Throwables, turrets, mines, status effects

if not RequiredScript then
	return
end



-- === THROWABLES (grenades, throwing knives) ===
if ProjectileBase then
	local original_projectile_give_impact_damage = ProjectileBase.give_impact_damage

	function ProjectileBase:give_impact_damage(...)
		local result = original_projectile_give_impact_damage(self, ...)

		-- If result is a number, apply damage multiplier
		if type(result) == "number" and CSR_ActiveBuffs and CSR_ActiveBuffs.damage then
			local multiplier = CSR_ActiveBuffs.damage_multiplier or 1
			result = result * multiplier
		end

		return result
	end

end

-- === TURRETS ===
if SentryGunWeapon then
	local original_sentry_fire = SentryGunWeapon._fire_raycast

	function SentryGunWeapon:_fire_raycast(...)
		-- Temporarily boost damage before firing
		local damage_mult = 1
		if CSR_ActiveBuffs and CSR_ActiveBuffs.damage then
			damage_mult = CSR_ActiveBuffs.damage_multiplier or 1
		end

		-- Save original damage
		local original_damage = nil
		if self._setup and self._setup.damage then
			original_damage = self._setup.damage
			self._setup.damage = original_damage * damage_mult
		end

		-- Fire
		local result = original_sentry_fire(self, ...)

		-- Restore original damage
		if original_damage and self._setup then
			self._setup.damage = original_damage
		end

		return result
	end

end

-- === MINES (Trip Mines) ===
if TripMineBase then
	local original_tripmine_detonate = TripMineBase._detonate

	function TripMineBase:_detonate(...)
		-- Temporarily boost explosion damage
		local damage_mult = 1
		if CSR_ActiveBuffs and CSR_ActiveBuffs.damage then
			damage_mult = CSR_ActiveBuffs.damage_multiplier or 1
		end

		-- Save original damage if present
		local original_damage = nil
		if tweak_data and tweak_data.upgrades and tweak_data.upgrades.trip_mine_damage then
			original_damage = tweak_data.upgrades.trip_mine_damage
			tweak_data.upgrades.trip_mine_damage = original_damage * damage_mult
		end

		-- Detonate
		local result = original_tripmine_detonate(self, ...)

		-- Restore original damage
		if original_damage and tweak_data and tweak_data.upgrades then
			tweak_data.upgrades.trip_mine_damage = original_damage
		end

		return result
	end

end

-- === STATUS EFFECTS (fire, poison, DOT) ===
-- Fire DOT (Damage Over Time)
if FireDotData then
	local original_fire_damage = FireDotData._get_fire_dot_data

	function FireDotData:_get_fire_dot_data(...)
		local result = original_fire_damage(self, ...)

		-- If result is a table with damage, apply multiplier
		if result and type(result) == "table" and result.damage then
			if CSR_ActiveBuffs and CSR_ActiveBuffs.damage then
				local multiplier = CSR_ActiveBuffs.damage_multiplier or 1
				result.damage = result.damage * multiplier
			end
		end

		return result
	end

end

-- Poison DOT (if present)
if PoisonDotData then
	local original_poison_damage = PoisonDotData._get_poison_dot_data

	function PoisonDotData:_get_poison_dot_data(...)
		local result = original_poison_damage(self, ...)

		if result and type(result) == "table" and result.damage then
			if CSR_ActiveBuffs and CSR_ActiveBuffs.damage then
				local multiplier = CSR_ActiveBuffs.damage_multiplier or 1
				result.damage = result.damage * multiplier
			end
		end

		return result
	end

end

-- === POISON GAS (Maniac perk deck, poison grenades) ===
if CopDamage then
	Hooks:PostHook(CopDamage, "damage_dot", "CSR_PoisonGasDamage", function(self, damage_info)
		-- Guard: must be poison damage
		if damage_info and damage_info.variant and damage_info.variant == "poison" then
			if CSR_ActiveBuffs and CSR_ActiveBuffs.damage then
				local multiplier = CSR_ActiveBuffs.damage_multiplier or 1
				if damage_info.damage then
					damage_info.damage = damage_info.damage * multiplier
				end
			end
		end
	end)

end

-- === EXPLOSIVES (grenade launchers, RPG, explosive arrows) ===
if ProjectileBase then
	Hooks:PostHook(ProjectileBase, "_setup_from_tweak_data", "CSR_ExplosiveDamage", function(self)
		if not CSR_ActiveBuffs or not CSR_ActiveBuffs.damage then return end

		local multiplier = CSR_ActiveBuffs.damage_multiplier or 1
		if multiplier == 1 then return end

		-- Boost explosion damage
		if self._damage then
			self._damage = self._damage * multiplier
		end
	end)

end

