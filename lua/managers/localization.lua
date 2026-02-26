-- Crime Spree Roguelike Alpha 1 - Localization with colors

log("[CSR Alpha1 LOC] localization_hook.lua загружается")

-- Rarity colors (hex)
local COLORS = {
	common = "ffffff",      -- white
	uncommon = "00ff00",    -- green
	rare = "0099ff",        -- blue
	contraband = "ff6600",  -- orange (trade-off items)
	legendary = "ffd700"    -- gold
}

-- Item data (player buffs) - English
local ITEMS_EN = {
	["menu_cs_modifier_player_health"] = {
		name = "DOG TAGS",
		desc = "Increases your max health.",
		rarity = "common"
	},
	["menu_cs_modifier_player_damage"] = {
		name = "EVIDENCE ROUNDS",
		desc = "All your attacks deal more damage.",
		rarity = "uncommon"
	},
	["csr_dozer_guide_desc"] = {
		name = "DOZER GUIDE",
		desc = "Greatly increases your armor and damage,\nbut slows you down.",
		rarity = "contraband"
	},
	["csr_bonnie_chip_desc"] = {
		name = "BONNIE'S LUCKY CHIP",
		desc = "Each hit has a small chance to instantly kill the target.",
		rarity = "rare"  -- Blue color (PAYDAY 2 blue)
	},
	["csr_glass_cannon_desc"] = {
		name = "GLASS PISTOL",
		desc = "Massively increases all damage,\nbut halves your maximum health and armor.",
		rarity = "contraband"
	},
	["csr_car_keys_desc"] = {
		name = "FALCOGINI KEYS",
		desc = "Gives you a chance to dodge incoming damage.",
		rarity = "uncommon"
	},
	["csr_plush_shark_desc"] = {
		name = "PLUSH SHARK",
		desc = "Saves you from a killing blow once per life,\nthen grants brief invulnerability.",
		rarity = "rare"
	},
	["csr_wolfs_toolbox_desc"] = {
		name = "WOLF'S TOOLBOX",
		desc = "Killing enemies reduces the timer\non active drills and saws.",
		rarity = "uncommon"
	},
	["menu_cs_modifier_duct_tape"] = {
		name = "DUCT TAPE",
		desc = "Makes you faster at interacting with objects.",
		rarity = "common"
	},
	["csr_escape_plan_desc"] = {
		name = "ESCAPE PLAN",
		desc = "Increases your movement speed.",
		rarity = "common"
	},
	["csr_worn_bandaid_desc"] = {
		name = "WORN BAND-AID",
		desc = "Slowly regenerates a small amount of health over time.",
		rarity = "common"
	},
	["csr_piece_of_rebar_desc"] = {
		name = "PIECE OF REBAR",
		desc = "Your first hit on an enemy deals bonus damage.",
		rarity = "common"
	},
	["csr_jiro_last_wish_desc"] = {
		name = "JIRO'S LAST WISH",
		desc = "Sprint while charging a melee attack. Increases melee damage.",
		rarity = "rare"
	},
	["csr_dearest_possession_desc"] = {
		name = "DEAREST POSSESSION",
		desc = "Healing at full HP converts to temporary shields that quickly fade away.",
		rarity = "rare"
	},
	["csr_viklund_vinyl_desc"] = {
		name = "VIKLUND'S VINYL",
		desc = "...and his beats were electric.",
		rarity = "rare"
	},
	["csr_equalizer_desc"] = {
		name = "EQUALIZER",
		desc = "Greatly increases damage against special enemies,\nbut reduces it against regular ones.",
		rarity = "contraband"
	},
	["csr_crooked_badge_desc"] = {
		name = "CROOKED BADGE",
		desc = "Chance to restore a down after each assault.\nBut your bleedout timer is reduced.",
		rarity = "contraband"
	},
	["csr_dead_mans_trigger_desc"] = {
		name = "DEAD MAN'S TRIGGER",
		desc = "Going down triggers an explosion around you.\nBut allies also receive damage from it.",
		rarity = "contraband"
	},
	["csr_overkill_rush_desc"] = {
		name = "OVERKILL RUSH",
		desc = "Killing enemies temporarily increases fire rate and reload speed.",
		rarity = "uncommon"
	},
	["csr_pink_slip_desc"] = {
		name = "PINK SLIP",
		desc = "Killing an enemy restores health.",
		rarity = "uncommon"
	},
	-- Dummy modifiers (should not appear in popup, but need localization just in case)
	["csr_base_modifier"] = {
		name = "",
		desc = "",
		rarity = "common"
	},
	["csr_dummy_5"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_10"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_15"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_30"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_35"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_45"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_55"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_65"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_70"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_85"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_90"] = { name = "", desc = "", rarity = "common" },
	["csr_dummy_95"] = { name = "", desc = "", rarity = "common" },
	-- Enemy HP/DMG (virtual modifier for UI)
	["csr_enemy_hp_damage_total"] = {
		name = "ENEMY HEALTH & DAMAGE",
		desc = "Increases with Crime Spree level",
		rarity = "forced"
	},
	-- Unlock modifiers
	["csr_enable_bulldozers_desc"] = {
		name = "YOU'RE UP AGAINST THE WALL AND I AM THE FUCKING WALL!",
		desc = "Bulldozers can now spawn on missions",
		rarity = "unlock"
	},
	["csr_enable_medics_desc"] = {
		name = "Don't worry, I'm here! And I brought drugs!",
		desc = "Medics can now spawn on missions",
		rarity = "unlock"
	},
	["csr_enable_tasers_desc"] = {
		name = "I'm the fucking SPARK MAN!",
		desc = "Tasers can now spawn on missions",
		rarity = "unlock"
	},
	["csr_enable_cloakers_desc"] = {
		name = "You call this resisting arrest? We call this a difficulty tweak!",
		desc = "Cloakers can now spawn on missions",
		rarity = "unlock"
	}
}

