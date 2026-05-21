-- CSR item-effect dispatcher — weapon-side (RaycastWeaponBase) bullet damage.
--
-- Sibling of csr_item_effects.lua (PlayerManager-side). Scales _get_current_damage
-- by (1 + managers.csr:sum_stat_mul("damage")) — the established CSR damage
-- convention (the legacy Evidence Rounds did damage*(1+bonus)). The summing
-- logic lives once on the manager (registry-indexed by effect.kind); see
-- csr_item_effects.lua. Because stat="damage" is ALL damage,
-- csr_item_effects_melee.lua adds the same bonus to melee swings.
--
-- Critical Rule #1 exception: _get_current_damage returns a value (PostHook
-- can't carry it). Raw chain wrap per the CSR return-value convention
-- (feedback_rule1_return_value_exception); the _G guard stops a hot-reload from
-- compounding the bonus.

if not RequiredScript then
	return
end

if RaycastWeaponBase and not _G._CSR_ITEM_EFFECTS_WEAPON_HOOKED then
	_G._CSR_ITEM_EFFECTS_WEAPON_HOOKED = true

	local orig_get_current_damage = RaycastWeaponBase._get_current_damage
	if orig_get_current_damage then
		function RaycastWeaponBase:_get_current_damage(...)
			local damage = orig_get_current_damage(self, ...)
			if type(damage) ~= "number" then
				return damage
			end
			local mgr = managers.csr
			local bonus = mgr and mgr:sum_stat_mul("damage") or 0
			if bonus ~= 0 then
				damage = damage * (1 + bonus)
			end
			return damage
		end
	end
end
