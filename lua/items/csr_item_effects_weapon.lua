-- CSR generic item-effect dispatcher - weapon-side (RaycastWeaponBase).
--
-- Sibling of csr_item_effects.lua: that file owns PlayerManager-side hooks
-- (max_health, ...); this file owns RaycastWeaponBase-side hooks (damage, ...).
-- Split because each is hooked on a different vanilla file path in mod.txt.
--
-- For every registered item whose effect is
--   { kind = "stat_mul", stat = <s>, per_stack = <f> }
-- this sums per_stack * owned-stacks across ALL such items targeting <s>.
-- For stat = "damage" the bonus is applied multiplicatively on top of vanilla
-- _get_current_damage's absolute return value (damage * (1 + bonus)), which is
-- the established CSR convention for damage scaling (the legacy Evidence
-- Rounds did `damage * (1 + total_damage_bonus)` in raycastweapon.lua).
--
-- Critical Rule #1 exception: _get_current_damage returns a value, which
-- Hooks:PostHook cannot carry. Raw chain wrap is the CSR convention for
-- return-value hooks (feedback_rule1_return_value_exception). The _G guard
-- stops a hot-reload from closing over the already-wrapped function and
-- compounding the bonus.

if not RequiredScript then
	return
end

local function csr_stat_mul_bonus(stat)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return 0
	end
	if not mgr.registered_items then
		return 0
	end
	local pid = mgr:local_peer_id()
	local total = 0
	for _, item in ipairs(mgr:registered_items()) do
		local e = item.effect
		if e and e.kind == "stat_mul" and e.stat == stat then
			local stacks = mgr:item_count(pid, item.type)
			if stacks > 0 then
				total = total + (e.per_stack or 0) * stacks
			end
		end
	end
	return total
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
			local bonus = csr_stat_mul_bonus("damage")
			if bonus ~= 0 then
				damage = damage * (1 + bonus)
			end
			return damage
		end
	end
end
