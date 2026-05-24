-- Stinkbug (loud modifier) -- killed Cloakers leave behind a toxic cloud.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "cloaker_tear_gas",
	category = "loud",
	loc = "menu_cs_modifier_cloaker_tear_gas",
	icon = "crime_spree_cloaker_tear_gas",
	class = "ModifierCloakerTearGas",
	data = { diameter = { 4, "none" }, damage = { 30, "none" }, duration = { 10, "none" } },
})
