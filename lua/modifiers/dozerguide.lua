-- Crime Spree Roguelike - Custom Modifier Class for DOZER GUIDE
-- Inherits from ModifierExplosionImmunity but with a custom desc_id

if not RequiredScript then
	return
end



-- Create a new class inheriting from CSRBaseModifier (standalone, no side effects)
ModifierDozerGuide = class(CSRBaseModifier)

-- Set custom desc_id for our modifier
ModifierDozerGuide.desc_id = "csr_dozer_guide_desc"

-- Use the custom Dozer Guide icon
ModifierDozerGuide.icon = "csr_dozer_guide"

