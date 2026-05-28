-- Stand Out (stealth) — added detection risk. Single combined tier.
-- NOTE: BlackMarketManager:GetConcealment is per-player, so under the current
-- host-only apply only the host's detection rises (full per-peer waits on MP sync).
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
