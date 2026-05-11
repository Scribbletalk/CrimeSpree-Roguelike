-- Crime Spree Roguelike Alpha 1 - Localization with colors

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("[CSR Alpha1 LOC] localization hook loading")

-- Rarity colors (hex)
local COLORS = {
	common = "ffffff", -- white
	uncommon = "00ff00", -- green
	rare = "0099ff", -- blue
	contraband = "ff6600", -- orange (trade-off items)
	wildcard = "ff4dcc", -- magenta (own-bucket, carry-1)
	legendary = "ffd700", -- gold
}

-- Item data (player buffs) - English
local ITEMS_EN = {
	["menu_cs_modifier_player_health"] = {
		name = "DOG TAGS",
		desc = "Increases your max health.",
		rarity = "common",
	},
	["menu_cs_modifier_player_damage"] = {
		name = "EVIDENCE ROUNDS",
		desc = "All your attacks deal more damage.",
		rarity = "uncommon",
	},
	["csr_dozer_guide_desc"] = {
		name = "DOZER GUIDE",
		desc = "Greatly increases your armor.\nBut slows you down and reduces dodge.",
		rarity = "contraband",
	},
	["csr_bonnie_chip_desc"] = {
		name = "BONNIE'S LUCKY CHIP",
		desc = "Each hit has a small chance to instantly kill the target.",
		rarity = "rare", -- Blue color (PAYDAY 2 blue)
	},
	["csr_glass_cannon_desc"] = {
		name = "GLASS PISTOL",
		desc = "Massively increases all damage.\nBut halves your maximum health and armor.",
		rarity = "contraband",
	},
	["csr_car_keys_desc"] = {
		name = "FALCOGINI KEYS",
		desc = "Gives you a chance to dodge incoming damage.",
		rarity = "uncommon",
	},
	["csr_plush_shark_desc"] = {
		name = "PLUSH SHARK",
		desc = "Saves you from custody once per life,\nrestores 1 down, full health and armor,\nthen grants brief invulnerability.",
		rarity = "rare",
	},
	["csr_wolfs_toolbox_desc"] = {
		name = "WOLF'S TOOLBOX",
		desc = "Killing enemies reduces the timer\non active drills and saws.",
		rarity = "uncommon",
	},
	["menu_cs_modifier_duct_tape"] = {
		name = "DUCT TAPE",
		desc = "Makes you faster at interacting with objects.",
		rarity = "common",
	},
	["csr_escape_plan_desc"] = {
		name = "ESCAPE PLAN",
		desc = "Increases your movement speed.",
		rarity = "common",
	},
	["csr_worn_bandaid_desc"] = {
		name = "WORN BAND-AID",
		desc = "Slowly regenerates a small amount of health over time.",
		rarity = "common",
	},
	["csr_cup_of_joe_desc"] = {
		name = "CUP OF JOE",
		desc = "Increases your maximum stamina.",
		rarity = "common",
	},
	["csr_piece_of_rebar_desc"] = {
		name = "PIECE OF REBAR",
		desc = "Your first hit on an enemy deals bonus damage.",
		rarity = "common",
	},
	["csr_jiro_last_wish_desc"] = {
		name = "JIRO'S LAST WISH",
		desc = "Sprint while charging a melee attack. Increases melee damage.",
		rarity = "rare",
	},
	["csr_dearest_possession_desc"] = {
		name = "DEAREST POSSESSION",
		desc = "Healing at full HP converts to temporary shields that quickly fade away.",
		rarity = "rare",
	},
	["csr_viklund_vinyl_desc"] = {
		name = "VIKLUND'S VINYL",
		desc = "...and his beats were electric.",
		rarity = "rare",
	},
	["csr_lockes_beret_desc"] = {
		name = "LOCKE'S BERET",
		desc = "Periodically heals everyone in your team.",
		rarity = "rare",
	},
	["csr_equalizer_desc"] = {
		name = "EQUALIZER",
		desc = "Greatly increases damage against special enemies.\nBut reduces it against regular ones.",
		rarity = "contraband",
	},
	["csr_crooked_badge_desc"] = {
		name = "CROOKED BADGE",
		desc = "Chance to restore a down after each assault.\nBut your bleedout timer is reduced.",
		rarity = "contraband",
	},
	["csr_dead_mans_trigger_desc"] = {
		name = "DEAD MAN'S TRIGGER",
		desc = "Going down triggers an explosion around you.\nBut allies also receive damage from it.",
		rarity = "contraband",
	},
	["csr_scrap_common_desc"] = {
		name = "COMMON SCRAP",
		desc = "Does nothing. Prioritized when used with Printers.",
		rarity = "common",
	},
	["csr_scrap_uncommon_desc"] = {
		name = "UNCOMMON SCRAP",
		desc = "Does nothing. Prioritized when used with Printers.",
		rarity = "uncommon",
	},
	["csr_scrap_rare_desc"] = {
		name = "RARE SCRAP",
		desc = "Does nothing. Prioritized when used with Printers.",
		rarity = "rare",
	},
	["csr_half_a_glass_desc"] = {
		name = "HALF-A-GLASS",
		desc = "Gage packages restore some ammo and raise your max ammo.",
		rarity = "common",
	},
	["csr_overkill_rush_desc"] = {
		name = "OVERKILL RUSH",
		desc = "Killing enemies temporarily increases fire rate and reload speed.",
		rarity = "uncommon",
	},
	["csr_pink_slip_desc"] = {
		name = "PINK SLIP",
		desc = "Killing an enemy restores health.",
		rarity = "uncommon",
	},
	["csr_the_edge_desc"] = {
		name = "THE EDGE",
		desc = "When critically low on health,\nrestores health and grants brief invulnerability.",
		rarity = "uncommon",
	},
	["csr_familiar_friend_desc"] = {
		name = "FAMILIAR FRIEND",
		desc = "Release spike nova around you.",
		rarity = "wildcard",
	},
	["csr_side_satchel_desc"] = {
		name = "SIDE SATCHEL",
		desc = "Doubles the carry amount of mission equipment.",
		rarity = "wildcard",
	},
	["csr_turron_desc"] = {
		name = "TURRON",
		desc = "Heals you and reduces incoming damage for few seconds.",
		rarity = "wildcard",
	},
	["csr_hippocratic_oath_desc"] = {
		name = "HIPPOCRATIC OATH",
		desc = "A medic joins your crew in loud and heals you when nearby.",
		rarity = "wildcard",
	},
	-- Dummy modifiers (should not appear in popup, but need localization just in case)
	["csr_base_modifier"] = {
		name = "",
		desc = "",
		rarity = "common",
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
		rarity = "forced",
	},
	-- Unlock modifiers
	["csr_enable_bulldozers_desc"] = {
		name = "YOU'RE UP AGAINST THE WALL AND I AM THE FUCKING WALL!",
		desc = "Bulldozers can now spawn on missions",
		rarity = "unlock",
	},
	["csr_enable_medics_desc"] = {
		name = "Don't worry, I'm here! And I brought drugs!",
		desc = "Medics can now spawn on missions",
		rarity = "unlock",
	},
	["csr_enable_tasers_desc"] = {
		name = "I'm the fucking SPARK MAN!",
		desc = "Tasers can now spawn on missions",
		rarity = "unlock",
	},
	["csr_enable_cloakers_desc"] = {
		name = "You call this resisting arrest? We call this a difficulty tweak!",
		desc = "Cloakers can now spawn on missions",
		rarity = "unlock",
	},
}

