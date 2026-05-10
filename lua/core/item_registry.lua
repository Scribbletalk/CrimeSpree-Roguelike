-- Crime Spree Roguelike - Centralized Item Registry
-- Single source of truth for all item mechanical data.
-- Consumer files (crimespree_filter, localization, auto_refill, etc.)
-- generate their local tables from this registry instead of hardcoding.

CSR_ItemRegistry = CSR_ItemRegistry or {}

_G.CSR_ITEM_REGISTRY = {
	-- ============ COMMON (weight 0.80) ============
	{
		-- type was "health" historically; renamed to match the user-facing name
		-- (and the csr_logbook_dog_tags_* loc-key suffix) so any code path that
		-- reads def.type can never print "HEALTH" for the player. id_prefix
		-- stays "player_health_boost_" because changing it would break every
		-- existing save and every "menu_cs_modifier_player_health_boost_<n>"
		-- localization key generated in localization.lua.
		type = "dog_tags",
		class = "ModifierDogTags",
		icon = "csr_dog_tags",
		id_prefix = "player_health_boost_",
		rarity = "common",
		weight = 0.80,
		loc_key = "menu_cs_modifier_player_health",
	},
	{
		type = "duct_tape",
		class = "ModifierDuctTape",
		icon = "csr_duct_tape",
		id_prefix = "player_duct_tape_",
		rarity = "common",
		weight = 0.80,
		loc_key = "menu_cs_modifier_duct_tape",
	},
	{
		type = "escape_plan",
		class = "ModifierEscapePlan",
		icon = "csr_escape_plan",
		id_prefix = "player_escape_plan_",
		rarity = "common",
		weight = 0.80,
		loc_key = "csr_escape_plan_desc",
	},
	{
		type = "worn_bandaid",
		class = "ModifierWornBandAid",
		icon = "csr_worn_bandaid",
		id_prefix = "player_worn_bandaid_",
		rarity = "common",
		weight = 0.80,
		loc_key = "csr_worn_bandaid_desc",
	},
	{
		type = "rebar",
		class = "ModifierPieceOfRebar",
		icon = "csr_rebar",
		id_prefix = "player_rebar_",
		rarity = "common",
		weight = 0.80,
		loc_key = "csr_piece_of_rebar_desc",
		needs_stub = true,
	},

	{
		type = "half_a_glass",
		class = "ModifierHalfAGlass",
		icon = "csr_half_a_glass",
		id_prefix = "player_half_a_glass_",
		rarity = "common",
		weight = 0.80,
		loc_key = "csr_half_a_glass_desc",
		needs_stub = true,
	},
	{
		type = "cup_of_joe",
		class = "ModifierCupOfJoe",
		icon = "csr_cup_of_joe",
		id_prefix = "player_cup_of_joe_",
		rarity = "common",
		weight = 0.80,
		loc_key = "csr_cup_of_joe_desc",
		needs_stub = true,
	},

	-- ============ UNCOMMON (weight 0.40) ============
	{
		-- type was "damage" historically; renamed to match the player-facing
		-- name (and the csr_logbook_evidence_rounds_* loc-key suffix). id_prefix
		-- stays "player_damage_boost_" to keep saves and existing
		-- "menu_cs_modifier_player_damage_boost_<n>" loc keys intact.
		type = "evidence_rounds",
		class = "ModifierEvidenceRounds",
		icon = "csr_evidence_rounds",
		id_prefix = "player_damage_boost_",
		rarity = "uncommon",
		weight = 0.40,
		loc_key = "menu_cs_modifier_player_damage",
	},
	{
		-- type was "car_keys" historically; renamed to match player-facing name
		-- and the csr_logbook_falcogini_keys_* loc-key suffix. id_prefix kept.
		type = "falcogini_keys",
		class = "ModifierCarKeys",
		icon = "csr_falcogini_keys",
		id_prefix = "player_car_keys_",
		rarity = "uncommon",
		weight = 0.40,
		loc_key = "csr_car_keys_desc",
	},
	{
		type = "wolfs_toolbox",
		class = "ModifierWolfsToolbox",
		icon = "csr_toolbox",
		id_prefix = "player_wolfs_toolbox_",
		rarity = "uncommon",
		weight = 0.40,
		loc_key = "csr_wolfs_toolbox_desc",
	},
	{
		type = "overkill_rush",
		class = "ModifierOverkillRush",
		icon = "csr_overkill_rush",
		id_prefix = "player_overkill_rush_",
		rarity = "uncommon",
		weight = 0.40,
		loc_key = "csr_overkill_rush_desc",
		needs_stub = true,
	},
	{
		type = "pink_slip",
		class = "ModifierPinkSlip",
		icon = "csr_pink_slip",
		id_prefix = "player_pink_slip_",
		rarity = "uncommon",
		weight = 0.40,
		loc_key = "csr_pink_slip_desc",
		needs_stub = true,
	},
	{
		type = "the_edge",
		class = "ModifierTheEdge",
		icon = "csr_the_edge",
		id_prefix = "player_the_edge_",
		rarity = "uncommon",
		weight = 0.40,
		loc_key = "csr_the_edge_desc",
		needs_stub = true,
	},

	-- ============ RARE (weight 0.04) ============
	{
		type = "bonnie_chip",
		class = "ModifierBonniesLuckyChip",
		icon = "csr_bonnie_chip",
		id_prefix = "player_bonnie_chip_",
		rarity = "rare",
		weight = 0.04,
		loc_key = "csr_bonnie_chip_desc",
	},
	{
		type = "plush_shark",
		class = "ModifierPlushShark",
		icon = "csr_plush_shark",
		id_prefix = "player_plush_shark_",
		rarity = "rare",
		weight = 0.04,
		loc_key = "csr_plush_shark_desc",
	},
	{
		type = "jiro_last_wish",
		class = "ModifierJiroLastWish",
		icon = "csr_jiro_last_wish",
		id_prefix = "player_jiro_last_wish_",
		rarity = "rare",
		weight = 0.04,
		loc_key = "csr_jiro_last_wish_desc",
		needs_stub = true,
	},
	{
		type = "dearest_possession",
		class = "ModifierDearestPossession",
		icon = "csr_dearest_possession",
		id_prefix = "player_dearest_possession_",
		rarity = "rare",
		weight = 0.04,
		loc_key = "csr_dearest_possession_desc",
		needs_stub = true,
	},
	{
		type = "viklund_vinyl",
		class = "ModifierViklundVinyl",
		icon = "csr_viklund_vinyl",
		id_prefix = "player_viklund_vinyl_",
		rarity = "rare",
		weight = 0.04,
		loc_key = "csr_viklund_vinyl_desc",
		needs_stub = true,
	},
	{
		type = "lockes_beret",
		class = "ModifierLockesBeret",
		icon = "csr_lockes_beret",
		id_prefix = "player_lockes_beret_",
		rarity = "rare",
		weight = 0.04,
		loc_key = "csr_lockes_beret_desc",
		needs_stub = true,
	},

	-- ============ CONTRABAND (weight 0.08) ============
	{
		type = "dozer_guide",
		class = "ModifierDozerGuide",
		icon = "csr_dozer_guide",
		id_prefix = "player_dozer_guide_",
		rarity = "contraband",
		weight = 0.08,
		loc_key = "csr_dozer_guide_desc",
	},
	{
		type = "glass_pistol",
		class = "ModifierGlassCannon",
		icon = "csr_glass_pistol",
		id_prefix = "player_glass_pistol_",
		rarity = "contraband",
		weight = 0.08,
		loc_key = "csr_glass_cannon_desc",
	},
	{
		type = "equalizer",
		class = "ModifierEqualizer",
		icon = "csr_equalizer",
		id_prefix = "player_equalizer_",
		rarity = "contraband",
		weight = 0.08,
		loc_key = "csr_equalizer_desc",
		needs_stub = true,
	},
	{
		type = "crooked_badge",
		class = "ModifierCrookedBadge",
		icon = "csr_crooked_badge",
		id_prefix = "player_crooked_badge_",
		rarity = "contraband",
		weight = 0.08,
		loc_key = "csr_crooked_badge_desc",
		needs_stub = true,
	},
	{
		type = "dead_mans_trigger",
		class = "ModifierDeadMansTrigger",
		icon = "csr_dead_mans_trigger",
		id_prefix = "player_dead_mans_trigger_",
		rarity = "contraband",
		weight = 0.08,
		loc_key = "csr_dead_mans_trigger_desc",
		needs_stub = true,
	},

	-- @WILDCARD-START (build script strips this entire block when --no-wildcards)
	-- ============ WILDCARD (weight 0.13, magenta tier) ============
	-- Own bucket (not a tier-up). Carry-1 per-tier. Never printer-spawned.
	-- Per-popup tier rate ~16% with 4 wildcards at 0.13.
	{
		type = "side_satchel",
		class = "ModifierSideSatchel",
		icon = "csr_side_satchel",
		id_prefix = "player_side_satchel_",
		rarity = "wildcard",
		weight = 0.13,
		loc_key = "csr_side_satchel_desc",
		needs_stub = true,
	},
	{
		type = "familiar_friend",
		class = "ModifierFamiliarFriend",
		icon = "csr_familiar_friend",
		id_prefix = "player_familiar_friend_",
		rarity = "wildcard",
		weight = 0.13,
		loc_key = "csr_familiar_friend_desc",
		needs_stub = true,
	},
	{
		type = "turron",
		class = "ModifierTurron",
		icon = "csr_turron",
		id_prefix = "player_turron_",
		rarity = "wildcard",
		weight = 0.13,
		loc_key = "csr_turron_desc",
		needs_stub = true,
	},
	{
		type = "hippocratic_oath",
		class = "ModifierHippocraticOath",
		icon = "csr_hippocratic_oath",
		id_prefix = "player_hippocratic_oath_",
		rarity = "wildcard",
		weight = 0.13,
		loc_key = "csr_hippocratic_oath_desc",
		needs_stub = true,
	},
	-- @WILDCARD-END

	-- ============ SCRAP (no effect, printer fodder) ============
	-- Produced by the in-world scrapper from real items. Has no modifier
	-- class (no buff, no stat snapshot). is_scrap = true gates filter.lua,
	-- crimespree_filter.lua's offer pool, the scrapper menu's own list, and
	-- any other consumer that needs to skip "fake" items. Weight 0 makes
	-- them invisible to weighted-pool selectors even if a stale codepath
	-- forgot to honor is_scrap.
	{
		type = "scrap_common",
		icon = "csr_scrap",
		id_prefix = "player_scrap_common_",
		rarity = "common",
		weight = 0,
		loc_key = "csr_scrap_common_desc",
		is_scrap = true,
	},
	{
		type = "scrap_uncommon",
		icon = "csr_scrap",
		id_prefix = "player_scrap_uncommon_",
		rarity = "uncommon",
		weight = 0,
		loc_key = "csr_scrap_uncommon_desc",
		is_scrap = true,
	},
	{
		type = "scrap_rare",
		icon = "csr_scrap",
		id_prefix = "player_scrap_rare_",
		rarity = "rare",
		weight = 0,
		loc_key = "csr_scrap_rare_desc",
		is_scrap = true,
	},
}

-- Build lookup tables for fast access
_G.CSR_ITEM_BY_TYPE = {}
_G.CSR_ITEM_BY_PREFIX = {}

for _, item in ipairs(_G.CSR_ITEM_REGISTRY) do
	_G.CSR_ITEM_BY_TYPE[item.type] = item
	-- Strip trailing underscore for prefix-key matching (e.g. "player_health_boost")
	local key = item.id_prefix:sub(1, -2)
	_G.CSR_ITEM_BY_PREFIX[key] = item
end
