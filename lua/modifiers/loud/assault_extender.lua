-- Extended Assault (loud modifier) -- police assaults last much longer.
-- Data taken verbatim from vanilla crimespreetweakdata so the keys match
-- ModifierAssaultExtender (hostages/converts shorten it, capped at max_hostages).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "assault_extender",
	category = "loud",
	loc = "menu_cs_modifier_assault_extender",
	icon = "crime_spree_heavies",
	class = "ModifierAssaultExtender",
	data = {
		duration = { 50, "add" },
		spawn_pool = { 50, "add" },
		deduction = { 4, "add" },
		max_hostages = { 8, "none" },
	},
})
