-- Phalanx Formation (loud modifier) -- all Shields become Captain Winters' Shields.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "shield_phalanx",
	category = "loud",
	loc = "menu_cs_modifier_shield_phalanx",
	icon = "crime_spree_shield_phalanx",
	class = "ModifierShieldPhalanx",
	data = {},
})
