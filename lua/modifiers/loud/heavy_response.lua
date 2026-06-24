-- Heavy Response (loud modifier) - PARKED. Vanilla ModifierHeavies only covers FBI SWATs,
-- not base CS_swat, so barely affects gameplay. Flip HEAVY_RESPONSE_ENABLED to restore.
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
