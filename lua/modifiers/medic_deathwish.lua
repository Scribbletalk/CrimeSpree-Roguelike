-- Final Dose (loud modifier) -- a killed Medic instantly heals nearby cops.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "medic_deathwish",
	category = "loud",
	loc = "menu_cs_modifier_medic_deathwish",
	icon = "crime_spree_medic_deathwish",
	class = "ModifierMedicDeathwish",
	data = {},
})
