-- Keen Dispatch (stealth family) — fewer pagers can be answered per heist.
-- data.count = pagers removed; "max" so the highest active tier wins.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "less_pagers",
	category = "stealth",
	icon = "crime_spree_pager",
	class = "ModifierLessPagers",
	tiers = {
		{ loc = "menu_cs_modifier_less_pagers_1", data = { count = { 1, "max" } } },
		{ loc = "menu_cs_modifier_less_pagers_2", data = { count = { 2, "max" } } },
		{ loc = "menu_cs_modifier_less_pagers_3", data = { count = { 3, "max" } } },
		{ loc = "menu_cs_modifier_less_pagers_4", data = { count = { 4, "max" } } },
	},
})
