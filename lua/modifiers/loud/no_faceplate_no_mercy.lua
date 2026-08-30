-- No Faceplate, No Mercy (loud modifier) -- Bulldozers berserk when faceplate breaks.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local RAGE_DAMAGE_PCT = 100

_G.CSR.register_modifier({
	id = "dozer_rage",
	category = "loud",
	loc = "csr_modifier_dozer_rage",
	icon = "crime_spree_dozer_rage",
	class = "ModifierDozerRage",
	data = { damage = { RAGE_DAMAGE_PCT, "add" } },
	loc_macros = { pct = RAGE_DAMAGE_PCT },
})
