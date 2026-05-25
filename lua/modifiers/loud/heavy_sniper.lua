-- Marshal Reinforcements (loud modifier) -- additional US Marshal Marksmen.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "heavy_sniper",
	category = "loud",
	loc = "menu_cs_modifier_heavy_sniper",
	icon = "crime_spree_heavy_sniper",
	class = "ModifierHeavySniper",
	data = { spawn_chance = { 5, "add" } },
})
