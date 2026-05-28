-- Scrap — printer fodder. No effect; gated out of selection rolls via is_scrap.
-- Shows in logbook / owned-items / scrapper pick list. One type per scrappable tier
-- (contraband + wildcard can't be scrapped).

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
		icon_scale = 0.95,
		is_scrap = true,
	})
end
