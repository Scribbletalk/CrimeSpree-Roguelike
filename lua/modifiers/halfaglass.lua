-- Crime Spree Roguelike - HALF-A-GLASS Modifier
-- Gage packages refill 10% ammo for all weapons and increase max ammo by 1%/stack for the mission.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

ModifierHalfAGlass = ModifierHalfAGlass or class(CSRBaseModifier)
ModifierHalfAGlass.desc_id = "csr_half_a_glass_desc"

function ModifierHalfAGlass:init(data)
	ModifierHalfAGlass.super.init(self, data)
end

CSR_log("[CSR] HALF-A-GLASS modifier loaded!")
