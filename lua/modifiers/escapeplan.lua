-- ESCAPE PLAN - Movement Speed item with hyperbolic scaling
-- Formula: speed_bonus = 0.5 * (1 - 1/(1 + k × stacks)), k = 3/47
-- 1 stack = 3%, cap ~50%. Counteracts Dozer Guide slowdown.

if not RequiredScript then
	return
end

ModifierEscapePlan = ModifierEscapePlan or class(CSRBaseModifier)

ModifierEscapePlan.desc_id = "csr_escape_plan_desc"
