-- Crime Spree Roguelike - Civilian Guilt Modifier
-- Forced loud modifier: each civilian killed in loud permanently reduces player max HP
-- Effect: -5% max HP per kill, minimum 30% of base max HP remains

if not RequiredScript then
	return
end


if not ModifierNoHurtAnims then
	return
end

-- Inherits from ModifierNoHurtAnims as a safe base class
-- The actual HP reduction is handled externally:
--   - Detection: playermanager.lua (spawned_player hook)
--   - Penalty: playermanager.lua (health_skill_multiplier override)
--   - Kill tracking: civilian_damage_hook.lua (CivilianDamage:die override)
ModifierCivilianGuilt = class(ModifierNoHurtAnims)
ModifierCivilianGuilt.desc_id = "menu_cs_modifier_civilian_guilt"

function ModifierCivilianGuilt:init(data)
	-- No-op: effect is handled dynamically via kill counter + health_skill_multiplier
end

