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
-- This file owns the PlayerManager-side hooks. Two effect shapes land here:
--   stat_mul (additive, vanilla returns 1 + sum of bonuses):
--     max_health  -> PlayerManager:health_skill_multiplier   (Dog Tags)
--     max_stamina -> PlayerManager:stamina_multiplier        (Cup of Joe)
--   stat_hyperbolic (diminishing-returns curve, combined probabilistically):
--     dodge       -> PlayerManager:skill_dodge_chance        (Falcogini Keys)
-- Other stat targets live in sibling files because their vanilla hook path
-- is on a different script (one mod.txt entry per hook target):
--   damage             -> csr_item_effects_weapon.lua          (Evidence Rounds, bullet)
--   damage/melee_damage-> csr_item_effects_melee.lua           (Evidence Rounds + Jiro, melee)
--   movement_speed     -> csr_item_effects_playerstandard.lua  (Escape Plan)
--   interaction_speed  -> csr_item_effects_interaction.lua     (Duct Tape)
-- Non-stat effects (event-driven / per-tick) also live in their own siblings:
--   regen_max_hp_pct   -> csr_item_effects_regen.lua           (Worn Band-Aid)
-- New stats/kinds are added one at a time as the item that needs them is ported
-- (never speculatively). The two additive PlayerManager stats above share their
-- application shape exactly -- if a third+ additive PlayerManager stat lands,
-- fold them into a { stat -> method } table; two is not yet worth the
-- abstraction.
--
-- Critical Rule #1 exception: health_skill_multiplier / skill_dodge_chance
-- RETURN values, which Hooks:PostHook cannot carry. Raw chain wrap is the
-- established CSR convention for return-value hooks
-- (feedback_rule1_return_value_exception). The _G guard stops a hot-reload from
-- closing over the already-wrapped function and compounding the bonus.

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

-- Combined hyperbolic bonus for one stat across every registered stat_hyperbolic
-- item the local player owns. Each item's bonus is
--   cap * (1 - 1 / (1 + (k_num/k_den) * stacks))
-- (~cap*k at 1 stack, asymptotes to cap). Multiple items targeting the same
-- stat combine as a diminishing union 1 - prod(1 - b_i) -- stays < 1 and reduces
-- to b for the single-item case, which is the only shipping reality (Escape Plan
-- owns movement_speed, Falcogini Keys owns dodge). Zero unless a run is active.
local function csr_stat_hyperbolic_bonus(stat)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return 0
	end
	if not mgr.registered_items then
		return 0
	end
	local pid = mgr:local_peer_id()
	local remain = 1
	for _, item in ipairs(mgr:registered_items()) do
		local e = item.effect
		if e and e.kind == "stat_hyperbolic" and e.stat == stat then
			local stacks = mgr:item_count(pid, item.type)
			if stacks > 0 then
				local k = (e.k_num or 1) / (e.k_den or 1)
				local b = (e.cap or 1) * (1 - 1 / (1 + k * stacks))
				remain = remain * (1 - b)
			end
		end
	end
	return 1 - remain
end

if PlayerManager and not _G._CSR_ITEM_EFFECTS_HOOKED then
	_G._CSR_ITEM_EFFECTS_HOOKED = true

	local orig_health = PlayerManager.health_skill_multiplier
	if orig_health then
		function PlayerManager:health_skill_multiplier()
			return orig_health(self) + csr_stat_mul_bonus("max_health")
		end
	end

	local orig_stamina = PlayerManager.stamina_multiplier
	if orig_stamina then
		function PlayerManager:stamina_multiplier()
			return orig_stamina(self) + csr_stat_mul_bonus("max_stamina")
		end
	end

	-- Falcogini Keys: combine the item's dodge chance with vanilla dodge
	-- probabilistically (final = 1 - (1-base)*(1-bonus)), so the result rises
	-- toward but never reaches 100% and never lowers the player's base dodge.
	-- Vanilla skill_dodge_chance takes (running, crouching, on_zipline,
	-- override_armor, detection_risk) -- forward all args verbatim via ...
	local orig_dodge = PlayerManager.skill_dodge_chance
	if orig_dodge then
		function PlayerManager:skill_dodge_chance(...)
			local base = orig_dodge(self, ...)
			local bonus = csr_stat_hyperbolic_bonus("dodge")
			if bonus <= 0 then
				return base
			end
			base = base or 0
			local result = 1 - (1 - base) * (1 - bonus)
			if result < 0 then
				result = 0
			elseif result > 1 then
				result = 1
			end
			return result
		end
	end
end
