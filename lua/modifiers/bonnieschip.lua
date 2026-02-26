-- Bonnie's Lucky Chip - Bonnie's poker chip
-- Rare (blue) item tied to luck

if not RequiredScript then
	return
end

-- Inherits from CSRBaseModifier (standalone base class with no side effects)
ModifierBonniesLuckyChip = ModifierBonniesLuckyChip or class(CSRBaseModifier)

-- desc_id points to the localization entry
ModifierBonniesLuckyChip.desc_id = "csr_bonnie_chip_desc"

-- Placeholder - no mechanic yet
-- Mechanic will be added once the effect is decided
