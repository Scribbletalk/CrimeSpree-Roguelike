-- Melee Damage Hook for DOZER GUIDE and GLASS PISTOL
if not RequiredScript then
	return
end



-- Hook on melee weapon initialization to increase damage
Hooks:PostHook(BlackMarketTweakData, "_init_melee_weapons", "CSR_MeleeDamage", function(self, tweak_data)
	if not CSR_ActiveBuffs then
		return
	end

	-- Calculate TOTAL damage bonus from all items (ADDITIVELY)
	local total_melee_bonus = 0

	-- EVIDENCE ROUNDS: +10% per stack
	if CSR_ActiveBuffs.damage then
		local evidence_bonus = (CSR_ActiveBuffs.damage_multiplier or 1) - 1
		total_melee_bonus = total_melee_bonus + evidence_bonus
	end

	-- DOZER GUIDE: +5% per stack
	if CSR_ActiveBuffs.dozer_guide_melee then
		local dozer_bonus = (CSR_ActiveBuffs.dozer_guide_melee_multiplier or 1) - 1
		total_melee_bonus = total_melee_bonus + dozer_bonus
	end

	-- GLASS PISTOL: +50% per stack
	if CSR_ActiveBuffs.glass_pistol_melee then
		local glass_bonus = (CSR_ActiveBuffs.glass_pistol_melee_multiplier or 1) - 1
		total_melee_bonus = total_melee_bonus + glass_bonus
	end

	-- JIRO'S LAST WISH: +50% per stack
	if CSR_ActiveBuffs.jiro_last_wish then
		local jiro_bonus = (CSR_ActiveBuffs.jiro_last_wish_melee_multiplier or 1) - 1
		total_melee_bonus = total_melee_bonus + jiro_bonus
	end

	-- No bonuses active - bail out early
	if total_melee_bonus == 0 then
		return
	end

	local multiplier = 1.0 + total_melee_bonus

	-- Apply multiplier to all melee weapons
	for weapon_id, weapon_data in pairs(self.melee_weapons) do
		if weapon_data.stats then
			if weapon_data.stats.min_damage then
				weapon_data.stats.min_damage = weapon_data.stats.min_damage * multiplier
			end
			if weapon_data.stats.max_damage then
				weapon_data.stats.max_damage = weapon_data.stats.max_damage * multiplier
			end
		end
	end

end)