-- Overridden vanilla modifiers - English
local VANILLA_OVERRIDES_EN = {
	-- Loud modifiers
	["menu_cs_modifier_cloaker_tear_gas"] = "Toxic Takedown\nKilled Cloakers leave behind a toxic cloud that drains 5% of your max health every second.",
	["menu_cs_modifier_taser_overcharge"] = "Rapid Shock\nThe tasing knockout effect of the Taser now knocks a player out 50% faster",
	["menu_cs_modifier_dozer_rage"] = "Berserker Mode\nWhen a Bulldozer's faceplate is destroyed, the Bulldozer enters a berserker rage, receiving a 100% increase to their base damage output",
	["menu_cs_modifier_more_dozers"] = "Heavy Reinforcement\nTwo additional Bulldozers are allowed into the level",
	["menu_cs_modifier_more_medics"] = "Field Hospital\nTwo additional Medics are allowed into the level",
	["menu_cs_modifier_heal_speed"] = "Autodidact\nMedic heal cooldown is 20% faster",
	["menu_cs_modifier_assault_extender"] = "Extended Assault\nPolice assaults will have a 50% longer duration. This gets reduced by 4% for every hostage and converted cop, up to a maximum of 8",
	-- Stealth modifiers - Less Pagers (4 tiers)
	["menu_cs_modifier_less_pagers_1"] = "Keen Dispatch\n1 less pager can be answered per heist",
	["menu_cs_modifier_less_pagers_2"] = "Keen Dispatch\n2 less pagers can be answered per heist",
	["menu_cs_modifier_less_pagers_3"] = "Keen Dispatch\n3 less pagers can be answered per heist",
	["menu_cs_modifier_less_pagers_4"] = "Keen Dispatch\n4 less pagers can be answered per heist",
	-- Stealth modifiers - Civilian Alarm (3 tiers)
	["menu_cs_modifier_civilian_alarm_1"] = "Witness Protection\nThe alarm will be sounded if more than 10 civilians are killed",
	["menu_cs_modifier_civilian_alarm_2"] = "Witness Protection\nThe alarm will be sounded if more than 7 civilians are killed",
	["menu_cs_modifier_civilian_alarm_3"] = "Witness Protection\nThe alarm will be sounded if more than 4 civilians are killed",
	-- Stealth modifiers - Less Concealment (same description, stacks)
	["menu_cs_modifier_less_concealment"] = "Stand Out\nDetection risk is increased by 3",
	-- Add missing loud modifiers
	["menu_cs_modifier_no_hurt_anims"] = "Immovable\nEnemies cannot be staggered by damage",
	["menu_cs_modifier_heavies"] = "Heavy Response\nAll FBI SWATs will be replaced with Heavy SWATs",
	["menu_cs_modifier_skulldozers"] = "Skulldozers\nBulldozers are replaced by Skulldozers",
	["menu_cs_modifier_dozer_minigun"] = "Minigun Dozers\nWhenever a Bulldozer spawns, there is a chance that it will be a slow-moving minigun-wielding Bulldozer",
	["menu_cs_modifier_dozer_medic"] = "Medic Bulldozers\nWhenever a Bulldozer spawns, there is a chance that it will be a Medic Bulldozer",
	["menu_cs_modifier_shield_reflect"] = "Reflective Shields\nShields will reflect projectiles",
	["menu_cs_modifier_cloaker_smoke"] = "Cloaker Smoke\nCloakers will drop a smokebomb when they kick a player",
	["menu_cs_modifier_heavy_sniper"] = "ZEAL Heavy SWAT Marksman\nFor every Heavy SWAT that spawns, there is a chance that it will be replaced by a ZEAL Heavy SWAT Marksman",
	["menu_cs_modifier_medic_adrenaline"] = "Medic Adrenaline\nWhenever a Medic revives another cop, the revived cop gets a 100% increase to their base damage output",
	["menu_cs_modifier_shield_phalanx"] = "Phalanx Formation\nAll Shield units in the game are replaced by Captain Winters' Shield units",
	["menu_cs_modifier_medic_deathwish"] = "Death Wish Medics\nWhenever a Medic is killed, all cops within the Medic's healing range are instantly healed",
	["menu_cs_modifier_explosion_immunity"] = "Explosive Resistance\nBulldozers are immune to explosive damage",
	["menu_cs_modifier_cloaker_arrest"] = "Cloaker Arrest\nCloakers executing a successful charge now cuffs the player instead of downing them",
	["menu_cs_modifier_medic_rage"] = "Medic Rage\nFor every cop that dies within a Medic's healing range, that Medic sees his base damage output increased by 20%. This effect stacks indefinitely",
	["menu_cs_modifier_civilian_guilt"] = "Guilty Conscience\nEach civilian killed permanently reduces your max health by 5% for this mission, down to a minimum of 30%.",
	-- Enable modifiers (unlock enemy spawns on low difficulties)
	["menu_cs_modifier_enable_bulldozers"] = "YOU'RE UP AGAINST THE WALL AND I AM THE FUCKING WALL!\nBulldozers can now spawn on this difficulty",
	["menu_cs_modifier_enable_medics"] = "Don't worry, I'm here! And I brought drugs!\nMedics can now spawn on this difficulty",
	["menu_cs_modifier_enable_tasers"] = "I'm the fucking SPARK MAN!\nTasers can now spawn on this difficulty",
	["menu_cs_modifier_enable_cloakers"] = "You call this resisting arrest? We call this a difficulty tweak!\nCloakers can now spawn on this difficulty",
}

