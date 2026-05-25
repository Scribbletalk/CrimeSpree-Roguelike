-- Rapid Shock (loud modifier) -- Tasers knock players out 50% faster.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "taser_overcharge",
	category = "loud",
	loc = "menu_cs_modifier_taser_overcharge",
	icon = "crime_spree_taser_overcharge",
	class = "ModifierTaserOvercharge",
	data = { speed = { 50, "add" } },
})
