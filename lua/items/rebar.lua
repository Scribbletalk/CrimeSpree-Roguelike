-- Piece of Rebar (common) — first hit on each enemy deals bonus damage.
-- Damage-amplification pattern; see csr_damage_amplification_pattern.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BASE_BONUS = 0.15
local EXTRA_BONUS = 0.10

local function rebar_apply_first_hit(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
		return
	end
	if not attack_data or not attack_data.damage then
		return
	end
	local au = attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	if cop._csr_rebar_hit then
		return
	end
	local stacks = mgr:owned("rebar")
	if stacks <= 0 then
		return
	end
	local bonus = BASE_BONUS + (stacks - 1) * EXTRA_BONUS
	cop._csr_rebar_hit = true
	attack_data.damage = attack_data.damage * (1 + bonus)
	if mgr:debug_enabled() then
		mgr:debug_log(string.format("rebar first-hit +%.0f%% damage", bonus * 100))
	end
end

_G.CSR.register_item({
	type = "rebar",
	rarity = "common",
	name = "csr_logbook_rebar_name",
	desc = "csr_item_rebar_desc",
	full_desc = "csr_logbook_rebar_effect",
	notes = "csr_logbook_rebar_notes",
	icon = "csr_rebar",
	icon_scale = 1.0,

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_REBAR_HOOKED then
				return
			end
			_G._CSR_REBAR_HOOKED = true
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_Rebar_Bullet", rebar_apply_first_hit)
			if CopDamage.damage_melee then
				Hooks:PreHook(CopDamage, "damage_melee", "CSR_Rebar_Melee", rebar_apply_first_hit)
			end
			if CopDamage.damage_dot then
				Hooks:PreHook(CopDamage, "damage_dot", "CSR_Rebar_Dot", rebar_apply_first_hit)
			end
			if CopDamage.damage_explosion then
				Hooks:PreHook(CopDamage, "damage_explosion", "CSR_Rebar_Explosion", rebar_apply_first_hit)
			end
		end,
	},
})
