-- Stand Out (stealth modifier family) -- increased detection risk. A single
-- combined tier (vanilla exposes one stacking concealment key). Stealth family
-- (see less_pagers.lua). EFFECT: vanilla ModifierLessConcealment, data `conceal`
-- = added detection risk; aggregated with "add". NOTE this is read per-player
-- (BlackMarketManager:GetConcealment), so under the current host-only apply only
-- the host's detection rises -- a full per-peer apply waits on the MP sync slice.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "less_concealment",
	category = "stealth",
	icon = "crime_spree_concealment",
	class = "ModifierLessConcealment",
	tiers = {
		{ loc = "menu_cs_modifier_less_concealment", data = { conceal = { 3, "add" } } },
	},
})
