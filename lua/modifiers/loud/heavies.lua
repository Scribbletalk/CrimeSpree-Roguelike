-- Heavy Response (loud modifier) -- all FBI SWATs are replaced with Heavy SWATs.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "heavies",
	category = "loud",
	loc = "menu_cs_modifier_heavies",
	icon = "crime_spree_heavies",
	class = "ModifierHeavies",
	data = {},
})
