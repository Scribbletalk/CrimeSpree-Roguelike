-- Smoke Bomb (loud modifier) -- Cloakers drop a smokebomb when they kick a player.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "cloaker_smoke",
	category = "loud",
	loc = "menu_cs_modifier_cloaker_smoke",
	icon = "crime_spree_cloaker_smoke",
	class = "ModifierCloakerKick",
	data = { effect = { "smoke", "none" } },
})
