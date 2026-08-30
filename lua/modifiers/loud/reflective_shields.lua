-- Reflective Shields (loud modifier) -- Shields reflect projectiles.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "shield_reflect",
	category = "loud",
	loc = "csr_modifier_shield_reflect",
	icon = "crime_spree_shield_reflect",
	class = "ModifierShieldReflect",
	data = {},
})
