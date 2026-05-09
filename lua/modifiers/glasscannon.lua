-- GLASS PISTOL (Glass Cannon) - Damage/Health trade-off item
-- +50% damage (weapon + melee), -50% health

if not RequiredScript then
	return
end

-- Inherit from CSRBaseModifier (standalone base class with no side effects)
ModifierGlassCannon = ModifierGlassCannon or class(CSRBaseModifier)

-- Set custom desc_id for localization
ModifierGlassCannon.desc_id = "csr_glass_cannon_desc"