-- Overridden vanilla modifiers - English
local VANILLA_OVERRIDES_EN = {
	-- Loud modifiers
	["menu_cs_modifier_cloaker_tear_gas"] = "Stinkbug\nKilled Cloakers leave behind a toxic cloud that drains 5% of your max health every second.",
	["menu_cs_modifier_taser_overcharge"] = "Rapid Shock\nThe tasing knockout effect of the Taser now knocks a player out 50% faster",
	["menu_cs_modifier_dozer_rage"] = "No Faceplate, No Mercy\nWhen a Bulldozer's faceplate is destroyed, the Bulldozer enters a berserker rage, receiving a 100% increase to their base damage output",
	["menu_cs_modifier_more_dozers"] = "Heavy Reinforcement\nTwo additional Bulldozers are allowed into the level",
	["menu_cs_modifier_more_medics"] = "Field Hospital\nTwo additional Medics are allowed into the level",
	["menu_cs_modifier_heal_speed"] = "Autodidact\nMedic heal cooldown is 20% faster",
	["menu_cs_modifier_assault_extender"] = "Extended Assault\nPolice assaults will have a 40% longer duration. This gets reduced by 5% for every hostage and converted cop, up to a maximum of 4",
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
	["menu_cs_modifier_less_concealment"] = "Stand Out\nDetection risk is increased by 3 (Stealth Only)",
	-- Add missing loud modifiers
	["menu_cs_modifier_no_hurt_anims"] = "Pain Tolerance\nEnemies have an 80% chance to resist stagger",
	["menu_cs_modifier_no_hurt"] = "Pain Tolerance\nEnemies have an 80% chance to resist stagger",
	["menu_cs_modifier_heavies"] = "Heavy Response\nAll FBI SWATs will be replaced with Heavy SWATs",
	["menu_cs_modifier_skulldozers"] = "Skulldozers\nSkulldozers can now appear alongside regular Bulldozers",
	["menu_cs_modifier_dozer_minigun"] = "Minigun Dozers\nWhenever a Bulldozer spawns, there is a chance that it will be a slow-moving minigun-wielding Bulldozer",
	["menu_cs_modifier_dozer_medic"] = "Medic Bulldozers\nWhenever a Bulldozer spawns, there is a chance that it will be a Medic Bulldozer",
	["menu_cs_modifier_shield_reflect"] = "Reflective Shields\nShields will reflect projectiles",
	["menu_cs_modifier_cloaker_smoke"] = "Smoke Bomb\nCloakers will drop a smokebomb when they kick a player",
	["menu_cs_modifier_heavy_sniper"] = "Marshal Reinforcements\nTwo additional US Marshal Marksmen are allowed into the level",
	["menu_cs_modifier_medic_adrenaline"] = "Combat Stimulant\nWhenever a Medic revives another cop, the revived cop gets a 100% increase to their base damage output",
	["menu_cs_modifier_shield_phalanx"] = "Phalanx Formation\nAll Shield units in the game are replaced by Captain Winters' Shield units",
	["menu_cs_modifier_medic_deathwish"] = "Final Dose\nWhenever a Medic is killed, all cops within the Medic's healing range are instantly healed",
	["menu_cs_modifier_explosion_immunity"] = "Blast Plating\nBulldozers take 50% reduced explosive damage",
	["menu_cs_modifier_cloaker_arrest"] = "\"You call this 'resisting' arrest?\"\nCloakers executing a successful charge now cuffs the player instead of downing them",
	["menu_cs_modifier_medic_rage"] = "Overdose\nFor every cop that dies within a Medic's healing range, that Medic sees his base damage output increased by 20%. This effect stacks indefinitely",
	["menu_cs_modifier_civilian_guilt"] = "Guilty Conscience\nEach civilian killed permanently reduces your max health by 5% for this mission, up to 30% total.",
	["menu_cs_modifier_shocking_surprise"] = "Shocking Surprise\nTasers release an electric burst on death, slowing nearby players and preventing sprint for 3 seconds",
	-- Enable modifiers (unlock enemy spawns on low difficulties)
	["menu_cs_modifier_enable_bulldozers"] = "YOU'RE UP AGAINST THE WALL AND I AM THE FUCKING WALL!\nBulldozers can now spawn on this difficulty",
	["menu_cs_modifier_enable_medics"] = "Don't worry, I'm here! And I brought drugs!\nMedics can now spawn on this difficulty",
	["menu_cs_modifier_enable_tasers"] = "I'm the fucking SPARK MAN!\nTasers can now spawn on this difficulty",
	["menu_cs_modifier_enable_cloakers"] = "You call this resisting arrest? We call this a difficulty tweak!\nCloakers can now spawn on this difficulty",
	-- Multiplayer
	["csr_mp_synced"] = "Synced with host",
	["csr_mp_host_picked"] = "Host picked",
	["csr_mp_lobby_blocked"] = "This lobby doesn't have CrimeSpree Roguelike",
	["csr_mp_auto_created"] = "You had no Crime Spree active. One was created for you at %s difficulty so you can earn rewards!",
}

