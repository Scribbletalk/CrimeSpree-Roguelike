-- Pain Tolerance (loud modifier) -- enemies have an 80% chance to resist stagger.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "no_hurt_anims",
	category = "loud",
	loc = "csr_modifier_no_hurt_anims",
	icon = "crime_spree_no_hurt",
	class = "ModifierNoHurtAnims",
	data = {},
})
