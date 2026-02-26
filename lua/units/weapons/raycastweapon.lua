-- Crime Spree Roguelike - Weapon damage multiplier hook

if not RequiredScript then
	return
end



-- Override _get_current_damage to apply CSR damage buffs to ranged weapons
local original_get_current_damage = RaycastWeaponBase._get_current_damage

function RaycastWeaponBase:_get_current_damage(dmg_mul)
	-- Skip all CSR logic outside Crime Spree to avoid unnecessary overhead
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return original_get_current_damage(self, dmg_mul)
	end

	-- Call vanilla through pcall as a safety net (bad weapon state won't crash the game)
	local success, damage = pcall(original_get_current_damage, self, dmg_mul)
	if not success then
		return 0
	end

	-- General damage buff (Evidence Rounds + passive progression)
	if CSR_ActiveBuffs and CSR_ActiveBuffs.damage and CSR_ActiveBuffs.damage_multiplier then
		local multiplier = CSR_ActiveBuffs.damage_multiplier
		if type(multiplier) == "number" and multiplier > 0 then
			damage = damage * multiplier
		end
	end

	-- Dozer Guide: ranged weapons only
	if CSR_ActiveBuffs and CSR_ActiveBuffs.dozer_guide_weapon_multiplier then
		damage = damage * CSR_ActiveBuffs.dozer_guide_weapon_multiplier
	end

	-- Glass Pistol: ranged weapons only (multiplicative, applied last)
	if CSR_ActiveBuffs and CSR_ActiveBuffs.glass_pistol_weapon_multiplier then
		damage = damage * CSR_ActiveBuffs.glass_pistol_weapon_multiplier
	end

	return damage
end


-- === PLUSH SHARK: Neutralise the Swan Song fire-rate bonus ===
-- During Plush Shark invulnerability the player is in a "pseudo-Swan Song" state.
-- We return fire_rate_multiplier = 1 so the speed boost doesn't apply — Plush Shark
-- invulnerability is meant to be a survival tool, not a DPS cooldown.
local original_fire_rate_multiplier = RaycastWeaponBase.fire_rate_multiplier

function RaycastWeaponBase:fire_rate_multiplier(...)
	local result = original_fire_rate_multiplier(self, ...)

	if CSR_PlushShark and CSR_PlushShark.invulnerability_end_time then
		local current_time = TimerManager:game():time()
		if CSR_PlushShark.invulnerability_end_time > current_time then
			local player_unit = managers.player:player_unit()
			if player_unit and player_unit:character_damage() then
				local damage_ext = player_unit:character_damage()
				if damage_ext._csr_plush_shark_active then
					-- Suppress any fire-rate bonus while invulnerable
					if result > 1 then
						return 1
					end
				end
			end
		end
	end

	return result
end
