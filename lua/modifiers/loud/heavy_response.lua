-- Heavy Response (loud modifier) -- all FBI SWATs are replaced with Heavy SWATs.
-- PARKED: kept here for reference / future re-enable, but intentionally NOT registered,
-- so it never enters the loud pool, the catalog, or any modifier UI. The vanilla
-- ModifierHeavies swap map only covers FBI SWATs (not the base CS_swat that most
-- assaults spawn), so it barely affected gameplay. Flip HEAVY_RESPONSE_ENABLED to
-- restore it.
local HEAVY_RESPONSE_ENABLED = false

if not (HEAVY_RESPONSE_ENABLED and _G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "heavies",
	category = "loud",
	loc = "menu_cs_modifier_heavies",
	icon = "crime_spree_heavies",
	class = "ModifierHeavies",
	data = {},
})
