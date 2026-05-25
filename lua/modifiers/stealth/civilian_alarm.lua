-- Witness Protection (stealth modifier family) -- the alarm sounds at fewer
-- civilian kills per tier (10 -> 7 -> 4). Stealth family (see less_pagers.lua).
-- EFFECT: vanilla ModifierCivilianAlarm, data `count` = body-count threshold;
-- aggregated with "min" so the strictest active tier wins. Host-side (the class
-- early-returns on a client).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "civilian_alarm",
	category = "stealth",
	icon = "crime_spree_civs_killed",
	class = "ModifierCivilianAlarm",
	tiers = {
		{ loc = "menu_cs_modifier_civilian_alarm_1", data = { count = { 10, "min" } } },
		{ loc = "menu_cs_modifier_civilian_alarm_2", data = { count = { 7, "min" } } },
		{ loc = "menu_cs_modifier_civilian_alarm_3", data = { count = { 4, "min" } } },
	},
})
