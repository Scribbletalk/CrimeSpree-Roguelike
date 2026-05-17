-- Crime Spree Roguelike - Localization loader
-- 6.3 refactor: static strings live in loc/english.json (BAI-style flat-file
-- pattern, loaded via loc:load_localization_file). Only the genuinely DYNAMIC
-- strings stay in Lua here: balance-number interpolation (CSR_ItemConstants),
-- the per-registry 200-copy key generation, the forced-modifier full-ID
-- generation, and the runtime LocalizationManager:text override. Ported 1:1
-- from the pre-refactor monolith lua/managers/localization.lua.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("[CSR LOC] localization loader loading")

Hooks:Add("LocalizationManagerPostInit", "CSR_Localization", function(loc)
	-- Static base: every literal string (flattened items, vanilla overrides,
	-- UI labels, logbook names/notes) is in loc/english.json.
	local json_path = ModPath .. "loc/english.json"
	loc:load_localization_file(json_path)

	-- Re-decode the JSON ourselves so the dynamic generation below can source
	-- base text without duplicating the data (single source of truth = JSON).
	local base = {}
	local file = io.open(json_path, "r")
	if file then
		local ok, decoded = pcall(json.decode, file:read("*all"))
		file:close()
		if ok and decoded then
			base = decoded
		else
			log("[CSR LOC] ERROR: english.json parse failed; dynamic keys may be missing")
		end
	else
		log("[CSR LOC] ERROR: english.json not found at " .. tostring(json_path))
	end

	-- Build dynamic localization strings
	local strings = {}

	-- Glyph / utf8 keys kept in Lua so the exact byte sequences are preserved
	-- (JSON round-trip risk for PUA glyphs / utf8.char). Verbatim from monolith.
	strings["menu_csr_logbook_new"] = "LOGBOOK" .. utf8.char(0xE012) .. "  "
	strings["menu_csr_printer_new"] = "PRINTER " .. utf8.char(0xE012)
	strings["csr_ready_confirmed"] = "READY \xe2\x9c\x93"
	strings["menu_cs_next_modifier_forced"] = "NEXT MODIFIER: $next \xEE\x80\x98"
	strings["menu_cs_next_modifier_loud"] = "NEXT GUARANTEED ITEM: $next \xEE\x80\x98"
	strings["menu_cs_next_modifier_stealth"] = "NEXT MODIFIER: $next \xEE\x80\x98"

	-- Dynamic localization for all item copies (up to 200 copies)
	-- Vanilla looks up localization by pattern: menu_cs_modifier_<modifier_id>
	-- Our IDs: player_health_boost_1 .. player_health_boost_200
	-- Base text (name\ndesc) comes from the JSON flatten (base[loc_key]).
	local item_types = {}
	for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
		table.insert(item_types, { prefix = item.id_prefix, base_key = item.loc_key })
	end

	for _, item_type in ipairs(item_types) do
		local text = base[item_type.base_key]
		if text then
			-- Generate keys for 200 copies
			for i = 1, 200 do
				local mod_id = item_type.prefix .. i
				local loc_key = "menu_cs_modifier_" .. mod_id
				strings[loc_key] = text
			end
			CSR_log("[CSR LOC] Generated 200 localization keys for: " .. item_type.prefix)
		end
	end

	-- Generate full-ID keys for forced modifiers so the vanilla Modifiers tab
	-- can find them. Vanilla UI looks up "menu_cs_modifier_" .. mod.id directly
	-- (e.g. "menu_cs_modifier_csr_civilian_guilt_20"). We map each full ID to
	-- its base text using the same stripping logic as forced_mods_notification.
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
			-- base text may be a generated copy (strings) or a static vanilla
			-- override / flattened item (base, from JSON).
			local base_text = strings["menu_cs_modifier_" .. base_id] or base["menu_cs_modifier_" .. base_id]
			if base_text then
				strings["menu_cs_modifier_" .. mod.id] = base_text
			end
		end
	end

	-- === LOGBOOK EFFECT STRINGS (balance-number interpolation) ===
	local C = _G.CSR_ItemConstants or {}

	-- DOG TAGS
	local dt_hp = C.dog_tags_hp_bonus or 0.10
	strings["csr_logbook_dog_tags_effect"] =
		string.format("Increases maximum health by {g}%g%%{/} (+%g%% per stack, linear).", dt_hp * 100, dt_hp * 100)

	-- DUCT TAPE
	local tape_spd = C.duct_tape_speed_bonus or 0.05
	strings["csr_logbook_duct_tape_effect"] = string.format(
		"Increases interaction speed by {g}%g%%{/} (+%g%% per stack, linear).\nAffects lockpicking, bagging loot, repairing, etc. Does {r}not{/} apply to reviving teammates or uncuffing.",
		tape_spd * 100,
		tape_spd * 100
	)

	-- ESCAPE PLAN
	local sn_cap = C.escape_plan_cap or 0.50
	local sn_k = (C.escape_plan_k_num or 3) / (C.escape_plan_k_den or 47)
	local sn_first = math.floor(sn_cap * sn_k / (1 + sn_k) * 100 + 0.5)
	strings["csr_logbook_escape_plan_effect"] =
		string.format("Increases movement speed by {g}%d%%{/} (+%d%% per stack, hyperbolic).", sn_first, sn_first)

	-- WORN BAND-AID
	local ba_first = (C.worn_bandaid_first_pct or 0.01) * 100
	local ba_max = (C.worn_bandaid_max_pct or 0.20) * 100
	local ba_int = C.worn_bandaid_interval or 5
	strings["csr_logbook_worn_bandaid_effect"] = string.format(
		"Regenerates {g}%g%%{/} (+%g%% per stack, hyperbolic, capped at %g%%) of max health every %g seconds.",
		ba_first,
		ba_first,
		ba_max,
		ba_int
	)

	-- LOCKE'S BERET
	local beret_first = (C.lockes_beret_first_pct or 0.10) * 100
	local beret_max = (C.lockes_beret_max_pct or 0.50) * 100
	local beret_interval = C.lockes_beret_interval or 30
	strings["csr_logbook_lockes_beret_effect"] = string.format(
		"Every {g}%g{/} seconds, heals everyone on your team (you, teammates, bots, jokers, turrets) for {g}%g%%{/} (+%g%% per stack, hyperbolic, capped at %g%%) of max health.",
		beret_interval,
		beret_first,
		beret_first,
		beret_max
	)

	-- CUP OF JOE
	local coj_per_stack = (C.cup_of_joe_per_stack or 0.10) * 100
	strings["csr_logbook_cup_of_joe_effect"] = string.format(
		"Increases maximum stamina by {g}%g%%{/} (+%g%% per stack, linear).",
		coj_per_stack,
		coj_per_stack
	)

	-- PIECE OF REBAR
	local rb_base = C.rebar_base_bonus or 0.15
	local rb_extra = C.rebar_extra_bonus or 0.10
	strings["csr_logbook_rebar_effect"] = string.format(
		"First hit on an enemy deals {g}+%g%%{/} (+%g%% per stack, linear) damage.",
		rb_base * 100,
		rb_extra * 100
	)

	-- HALF-A-GLASS
	local hg_refill = C.half_a_glass_refill or 0.15
	local hg_first = C.half_a_glass_max_ammo_first or 0.02
	local hg_extra = C.half_a_glass_max_ammo_extra or 0.01
	strings["csr_logbook_half_a_glass_effect"] = string.format(
		"Picking up a Gage package instantly refills {g}%g%%{/} ammo for primary and secondary weapons and increases their max ammo by {g}%g%%{/} (+%g%% per stack, linear) for the rest of the mission.",
		hg_refill * 100,
		hg_first * 100,
		hg_extra * 100
	)

	-- EVIDENCE ROUNDS
	local ap_dmg = C.ap_rounds_damage_bonus or 0.05
	strings["csr_logbook_evidence_rounds_effect"] = string.format(
		"Increases damage from ALL sources by {g}%g%%{/} (+%g%% per stack, linear).",
		ap_dmg * 100,
		ap_dmg * 100
	)

	-- FALCOGINI KEYS
	local keys_first = math.floor(100 / (1 + (C.car_keys_k_den or 32)) + 0.5)
	strings["csr_logbook_falcogini_keys_effect"] = string.format(
		"Increases chance to dodge by {g}%d%%{/} (+%d%% per stack, hyperbolic).\nSuccessful dodging blocks incoming damage (does not work on self-inflicted damage).",
		keys_first,
		keys_first
	)

	-- WOLF'S TOOLBOX
	local wt_norm_base = C.wolfs_toolbox_normal_base or 0.2
	local wt_norm_extra = C.wolfs_toolbox_normal_extra or 0.1
	local wt_spec_base = C.wolfs_toolbox_special_base or 1.0
	local wt_spec_extra = C.wolfs_toolbox_special_extra or 0.5
	strings["csr_logbook_wolfs_toolbox_effect"] = string.format(
		"Killing regular enemies reduces active drill/saw timer by {g}%g second(s){/} (+%gs per stack, linear).\nKilling special enemies reduces timer by {g}%g second(s){/} (+%gs per stack, linear).",
		wt_norm_base,
		wt_norm_extra,
		wt_spec_base,
		wt_spec_extra
	)

	-- PINK SLIP
	local ps_pct = (C.pink_slip_base_percent or 0.01) * 100
	local ps_base_flat = C.pink_slip_base_flat or 4
	local ps_heal_extra = C.pink_slip_extra_heal or 6
	strings["csr_logbook_pink_slip_effect"] = string.format(
		"Killing any enemy restores {g}%g%%{/} of max health + {g}%g{/} (+%g per stack, linear) health.",
		ps_pct,
		ps_base_flat,
		ps_heal_extra
	)

	-- THE EDGE
	local te_threshold = (C.the_edge_hp_threshold or 0.10) * 100
	local te_pct = (C.the_edge_heal_pct or 0.20) * 100
	local te_flat = C.the_edge_heal_flat or 20
	local te_extra = C.the_edge_heal_flat_extra or 40
	local te_invuln = C.the_edge_invuln or 0.5
	local te_cd = C.the_edge_cooldown or 60
	strings["csr_logbook_the_edge_effect"] = string.format(
		"When health drops below {r}%.0f%%{/}, restores {g}%.0f%%{/} max health + {g}%g{/} (+%g per stack) and grants {g}%.1fs{/} invulnerability.\n%gs cooldown.",
		te_threshold,
		te_pct,
		te_flat,
		te_extra,
		te_invuln,
		te_cd
	)

	-- OVERKILL RUSH
	local ok_first = C.overkill_rush_first_bonus or 0.02
	local ok_extra = C.overkill_rush_extra_bonus or 0.01
	local ok_stacks = C.overkill_rush_max_stacks or 4
	local ok_dur = C.overkill_rush_duration or 4.0
	strings["csr_logbook_overkill_rush_effect"] = string.format(
		"Killing any enemy grants you a rush stack. For each rush stack your fire rate and reload speed increase by {g}%g%%{/} (+%g%% per stack, linear).\nAll rush stacks expire %g seconds after the last kill.",
		ok_first * 100,
		ok_extra * 100,
		ok_dur
	)

	-- BONNIE'S LUCKY CHIP
	local bc_chance = C.bonnie_chip_chance or 0.10
	local bc_cd = C.bonnie_chip_cooldown or 1.5
	strings["csr_logbook_bonnie_chip_effect"] = string.format(
		"Gain {g}%g%%{/} (+%g%% per stack, hyperbolic) chance to instantly kill an enemy on hit.\nHas %g second cooldown.",
		bc_chance * 100,
		bc_chance * 100,
		bc_cd
	)

	-- PLUSH SHARK
	local ps_heal_pct = C.plush_shark_heal_pct or 1.00
	local ps_inv_base = C.plush_shark_invuln_base or 10
	local ps_inv_extra = C.plush_shark_invuln_extra or 20
	strings["csr_logbook_plush_shark_effect"] = string.format(
		"When have only down and your health reaches 0, this item ictivates.\nOn activation restores {g}1 down{/}, {g}%g%%{/} maximum {g}health{/} and {g}armor{/}, then grants invulnerability that lasts {g}%g seconds{/} (+%gs per stack, linear).\nCan be activated again if you were freed from custody.",
		ps_heal_pct * 100,
		ps_inv_base,
		ps_inv_extra
	)

	-- JIRO'S LAST WISH
	local jiro_dmg_bonus = C.jiro_melee_bonus or 0.50
	strings["csr_logbook_jiro_last_wish_effect"] = string.format(
		"Grants an ability to sprint while charging a melee attack. Increases melee damage by {g}%d%%{/} (+%d%% per stack, linear).",
		jiro_dmg_bonus * 100,
		jiro_dmg_bonus * 100
	)

	-- DEAREST POSSESSION
	local dp_cap = C.dearest_armor_cap or 0.5
	local dp_decay = C.dearest_decay_rate or 0.01666
	-- Per-tick drain percentage (5s tick interval is hardcoded in dearestpossession.lua).
	local dp_per_tick_pct = dp_decay * 5 * 100
	strings["csr_logbook_dearest_possession_effect"] = string.format(
		"Healing received at full HP is converted into temporary shields. Temporary shield cap: %g%% of maximum health (+%g%% per stack,linear). Temporary shields drain by %g%% every 5 seconds.",
		dp_cap * 100,
		dp_cap * 100,
		dp_per_tick_pct
	)

	-- VIKLUND'S VINYL
	local vv_dmg_pct = C.viklund_chain_dmg_pct or 0.25
	local vv_count = C.viklund_chain_count or 2
	local vv_radius = (C.viklund_radius_base or 500) / 100
	local vv_rad_step = (C.viklund_radius_step or 200) / 100
	strings["csr_logbook_viklund_vinyl_effect"] = string.format(
		"Gain {g}80%%{/} chance on hit to chain {g}%d{/} nearest enemies within {g}%gm{/} (+%gm per stack, linear) range. Chained enemies receive {g}%g%%{/} of the initial damage.",
		vv_count,
		vv_radius,
		vv_rad_step,
		vv_dmg_pct * 100
	)

	-- DOZER GUIDE
	local dz_armor = C.dozer_armor_bonus or 0.50
	local dz_dmg = C.dozer_damage_bonus or 0.05
	local dz_spd = C.dozer_speed_penalty or 0.15
	local dz_dodge = C.dozer_dodge_penalty or 5
	local dz_min = C.dozer_speed_min or 0.40
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

	-- GLASS PISTOL
	local gp_dmg = C.glass_pistol_dmg_per_stack or 1.75
	local gp_div = C.glass_pistol_div_per_stack or 2
	strings["csr_logbook_glass_pistol_effect"] = string.format(
		"Multiplies damage from ranged and melee weapons by {g}x%g{/} (x%g per stack, multiplicative).\nBut divides max health and armor by {r}%d{/} (+%d per stack, multiplicative).",
		gp_dmg,
		gp_dmg,
		gp_div,
		gp_div
	)

	-- EQUALIZER
	local eq_bonus = C.equalizer_bonus or 0.5
	local eq_penalty = C.equalizer_penalty or 0.5
	local eq_penalty_mult = 1 - eq_penalty
	strings["csr_logbook_equalizer_effect"] = string.format(
		"Increases damage against special enemies by {g}%g%%{/} (+%g%% per stack, linear).\nBut multiplies damage against regular enemies by {r}x%g{/} (x%g per stack, multiplicative).",
		eq_bonus * 100,
		eq_bonus * 100,
		eq_penalty_mult,
		eq_penalty_mult
	)

	-- DEAD MAN'S TRIGGER
	local dmt_dmg_display = (C.dmt_base_damage or 2400) / 5
	local dmt_extra_display = (C.dmt_damage_per_stack or 1200) / 5
	local dmt_radius_m = (C.dmt_base_radius or 300) / 100
	local dmt_radius_step_m = (C.dmt_radius_per_stack or 200) / 100
	local dmt_ally = C.dmt_ally_mult or 0.20
	strings["csr_logbook_dead_mans_trigger_effect"] = string.format(
		"When going down you explode dealing {g}%g{/} (+%g per stack, linear) damage in a {g}%g{/} (+%g per stack, linear) meter radius. Damage scales with Crime Spree rank.\nBut allies within the radius take {r}%g%%{/} of the damage.",
		dmt_dmg_display,
		dmt_extra_display,
		dmt_radius_m,
		dmt_radius_step_m,
		dmt_ally * 100
	)

	-- === WILDCARD ITEMS ===
	local ff_radius_m = (C.familiar_friend_radius or 600) / 100
	local ff_dmg_display = (C.familiar_friend_damage or 2000) / 5
	local ff_cooldown = C.familiar_friend_cooldown or 60
	strings["csr_logbook_familiar_friend_effect"] = string.format(
		"Release spike nova around you in {g}%gm{/} that deals {g}%g{/} damage. Damage scales with CS rank. Cooldown {b}%gs{/}.",
		ff_radius_m,
		ff_dmg_display,
		ff_cooldown
	)

	local ss_speed_pct = ((C.side_satchel_carry_speed_mult or 1.20) - 1) * 100
	strings["csr_logbook_side_satchel_effect"] = string.format(
		"{g} Doubles the amount of mission equipment you can carry{/} (ex. C4, keycards, planks, etc.). Increases movement speed while you carry a bag by {g}%g%%{/}",
		ss_speed_pct
	)

	local turron_heal_pct_disp = (C.turron_heal_pct or 0.33) * 100
	local turron_dr_pct_disp = (C.turron_dr_pct or 0.33) * 100
	local turron_dr_dur = C.turron_dr_duration or 5
	local turron_cd = C.turron_cooldown or 90
	strings["csr_logbook_turron_effect"] = string.format(
		"Instantly heal {g}%g%% of your max health{/} and gain {g}%g%% damage reduction{/} for {b}%g{/} seconds. Cooldown {b}%g{/} seconds.",
		turron_heal_pct_disp,
		turron_dr_pct_disp,
		turron_dr_dur,
		turron_cd
	)

	local hippo_aura_tick = C.hippocratic_aura_tick or 5.0
	local hippo_aura_radius_m = (C.hippocratic_aura_radius or 500) / 100
	local hippo_heal_pct_disp = (C.hippocratic_heal_pct_per_tick or 0.05) * 100
	local hippo_respawn_min = (C.hippocratic_respawn_delay or 360) / 60
	strings["csr_logbook_hippocratic_oath_effect"] = string.format(
		"On loud transition, spawns a {g}medic that fights on your side{/}. Every {b}%g{/} seconds medic releases aura with {g}%gm{/} radius, that heals {g}%g%% of health{/}. After death, the medic respawns {b}%g{/} minutes later.",
		hippo_aura_tick,
		hippo_aura_radius_m,
		hippo_heal_pct_disp,
		hippo_respawn_min
	)

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

-- Diagnostic load trace (kept per debug policy; load-triggered subsystem).
log("[CSR LOC] csr_localization.lua loaded; LocalizationManagerPostInit hook + text override registered")