-- Returns the currently selected language
local function get_current_language()
	if CSR_Settings and CSR_Settings.GetLanguage then
		return CSR_Settings:GetLanguage()
	end
	return "en"
end

Hooks:Add("LocalizationManagerPostInit", "CSR_Alpha1_Localization", function(loc)
	log("[CSR Alpha1 LOC] LocalizationManagerPostInit вызван!")

	-- Russian localization disabled - English only
	local ITEMS = ITEMS_EN
	local VANILLA_OVERRIDES = VANILLA_OVERRIDES_EN

	-- Build localization strings
	local strings = {}

	-- Player buffs (base keys)
	for key, item in pairs(ITEMS) do
		strings[key] = item.name .. "\n" .. item.desc
	end

	-- Dynamic localization for all item copies (up to 200 copies)
	-- Vanilla looks up localization by pattern: menu_cs_modifier_<modifier_id>
	-- Our IDs: player_health_boost_1, player_health_boost_2, ... player_health_boost_200
	-- Need to generate keys: menu_cs_modifier_player_health_boost_1, menu_cs_modifier_player_health_boost_2, etc.
	local item_types = {
		{ prefix = "player_health_boost_", base_key = "menu_cs_modifier_player_health" },
		{ prefix = "player_damage_boost_", base_key = "menu_cs_modifier_player_damage" },
		{ prefix = "player_dozer_guide_", base_key = "csr_dozer_guide_desc" },
		{ prefix = "player_bonnie_chip_", base_key = "csr_bonnie_chip_desc" },
		{ prefix = "player_glass_pistol_", base_key = "csr_glass_cannon_desc" },
		{ prefix = "player_car_keys_", base_key = "csr_car_keys_desc" },
		{ prefix = "player_plush_shark_", base_key = "csr_plush_shark_desc" },
		{ prefix = "player_wolfs_toolbox_", base_key = "csr_wolfs_toolbox_desc" },
		{ prefix = "player_duct_tape_", base_key = "menu_cs_modifier_duct_tape" },
		{ prefix = "player_escape_plan_", base_key = "csr_escape_plan_desc" },
		{ prefix = "player_worn_bandaid_", base_key = "csr_worn_bandaid_desc" },
		{ prefix = "player_rebar_", base_key = "csr_piece_of_rebar_desc" },
		{ prefix = "player_overkill_rush_", base_key = "csr_overkill_rush_desc" },
		{ prefix = "player_pink_slip_", base_key = "csr_pink_slip_desc" },
		{ prefix = "player_jiro_last_wish_", base_key = "csr_jiro_last_wish_desc" },
		{ prefix = "player_dearest_possession_", base_key = "csr_dearest_possession_desc" },
		{ prefix = "player_viklund_vinyl_", base_key = "csr_viklund_vinyl_desc" },
		{ prefix = "player_equalizer_", base_key = "csr_equalizer_desc" },
		{ prefix = "player_crooked_badge_", base_key = "csr_crooked_badge_desc" },
		{ prefix = "player_dead_mans_trigger_", base_key = "csr_dead_mans_trigger_desc" }
	}

	for _, item_type in ipairs(item_types) do
		local base_item = ITEMS[item_type.base_key]
		if base_item then
			local text = base_item.name .. "\n" .. base_item.desc
			-- Generate keys for 200 copies
			for i = 1, 200 do
				local mod_id = item_type.prefix .. i
				local loc_key = "menu_cs_modifier_" .. mod_id
				strings[loc_key] = text
			end
			log("[CSR LOC] Generated 200 localization keys for: " .. item_type.prefix)
		end
	end

	-- Vanilla modifiers with fixed text
	for key, text in pairs(VANILLA_OVERRIDES) do
		strings[key] = text
	end

	-- Items tab label
	strings["menu_csr_items"] = "ITEMS"
	strings["menu_csr_items_placeholder"] = "Collected items will show up here."

	-- Stats tab label
	strings["menu_csr_stats"] = "STATS"

	-- Override "Select Modifiers" with "Select Item/Items"
	strings["menu_cs_select_modifier"] = "SELECT ITEM"
	strings["menu_cs_select_modifiers"] = "SELECT ITEMS"

	-- Override "Loud Modifiers" with "Items"
	strings["menu_cs_modifier_loud"] = "ITEMS"
	strings["menu_cs_modifiers_loud"] = "ITEMS"

	-- Override "Next Loud Modifier" with "Next Item Drop"
	strings["menu_cs_next_modifier_in"] = "NEXT ITEM DROP IN"
	strings["menu_cs_next_modifier"] = "NEXT ITEM DROP"

	-- Override "Starting Level" with "Starting Difficulty"
	strings["menu_cs_starting_level"] = "STARTING DIFFICULTY"
	-- Try different possible keys
	strings["menu_cs_starting_level_title"] = "STARTING DIFFICULTY"
	strings["menu_starting_level"] = "STARTING DIFFICULTY"

	-- === LOGBOOK LOCALIZATION ===
	strings["menu_csr_logbook"] = "LOGBOOK"
	strings["menu_csr_logbook_new"] = "LOGBOOK !"

	-- Rarities
	strings["csr_logbook_rarity_common"] = "Common"
	strings["csr_logbook_rarity_uncommon"] = "Uncommon"
	strings["csr_logbook_rarity_rare"] = "Rare"
	strings["csr_logbook_rarity_contraband"] = "Contraband"

	local C = _G.CSR_ItemConstants or {}

	-- DOG TAGS
	local dt_hp = C.dog_tags_hp_bonus or 0.10
	strings["csr_logbook_dog_tags_name"] = "DOG TAGS"
	strings["csr_logbook_dog_tags_effect"] = string.format("+%g%% Max Health per stack.\nStacks additively with other bonuses.", dt_hp * 100)
	strings["csr_logbook_dog_tags_lore"] = "Dog tags of fallen comrades. They say these bring luck in battle and remind you of those who walked this path before."

	-- DUCT TAPE
	local tape_spd = C.duct_tape_speed_bonus or 0.05
	strings["csr_logbook_duct_tape_name"] = "DUCT TAPE"
	strings["csr_logbook_duct_tape_effect"] = string.format("+%g%% Interaction Speed per stack.\nStacks additively with crew bonuses.", tape_spd * 100)
	strings["csr_logbook_duct_tape_lore"] = "Universal solution to all problems. If something doesn't work - wrap it with duct tape. If it works too well - also wrap it with duct tape."

	-- ESCAPE PLAN
	local sn_cap = C.escape_plan_cap or 0.50
	local sn_k   = (C.escape_plan_k_num or 3) / (C.escape_plan_k_den or 47)
	local sn_first = math.floor(sn_cap * sn_k / (1 + sn_k) * 100 + 0.5)
	strings["csr_logbook_escape_plan_name"] = "ESCAPE PLAN"
	strings["csr_logbook_escape_plan_effect"] = string.format("+~%d%% Movement Speed per stack.\nCap ~%g%%.", sn_first, sn_cap * 100)
	strings["csr_logbook_escape_plan_lore"] = "Old sneakers of an unknown heister. Worn out, but incredibly comfortable. They say their previous owner outran the cops so fast that even bullets couldn't keep up."

	-- WORN BAND-AID
	local ba_regen = C.worn_bandaid_regen    or 5
	local ba_int   = C.worn_bandaid_interval or 10
	strings["csr_logbook_worn_bandaid_name"] = "WORN BAND-AID"
	strings["csr_logbook_worn_bandaid_effect"] = string.format("+%g HP regeneration every %g seconds per stack.\nFlat value, independent of max HP.", ba_regen, ba_int)
	strings["csr_logbook_worn_bandaid_lore"] = "An old band-aid from an unknown medic's kit. Doesn't look great, but still works. Maybe it's not about the band-aid, but the will to survive?"

	-- EVIDENCE ROUNDS
	local ap_dmg = C.ap_rounds_damage_bonus or 0.05
	strings["csr_logbook_ap_rounds_name"] = "EVIDENCE ROUNDS"
	strings["csr_logbook_ap_rounds_effect"] = string.format("+%g%% to ALL damage per stack.\nIncludes: weapons, melee, throwables, sentries, tripmines, fire.", ap_dmg * 100)
	strings["csr_logbook_ap_rounds_lore"] = "Rounds infused with evidence of crimes. Each bullet damages not only the body, but the conscience of enemies."

	-- FALCOGINI KEYS
	local keys_first = math.floor(100 / (1 + (C.car_keys_k_den or 19)) + 0.5)
	strings["csr_logbook_falcogini_keys_name"] = "FALCOGINI KEYS"
	strings["csr_logbook_falcogini_keys_effect"] = string.format("+~%d%% Dodge chance per stack (diminishing returns).\nNo hard cap.", keys_first)
	strings["csr_logbook_falcogini_keys_lore"] = "Keys to a Falcogini sports car. The owner was so fast that bullets simply couldn't catch up."

	-- WOLF'S TOOLBOX
	local wt_norm = C.wolfs_toolbox_normal  or 0.1
	local wt_spec = C.wolfs_toolbox_special or 1.0
	strings["csr_logbook_wolfs_toolbox_name"] = "WOLF'S TOOLBOX"
	strings["csr_logbook_wolfs_toolbox_effect"] = string.format("Kills reduce drill/saw timer per stack:\n• Normal enemy: -%gs\n• Special enemy: -%gs\nDoes not affect jammed drills.", wt_norm, wt_spec)
	strings["csr_logbook_wolfs_toolbox_lore"] = "Wolf's personal toolbox. He always said: 'If something breaks - kill someone, and it'll fix itself'."

	-- BONNIE'S LUCKY CHIP
	local bc_chance = C.bonnie_chip_chance   or 0.05
	local bc_cd     = C.bonnie_chip_cooldown or 1.5
	strings["csr_logbook_bonnie_chip_name"] = "BONNIE'S LUCKY CHIP"
	strings["csr_logbook_bonnie_chip_effect"] = string.format("%g%% chance to instantly kill an enemy on hit.\nStacks increase chance through independent rolls.\n%gs cooldown.", bc_chance * 100, bc_cd)
	strings["csr_logbook_bonnie_chip_lore"] = "Bonnie's poker chip from Murkywater casino. Legend says she won it in a game where life was the stake."

	-- PLUSH SHARK
	local ps_inv_base  = C.plush_shark_invuln_base  or 10
	local ps_inv_extra = C.plush_shark_invuln_extra or 20
	strings["csr_logbook_plush_shark_name"] = "PLUSH SHARK"
	strings["csr_logbook_plush_shark_effect"] = string.format("Protects from lethal damage once per life.\nGrants invulnerability for %gs (+%gs per additional stack).", ps_inv_base, ps_inv_extra)
	strings["csr_logbook_plush_shark_lore"] = "BLÅHAJ from IKEA. This cute plushie friend will save you even in the most hopeless situation. Just don't ask how."

	-- DOZER GUIDE
	local dz_armor = C.dozer_armor_bonus   or 0.50
	local dz_dmg   = C.dozer_damage_bonus  or 0.05
	local dz_spd   = C.dozer_speed_penalty or 0.15
	local dz_dodge = C.dozer_dodge_penalty or 5
	local dz_min   = C.dozer_speed_min     or 0.40
	strings["csr_logbook_dozer_guide_name"] = "DOZER GUIDE"
	strings["csr_logbook_dozer_guide_effect"] = string.format("+%g%% armor, +%g%% damage, -%g%% movement speed per stack.\nMinimum speed %g%%. Also -%d dodge per stack.", dz_armor * 100, dz_dmg * 100, dz_spd * 100, dz_min * 100, dz_dodge)
	strings["csr_logbook_dozer_guide_lore"] = "Field manual for bulldozers. 'Be unstoppable like a tank. Be slow like a tank. Be the tank'."

	-- GLASS PISTOL
	local gp_dmg = C.glass_pistol_dmg_per_stack or 1.5
	local gp_div = C.glass_pistol_div_per_stack  or 2
	strings["csr_logbook_glass_pistol_name"] = "GLASS PISTOL"
	strings["csr_logbook_glass_pistol_effect"] = string.format("×%g Weapon/Melee Damage, ÷%d Health, ÷%d Armor per stack.\nAll multipliers stack multiplicatively.", gp_dmg, gp_div, gp_div)
	strings["csr_logbook_glass_pistol_lore"] = "A pistol carved from pure glass. Fragile on the outside, deadly on the inside. Two stacks = death from one shot. Three stacks = you're already dead."

	-- PINK SLIP
	local ps_heal_base  = _G.CSR_ItemConstants and _G.CSR_ItemConstants.pink_slip_base_heal  or 5
	local ps_heal_extra = _G.CSR_ItemConstants and _G.CSR_ItemConstants.pink_slip_extra_heal or 2.5
	strings["csr_logbook_pink_slip_name"] = "PINK SLIP"
	strings["csr_logbook_pink_slip_effect"] = string.format(
		"Killing an enemy restores +%g HP (+%g HP per stack).",
		ps_heal_base, ps_heal_extra)
	strings["csr_logbook_pink_slip_lore"] = "Termination papers belonging to a bank employee. Apparently he lost his job after the clowns' last visit. Motivates effectively."

	-- OVERKILL RUSH
	local ok_extra  = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_extra_bonus   or 0.01
	local ok_stacks = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_max_stacks    or 4
	local ok_dur    = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_duration      or 4.0
	strings["csr_logbook_overkill_rush_name"] = "OVERKILL RUSH"
	strings["csr_logbook_overkill_rush_effect"] = string.format(
		"On kill: gain a kill stack (+%g%% fire rate & reload speed per stack, +%g%% per additional item).\nMax %d kill stacks. All stacks expire %gs after the last kill.",
		ok_extra * 2 * 100, ok_extra * 100, ok_stacks, ok_dur)
	strings["csr_logbook_overkill_rush_lore"] = "A syringe full of stolen adrenaline. The more enemies fall, the faster you move."

	-- PIECE OF REBAR
	local rb_base  = C.rebar_base_bonus  or 0.20
	local rb_extra = C.rebar_extra_bonus or 0.10
	strings["csr_logbook_rebar_name"] = "PIECE OF REBAR"
	strings["csr_logbook_rebar_effect"] = string.format("First hit on an enemy deals +%g%% bonus damage (+%g%% per stack).\nWorks with all damage sources: bullets, melee, fire, gas, explosions.", rb_base * 100, rb_extra * 100)
	strings["csr_logbook_rebar_lore"] = "A bent piece of rebar found on a construction site. Heavy enough to mean business, rusty enough to leave an impression."

	-- JIRO'S LAST WISH
	local jiro_dmg_bonus = C.jiro_melee_bonus or 0.50
	strings["csr_logbook_jiro_last_wish_name"] = "JIRO'S LAST WISH"
	strings["csr_logbook_jiro_last_wish_effect"] = string.format("Grants an ability to sprint while charging a melee attack. Increases melee damage by %d%% (+%d%% per stack, linear).", jiro_dmg_bonus * 100, jiro_dmg_bonus * 100)
	strings["csr_logbook_jiro_last_wish_lore"] = "A letter Jiro wrote for his son Kento but never sent. No one knows what's written inside."

	-- DEAREST POSSESSION
	strings["csr_logbook_dearest_possession_name"] = "DEAREST POSSESSION"
	strings["csr_logbook_dearest_possession_effect"] = "Healing received at full HP is converted into temporary shields. Shield cap: 50% of maximum health (+50% per stack, linear). Shields decay at 20% per second."
	strings["csr_logbook_dearest_possession_lore"] = "A silver locket Dallas keeps close. Inside, where a photo should be, there's a small medkit. He says it's just practical."

	loc:add_localized_strings(strings)
	log("[CSR Alpha1 LOC] Локализация добавлена (язык: english)")
end)

