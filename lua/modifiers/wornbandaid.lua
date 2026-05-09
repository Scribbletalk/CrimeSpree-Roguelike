-- Crime Spree Roguelike - WORN BAND-AID Modifier
-- Hyperbolic % of max HP regeneration (1% at 1 stack, 20% asymptote)

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

-- IMPORTANT: Inherit from CSRBaseModifier (NOT from vanilla classes!)
ModifierWornBandAid = ModifierWornBandAid or class(CSRBaseModifier)
ModifierWornBandAid.desc_id = "csr_worn_bandaid_desc"

function ModifierWornBandAid:init(data)
	ModifierWornBandAid.super.init(self, data)
end

CSR_log("[CSR] WORN BAND-AID modifier loaded!")
