-- Combat Stimulant (loud modifier) -- a revived cop gains +N% base damage.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local DAMAGE_BONUS = 100

_G.CSR.register_modifier({
	id = "medic_adrenaline",
	category = "loud",
	loc = "csr_modifier_medic_adrenaline",
	loc_macros = { pct = DAMAGE_BONUS },
	icon = "crime_spree_medic_adrenaline",
	class = "ModifierMedicAdrenaline",
	data = { damage = { DAMAGE_BONUS, "add" } },
})
