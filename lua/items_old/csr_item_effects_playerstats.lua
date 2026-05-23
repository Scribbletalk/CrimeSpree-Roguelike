-- CSR item-effect dispatcher — player stat bonuses (PlayerManager-side).
--
-- Items that add to a player CHARACTERISTIC routed through a PlayerManager
-- return-value method live here. NOT a catch-all for every item effect — it is
-- one dispatcher among several (siblings handle weapon/melee/movement/etc. on
-- their own hook targets). Wires those methods to the shared, registry-indexed
-- effect math on the manager (managers.csr:sum_stat_mul / combine_stat_hyperbolic):
--   max_health  -> health_skill_multiplier  + sum_stat_mul("max_health")   (Dog Tags)
--   max_stamina -> stamina_multiplier        + sum_stat_mul("max_stamina")  (Cup of Joe)
--   dodge       -> skill_dodge_chance combined w/ combine_stat_hyperbolic("dodge") (Falcogini Keys)
-- The "scan owned items of a kind and fold their effect" logic lives ONCE on
-- CSRGameManager now (it used to be copy-pasted into each dispatcher file —
-- file-locals can't be shared across SuperBLT chunk loads). Sibling files hook
-- the same manager methods for stats whose vanilla hook path is a different
-- script (one mod.txt entry per hook target): damage/melee_damage ->
-- csr_item_effects_weapon.lua + _melee.lua; movement_speed ->
-- csr_item_effects_playerstandard.lua; interaction_speed -> csr_item_effects_interaction.lua.
--
-- Critical Rule #1 exception: these methods RETURN values, which Hooks:PostHook
-- cannot carry, so a raw chain wrap is used per the CSR return-value convention
-- (feedback_rule1_return_value_exception). The _G guard stops a hot-reload from
-- re-wrapping the already-wrapped function and compounding the bonus.

if not RequiredScript then
	return
end

if PlayerManager and not _G._CSR_ITEM_EFFECTS_PLAYERSTATS_HOOKED then
	_G._CSR_ITEM_EFFECTS_PLAYERSTATS_HOOKED = true

	local orig_health = PlayerManager.health_skill_multiplier
	if orig_health then
		function PlayerManager:health_skill_multiplier()
			local mgr = managers.csr
			return orig_health(self) + (mgr and mgr:sum_stat_mul("max_health") or 0)
		end
	end

	local orig_stamina = PlayerManager.stamina_multiplier
	if orig_stamina then
		function PlayerManager:stamina_multiplier()
			local mgr = managers.csr
			return orig_stamina(self) + (mgr and mgr:sum_stat_mul("max_stamina") or 0)
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
			local mgr = managers.csr
			local bonus = mgr and mgr:combine_stat_hyperbolic("dodge") or 0
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
