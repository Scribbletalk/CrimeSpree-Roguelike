-- Medic Bulldozers (loud modifier) -- spawned Bulldozers may be Medic Dozers.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "dozer_medic",
	category = "loud",
	loc = "csr_modifier_dozer_medic",
	icon = "crime_spree_dozer_medic",
	class = "ModifierDozerMedic",
	data = {},
})
