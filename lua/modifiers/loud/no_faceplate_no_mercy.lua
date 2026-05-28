-- No Faceplate, No Mercy (loud modifier) -- Bulldozers berserk when faceplate breaks.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "dozer_rage",
	category = "loud",
	loc = "menu_cs_modifier_dozer_rage",
	icon = "crime_spree_dozer_rage",
	class = "ModifierDozerRage",
	data = { damage = { 100, "add" } },
})
