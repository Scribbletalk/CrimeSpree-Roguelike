-- Crime Spree Roguelike Alpha 1 - Health modifier
-- Effect is applied only at mission start, not in the menu

if not RequiredScript then
	return
end



if not ModifierShieldReflect then
	return
end


-- Override desc_id with our own text
ModifierShieldReflect.desc_id = "menu_cs_modifier_player_health"

-- DO NOT touch init() - it is called in the menu and causes a crash
-- Effects will be applied via mission_hook.lua at mission start

