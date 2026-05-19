-- CSR generic item-effect dispatcher — declarative `stat_mul`.
--
-- Replaces the per-item mechanic files (lua/items/dogtags.lua, deleted). For
-- every registered item whose effect is
--   { kind = "stat_mul", stat = <s>, per_stack = <f> }
-- this sums per_stack * owned-stacks across ALL such items targeting <s> and
-- adds it to the matching vanilla return-value multiplier. Additive, per the
-- project convention (the Glass-Pistol multiplicative exception is handled
-- when that item is ported, not here).
--
-- stat -> vanilla method: slice 1 implements only `max_health`
-- (PlayerManager:health_skill_multiplier). New stats are added one at a time
-- as the item that needs them is ported (never speculatively).
--
-- Critical Rule #1 exception: health_skill_multiplier RETURNS a value, which
-- Hooks:PostHook cannot carry. Raw chain wrap is the established CSR convention
-- for return-value hooks (feedback_rule1_return_value_exception). The _G guard
-- stops a hot-reload from closing over the already-wrapped function and
-- compounding the bonus.

if not RequiredScript then
	return
end

-- Summed additive bonus for one stat across every registered stat_mul item the
-- local player owns. Zero unless a CSR run is active (item gating convention).
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

if PlayerManager and not _G._CSR_ITEM_EFFECTS_HOOKED then
	_G._CSR_ITEM_EFFECTS_HOOKED = true

	local orig_health = PlayerManager.health_skill_multiplier
	if orig_health then
		function PlayerManager:health_skill_multiplier()
			return orig_health(self) + csr_stat_mul_bonus("max_health")
		end
	end
end
