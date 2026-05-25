-- Scrap -- printer fodder. Produced by the in-world scrapper from unwanted
-- items; consumed (preferentially) by the printer as the sacrifice so a real
-- item is not lost in the exchange. No effect, no hooks -- pure inventory.
--
-- is_scrap = true gates it out of the selection-window roll (roll_item_pool,
-- game_manager.lua). It DOES show in the logbook compendium (at the end of its
-- tier), the owned-items grid, and the scrapper's own pick list.
--
-- One type per scrappable tier; contraband and wildcard cannot be scrapped, so
-- there is no contraband/wildcard scrap. Auto-discovered by extension_api.lua.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local SCRAP_TIERS = {
	{ type = "scrap_common", rarity = "common" },
	{ type = "scrap_uncommon", rarity = "uncommon" },
	{ type = "scrap_rare", rarity = "rare" },
}

for _, s in ipairs(SCRAP_TIERS) do
	_G.CSR.register_item({
		type = s.type,
		rarity = s.rarity,
		name = "csr_logbook_" .. s.type .. "_name",
		desc = "csr_item_" .. s.type .. "_desc",
		icon = "csr_scrap",
		icon_scale = 1.0,
		is_scrap = true,
	})
end
