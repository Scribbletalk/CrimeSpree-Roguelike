-- Field Hospital (loud modifier) -- two additional Medics allowed into the level.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "more_medics",
	category = "loud",
	loc = "menu_cs_modifier_more_medics",
	icon = "crime_spree_more_medics",
	class = "ModifierMoreMedics",
	data = { inc = { 2, "add" } },
})
