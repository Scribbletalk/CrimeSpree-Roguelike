-- Skulldozers (loud modifier) -- Skulldozers appear alongside regular Bulldozers.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "skulldozers",
	category = "loud",
	loc = "menu_cs_modifier_skulldozers",
	icon = "crime_spree_dozer_lmg",
	class = "ModifierSkulldozers",
	data = {},
})
