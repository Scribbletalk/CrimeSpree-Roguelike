-- Override vanilla Explosive Resistance modifier: 50% damage reduction instead of full immunity
-- Vanilla: Bulldozers take 0 explosive damage (100% block)
-- CSR: configurable reduction via CSR_ItemConstants.dozer_explosion_resistance
--
-- Approach: wrap ModifiersManager:modify_value. When vanilla returns 0 for
-- CopDamage:DamageExplosion (= explosion was fully blocked), restore partial damage.

if not RequiredScript then
	return
end

if not ModifiersManager then
	return
end

local original_modify_value = ModifiersManager.modify_value

function ModifiersManager:modify_value(id, value, ...)
	local result = original_modify_value(self, id, value, ...)

	if id == "CopDamage:DamageExplosion" and result == 0 and value > 0 then
		local C = _G.CSR_ItemConstants or {}
		local resistance = C.dozer_explosion_resistance or 0.50
		return value * (1 - resistance)
	end

	return result
end
