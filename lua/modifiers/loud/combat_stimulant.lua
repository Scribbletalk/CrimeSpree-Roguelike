-- Combat Stimulant (loud modifier) -- a revived cop gains +100% base damage.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "medic_adrenaline",
	category = "loud",
	loc = "menu_cs_modifier_medic_adrenaline",
	icon = "crime_spree_medic_adrenaline",
	class = "ModifierMedicAdrenaline",
	data = { damage = { 100, "add" } },
})