Hooks:Add("LocalizationManagerPostInit", "CSR_Alpha1_Localization", function(loc)
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
	-- Item types generated from centralized registry
	local item_types = {}
	for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
		table.insert(item_types, { prefix = item.id_prefix, base_key = item.loc_key })
	end

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
			CSR_log("[CSR LOC] Generated 200 localization keys for: " .. item_type.prefix)
		end
	end

	-- Vanilla modifiers with fixed text
	for key, text in pairs(VANILLA_OVERRIDES) do
		strings[key] = text
	end

	-- Generate full-ID keys for forced modifiers so the vanilla Modifiers tab can find them.
	-- Vanilla UI looks up "menu_cs_modifier_" .. mod.id directly (e.g. "menu_cs_modifier_csr_civilian_guilt_20").
	-- We map each full ID to its base text using the same stripping logic as forced_mods_notification.
	local forced_mods = tweak_data.crime_spree
			and tweak_data.crime_spree.repeating_modifiers
			and tweak_data.crime_spree.repeating_modifiers.forced
		or {}
	for _, mod in ipairs(forced_mods) do
		if mod.id then
			local clean_id = mod.id:gsub("^csr_", "")
			local is_stealth_tiered = clean_id:find("^less_pagers_") or clean_id:find("^civilian_alarm_")
			local base_id = clean_id
			if not is_stealth_tiered then
				base_id = clean_id:gsub("_(%d+)$", "")
			end
			local base_text = strings["menu_cs_modifier_" .. base_id]
			if base_text then
				strings["menu_cs_modifier_" .. mod.id] = base_text
			end
		end
	end

	-- Items tab label
	strings["menu_csr_items"] = "ITEMS"
	strings["menu_csr_items_placeholder"] = "Collected items will show up here."

	-- Gage's Services tab (hosts Shop + Printer sub-tabs)
	strings["menu_csr_gage_services"] = "GAGE'S SERVICES"
	strings["csr_gage_services_title"] = "GAGE'S SERVICES"
	strings["csr_gage_services_tab_shop"] = "SHOP"
	strings["csr_gage_services_tokens_label"] = "Tokens: "
	strings["csr_gage_services_reroll"] = "Reroll"
	strings["csr_gage_services_buy"] = "Buy"
	strings["csr_gage_services_sold"] = "SOLD"
	strings["csr_gage_services_owned_x"] = "x $count owned"
	strings["csr_gage_services_cant_afford"] = "Insufficient tokens"

	-- Gage dialogue lines. Greetings re-roll only on heist completion (one
	-- greeting per heist, persists across menu open/close). Reroll/purchase
	-- lines re-roll on each action. Counts must match GAGE_*_COUNT in
	-- csr_shop_manager.lua.
	strings["csr_gage_line_greeting_1"] = "Hello, stranger."
	strings["csr_gage_line_greeting_2"] = "'What are you buying?' Heh, always wanted to say that."
	strings["csr_gage_line_greeting_3"] = "Back so soon? Let's see what I've got."
	strings["csr_gage_line_greeting_4"] = "Pull up a crate, friend."
	strings["csr_gage_line_greeting_5"] = "Take your time. I'm not going anywhere."
	strings["csr_gage_line_greeting_6"] = "Ah, you're back."
	strings["csr_gage_line_greeting_7"] = "Were you being followed? I hope not..."
	strings["csr_gage_line_greeting_8"] = "Heard you've been busy out there."
	strings["csr_gage_line_greeting_9"] = "Lamp oil, rope, bombs... Oh, wait, nevermind."
	strings["csr_gage_line_greeting_10"] =
		"I had a dream where I saw some strange blue creature with a tremoring hand... How long have you been standing there?"
	strings["csr_gage_line_greeting_11"] = "Hello, valued customer... Welcome to my shop! Please buy something!"
	strings["csr_gage_line_greeting_12"] = "Konnichiwasup...! Don't ask why I said that..."
	strings["csr_gage_line_reroll_1"] = "Don't like 'em? Let me check the back."
	strings["csr_gage_line_reroll_2"] = "Picky one, eh? Try these."
	strings["csr_gage_line_reroll_3"] = "Fresh batch, coming up."
	strings["csr_gage_line_reroll_4"] = "Take another look."
	strings["csr_gage_line_reroll_5"] = "No? Ok."
	strings["csr_gage_line_reroll_6"] = "More where that came from."
	strings["csr_gage_line_purchase_1"] = "Pleasure doing business."
	strings["csr_gage_line_purchase_2"] = "Good choice. Use it well."
	strings["csr_gage_line_purchase_3"] = "Don't lose it out there."
	strings["csr_gage_line_purchase_4"] = "Sold."
	strings["csr_gage_line_purchase_5"] = "Another satisfied customer."

	-- Printer tab labels
	strings["menu_csr_printer"] = "PRINTER"
	strings["menu_csr_printer_new"] = "PRINTER " .. utf8.char(0xE012)
	strings["csr_printer_empty"] = "No printer available.\nComplete a mission for a chance to find one."
	strings["csr_waiting_for_selections"] = "Waiting for players to select items... (%ds)"

	-- Printer interaction prompt (native PD2 Hold-to-Use).
	-- $BTN_INTERACT is a vanilla macro populated by BaseInteractionExt:_add_string_macros;
	-- it renders as the player's currently-bound interact key glyph (e.g. "[F]").
	-- The HUD uppercases the whole prompt, so the final on-screen text reads
	-- "HOLD [F] TO USE PRINTER".
	strings["csr_interact_copier"] = "Hold $BTN_INTERACT to use printer"
	strings["csr_interact_copier_action"] = "USING PRINTER"
	strings["csr_copier_no_item"] = "No matching-tier item to exchange"

	-- Scrapper interaction prompt + item-pick dialog
	strings["csr_interact_scrapper"] = "Hold $BTN_INTERACT to use scrapper"
	strings["csr_interact_scrapper_action"] = "USING SCRAPPER"
	strings["csr_scrapper_no_items"] = "No items to scrap"
	strings["csr_scrapper_pick_title"] = "Scrapper"
	strings["csr_scrapper_pick_text"] = "Pick an item to turn into scrap."
	strings["csr_scrapper_cancel"] = "Cancel"
	strings["csr_scrapper_cancel_hint"] = "Movement keys or click outside window to close."

	-- Printer penalty threshold messages (shown as red chat, local player only)
	-- Each key corresponds to a cumulative usage % threshold in the printer mechanic.
	strings["csr_printer_msg_1"] = "Something feels off..."
	strings["csr_printer_msg_15"] = "You feel weaker."
	strings["csr_printer_msg_35"] = "Pain comes easier now."
	strings["csr_printer_msg_50"] = "Your wounds run deeper."
	strings["csr_printer_msg_70"] = "You bleed too easily."
	strings["csr_printer_msg_85"] = "The cost catches up."
	strings["csr_printer_msg_100"] = "You are not gonna stop, aren't you?"

	-- Stats tab label
	strings["menu_csr_stats"] = "STATS"

	-- Override "Select Modifiers" with "Select Item/Items"
	strings["menu_cs_select_modifier"] = "SELECT ITEM"
	strings["menu_cs_select_modifiers"] = "SELECT ITEMS"
	strings["csr_auto_fill_items"] = "AUTO-FILL"
	strings["csr_auto_fill_confirm_title"] = "Auto-Fill Items"
	strings["csr_auto_fill_confirm_text"] =
		"Are you sure you want to auto-fill all remaining item slots with random items? This cannot be undone."
	strings["csr_items_ready"] = "READY"
	strings["csr_waiting_for_others"] = "Waiting for others to select items"
	strings["csr_all_players_ready"] = "All players ready"

	-- Lobby player status (shown below nickname during item selection)
	strings["menu_lobby_menu_state_selecting_item"] = "SELECTING ITEM"

	-- Ready system (MP lobby)
	strings["csr_ready"] = "READY"
	strings["csr_ready_confirmed"] = "READY \xe2\x9c\x93"
	strings["csr_ready_waiting"] = "Waiting"
	strings["csr_ready_starting"] = "Starting in"
	strings["csr_ready_launching"] = "Launching..."

	-- Override "Loud Modifiers" with "Items"
	strings["menu_cs_modifier_loud"] = "ITEMS"
	strings["menu_cs_modifiers_loud"] = "ITEMS"

	-- Override "Next Modifier" labels in Modifiers tab
	strings["menu_cs_next_modifier_in"] = "NEXT ITEM DROP IN"
	strings["menu_cs_next_modifier"] = "NEXT ITEM DROP"
	strings["menu_cs_next_modifier_forced"] = "NEXT MODIFIER: $next \xEE\x80\x98"
	strings["menu_cs_next_modifier_loud"] = "NEXT GUARANTEED ITEM: $next \xEE\x80\x98"
	strings["menu_cs_next_modifier_stealth"] = "NEXT MODIFIER: $next \xEE\x80\x98"

	-- Override "Starting Level" with "Starting Difficulty"
	strings["menu_cs_starting_level"] = "STARTING DIFFICULTY"
	-- Try different possible keys
	strings["menu_cs_starting_level_title"] = "STARTING DIFFICULTY"
	strings["menu_starting_level"] = "STARTING DIFFICULTY"

	-- === LOGBOOK LOCALIZATION ===
	strings["menu_csr_logbook"] = "LOGBOOK"
	strings["menu_csr_logbook_new"] = "LOGBOOK" .. utf8.char(0xE012) .. "  "
	strings["menu_csr_kill_bonus"] = "Kill Bonus"
	strings["menu_csr_cash_bonus"] = "Cash Bonus"
	strings["csr_cash_convert_title"] = "CASH -> RANKS"
	strings["menu_csr_catchup_bonus"] = "Catchup Bonus"
	strings["menu_csr_rank_penalty"] = "Rank Penalty"

	-- Rarities
	strings["csr_logbook_rarity_common"] = "Common"
	strings["csr_logbook_rarity_uncommon"] = "Uncommon"
	strings["csr_logbook_rarity_rare"] = "Rare"
	strings["csr_logbook_rarity_contraband"] = "Contraband"

	local C = _G.CSR_ItemConstants or {}

	-- DOG TAGS
	local dt_hp = C.dog_tags_hp_bonus or 0.10
	strings["csr_logbook_dog_tags_name"] = "DOG TAGS"
	strings["csr_logbook_dog_tags_effect"] =
		string.format("Increases maximum health by {g}%g%%{/} (+%g%% per stack, linear).", dt_hp * 100, dt_hp * 100)
	strings["csr_logbook_dog_tags_notes"] =
		"He always came in first. Before everyone else on shift, before everyone else on scene. We joked that he lived there.\n\nI don't know why I'm writing this. Command already filed their report. Everything's in order - date, circumstances, rank. All by the book.\n\nWhat the report doesn't mention is that he brought coffee for the whole department every Friday. That he remembered the names of every colleague's kids. That when a shift turned quiet he'd pull out a worn paperback and read - always something about history, never said what exactly.\n\nThe tags were never found. They say someone took them off the body.\n\nWhat the hell did they want with his tags. A trophy? A souvenir? I hope they're keeping busy while we're looking for them.\n\nBastards... I'd kill you myself."

	-- DUCT TAPE
	local tape_spd = C.duct_tape_speed_bonus or 0.05
	strings["csr_logbook_duct_tape_name"] = "DUCT TAPE"
	strings["csr_logbook_duct_tape_effect"] = string.format(
		"Increases interaction speed by {g}%g%%{/} (+%g%% per stack, linear).\nAffects lockpicking, bagging loot, repairing, etc. Does {r}not{/} apply to reviving teammates or uncuffing.",
		tape_spd * 100,
		tape_spd * 100
	)
	strings["csr_logbook_duct_tape_notes"] =
		"DUSK TAPE™ - for any situation.\nLeaky pipe? DUSK TAPE™.\nNeed to strap a flashlight to anything? DUSK TAPE™.\nDoor won't close? DUSK TAPE™.\nDrill gave out mid-job? DUSK TAPE™.\nHostages being too loud? DUSK TAPE™.\nDUSK TAPE™ - holds everything. Always. No questions asked.\nAvailable at hardware stores nationwide."

	-- ESCAPE PLAN
	local sn_cap = C.escape_plan_cap or 0.50
	local sn_k = (C.escape_plan_k_num or 3) / (C.escape_plan_k_den or 47)
	local sn_first = math.floor(sn_cap * sn_k / (1 + sn_k) * 100 + 0.5)
	strings["csr_logbook_escape_plan_name"] = "ESCAPE PLAN"
	strings["csr_logbook_escape_plan_effect"] =
		string.format("Increases movement speed by {g}%d%%{/} (+%d%% per stack, hyperbolic).", sn_first, sn_first)
	strings["csr_logbook_escape_plan_notes"] =
		"March 3rd. Started today. Under the bed, in the corner - there's a tile that's been cracked for ages, nobody notices. Smuggled the shovel in pieces. Spent a long time figuring out how - turned out easier than I thought. The guards here are dumb.\n\nMarch 19th. Almost a meter deep. Hands are blistered. I hide the dirt in my mattress, then flush it down the toilet.\nSlow, but it's working.\n\nApril 2nd. Three meters. By my calculations - same distance again and I'll be past the outer wall. I counted the steps when they took us out for exercise.\n\nApril 14th. Five meters. Soon.\n\nApril 21st. Dug through the night. The soil felt softer. Just a little more.\n\nApril 22nd. Came up in cell №108.\n\nGarcia was asleep there.\n\nHe didn't even seem surprised. Just looked at me and said - \"wrong way.\"\n\nI know, Garcia. I know."

	-- WORN BAND-AID
	local ba_first = (C.worn_bandaid_first_pct or 0.01) * 100
	local ba_max = (C.worn_bandaid_max_pct or 0.20) * 100
	local ba_int = C.worn_bandaid_interval or 5
	strings["csr_logbook_worn_bandaid_name"] = "WORN BAND-AID"
	strings["csr_logbook_worn_bandaid_effect"] = string.format(
		"Regenerates {g}%g%%{/} (+%g%% per stack, hyperbolic, capped at %g%%) of max health every %g seconds.",
		ba_first,
		ba_first,
		ba_max,
		ba_int
	)
	strings["csr_logbook_worn_bandaid_notes"] =
		'"You\'ll be fine, buddy. I\'ve got you." - said the medic with a warm smile as he bandaged my gunshot wound.\n"Hey, doc. Why do you keep reusing band-aids? Isn\'t that against hygiene rules?" - I winced.\n"Why? Do you have any idea how many band-aids it takes to patch someone up? You think one? Two? It takes dozens. Sometimes hundreds."\nI looked around and only now noticed the shelves were packed with band-aids. "Looks like I\'m leaving here as a band-aid mummy," I thought to myself, and just kept enduring.'

	-- LOCKE'S BERET
	local beret_first = (C.lockes_beret_first_pct or 0.10) * 100
	local beret_max = (C.lockes_beret_max_pct or 0.50) * 100
	local beret_interval = C.lockes_beret_interval or 30
	strings["csr_logbook_lockes_beret_name"] = "LOCKE'S BERET"
	strings["csr_logbook_lockes_beret_effect"] = string.format(
		"Every {g}%g{/} seconds, heals everyone on your team (you, teammates, bots, jokers, turrets) for {g}%g%%{/} (+%g%% per stack, hyperbolic, capped at %g%%) of max health.",
		beret_interval,
		beret_first,
		beret_first,
		beret_max
	)
	strings["csr_logbook_lockes_beret_notes"] =
		'- "The Major\'s got fourteen of them. I counted."\n- "Fourteen berets?"\n- "Yeah. All identical. Lined up in his quarters."\n- "Damn..."\n- "Oh, and he also got one dress shirt that\'s still in dry-cleaning bag. Receipt said 2009..."\n- "..."\n- "Reyes saw him at an airport once. Off-duty."\n- "And?"\n- "Full kit. Beret and all. Said he looked completely normal about it."\n- *Footsteps in the corridor.*\n- "Morning, sir." / "Morning, sir."\n- "Aye, friends."\n- *Footsteps recede.*\n- "Fifteen. I miscounted."'

	-- CUP OF JOE
	local coj_per_stack = (C.cup_of_joe_per_stack or 0.10) * 100
	strings["csr_logbook_cup_of_joe_name"] = "CUP OF JOE"
	strings["csr_logbook_cup_of_joe_effect"] = string.format(
		"Increases maximum stamina by {g}%g%%{/} (+%g%% per stack, linear).",
		coj_per_stack,
		coj_per_stack
	)
	strings["csr_logbook_cup_of_joe_notes"] =
		"- Total stolen: 1 artifact, 3 assault rifles, a set of samurai armor, a server... and a cup of Joe.\n- Sorry, a cup of Joe?\n- A cup of Joe.\n- ...\n- So where's Joe, exactly?\n- Not funny.\n- No, seriously. Where's Joe?\n- Oh, that Joe. He's right over there. Crying about his favorite mug being stolen."

	-- PIECE OF REBAR
	local rb_base = C.rebar_base_bonus or 0.15
	local rb_extra = C.rebar_extra_bonus or 0.10
	strings["csr_logbook_rebar_name"] = "PIECE OF REBAR"
	strings["csr_logbook_rebar_effect"] = string.format(
		"First hit on an enemy deals {g}+%g%%{/} (+%g%% per stack, linear) damage.",
		rb_base * 100,
		rb_extra * 100
	)
	strings["csr_logbook_rebar_notes"] =
		'INCIDENT REPORT\nCase No. 2014-7732-CR\nDate: October 27, 2014\nFiled by: Detective S. Morris, Violent Crimes Division\n\nAt approximately 2:00 PM, a directed explosion was recorded in the underground transport corridor of the Federal Courthouse, District of Columbia. The device was planted in the outer concrete wall. The nature of the damage indicates professional placement - destruction strictly contained to the target area. No civilian casualties. Three escort officers were killed on the scene; two others hospitalized in critical condition.\n\nAt the time of the explosion, the convoy was transferring inmate James "Jim" Hoxworth, known as "Hoxton". Hoxworth has since disappeared from the scene.\n\nA fragment of construction rebar, approximately 24 centimeters in length, was recovered in the corridor bearing biological trace evidence. DNA analysis confirmed it belongs to Hoxworth. The nature of contamination suggests a penetrating wound to the lower extremity. The rebar was removed on-site - bandaging materials were also found nearby.\n\n.......................................................................................................................................'

	-- HALF-A-GLASS
	local hg_refill = C.half_a_glass_refill or 0.15
	local hg_first = C.half_a_glass_max_ammo_first or 0.02
	local hg_extra = C.half_a_glass_max_ammo_extra or 0.01
	strings["csr_logbook_half_a_glass_name"] = "HALF-A-GLASS"
	strings["csr_logbook_half_a_glass_effect"] = string.format(
		"Picking up a Gage package instantly refills {g}%g%%{/} ammo for primary and secondary weapons and increases their max ammo by {g}%g%%{/} (+%g%% per stack, linear) for the rest of the mission.",
		hg_refill * 100,
		hg_first * 100,
		hg_extra * 100
	)
	strings["csr_logbook_half_a_glass_notes"] =
		"His hands reached for the magnifying glass. A malicious grin looked right through me, consuming what little humanity I had left. \"Interesting...\" - the demonic voice echoed toward me. So this is how it ends? My worthless life finally coming to a close? All because of my own stupid decisions. No-no-no. I can't... I can't give up now... I won't-!\n\nA shot rings out."

	-- EVIDENCE ROUNDS
	local ap_dmg = C.ap_rounds_damage_bonus or 0.05
	strings["csr_logbook_evidence_rounds_name"] = "EVIDENCE ROUNDS"
	strings["csr_logbook_evidence_rounds_effect"] = string.format(
		"Increases damage from ALL sources by {g}%g%%{/} (+%g%% per stack, linear).",
		ap_dmg * 100,
		ap_dmg * 100
	)
	strings["csr_logbook_evidence_rounds_notes"] =
		"INTERNAL MEMORANDUM\nTo: Evidence Storage Supervisor, Unit 4\nFrom: Detective R. Hughes\nRe: Missing evidence\n\nDuring a routine inspection, a shortage was found in box №14 (section D):\n- Non-standard ammunition, $rounds round(s) (case PD-2014-11847)\n\nNo signs of forced entry. Last access - Sergeant P. Tucker, February 12th.\nTucker retired February 14th.\n\nPlease initiate an internal investigation."

	-- FALCOGINI KEYS
	local keys_first = math.floor(100 / (1 + (C.car_keys_k_den or 32)) + 0.5)
	strings["csr_logbook_falcogini_keys_name"] = "FALCOGINI KEYS"
	strings["csr_logbook_falcogini_keys_effect"] = string.format(
		"Increases chance to dodge by {g}%d%%{/} (+%d%% per stack, hyperbolic).\nSuccessful dodging blocks incoming damage (does not work on self-inflicted damage).",
		keys_first,
		keys_first
	)
	strings["csr_logbook_falcogini_keys_notes"] =
		"LOST\nLost a set of Falcogini F40 keys near Fourth Avenue. Red keychain, chip key with logo. Please return - the car is the only thing I have left of my father.\nReward: $500\nTel: (555) 013-0124"

	-- WOLF'S TOOLBOX
	local wt_norm_base = C.wolfs_toolbox_normal_base or 0.2
	local wt_norm_extra = C.wolfs_toolbox_normal_extra or 0.1
	local wt_spec_base = C.wolfs_toolbox_special_base or 1.0
	local wt_spec_extra = C.wolfs_toolbox_special_extra or 0.5
	strings["csr_logbook_wolfs_toolbox_name"] = "WOLF'S TOOLBOX"
	strings["csr_logbook_wolfs_toolbox_effect"] = string.format(
		"Killing regular enemies reduces active drill/saw timer by {g}%g second(s){/} (+%gs per stack, linear).\nKilling special enemies reduces timer by {g}%g second(s){/} (+%gs per stack, linear).",
		wt_norm_base,
		wt_norm_extra,
		wt_spec_base,
		wt_spec_extra
	)
	strings["csr_logbook_wolfs_toolbox_notes"] =
		"Dear representatives of Eisen Brechmann Tools,\nI am writing to inform you that your products are absolute garbage.\nThe drill I purchased in 2013 (model EB-7700X) has broken down SEVENTEEN TIMES over the past eight months.\nEvery time at the worst possible moment. Every. Single. Time.\nI demand either a full refund or a replacement with something that is actually capable of functioning properly.\nWith no regards,\nW."

	-- PINK SLIP
	local ps_pct = (C.pink_slip_base_percent or 0.01) * 100
	local ps_base_flat = C.pink_slip_base_flat or 4
	local ps_heal_extra = C.pink_slip_extra_heal or 6
	strings["csr_logbook_pink_slip_name"] = "PINK SLIP"
	strings["csr_logbook_pink_slip_effect"] = string.format(
		"Killing any enemy restores {g}%g%%{/} of max health + {g}%g{/} (+%g per stack, linear) health.",
		ps_pct,
		ps_base_flat,
		ps_heal_extra
	)
	strings["csr_logbook_pink_slip_notes"] =
		"You should've seen his face when he came to me! \"Robbers in clown masks threatened me!\" Ha-ha-ha! What an idiot! Serves him right for getting fired.\nInaudible muttering.\nRight... Him? Bob Bubblehead or something? What a stupid last name... No-no, I'm not talking to you!\nInaudible muttering.\nOf course. I want this partnership just as much as you do, Mr. Garnet."

	-- THE EDGE
	local te_threshold = (C.the_edge_hp_threshold or 0.10) * 100
	local te_pct = (C.the_edge_heal_pct or 0.20) * 100
	local te_flat = C.the_edge_heal_flat or 20
	local te_extra = C.the_edge_heal_flat_extra or 40
	local te_invuln = C.the_edge_invuln or 0.5
	local te_cd = C.the_edge_cooldown or 60
	strings["csr_logbook_the_edge_name"] = "THE EDGE"
	strings["csr_logbook_the_edge_effect"] = string.format(
		"When health drops below {r}%.0f%%{/}, restores {g}%.0f%%{/} max health + {g}%g{/} (+%g per stack) and grants {g}%.1fs{/} invulnerability.\n%gs cooldown.",
		te_threshold,
		te_pct,
		te_flat,
		te_extra,
		te_invuln,
		te_cd
	)
	strings["csr_logbook_the_edge_notes"] =
		'"I wish this prick would just shoot himself." - the last thought spinning in my head. It felt like this nightmare would never end. "If I\'m going to die, at least let it be with a clear conscience and rotten lungs."\n\nClick.\n\nMy turn now...'

	-- OVERKILL RUSH
	local ok_first = C.overkill_rush_first_bonus or 0.02
	local ok_extra = C.overkill_rush_extra_bonus or 0.01
	local ok_stacks = C.overkill_rush_max_stacks or 4
	local ok_dur = C.overkill_rush_duration or 4.0
	strings["csr_logbook_overkill_rush_name"] = "OVERKILL RUSH"
	strings["csr_logbook_overkill_rush_effect"] = string.format(
		"Killing any enemy grants you a rush stack. For each rush stack your fire rate and reload speed increase by {g}%g%%{/} (+%g%% per stack, linear).\nAll rush stacks expire %g seconds after the last kill.",
		ok_first * 100,
		ok_extra * 100,
		ok_dur
	)
	strings["csr_logbook_overkill_rush_notes"] =
		"I'm alive...? How? Right... This isn't just a game anymore... It feels like punishment for my sins. What am I saying? This is a nightmare. There's no way out. What are my options... Not many... Adrenaline. Yeah, that'll help. I'll take his... Beer. Yeah, I could really go for a beer right now... No! What is wrong with me? What the hell do I want with beer?! Huh? A phone... Yeah, I'll call the police. And... Or... I don't know! God help me!"

	-- BONNIE'S LUCKY CHIP
	local bc_chance = C.bonnie_chip_chance or 0.10
	local bc_cd = C.bonnie_chip_cooldown or 1.5
	strings["csr_logbook_bonnie_chip_name"] = "BONNIE'S LUCKY CHIP"
	strings["csr_logbook_bonnie_chip_effect"] = string.format(
		"Gain {g}%g%%{/} (+%g%% per stack, hyperbolic) chance to instantly kill an enemy on hit.\nHas %g second cooldown.",
		bc_chance * 100,
		bc_chance * 100,
		bc_cd
	)
	strings["csr_logbook_bonnie_chip_notes"] =
		"Bonnie isn't someone you can easily catch off guard. Poker and gambling in general isn't a simple game where you either win everything or lose it all before you can blink. At least that's what Bonnie thinks. In her words, poker is a \"slow psychological duel.\" Sure, luck plays its part. But you always have to keep your cool, arm yourself with patience, never let your emotions show... Or just shoot your opponents. Works 100% of the time. (Cases where they shoot back are not counted.)"

	-- PLUSH SHARK
	local ps_heal_pct = C.plush_shark_heal_pct or 1.00
	local ps_inv_base = C.plush_shark_invuln_base or 10
	local ps_inv_extra = C.plush_shark_invuln_extra or 20
	strings["csr_logbook_plush_shark_name"] = "PLUSH SHARK"
	strings["csr_logbook_plush_shark_effect"] = string.format(
		"When have only down and your health reaches 0, this item ictivates.\nOn activation restores {g}1 down{/}, {g}%g%%{/} maximum {g}health{/} and {g}armor{/}, then grants invulnerability that lasts {g}%g seconds{/} (+%gs per stack, linear).\nCan be activated again if you were freed from custody.",
		ps_heal_pct * 100,
		ps_inv_base,
		ps_inv_extra
	)
	strings["csr_logbook_plush_shark_notes"] =
		"This is Gura. She's always with me - on a job, after a job, everywhere. My irreplaceable friend and partner.\nRust tried to throw her out once, but I quickly reminded him that I'm not someone to mess with. He hasn't bothered me since. Smart of him.\nGura has pulled me out of some serious shit that I can't even begin to explain. Some kind of magic or whatever. (Not that I actually believe in that stuff.)"

	-- JIRO'S LAST WISH
	local jiro_dmg_bonus = C.jiro_melee_bonus or 0.50
	strings["csr_logbook_jiro_last_wish_name"] = "JIRO'S LAST WISH"
	strings["csr_logbook_jiro_last_wish_effect"] = string.format(
		"Grants an ability to sprint while charging a melee attack. Increases melee damage by {g}%d%%{/} (+%d%% per stack, linear).",
		jiro_dmg_bonus * 100,
		jiro_dmg_bonus * 100
	)
	strings["csr_logbook_jiro_last_wish_notes"] =
		'Jiro wrote this letter when he still lived in Japan. His son was the most precious thing he had left. He only wished to be reunited with him, even if just through a letter.\n\nThe envelope is worn and slightly crumpled. No stamp, no proper address - just "USA".\n\nWhy he never sent it - nobody knows.'

	-- DEAREST POSSESSION
	local dp_cap = C.dearest_armor_cap or 0.5
	local dp_decay = C.dearest_decay_rate or 0.01666
	-- Per-tick drain percentage (5s tick interval is hardcoded in dearestpossession.lua).
	local dp_per_tick_pct = dp_decay * 5 * 100
	strings["csr_logbook_dearest_possession_name"] = "DEAREST POSSESSION"
	strings["csr_logbook_dearest_possession_effect"] = string.format(
		"Healing received at full HP is converted into temporary shields. Temporary shield cap: %g%% of maximum health (+%g%% per stack,linear). Temporary shields drain by %g%% every 5 seconds.",
		dp_cap * 100,
		dp_cap * 100,
		dp_per_tick_pct
	)
	strings["csr_logbook_dearest_possession_notes"] =
		"The crew doesn't know exactly where Dallas got his obsession with medic bags. But one thing they know for sure - Dallas genuinely loves them. Real love isn't shown through \"I love you\", gifts, or a partner's attention. It's shown through nothing other than: \"AAAAAAA!!! I NEED A MEDIC BAG!\""

	-- VIKLUND'S VINYL
	local vv_dmg_pct = C.viklund_chain_dmg_pct or 0.25
	local vv_count = C.viklund_chain_count or 2
	local vv_radius = (C.viklund_radius_base or 500) / 100
	local vv_rad_step = (C.viklund_radius_step or 200) / 100
	strings["csr_logbook_viklund_vinyl_name"] = "VIKLUND'S VINYL"
	strings["csr_logbook_viklund_vinyl_effect"] = string.format(
		"Gain {g}80%%{/} chance on hit to chain {g}%d{/} nearest enemies within {g}%gm{/} (+%gm per stack, linear) range. Chained enemies receive {g}%g%%{/} of the initial damage.",
		vv_count,
		vv_radius,
		vv_rad_step,
		vv_dmg_pct * 100
	)
	strings["csr_logbook_viklund_vinyl_notes"] =
		"Everyone connected to Crime.net knows who Bain is, but nobody knows who he actually is. Once me and the crew got into an argument about what kind of music our mysterious hacker might listen to. Someone suggested Alesso, but I said that's too mainstream for a guy like him. Then someone said classical, but that didn't fit either. \"Maybe something modern? Like dubstep or drum and bass?\" I got tired of the argument and just decided to ask him directly. \"Curious about my taste? Heh, alright, but don't make a face. I don't have a favorite genre or artist, but I can say that I've taken a bit of a liking to the work of someone called Viklund.\"\n\nWho the hell is Viklund?"

	-- DOZER GUIDE
	local dz_armor = C.dozer_armor_bonus or 0.50
	local dz_dmg = C.dozer_damage_bonus or 0.05
	local dz_spd = C.dozer_speed_penalty or 0.15
	local dz_dodge = C.dozer_dodge_penalty or 5
	local dz_min = C.dozer_speed_min or 0.40
	strings["csr_logbook_dozer_guide_name"] = "DOZER GUIDE"
	strings["csr_logbook_dozer_guide_effect"] = string.format(
		"Increases armor by {g}%g%%{/} (+%g%% per stack, linear) and damage by {g}%g%%{/} (+%g%% per stack, linear) from ranged and melee weapons.\nBut decreases movement speed by {r}%g%%{/} (+%g%% per stack, linear) (cannot be lower than %g%% of normal movement speed) and chance to dodge by {r}%d{/} (+%d per stack, linear).",
		dz_armor * 100,
		dz_armor * 100,
		dz_dmg * 100,
		dz_dmg * 100,
		dz_spd * 100,
		dz_spd * 100,
		dz_min * 100,
		dz_dodge,
		dz_dodge
	)
	strings["csr_logbook_dozer_guide_notes"] =
		'How to become a "wall". A beginner\'s guide.\n\n1. Infiltrate a military warehouse and steal one sapper uniform.\n2. Learn to shout loud and intimidating phrases. For example: "Out of the way. Bulldozer coming through!" or "You are nothing to me!"\n3. Forget about running. Walls don\'t run. Move slowly, confidently, and with dignity - as if you have nowhere to be.\n4. To become a "wall", you must act like a "wall". Bullets and explosives should not concern you. Dodging is for the weak.\n5. Upon spotting clowns, stay calm and move forward. They will shoot, they will scream. But don\'t give up. Run straight at them. They will fear you. (Well, in theory at least.)'

	-- GLASS PISTOL
	local gp_dmg = C.glass_pistol_dmg_per_stack or 1.75
	local gp_div = C.glass_pistol_div_per_stack or 2
	strings["csr_logbook_glass_pistol_name"] = "GLASS PISTOL"
	strings["csr_logbook_glass_pistol_effect"] = string.format(
		"Multiplies damage from ranged and melee weapons by {g}x%g{/} (x%g per stack, multiplicative).\nBut divides max health and armor by {r}%d{/} (+%d per stack, multiplicative).",
		gp_dmg,
		gp_dmg,
		gp_div,
		gp_div
	)
	strings["csr_logbook_glass_pistol_notes"] =
		'PROTOTYPE TEST REPORT\nDesignation: Prototype GG-1 ("Glass")\nDate: June 14, 2011\n\nThe sample demonstrates outstanding lethality, significantly exceeding standard police issue weaponry.\n\nIssue: The weapon\'s structure proved far too fragile and literally fell apart after firing. 6 testers were hospitalized. Two died on the scene.\n\nRecommendation: Discontinue production. Transfer to storage category "G".'

	-- EQUALIZER
	local eq_bonus = C.equalizer_bonus or 0.5
	local eq_penalty = C.equalizer_penalty or 0.5
	local eq_penalty_mult = 1 - eq_penalty
	strings["csr_logbook_equalizer_name"] = "EQUALIZER"
	strings["csr_logbook_equalizer_effect"] = string.format(
		"Increases damage against special enemies by {g}%g%%{/} (+%g%% per stack, linear).\nBut multiplies damage against regular enemies by {r}x%g{/} (x%g per stack, multiplicative).",
		eq_bonus * 100,
		eq_bonus * 100,
		eq_penalty_mult,
		eq_penalty_mult
	)
	strings["csr_logbook_equalizer_notes"] =
		"You all keep sending me messages like \"how do I make my music sound like yours?\", \"why does it sound like that\", \"what headphones do I need\" and all that stuff. Look, you don't need any expensive headphones. That's all nonsense. You just need an Equalizer! It's simple. You buy this thing, plug it into whatever you listen to music on, plug your headphones into it, and start tweaking the knobs until it sounds \"cool\". That's it! But to make it easier, here are my settings:\nBass: -12 dB (why do these even exist?)\nMids: -6 dB (boring too)\nHighs: +15 dB (now we're talking!)\nPhone rings.\nOne sec guys.\nMy producer called and said I'm not allowed to advertise products on stream. You know what? Screw him! I'm the one making music here, and they're just cashing in on my work."

	-- CROOKED BADGE
	strings["csr_logbook_crooked_badge_name"] = "CROOKED BADGE"
	strings["csr_logbook_crooked_badge_effect"] = string.format(
		"After each assault, {g}30%%{/} (+20%%, hyperbolic) chance to restore 1 down. Chance above 100%% guarantees multiple downs.\nBut bleedout timer is reduced by {r}10{/} (+1s, hyperbolic) seconds."
	)
	strings["csr_logbook_crooked_badge_notes"] =
		"March 14th, 2014\nHey diary... What a stupid way to start, but whatever. So, lately I've been feeling off. My colleagues have been giving me looks. The therapist says journaling will help me let go of my \"inner ailments\". Heh... Funny... He doesn't even know what I did. Nobody knows but me. What if someone reads this someday? Nah, doubt it. I'll burn it then. Alright, it's late. Going to sleep.\n\nMarch 20th, 2014\nDon't feel like doing anything. Why am I even writing this right now? -----------\n\nMarch 21st, 2014\nYesterday was a really rough day, and I don't know why I even wrote any of that. I feel like people are starting to dislike me. I understand them, can't blame them, but... Never mind.\n\nMarch 24th, 2014\nIt's always so hard to figure out what to write. Well, I lost my badge. I don't really know what's next for me, to be honest. Maybe I'll join \"them\"... Maybe I'll start robbing places myself. No, that's a terrible idea. I need to buy more sleeping pills.\n\nThe following pages are impossible to read as they are half-burned."

	-- DEAD MAN'S TRIGGER
	local dmt_dmg_display = (C.dmt_base_damage or 2400) / 5
	local dmt_extra_display = (C.dmt_damage_per_stack or 1200) / 5
	local dmt_radius_m = (C.dmt_base_radius or 300) / 100
	local dmt_radius_step_m = (C.dmt_radius_per_stack or 200) / 100
	strings["csr_logbook_dead_mans_trigger_name"] = "DEAD MAN'S TRIGGER"
	local dmt_ally = C.dmt_ally_mult or 0.20
	strings["csr_logbook_dead_mans_trigger_effect"] = string.format(
		"When going down you explode dealing {g}%g{/} (+%g per stack, linear) damage in a {g}%g{/} (+%g per stack, linear) meter radius. Damage scales with Crime Spree rank.\nBut allies within the radius take {r}%g%%{/} of the damage.",
		dmt_dmg_display,
		dmt_extra_display,
		dmt_radius_m,
		dmt_radius_step_m,
		dmt_ally * 100
	)
	strings["csr_logbook_dead_mans_trigger_notes"] =
		"LAST WILL AND TESTAMENT\nWritten: November 3rd. Afghanistan.\n\nIf you are reading this - I didn't make it back.\n\nThe house and everything in it - to Sara. The car - to my brother, he's had his eye on it for a while. The money in the account - to my mother. She can spend it however she likes.\n\nTo the guys in the unit - separately. I'm sorry. I didn't want you to get caught in it. You knew what you were getting into, but it was still my idea. Forgive me.\n\nTo Major Heller - nothing. He knows why.\nThe device is on me. Let them take it. Along with me.\n\n(Former) Private First Class D. Ward"

	-- === WILDCARD ITEMS ===
	local ff_radius_m = (C.familiar_friend_radius or 600) / 100
	local ff_dmg_display = (C.familiar_friend_damage or 2000) / 5
	local ff_cooldown = C.familiar_friend_cooldown or 60
	strings["csr_logbook_familiar_friend_name"] = "FAMILIAR FRIEND"
	strings["csr_logbook_familiar_friend_effect"] = string.format(
		"Release spike nova around you in {g}%gm{/} that deals {g}%g{/} damage. Damage scales with CS rank. Cooldown {b}%gs{/}.",
		ff_radius_m,
		ff_dmg_display,
		ff_cooldown
	)
	strings["csr_logbook_familiar_friend_notes"] =
		"It's 11th of August, 2020. Field Report #57. Subject: unidentified gelatinous organism, designated UGO-1 for documentation purposes. Behavior appears non-aggressive. Further observation requ- it just looked at me. Oh-oh... I think I am spotted. I need to run. How to turn off this thing...?! *leaves noises* *panic breathing* Is it still recording? I think it is. I got away. The subject appears to 'hop' around like some kind of bunny or rabbit. It's orange with yellow tint. It has some sort of horns..? I didn't quite catch what they were, but... *away from microphone* What the hell? Oh god... *into the mic again* The subject just duplicated itself. It became smaller, but now there's two of them. I... I've never seen anything like this. This is so... Beautiful. Maybe they are not bad. I will try to reason with it. *more noises* Hello, buddy. *strange alien noises* Whoa. Subject can produce sounds, but they are unlike anything I've heard from animals. Can I touch you? Ew... You're so sticky. But, at the same time, kinda cute? *petting* *strange loud alien noise* Ow! It just spiked me! It appears that its gelatinous body can reshape into spikes. I... Uh... *recording stops*"

	local ss_speed_pct = ((C.side_satchel_carry_speed_mult or 1.20) - 1) * 100
	strings["csr_logbook_side_satchel_name"] = "SIDE SATCHEL"
	strings["csr_logbook_side_satchel_effect"] = string.format(
		"{g} Doubles the amount of mission equipment you can carry{/} (ex. C4, keycards, planks, etc.). Increases movement speed while you carry a bag by {g}%g%%{/}",
		ss_speed_pct
	)
	strings["csr_logbook_side_satchel_notes"] =
		"- Son, listen carefully. I want you to buy: 8 c4 charges, 2 planks, 2 keycards and\226\128\166\n- Wait-wait-wait. Why do you need all that stuff?\n- For escape room..?\n- What kind of escape room need all of this?!\n- Prison\226\128\166\n- \226\128\166sigh. I hate you so much. I will be there in 10."

	local turron_heal_pct_disp = (C.turron_heal_pct or 0.33) * 100
	local turron_dr_pct_disp = (C.turron_dr_pct or 0.33) * 100
	local turron_dr_dur = C.turron_dr_duration or 5
	local turron_cd = C.turron_cooldown or 90
	strings["csr_logbook_turron_name"] = "TURRON"
	strings["csr_logbook_turron_effect"] = string.format(
		"Instantly heal {g}%g%% of your max health{/} and gain {g}%g%% damage reduction{/} for {b}%g{/} seconds. Cooldown {b}%g{/} seconds.",
		turron_heal_pct_disp,
		turron_dr_pct_disp,
		turron_dr_dur,
		turron_cd
	)
	strings["csr_logbook_turron_notes"] =
		"- Arghh... another *redacted* troublemaker. Go away. Our *redacted* is no longer giving out horoscopes!\n- Dare I ask you for some private time with the famous entity?\n- YOU - SSH - INSOLENT - SSH - BRAT - SSH!\n  None shall pass! The *redacted* would be real angry if some simpleton like you showed up to its favorite plac-\n  Eh?.... Is that a... Turron?\n- Turron.\n- Turron! | Turron!\n- Turron! | Turron!\n- Turron! | Turron!\n- You may have won this war, but you've lost the battle! Take this blood ID, it says you'll collect generous offerings for us.\n  To proceed, head straight and enter the holy code. Then, look for the blue door."

	local hippo_aura_tick = C.hippocratic_aura_tick or 5.0
	local hippo_aura_radius_m = (C.hippocratic_aura_radius or 500) / 100
	local hippo_heal_pct_disp = (C.hippocratic_heal_pct_per_tick or 0.05) * 100
	local hippo_respawn_min = (C.hippocratic_respawn_delay or 360) / 60
	strings["csr_logbook_hippocratic_oath_name"] = "HIPPOCRATIC OATH"
	strings["csr_logbook_hippocratic_oath_effect"] = string.format(
		"On loud transition, spawns a {g}medic that fights on your side{/}. Every {b}%g{/} seconds medic releases aura with {g}%gm{/} radius, that heals {g}%g%% of health{/}. After death, the medic respawns {b}%g{/} minutes later.",
		hippo_aura_tick,
		hippo_aura_radius_m,
		hippo_heal_pct_disp,
		hippo_respawn_min
	)
	strings["csr_logbook_hippocratic_oath_notes"] =
		'Article 4, Section 2: I shall render aid to any person in need of medical assistance, regardless of personal characteristics or circumstances. This includes, but is not limited to: political affiliation, nationality, religious beliefs, prior criminal record, individuals currently under active arrest, persons evading law enforcement on foot, individuals in possession of unlicensed firearms, persons wearing masks for non-medical purposes, individuals who have recently discharged an explosive device, anyone currently in the process of drilling through a vault, left-handed accountants, persons with outstanding parking fines exceeding $7, anyone who has insulted a notary public, individuals operating a vehicle without a valid license, persons who have exited a moving vehicle in the past 24 hours, anyone found in possession of more than three sets of handcuffs, individuals wearing body armor of non-regulation color, persons carrying currency in denominations exceeding $500, anyone who has rerouted a ventilation system for non-ventilation purposes, individuals who have rappelled from a building within the last 72 hours, persons who have disabled a security camera intentionally or otherwise, anyone currently in possession of a bag labeled "not a bomb", individuals who have zip-tied a security guard, persons who have ordered a helicopter for non-transportation purposes, anyone who has welded a door shut from the inside, individuals whose fingerprints do not appear in any federal database, persons who have filed a false floor plan with the city, anyone currently on a first-name basis with a criminal attorney\226\128\166'

	-- === SCRAP (printer fodder) ===
	strings["csr_logbook_scrap_common_name"] = "COMMON SCRAP"
	strings["csr_logbook_scrap_uncommon_name"] = "UNCOMMON SCRAP"
	strings["csr_logbook_scrap_rare_name"] = "RARE SCRAP"

	-- === BONUS ITEM DROP ===
	strings["csr_bonus_drop_title"] = "BONUS DROP!"
	strings["csr_bonus_drop_dismiss"] = "Click to continue"
	strings["csr_stats_drop_chance"] = "Bonus Drop Chance"

	loc:add_localized_strings(strings)
end)

