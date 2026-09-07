-- Heavy Reinforcement (loud modifier) -- two additional Bulldozers allowed.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "more_dozers",
	category = "loud",
	loc = "csr_modifier_more_dozers",
	icon = "crime_spree_more_dozers",
	class = "ModifierMoreDozers",
	data = { inc = { 2, "add" } },
})
