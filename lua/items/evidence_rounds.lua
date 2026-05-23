-- Evidence Rounds (uncommon) -- +10% to ALL damage per copy owned.
--
-- "All damage" = ranged AND melee, so this hooks two engine classes (one hooks
-- entry each). Per-item-file model (see cup_of_joe.lua). Text fields are
-- localization keys.
--
-- NOTE: the live mechanic is +10%/stack (the 6.2 register value). The logbook
-- effect string still reads "5%" -- a pre-existing text/mechanic mismatch carried
-- over from the partially-ported constants generator, not introduced here.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local PER_STACK = 0.10

_G.CSR.register_item({
	type = "evidence_rounds",
	rarity = "uncommon",
	name = "logbook_evidence_rounds_name",
	desc = "item_evidence_rounds_desc",
	full_desc = "logbook_evidence_rounds_effect",
	notes = "logbook_evidence_rounds_notes",
	icon = "evidence_rounds",

	hooks = {
		-- Ranged: scale RaycastWeaponBase:_get_current_damage by (1 + bonus).
		["lib/units/weapons/raycastweaponbase"] = function()
			if _G._CSR_EVIDENCE_ROUNDS_RANGED_HOOKED then
				return
			end
			_G._CSR_EVIDENCE_ROUNDS_RANGED_HOOKED = true
			local orig = RaycastWeaponBase._get_current_damage
			if not orig then
				return
			end
			function RaycastWeaponBase:_get_current_damage(...)
				local damage = orig(self, ...)
				if type(damage) ~= "number" then
					return damage
				end
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return damage
				end
				local bonus = PER_STACK * mgr:owned("evidence_rounds")
				if bonus ~= 0 then
					damage = damage * (1 + bonus)
				end
				return damage
			end
		end,

		-- Melee: scale BlackMarketManager:equipped_melee_weapon_damage_info's dmg
		-- and dmg_effect by (1 + bonus). Only the local player calls this, so each
		-- peer scales its own swing; the boosted value networks via attack_data
		-- (standard PD2 path). Stacks multiplicatively with Jiro's melee bonus
		-- (each item wraps independently -- the per-item-file model's natural,
		-- user-accepted result).
		["lib/managers/blackmarketmanager"] = function()
			if _G._CSR_EVIDENCE_ROUNDS_MELEE_HOOKED then
				return
			end
			_G._CSR_EVIDENCE_ROUNDS_MELEE_HOOKED = true
			local orig = BlackMarketManager.equipped_melee_weapon_damage_info
			if not orig then
				return
			end
			function BlackMarketManager:equipped_melee_weapon_damage_info(lerp_value)
				local dmg, dmg_effect = orig(self, lerp_value)
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return dmg, dmg_effect
				end
				local bonus = PER_STACK * mgr:owned("evidence_rounds")
				if bonus ~= 0 and type(dmg) == "number" then
					local mul = 1 + bonus
					dmg = dmg * mul
					if type(dmg_effect) == "number" then
						dmg_effect = dmg_effect * mul
					end
				end
				return dmg, dmg_effect
			end
		end,
	},
})
