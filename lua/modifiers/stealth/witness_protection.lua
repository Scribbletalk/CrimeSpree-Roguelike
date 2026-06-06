-- Witness Protection (stealth family) — alarm at fewer civ kills (10 → 7 → 4).
-- data.count is the body-count threshold; "min" so the strictest active tier wins.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local T1, T2, T3 = 10, 7, 4

_G.CSR.register_modifier({
	id = "civilian_alarm",
	category = "stealth",
	icon = "crime_spree_civs_killed",
	class = "ModifierCivilianAlarm",
	tiers = {
		{ loc = "menu_cs_modifier_civilian_alarm_1", data = { count = { T1, "min" } }, loc_macros = { n = T1 } },
		{ loc = "menu_cs_modifier_civilian_alarm_2", data = { count = { T2, "min" } }, loc_macros = { n = T2 } },
		{ loc = "menu_cs_modifier_civilian_alarm_3", data = { count = { T3, "min" } }, loc_macros = { n = T3 } },
	},
})
