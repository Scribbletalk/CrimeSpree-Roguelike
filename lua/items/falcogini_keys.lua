-- Falcogini Keys (uncommon) — hyperbolic dodge chance, combined probabilistically.
-- bonus = 1 - 1/(1 + (1/32)*stacks). final = 1 - (1-base)*(1-bonus).

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
	icon_scale = 0.9,

	hooks = {
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
