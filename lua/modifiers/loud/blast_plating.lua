-- Blast Plating (loud modifier) -- Bulldozers take 50% reduced explosive damage.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "explosion_immunity",
	category = "loud",
	loc = "csr_modifier_explosion_immunity",
	icon = "crime_spree_dozer_explosion",
	class = "ModifierExplosionImmunity",
	data = {},
})
