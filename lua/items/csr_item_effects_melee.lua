-- CSR generic item-effect dispatcher - melee-damage side (BlackMarketManager).
--
-- Sibling of csr_item_effects_weapon.lua (bullet damage). Bullet and melee are
-- hooked on different vanilla scripts, hence separate files (one mod.txt entry
-- each).
--
-- Melee swing damage is scaled by the SUM of two stat_mul stats:
--   stat = "damage"        -- applies to ALL damage (bullet AND melee). Evidence
--                             Rounds. The bullet half is added in
--                             csr_item_effects_weapon.lua; THIS file adds its
--                             melee half. The 6.2 line scaled both from one
--                             "damage" buff (blackmarket.lua) -- porting only
--                             the bullet side would have silently dropped
--                             Evidence Rounds' melee bonus, so it is restored
--                             here alongside Jiro.
--   stat = "melee_damage"  -- melee only. Jiro's Last Wish (+50%/stack).
-- Applied multiplicatively on equipped_melee_weapon_damage_info's dmg AND
-- dmg_effect returns (value * (1 + bonus)) -- the established CSR convention
-- (the 6.2 line scaled both, blackmarket.lua). Only the local player calls
-- this, so host and client each scale their own swing; the boosted value
-- networks to the host via attack_data.damage -> CopDamage:damage_melee
-- (standard PD2 path, same as the bullet side).
--
-- Critical Rule #1 exception: equipped_melee_weapon_damage_info RETURNS values,
-- which Hooks:PostHook cannot carry. Raw chain wrap is the CSR convention for
-- return-value hooks (feedback_rule1_return_value_exception). The _G guard stops
-- a hot-reload from closing over the already-wrapped function and compounding
-- the bonus.

if not RequiredScript then
	return
end

if BlackMarketManager and not _G._CSR_ITEM_EFFECTS_MELEE_HOOKED then
	_G._CSR_ITEM_EFFECTS_MELEE_HOOKED = true

	local orig_info = BlackMarketManager.equipped_melee_weapon_damage_info
	if orig_info then
		function BlackMarketManager:equipped_melee_weapon_damage_info(lerp_value)
			local dmg, dmg_effect = orig_info(self, lerp_value)
			-- "damage" (all damage) + "melee_damage" (melee only); summed on the
			-- manager (registry-indexed). See csr_item_effects_playerstats.lua.
			local mgr = managers.csr
			local bonus = mgr and (mgr:sum_stat_mul("damage") + mgr:sum_stat_mul("melee_damage")) or 0
			if bonus ~= 0 and type(dmg) == "number" then
				local mul = 1 + bonus
				dmg = dmg * mul
				if type(dmg_effect) == "number" then
					dmg_effect = dmg_effect * mul
				end
			end
			return dmg, dmg_effect
		end
	end
end
