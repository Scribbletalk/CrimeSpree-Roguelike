-- "You call this 'resisting' arrest?" (loud modifier) -- a charging Cloaker
-- cuffs the player instead of downing them.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "cloaker_arrest",
	category = "loud",
	loc = "menu_cs_modifier_cloaker_arrest",
	icon = "crime_spree_cloaker_arrest",
	class = "ModifierCloakerArrest",
	data = {},
})
