-- Autodidact (loud modifier) -- Medic heal cooldown is 20% faster.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "heal_speed",
	category = "loud",
	loc = "menu_cs_modifier_heal_speed",
	icon = "crime_spree_medic_speed",
	class = "ModifierHealSpeed",
	data = { speed = { 20, "add" } },
})
