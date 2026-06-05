-- Equalizer (contraband) — boost damage on specials, reduce on regular cops.
-- Target-side scaling on CopDamage (one PreHook per damage variant).
-- See csr_damage_amplification_pattern.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BONUS = 0.5
local PENALTY = 0.5

local SPECIAL_KEYWORDS = { "taser", "cloaker", "tank", "medic", "captain", "phalanx", "sniper", "shield", "marshal" }

local function is_special(cop_damage)
	local unit = cop_damage._unit
	if not unit or not alive(unit) then
		return false
	end
	local base = unit:base()
	local tt = base and base._tweak_table
	if type(tt) ~= "string" then
		return false
	end
	for i = 1, #SPECIAL_KEYWORDS do
		if tt:find(SPECIAL_KEYWORDS[i], 1, true) then
			return true
		end
	end
	return false
end

local function apply_equalizer(self, attack_data)
	if not attack_data or not attack_data.damage or attack_data.damage <= 0 then
		return
	end
	local au = attack_data.attacker_unit
	if not au or not alive(au) or not au:base() or au:base().is_local_player ~= true then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end
	local stacks = mgr:owned("equalizer")
	if stacks <= 0 then
		return
	end
	if is_special(self) then
		-- Multiplicative so 2 stacks @ +50% = x2.25, mirroring the penalty.
		attack_data.damage = attack_data.damage * (1 + BONUS) ^ stacks
	else
		-- Multiplicative so 2 stacks @ 50% = x0.25, not 0.
		attack_data.damage = math.max(1, attack_data.damage * (1 - PENALTY) ^ stacks)
	end
end

_G.CSR.register_item({
	type = "equalizer",
	rarity = "contraband",
	name = "csr_logbook_equalizer_name",
	desc = "csr_item_equalizer_desc",
	full_desc = "csr_logbook_equalizer_effect",
	notes = "csr_logbook_equalizer_notes",
	icon = "csr_equalizer",
	icon_scale = 0.9,

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_EQUALIZER_HOOKED then
				return
			end
			_G._CSR_EQUALIZER_HOOKED = true
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_Equalizer_Bullet", apply_equalizer)
			if CopDamage.damage_melee then
				Hooks:PreHook(CopDamage, "damage_melee", "CSR_Equalizer_Melee", apply_equalizer)
			end
			if CopDamage.damage_dot then
				Hooks:PreHook(CopDamage, "damage_dot", "CSR_Equalizer_Dot", apply_equalizer)
			end
			if CopDamage.damage_explosion then
				Hooks:PreHook(CopDamage, "damage_explosion", "CSR_Equalizer_Explosion", apply_equalizer)
			end
		end,
	},
})
