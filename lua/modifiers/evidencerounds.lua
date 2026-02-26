-- EVIDENCE ROUNDS - Damage boost item
-- Increases all player damage (weapons + melee)

if not RequiredScript then
	return
end

-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierEvidenceRounds = ModifierEvidenceRounds or class(CSRBaseModifier)

-- Set custom desc_id for localization
ModifierEvidenceRounds.desc_id = "menu_cs_modifier_player_damage"

-- Set custom icon
ModifierEvidenceRounds.icon = "csr_bullets"
