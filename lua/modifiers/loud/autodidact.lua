-- Autodidact (loud modifier) -- Medic heal cooldown is faster.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local HEAL_SPEED_PCT = 20

_G.CSR.register_modifier({
	id = "heal_speed",
	category = "loud",
	loc = "menu_cs_modifier_heal_speed",
	icon = "crime_spree_medic_speed",
	class = "ModifierHealSpeed",
	data = { speed = { HEAL_SPEED_PCT, "add" } },
	loc_macros = { pct = HEAL_SPEED_PCT },
})
