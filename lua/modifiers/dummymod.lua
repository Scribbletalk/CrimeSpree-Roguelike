-- Dummy modifier (does nothing)
-- Used to fill empty slots in repeating_modifiers

ModifierCSRDummy = ModifierCSRDummy or class(CSRBaseModifier)
ModifierCSRDummy.type_id = "ModifierCSRDummy"

function ModifierCSRDummy:init(data)
	ModifierCSRDummy.super.init(self, data)
end

-- No-op passthrough
function ModifierCSRDummy:modify_value(id, value)
	return value
end