-- Counts active modifier stacks matching the given id prefix
local function count_modifier_stacks(id_prefix)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end

	local count = 0
	local active_modifiers = managers.crime_spree:active_modifiers() or {}
	for _, mod_data in ipairs(active_modifiers) do
		if mod_data.id and string.find(mod_data.id, id_prefix, 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Call counter used to show Total only on the first modifier entry
local call_counter = {}
local last_call_time = {}

-- Hook text() to dynamically append Total and handle context-specific localization
local original_text = LocalizationManager.text
function LocalizationManager:text(string_id, macros)
	if not string_id or type(string_id) ~= "string" then return original_text(self, string_id, macros) end

	local current_time = os.clock()
	local lang = get_current_language()

	-- SPECIAL CASE: Less Concealment - bypass vanilla system entirely
	-- to avoid the $value substitution problem
	if string_id == "menu_cs_modifier_less_concealment" then
		-- Base text without Total
		local base_text = "Stand Out\nDetection risk is increased by 3"

		-- Show Total ONLY in the view menu (CSR_FilterForUI = true), NOT in the selection popup
		if CSR_FilterForUI then
			local total_stacks = count_modifier_stacks("csr_less_concealment")

			if total_stacks >= 1 then
				-- Reset counter if more than 0.5s has passed (new menu open)
				if last_call_time[string_id] and (current_time - last_call_time[string_id]) > 0.5 then
					call_counter[string_id] = 0
				end
				last_call_time[string_id] = current_time

				-- Increment counter
				call_counter[string_id] = (call_counter[string_id] or 0) + 1

				-- Show Total only on the first (top) modifier entry
				if call_counter[string_id] == 1 then
					local total_concealment = total_stacks * 3
					base_text = base_text .. " (Total: +" .. total_concealment .. " detection risk)"
				end
			end
		end

		return base_text
	end

	-- SPECIAL CASE: Heavy Sniper - vanilla string has no name, force-inject it
	if string.find(string_id, "heavy_sniper", 1, true) then
		return "ZEAL Heavy SWAT Marksman\nFor every Heavy SWAT that spawns, there is a chance that it will be replaced by a ZEAL Heavy SWAT Marksman"
	end

	-- All other keys - standard processing
	local result = original_text(self, string_id, macros)

	-- Replace "STARTING LEVEL" with "STARTING DIFFICULTY" everywhere
	if result and type(result) == "string" then
		if string.find(result, "STARTING LEVEL") then
			local new_text = "STARTING DIFFICULTY"
			result = string.gsub(result, "STARTING LEVEL:?", new_text .. ":")
		end
	end

	-- Show Total ONLY in the view menu (CSR_FilterForUI = true), NOT in the selection popup
	if CSR_FilterForUI then
		-- DOG TAGS - show Total for health
		if string_id == "menu_cs_modifier_player_health" then
			local stacks = count_modifier_stacks("player_health_boost")
			if stacks > 1 then
				-- Reset counter if more than 0.5s has passed (new menu open)
				if last_call_time[string_id] and (current_time - last_call_time[string_id]) > 0.5 then
					call_counter[string_id] = 0
				end
				last_call_time[string_id] = current_time

				-- Increment counter
				call_counter[string_id] = (call_counter[string_id] or 0) + 1

				-- Show Total only on the first (top) modifier entry
				if call_counter[string_id] == 1 then
					local total_percent = stacks * 10
					result = result .. " (Total: +" .. total_percent .. "% health)"
				end
			end
		end

		-- EVIDENCE ROUNDS - show Total for damage
		if string_id == "menu_cs_modifier_player_damage" then
			local stacks = count_modifier_stacks("player_damage_boost")
			if stacks > 1 then
				-- Reset counter if more than 0.5s has passed
				if last_call_time[string_id] and (current_time - last_call_time[string_id]) > 0.5 then
					call_counter[string_id] = 0
				end
				last_call_time[string_id] = current_time

				-- Increment counter
				call_counter[string_id] = (call_counter[string_id] or 0) + 1

				-- Show Total only on the first (top) modifier entry
				if call_counter[string_id] == 1 then
					local total_percent = stacks * 10
					result = result .. " (Total: +" .. total_percent .. "% damage)"
				end
			end
		end
	end

	return result
end

log("[CSR Alpha1 LOC] Хук установлен!")
