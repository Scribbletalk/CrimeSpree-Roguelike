-- FALCOGINI KEYS / CAR KEYS - Dodge item with hyperbolic scaling
-- Formula same as Tougher Times (RoR2): dodge = 1 - 1/(1 + k × stacks)
-- 1 stack = 5% dodge, approaches 100% but never reaches it

if not RequiredScript then
	return
end

-- Inherits from CSRBaseModifier (standalone base class with no side effects)
ModifierCarKeys = ModifierCarKeys or class(CSRBaseModifier)

-- Set custom desc_id for localization
ModifierCarKeys.desc_id = "csr_car_keys_desc"
