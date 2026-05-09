-- PLUSH SHARK - Guardian angel item
-- Protects against lethal damage once per life

if not RequiredScript then
	return
end

-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierPlushShark = ModifierPlushShark or class(CSRBaseModifier)

-- Set custom desc_id for localization
ModifierPlushShark.desc_id = "csr_plush_shark_desc"

-- Set custom icon
ModifierPlushShark.icon = "csr_plush_shark"
