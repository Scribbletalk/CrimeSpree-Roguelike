-- Crime Spree Roguelike - Less Pagers Modifier
-- Reduces number of pagers available (4 tiers)

if not RequiredScript then
	return
end

-- Tier 1: 1 less pager (3 available)
ModifierCSRLessPagers1 = ModifierCSRLessPagers1 or class(ModifierLessPagers)
ModifierCSRLessPagers1.desc_id = "menu_cs_modifier_less_pagers_1"

-- Tier 2: 2 less pagers (2 available)
ModifierCSRLessPagers2 = ModifierCSRLessPagers2 or class(ModifierLessPagers)
ModifierCSRLessPagers2.desc_id = "menu_cs_modifier_less_pagers_2"

-- Tier 3: 3 less pagers (1 available)
ModifierCSRLessPagers3 = ModifierCSRLessPagers3 or class(ModifierLessPagers)
ModifierCSRLessPagers3.desc_id = "menu_cs_modifier_less_pagers_3"

-- Tier 4: 4 less pagers (0 available)
ModifierCSRLessPagers4 = ModifierCSRLessPagers4 or class(ModifierLessPagers)
ModifierCSRLessPagers4.desc_id = "menu_cs_modifier_less_pagers_4"

log("[CSR LessPagers] 4 tier classes created")
