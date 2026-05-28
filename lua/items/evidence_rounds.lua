-- Evidence Rounds (uncommon) — +10%/stack to all damage (ranged + melee).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local PER_STACK = 0.10

_G.CSR.register_item({
	type = "evidence_rounds",
	rarity = "uncommon",
	name = "csr_logbook_evidence_rounds_name",
	desc = "csr_item_evidence_rounds_desc",
	full_desc = "csr_logbook_evidence_rounds_effect",
	notes = "csr_logbook_evidence_rounds_notes",
	icon = "csr_evidence_rounds",
	icon_scale = 0.9,

	hooks = {
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
