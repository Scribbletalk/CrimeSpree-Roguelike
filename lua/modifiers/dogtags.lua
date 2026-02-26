-- DOG TAGS - Health boost item
-- Increases the player's maximum health

if not RequiredScript then
	return
end

-- Inherits from CSRBaseModifier (standalone base class with no side effects)
ModifierDogTags = ModifierDogTags or class(CSRBaseModifier)

-- Set custom desc_id for localization
ModifierDogTags.desc_id = "menu_cs_modifier_player_health"