-- Counts active modifier stacks matching the given id prefix.
-- For player items (player_*) uses the per-player store via CSR_CountStacks.
-- For CS modifiers (csr_*) still uses active_modifiers().
local function count_modifier_stacks(id_prefix)
	-- Player items: use the new per-player store
	if string.find(id_prefix, "player_", 1, true) == 1 then
		return CSR_CountStacks(id_prefix)
	end
	-- CS modifiers: fall back to active_modifiers
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end
	local count = 0
	for _, mod_data in ipairs(managers.crime_spree:active_modifiers() or {}) do
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
	if not string_id or type(string_id) ~= "string" then
		return original_text(self, string_id, macros)
	end

	local current_time = os.clock()

	-- SPECIAL CASE: Less Concealment - bypass vanilla system entirely
	-- to avoid the $value substitution problem
	if string_id == "menu_cs_modifier_less_concealment" then
		-- Base text without Total
		local base_text = "Stand Out\nDetection risk is increased by 3 (Stealth Only)"

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
		return "Marshal Reinforcements\nTwo additional US Marshal Marksmen are allowed into the level"
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

	-- BULLSEYE (Headshot Armor Regen) - append CSR scaling note in skill tree
	-- Vanilla key: "menu_prison_wife_beta_desc" (internal name for Bullseye skill)
	-- Contains both BASIC and ACE in one string, so we append once at the end.
	if string_id == "menu_prison_wife_beta_desc" then
		local armor_mult = CSR_ActiveBuffs and CSR_ActiveBuffs.passive_armor_multiplier
		if armor_mult and armor_mult > 1.0 then
			local bonus_pct = math.floor((armor_mult - 1) * 100 + 0.5)
			result = result
				.. "\n\nIn ##Crime Spree Roguelike##, armor regen is scaled by rank bonus (##+"
				.. bonus_pct
				.. "%##)."
		else
			result = result .. "\n\nIn ##Crime Spree Roguelike##, armor regen scales with rank."
		end
	end

	return result
end
