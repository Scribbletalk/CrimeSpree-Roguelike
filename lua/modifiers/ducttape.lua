-- DUCT TAPE - Interaction speed boost item
-- Increases interaction speed (reduces interaction time)
-- Bonuses stack ADDITIVELY with the crew bonus from bots

if not RequiredScript then
	return
end

-- Inherits from CSRBaseModifier (standalone base class with no side effects)
ModifierDuctTape = ModifierDuctTape or class(CSRBaseModifier)

-- Set custom desc_id for localization
ModifierDuctTape.desc_id = "menu_cs_modifier_duct_tape"
