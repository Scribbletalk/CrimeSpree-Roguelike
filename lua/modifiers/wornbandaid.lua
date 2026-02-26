-- Crime Spree Roguelike - WORN BAND-AID Modifier
-- +5 HP regeneration (flat value, not percentage)

if not RequiredScript then
	return
end

-- IMPORTANT: Inherit from CSRBaseModifier (NOT from vanilla classes!)
ModifierWornBandAid = ModifierWornBandAid or class(CSRBaseModifier)
ModifierWornBandAid.desc_id = "csr_worn_bandaid_desc"

function ModifierWornBandAid:init(data)
	ModifierWornBandAid.super.init(self, data)
end

log("[CSR] WORN BAND-AID modifier loaded!")
