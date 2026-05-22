-- CSR generic item-effect dispatcher - interaction-speed side (BaseInteractionExt).
--
-- Sibling of csr_item_effects_playerstats.lua (PlayerManager-side) and
-- csr_item_effects_weapon.lua (RaycastWeaponBase-side). Split because each is
-- hooked on a different vanilla file path in mod.txt.
--
-- For every registered item whose effect is
--   { kind = "stat_mul", stat = "interaction_speed", per_stack = <f> }
-- this sums per_stack * owned-stacks across ALL such items, then divides the
-- vanilla _get_timer return by (1 + total_bonus). Linear stacking among CSR
-- bonuses (3 stacks of +10% -> divide by 1.30, not 1.10^3). Multiplicative
-- with all vanilla upgrade multipliers (drill skills, crew Quick, level-based,
-- etc.); the legacy 6.x mechanic was additive-with-crew-Quick-only and
-- multiplicative with the rest, U1 simplifies to uniformly multiplicative
-- since the difference only matters when crew Quick is active.
--
-- Player-facing exclusions (mirrored from 6.x logbook contract): the bonus
-- does NOT apply to "revive" (helping up a downed teammate) or "free"
-- (uncuffing teammates / freeing hostages). All other interactions
-- (lockpicking, bagging, drilling, repairing, etc.) get the boost.
--
-- Critical Rule #1 exception: _get_timer RETURNS a value, which
-- Hooks:PostHook cannot carry. Raw chain wrap is the established CSR convention
-- for return-value hooks (feedback_rule1_return_value_exception). The _G guard
-- stops a hot-reload from closing over the already-wrapped function and
-- compounding the bonus.

if not RequiredScript then
	return
end

if BaseInteractionExt and not _G._CSR_ITEM_EFFECTS_INTERACTION_HOOKED then
	_G._CSR_ITEM_EFFECTS_INTERACTION_HOOKED = true

	local orig_get_timer = BaseInteractionExt._get_timer
	if orig_get_timer then
		function BaseInteractionExt:_get_timer()
			local t = orig_get_timer(self)
			if type(t) ~= "number" then
				return t
			end
			local tid = self.tweak_data
			if tid == "revive" or tid == "free" then
				return t
			end
			local mgr = managers.csr
			local bonus = mgr and mgr:sum_stat_mul("interaction_speed") or 0
			if bonus <= 0 then
				return t
			end
			return t / (1 + bonus)
		end
	end
end
