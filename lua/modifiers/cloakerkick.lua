-- Crime Spree Roguelike Alpha 1 - Hook on ModifierCloakerKick (Damage Boost)

if not RequiredScript then return end



if not ModifierCloakerKick then
	return
end


-- Override the class desc_id to display the damage text
ModifierCloakerKick.desc_id = "menu_cs_modifier_player_damage"

