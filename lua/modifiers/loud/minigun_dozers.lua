-- Minigun Dozers (loud modifier) -- spawned Bulldozers may be minigun Dozers.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "dozer_minigun",
	category = "loud",
	loc = "csr_modifier_dozer_minigun",
	icon = "crime_spree_more_dozers",
	class = "ModifierDozerMinigun",
	data = {},
})
