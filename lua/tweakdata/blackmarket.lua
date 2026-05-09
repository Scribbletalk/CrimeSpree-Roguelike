-- Melee Damage Hook for Evidence Rounds, Dozer Guide, Glass Pistol, Jiro's Last Wish.
--
-- Previous implementation hooked BlackMarketTweakData:_init_melee_weapons, which
-- fires once during BlackMarketTweakData:init (game start) — at that time
-- managers.crime_spree does not exist and CSR_ActiveBuffs is empty, so the hook
-- always bailed out and no melee bonus was ever applied.
--
-- Hook BlackMarketManager:equipped_melee_weapon_damage_info instead. It runs
-- per swing (PlayerStandard:_do_melee_damage), so it picks up live CSR_ActiveBuffs
-- and updates as items are gained/lost. Only the local player calls it, so
-- host and client each scale their own swing damage; the boosted value flows
-- through attack_data.damage to CopDamage:damage_melee, which networks to the
-- host via the standard PD2 pipeline (same path as equalizer.lua).
if not RequiredScript then
	return
end

local function csr_total_melee_bonus()
	if not CSR_ActiveBuffs then
		return 0
	end
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end

	local total = 0
	if CSR_ActiveBuffs.damage then
		total = total + ((CSR_ActiveBuffs.damage_multiplier or 1) - 1)
	end
	if CSR_ActiveBuffs.dozer_guide_melee then
		total = total + ((CSR_ActiveBuffs.dozer_guide_melee_multiplier or 1) - 1)
	end
	if CSR_ActiveBuffs.glass_pistol_melee then
		total = total + ((CSR_ActiveBuffs.glass_pistol_melee_multiplier or 1) - 1)
	end
	if CSR_ActiveBuffs.jiro_last_wish then
		total = total + ((CSR_ActiveBuffs.jiro_last_wish_melee_multiplier or 1) - 1)
	end
	return total
end

if BlackMarketManager then
	local _orig_dmg_info = BlackMarketManager.equipped_melee_weapon_damage_info
	Hooks:OverrideFunction(BlackMarketManager, "equipped_melee_weapon_damage_info", function(self, lerp_value)
		local dmg, dmg_effect = _orig_dmg_info(self, lerp_value)
		local bonus = csr_total_melee_bonus()
		if bonus ~= 0 then
			local mul = 1 + bonus
			dmg = dmg * mul
			dmg_effect = dmg_effect * mul
		end
		return dmg, dmg_effect
	end)
end
