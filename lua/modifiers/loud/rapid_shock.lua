-- Rapid Shock (loud modifier) -- Tasers knock players out faster.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local SPEED = 50 -- percent faster knockout

_G.CSR.register_modifier({
	id = "taser_overcharge",
	category = "loud",
	loc = "csr_modifier_taser_overcharge",
	loc_macros = { pct = SPEED },
	icon = "crime_spree_taser_overcharge",
	class = "ModifierTaserOvercharge",
	data = { speed = { SPEED, "add" } },
})
