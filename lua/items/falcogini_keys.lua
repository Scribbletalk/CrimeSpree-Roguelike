-- Falcogini Keys (uncommon) -- chance to dodge, diminishing returns (hyperbolic).
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "falcogini_keys",
	rarity = "uncommon",
	name = "csr_logbook_falcogini_keys_name",
	desc = "csr_item_falcogini_keys_desc",
	full_desc = "csr_logbook_falcogini_keys_effect",
	notes = "csr_logbook_falcogini_keys_notes",
	icon = "csr_falcogini_keys",

	hooks = {
		-- Combine the item's dodge chance with vanilla dodge probabilistically
		-- (final = 1 - (1-base)*(1-bonus)) so the result rises toward but never
		-- reaches 100% and never lowers base dodge. bonus = cap*(1 - 1/(1 +
		-- (k_num/k_den)*stacks)); cap/k_den mirror the 6.2 constant car_keys_k_den
		-- (32). Vanilla skill_dodge_chance takes (running, crouching, on_zipline,
		-- override_armor, detection_risk) -- forward all args via ... Return-value
		-- method -> raw chain wrap; _G guard stops a double-wrap.
		["lib/managers/playermanager"] = function()
			if _G._CSR_FALCOGINI_KEYS_HOOKED then
				return
			end
			_G._CSR_FALCOGINI_KEYS_HOOKED = true
			local orig = PlayerManager.skill_dodge_chance
			if not orig then
				return
			end
			function PlayerManager:skill_dodge_chance(...)
				local base = orig(self, ...)
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return base
				end
				local stacks = mgr:owned("falcogini_keys")
				if stacks <= 0 then
					return base
				end
				local k = 1 / 32
				local bonus = 1.0 * (1 - 1 / (1 + k * stacks))
				base = base or 0
				local result = 1 - (1 - base) * (1 - bonus)
				if result < 0 then
					result = 0
				elseif result > 1 then
					result = 1
				end
				return result
			end
		end,
	},
})
