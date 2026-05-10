-- Crime Spree Roguelike Alpha 1 - Modifier replacement

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("========================================")
CSR_log("=== CRIME SPREE ROGUELIKE Alpha 1 ===")
CSR_log("========================================")

-- Gage package contour material_config registration moved to seed_manager.lua
-- (conditional: only when Half-a-Glass is in inventory)

-- TODO: Custom icon for DOG TAGS (needs a hook on HUDIconsTweakData later)

-- Stubs for early class availability in menu context (registry-driven):
-- Several modifier scripts are loaded in mission scope (copdamage, playerdamage, playerstandard)
-- and are NOT available when the modifier selection popup appears between missions.
-- These minimal stubs provide desc_id so make_modifier_description can show descriptions.
-- The "or class(...)" pattern ensures the real class takes over once the script loads.
for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
	if item.needs_stub then
		_G[item.class] = _G[item.class] or class(CSRBaseModifier)
		_G[item.class].desc_id = item.loc_key
	end
end
-- Non-player modifier stub (not in registry)
ModifierCivilianGuilt = ModifierCivilianGuilt or class(CSRBaseModifier)
ModifierCivilianGuilt.desc_id = "menu_cs_modifier_civilian_guilt"
ModifierShockingSurprise = ModifierShockingSurprise or class(CSRBaseModifier)
ModifierShockingSurprise.desc_id = "menu_cs_modifier_shocking_surprise"

-- Prevent Crime Spree loss on crash (credit: Nepsy - "Stop the crimespree loss on crash")
Hooks:PostHook(CrimeSpreeTweakData, "init", "CSR_NoCrashLoss", function(self)
	self.crash_causes_loss = false
end)

-- Remove vanilla level-60 (or rank > 0) gate so CSR is always available.
-- Gate lives in CrimeSpreeManager:can_play_crime_spree (managers/crimespreemanager.lua):
--   return tweak_data.crime_spree.unlock_level <= managers.experience:current_level() or current_rank() > 0
-- Setting unlock_level = 0 makes the inequality always true at level 1+.
Hooks:PostHook(CrimeSpreeTweakData, "init", "CSR_UnlockAtAnyLevel", function(self)
	self.unlock_level = 0
end)

-- PostHook to replace modifiers
Hooks:PostHook(CrimeSpreeTweakData, "init", "CSR_Alpha1_ModifyLoud", function(self)
	-- === PLAYER BUFFS (chosen by the player) ===
	-- Generated from centralized item registry (1 copy of each type as seed)
	local player_buffs = {}
	for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
		table.insert(player_buffs, {
			id = item.id_prefix .. "1",
			class = item.class,
			icon = item.icon,
			level = 0,
			data = {},
		})
	end

	self.modifiers.loud = player_buffs

	-- === VANILLA LOUD MODIFIERS ===
	-- Data format: {value, "none"} or {value, "add"}
	-- min_difficulty: minimum difficulty at which the modifier is redundant (enemies already present)
	-- requires_difficulty: minimum difficulty at which the modifier makes sense (requires specific enemies)
	-- requires_enemy: enemy type required (for checking unlocks at low difficulties)
	local vanilla_loud_modifiers = {
		{
			id = "csr_cloaker_tear_gas",
			class = "ModifierCloakerTearGas",
			icon = "crime_spree_cloaker_tear_gas",
			data = { diameter = { 4, "none" }, damage = { 30, "none" }, duration = { 10, "none" } },
			requires_difficulty = "overkill",
			requires_enemy = "cloakers",
		},
		{ id = "csr_no_hurt_anims", class = "ModifierNoHurtAnims", icon = "crime_spree_no_hurt", data = {} },
		{
			id = "csr_taser_overcharge",
			class = "ModifierTaserOvercharge",
			icon = "crime_spree_taser_overcharge",
			data = { speed = { 50, "add" } },
			requires_difficulty = "hard",
			requires_enemy = "tasers",
		},
		{ id = "csr_heavies", class = "ModifierHeavies", icon = "crime_spree_heavies", data = {} },
		{
			id = "csr_dozer_rage",
			class = "ModifierDozerRage",
			icon = "crime_spree_dozer_rage",
			data = { damage = { 100, "add" } },
			requires_difficulty = "overkill_145",
			requires_enemy = "bulldozers",
		},
		{
			id = "csr_skulldozers",
			class = "ModifierSkulldozers",
			icon = "crime_spree_dozer_lmg",
			data = {},
			min_difficulty = "easy_wish",
			requires_difficulty = "overkill_145",
			requires_enemy = "bulldozers",
		},
		{
			id = "csr_dozer_minigun",
			class = "ModifierDozerMinigun",
			icon = "crime_spree_more_dozers",
			data = {},
			min_difficulty = "overkill_290",
			requires_difficulty = "overkill_145",
			requires_enemy = "bulldozers",
		},
		{
			id = "csr_dozer_medic",
			class = "ModifierDozerMedic",
			icon = "crime_spree_dozer_medic",
			data = {},
			min_difficulty = "sm_wish",
			requires_difficulty = "overkill_145",
			requires_enemy = "bulldozers",
		},
		{
			id = "csr_more_dozers",
			class = "ModifierMoreDozers",
			icon = "crime_spree_more_dozers",
			data = { inc = { 2, "add" } },
			requires_difficulty = "overkill_145",
			requires_enemy = "bulldozers",
		},
		{
			id = "csr_more_medics",
			class = "ModifierMoreMedics",
			icon = "crime_spree_more_medics",
			data = { inc = { 2, "add" } },
			requires_difficulty = "overkill_145",
			requires_enemy = "medics",
		},
		{
			id = "csr_heal_speed",
			class = "ModifierHealSpeed",
			icon = "crime_spree_medic_speed",
			data = { speed = { 20, "add" } },
			requires_difficulty = "overkill_145",
			requires_enemy = "medics",
		},
		-- Additional vanilla modifiers (10 total)
		{
			id = "csr_shield_reflect",
			class = "ModifierShieldReflect",
			icon = "crime_spree_shield_reflect",
			data = {},
		},
		{
			id = "csr_cloaker_smoke",
			class = "ModifierCloakerKick",
			icon = "crime_spree_cloaker_smoke",
			data = { effect = { "smoke", "none" } },
			requires_difficulty = "overkill",
			requires_enemy = "cloakers",
		},
		{
			id = "csr_heavy_sniper",
			class = "ModifierHeavySniper",
			icon = "crime_spree_heavy_sniper",
			data = { amount = { 2, "add" } },
		}, -- Reworked 6.0.2: +2 max US Marshal Marksmen per stack (was: ZEAL sniper swap)
		{
			id = "csr_medic_adrenaline",
			class = "ModifierMedicAdrenaline",
			icon = "crime_spree_medic_adrenaline",
			data = { damage = { 100, "add" } },
			requires_difficulty = "overkill_145",
			requires_enemy = "medics",
		},
		{
			id = "csr_shield_phalanx",
			class = "ModifierShieldPhalanx",
			icon = "crime_spree_shield_phalanx",
			data = {},
		}, -- Shields are everywhere, but Winters is CS-exclusive
		{
			id = "csr_medic_deathwish",
			class = "ModifierMedicDeathwish",
			icon = "crime_spree_medic_deathwish",
			data = {},
			requires_difficulty = "overkill_145",
			requires_enemy = "medics",
		},
		{
			id = "csr_explosion_immunity",
			class = "ModifierExplosionImmunity",
			icon = "crime_spree_dozer_explosion",
			data = {},
			requires_difficulty = "overkill_145",
			requires_enemy = "bulldozers",
		},
		{
			id = "csr_assault_extender",
			class = "ModifierAssaultExtender",
			icon = "crime_spree_heavies",
			data = {
				duration = { 40, "add" },
				spawn_pool = { 20, "add" },
				deduction = { 4, "add" },
				duration_deduction = { 5, "add" },
				spawn_deduction = { 2.5, "add" },
				max_hostages = { 4, "none" },
			},
		},
		{
			id = "csr_cloaker_arrest",
			class = "ModifierCloakerArrest",
			icon = "crime_spree_cloaker_arrest",
			data = {},
			requires_difficulty = "overkill",
			requires_enemy = "cloakers",
		},
		{
			id = "csr_medic_rage",
			class = "ModifierMedicRage",
			icon = "crime_spree_medic_rage",
			data = { damage = { 20, "add" } },
			requires_difficulty = "overkill_145",
			requires_enemy = "medics",
		},
		-- Civilian Guilt: player punishment for killing civilians in loud
		{ id = "csr_civilian_guilt", class = "ModifierCivilianGuilt", icon = "csr_guilty_conscience", data = {} },
		-- Shocking Surprise: taser death stuns nearby players
		{
			id = "csr_shocking_surprise",
			class = "ModifierShockingSurprise",
			icon = "csr_shocking_surprise",
			data = {},
			requires_difficulty = "hard",
			requires_enemy = "tasers",
		},
		-- Unlock modifiers (enable enemy spawning at low difficulties)
		{
			id = "csr_enable_bulldozers",
			class = "ModifierEnableBulldozers",
			icon = "crime_spree_more_dozers",
			data = {},
			max_difficulty = "overkill",
			skip_level_count = true,
		},
		{
			id = "csr_enable_medics",
			class = "ModifierEnableMedics",
			icon = "crime_spree_more_medics",
			data = {},
			max_difficulty = "overkill",
			skip_level_count = true,
		},
		{
			id = "csr_enable_tasers",
			class = "ModifierEnableTasers",
			icon = "crime_spree_taser_overcharge",
			data = {},
			max_difficulty = "normal",
			skip_level_count = true,
		},
		{
			id = "csr_enable_cloakers",
			class = "ModifierEnableCloakers",
			icon = "crime_spree_cloaker_smoke",
			data = {},
			max_difficulty = "hard",
			skip_level_count = true,
		},
	}

	-- === FORCED MODIFIERS ===
	-- HP/Damage: every level (+0.4% HP, +0.3% DMG, additive)
	-- Loud (vanilla): every 20 levels (20, 40, 60, ...)
	-- Stealth: every 20 levels (20, 40, 60, ...)
	-- BOTH can occur on the same level (loud + stealth) - handled in code!
	-- Must stay in sync with self.modifier_levels.loud / .forced at the bottom of this file.
	local STEALTH_INTERVAL = 20 -- Interval between stealth modifiers
	local STEALTH_START = 20 -- First stealth modifier at level 20 (same as loud)
	local LOUD_INTERVAL = 20 -- Loud every 20 levels

	-- Read seed, difficulty, and version from file (generated when Crime Spree starts)
	local SEED_FILE = SavePath .. "crime_spree_seed.txt"
	local CURRENT_VERSION = _G.CSR_MOD_VERSION or "alpha-2.0.0"
	local current_seed = nil
	local current_difficulty = nil
	local seed_version = nil
	local needs_regeneration = false
	local _extra_lines = nil

	local seed_file = io.open(SEED_FILE, "r")
	if seed_file then
		local seed_line = seed_file:read("*line")
		local difficulty_line = seed_file:read("*line")
		local version_line = seed_file:read("*line") -- Line 3: version
		local mission_level_line = seed_file:read("*line") -- Line 4
		local forced_mods_line = seed_file:read("*line") -- Line 5
		local player_items_line = seed_file:read("*line") -- Line 6
		local bonus_chance_line = seed_file:read("*line") -- Line 7
		seed_file:close()

		-- Preserve extra lines for re-saving
		_extra_lines = {
			mission_level_line or "",
			forced_mods_line or "",
			player_items_line or "",
			bonus_chance_line or "",
		}

		local saved_seed = tonumber(seed_line)
		if saved_seed then
			current_seed = saved_seed
			current_difficulty = difficulty_line or "normal"
			seed_version = version_line -- May be nil for old seeds

			-- Check version
			if not seed_version or seed_version ~= CURRENT_VERSION then
				needs_regeneration = true
				-- Set global flag for force update module
				_G.CSR_NeedsRegenerationFlag = true
				_G.CSR_CurrentSeed = current_seed
				_G.CSR_CurrentDifficulty = current_difficulty
				-- ACTIVE CRIME SPREE CHECK TEMPORARILY DISABLED
				-- This allows modifiers to be regenerated in an already-started Crime Spree
			end
		else
		end
	else
	end

	-- If no seed found, generate a new one and save it
	if not current_seed then
		current_seed = os.time()
		current_difficulty = "normal"
		local new_file = io.open(SEED_FILE, "w")
		if new_file then
			new_file:write(tostring(current_seed) .. "\n")
			new_file:write(current_difficulty .. "\n")
			new_file:write(CURRENT_VERSION .. "\n")
			new_file:write("0\n") -- Line 4: mission_selection_level
			new_file:write("\n") -- Line 5: forced modifiers
			new_file:write("\n") -- Line 6: player items
			new_file:write("0.01|0") -- Line 7: bonus chance|drop count
			new_file:close()
		end
	end

	-- Deterministic index selection based on level and seed
	-- Different seed = different sequence, but stable within a run
	local function deterministic_index(level, max, seed)
		return ((level * 7919 + seed) % max) + 1
	end

	-- Check whether the player has taken an unlock for a specific enemy type
	local function has_enemy_unlock(enemy_type, generated_modifiers)
		local unlock_map = {
			bulldozers = "csr_enable_bulldozers",
			medics = "csr_enable_medics",
			tasers = "csr_enable_tasers",
			cloakers = "csr_enable_cloakers",
		}

		local unlock_id = unlock_map[enemy_type]
		if not unlock_id then
			return false
		end

		-- Check if the unlock exists among already-generated modifiers
		for _, mod in ipairs(generated_modifiers) do
			if string.find(mod.id, unlock_id, 1, true) then
				return true
			end
		end

		return false
	end

	-- Check whether the modifier class has already been used
	local function is_class_already_used(modifier_class, generated_modifiers)
		for _, mod in ipairs(generated_modifiers) do
			if mod.class == modifier_class then
				return true
			end
		end
		return false
	end

	-- Check whether the modifier is redundant at the current difficulty
	local function is_modifier_redundant(modifier, difficulty, generated_modifiers)
		-- Difficulty aliases (seed uses different names from the game code)
		local difficulty_aliases = {
			death_wish = "overkill_290", -- Death Wish = overkill_290, NOT easy_wish!
			death_sentence = "sm_wish",
			mayhem = "easy_wish", -- Mayhem = easy_wish OR overkill_145
		}

		-- Difficulty order (using internal names)
		local difficulty_order = {
			"normal",
			"hard",
			"very_hard",
			"overkill",
			"overkill_145",
			"easy_wish",
			"overkill_290",
			"sm_wish",
		}

		local function get_diff_level(diff)
			-- Check aliases
			local normalized_diff = difficulty_aliases[diff] or diff

			for i, d in ipairs(difficulty_order) do
				if d == normalized_diff then
					return i
				end
			end

			return 1 -- Default: normal
		end

		local current_level = get_diff_level(difficulty)

		-- Check requires_difficulty: redundant if difficulty < required (needed enemies not yet present)
		if modifier.requires_difficulty then
			local required_level = get_diff_level(modifier.requires_difficulty)
			if current_level < required_level then
				-- Difficulty too low, but check unlocks
				if modifier.requires_enemy then
					-- Check if player has the unlock for these enemies
					if has_enemy_unlock(modifier.requires_enemy, generated_modifiers) then
						return false -- Not redundant (unlock enabled the enemies)
					end

					-- Check if enemies are naturally present at current difficulty
					-- (their unlock modifier would be redundant = enemies already spawning)
					local enemy_natural_difficulty = {
						bulldozers = "overkill",
						medics = "overkill",
						tasers = "hard",
						cloakers = "very_hard",
					}
					local natural_diff = enemy_natural_difficulty[modifier.requires_enemy]
					if natural_diff and current_level >= get_diff_level(natural_diff) then
						return false -- Not redundant (enemies naturally present at this difficulty)
					end

					return true -- Redundant (enemies not unlocked and not naturally present)
				else
					return true -- Redundant (difficulty too low, required enemies absent)
				end
			end
		end

		-- Check min_difficulty: redundant if difficulty >= min (enemies already present)
		if modifier.min_difficulty then
			local min_level = get_diff_level(modifier.min_difficulty)
			if current_level >= min_level then
				return true -- Redundant (difficulty too high, enemies already present)
			end
		end

		-- Check max_difficulty: redundant if difficulty >= max (enemies already present)
		-- max_difficulty = "overkill" means the modifier is useful BELOW Overkill (Normal, Hard)
		-- At Overkill enemies are already present, so the modifier is redundant
		if modifier.max_difficulty then
			local max_level = get_diff_level(modifier.max_difficulty)
			if current_level >= max_level then
				return true -- Redundant (enemies already present at this difficulty)
			else
			end
		end

		return false -- Modifier is useful
	end

	-- Count valid modifiers at the current difficulty
	-- (used to compute MAX_LEVEL)
	local function count_valid_modifiers(modifiers, difficulty)
		local count = 0
		for _, mod in ipairs(modifiers) do
			-- Check modifier without considering unlocks (empty list)
			-- This gives the base count of modifiers available at this difficulty
			if not is_modifier_redundant(mod, difficulty, {}) then
				count = count + 1
			end
		end
		return count
	end

	-- Compute MAX_LEVEL based on the number of valid modifiers
	-- Vanilla loud modifiers appear every 100 levels (even intervals)
	-- Therefore MAX_LEVEL = valid_mod_count * 100
	local valid_loud_count = count_valid_modifiers(vanilla_loud_modifiers, current_difficulty)
	local MAX_LEVEL = valid_loud_count * 100

	-- Export for difficulty_select.lua (starting level buttons)
	-- Excludes modifiers with skip_level_count=true (unlock helpers, not real difficulty mods)
	local countable_loud = 0
	for _, m in ipairs(vanilla_loud_modifiers) do
		if not m.skip_level_count then
			countable_loud = countable_loud + 1
		end
	end
	_G.CSR_TotalLoudModifiers = countable_loud

	-- === STEALTH MODIFIERS WITH PROGRESSION ===
	local stealth_progressions = {
		less_pagers = {
			{
				id = "csr_less_pagers_1",
				class = "ModifierCSRLessPagers1",
				icon = "crime_spree_pager",
				data = { count = { 1, "max" } },
			},
			{
				id = "csr_less_pagers_2",
				class = "ModifierCSRLessPagers2",
				icon = "crime_spree_pager",
				data = { count = { 2, "max" } },
			},
			{
				id = "csr_less_pagers_3",
				class = "ModifierCSRLessPagers3",
				icon = "crime_spree_pager",
				data = { count = { 3, "max" } },
			},
			{
				id = "csr_less_pagers_4",
				class = "ModifierCSRLessPagers4",
				icon = "crime_spree_pager",
				data = { count = { 4, "max" } },
			},
		},
		civilian_alarm = {
			{
				id = "csr_civilian_alarm_1",
				class = "ModifierCSRCivilianAlarm1",
				icon = "crime_spree_civs_killed",
				data = { count = { 10, "min" } },
			},
			{
				id = "csr_civilian_alarm_2",
				class = "ModifierCSRCivilianAlarm2",
				icon = "crime_spree_civs_killed",
				data = { count = { 7, "min" } },
			},
			{
				id = "csr_civilian_alarm_3",
				class = "ModifierCSRCivilianAlarm3",
				icon = "crime_spree_civs_killed",
				data = { count = { 4, "min" } },
			},
		},
		less_concealment = {}, -- Generated dynamically
	}

	-- Generate infinite Less Concealment tiers (up to 72 concealment)
	-- Player min concealment: 3, max: 75, so increase range: 75-3=72
	local MAX_CONCEALMENT = 72
	local CONCEALMENT_PER_TIER = 3
	local max_concealment_tiers = math.floor(MAX_CONCEALMENT / CONCEALMENT_PER_TIER) -- 24 tiers

	for tier = 1, max_concealment_tiers do
		table.insert(stealth_progressions.less_concealment, {
			id = "csr_less_concealment_" .. tier,
			class = "ModifierCSRLessConcealment",
			icon = "crime_spree_concealment",
			data = { conceal = { CONCEALMENT_PER_TIER, "add" } },
		})
	end

	local stealth_types = { "less_pagers", "civilian_alarm", "less_concealment" }

	-- === FORCED MODIFIER GENERATION ===
	-- 3 separate streams: HP/Damage (every level), Loud (every 25), Stealth (every 20)
	local forced_modifiers = {} -- All modifiers (for UI in modifiers.forced)
	local stealth_modifiers = {} -- Stealth only (for repeating_modifiers.stealth)
	local loud_modifiers = {} -- Loud only (for repeating_modifiers.forced)
	local stealth_levels = { less_pagers = 0, civilian_alarm = 0, less_concealment = 0 }

	-- Compute maximum level for stealth (all tiers)
	local total_stealth_tiers = #stealth_progressions.less_pagers
		+ #stealth_progressions.civilian_alarm
		+ #stealth_progressions.less_concealment
	local MAX_STEALTH_LEVEL = total_stealth_tiers * STEALTH_INTERVAL + STEALTH_START

	-- Cap generation at a reasonable level (1000)
	-- Once tiers are exhausted, stealth modifiers will cycle
	local max_generation_level = math.min(math.max(MAX_LEVEL, MAX_STEALTH_LEVEL), 1000)

	-- Pre-compute which levels are occupied by Loud and Stealth
	local loud_levels = {}
	local stealth_level_set = {}

	-- Loud: every 25 levels (25, 50, 75...)
	for level = LOUD_INTERVAL, MAX_LEVEL, LOUD_INTERVAL do
		loud_levels[level] = true
	end

	-- Stealth: every 20 levels starting at 20 (20, 40, 60, 80...)
	for level = STEALTH_START, max_generation_level, STEALTH_INTERVAL do
		stealth_level_set[level] = true
	end

	-- Generate modifiers for each level
	for level = 1, max_generation_level do
		-- Priority: Stealth > Loud > HP/Damage
		-- BUT: if the level matches both intervals, add BOTH modifiers
		local stealth_added = false

		if stealth_level_set[level] then
			-- === STEALTH ===
			local all_stealth_exhausted = true
			for _, st in ipairs(stealth_types) do
				if stealth_levels[st] < #stealth_progressions[st] then
					all_stealth_exhausted = false
					break
				end
			end

			if not all_stealth_exhausted then
				local type_index = deterministic_index(level, #stealth_types, current_seed)
				local mod_type_name = stealth_types[type_index]
				local current_tier = stealth_levels[mod_type_name]
				local progression = stealth_progressions[mod_type_name]

				if current_tier >= #progression then
					for _, st in ipairs(stealth_types) do
						if stealth_levels[st] < #stealth_progressions[st] then
							mod_type_name = st
							current_tier = stealth_levels[st]
							progression = stealth_progressions[st]
							break
						end
					end
				end

				if current_tier < #progression then
					local next_tier = current_tier + 1
					stealth_levels[mod_type_name] = next_tier
					local template = progression[next_tier]
					local mod = {
						id = template.id,
						class = template.class,
						icon = template.icon,
						level = level,
						data = template.data,
					}
					table.insert(forced_modifiers, mod)
					table.insert(stealth_modifiers, clone(mod))
					stealth_added = true
					-- else: all tiers exhausted, skip (HP/DMG applied via snapshots)
				end
				-- else: all stealth exhausted, skip (HP/DMG applied via snapshots)
			end
		end

		-- === LOUD (Vanilla) ===
		-- Separate check (not elseif) so both Stealth and Loud can be added on shared levels
		if loud_levels[level] then
			-- === LOUD (Vanilla) ===
			local index = deterministic_index(level, #vanilla_loud_modifiers, current_seed)
			local template = vanilla_loud_modifiers[index]

			-- Check redundancy and class duplication
			local is_redundant = is_modifier_redundant(template, current_difficulty, forced_modifiers)
			local is_duplicate = is_class_already_used(template.class, forced_modifiers)

			if is_redundant then
			end
			if is_duplicate then
			end

			if is_redundant or is_duplicate then
				local original_index = index
				local attempts = 0

				repeat
					index = (index % #vanilla_loud_modifiers) + 1
					template = vanilla_loud_modifiers[index]
					attempts = attempts + 1

					local temp_redundant = is_modifier_redundant(template, current_difficulty, forced_modifiers)
					local temp_duplicate = is_class_already_used(template.class, forced_modifiers)

				until (
						not is_modifier_redundant(template, current_difficulty, forced_modifiers)
						and not is_class_already_used(template.class, forced_modifiers)
					) or attempts >= #vanilla_loud_modifiers

				if attempts >= #vanilla_loud_modifiers then
				else
					local mod = {
						id = template.id .. "_" .. level,
						class = template.class,
						icon = template.icon,
						level = level,
						data = template.data,
					}
					table.insert(forced_modifiers, mod)
					table.insert(loud_modifiers, clone(mod))
				end
			else
				local mod = {
					id = template.id .. "_" .. level,
					class = template.class,
					icon = template.icon,
					level = level,
					data = template.data,
				}
				table.insert(forced_modifiers, mod)
				table.insert(loud_modifiers, clone(mod))
			end

			-- else: HP/Damage every level, skip here (applied via snapshots)
		end
	end

	-- === VALIDATION: MISSING MODIFIERS ===
	-- Verify that each level divisible by LOUD_INTERVAL has at least 1 loud modifier

	for level = LOUD_INTERVAL, max_generation_level, LOUD_INTERVAL do
		local has_loud = false
		for _, mod in ipairs(loud_modifiers) do
			if mod.level == level then
				has_loud = true
				break
			end
		end

		if not has_loud then
			-- Count how many valid modifiers are available in total
			local valid_count = 0
			for _, template in ipairs(vanilla_loud_modifiers) do
				if
					not is_modifier_redundant(template, current_difficulty, forced_modifiers)
					and not is_class_already_used(template.class, forced_modifiers)
				then
					valid_count = valid_count + 1
				end
			end

			-- Find the first valid modifier
			local found = false
			for i, template in ipairs(vanilla_loud_modifiers) do
				local temp_redundant = is_modifier_redundant(template, current_difficulty, forced_modifiers)
				local temp_duplicate = is_class_already_used(template.class, forced_modifiers)

				if not temp_redundant and not temp_duplicate then
					local mod = {
						id = template.id .. "_" .. level,
						class = template.class,
						icon = template.icon,
						level = level,
						data = template.data,
					}
					table.insert(forced_modifiers, mod)
					table.insert(loud_modifiers, clone(mod))
					found = true
					break
				end
			end

			if not found then
			end
		end
	end

	-- === BUILD MODIFIER ARRAYS ===
	-- modifiers.forced is used by vanilla _get_modifiers and must contain dummy slots
	-- repeating_modifiers.forced contains the real modifiers without dummies

	-- Build flat list of all modifiers (stealth + loud) sorted by level
	local all_modifiers = {}
	for _, mod in ipairs(stealth_modifiers) do
		table.insert(all_modifiers, mod)
	end
	for _, mod in ipairs(loud_modifiers) do
		table.insert(all_modifiers, mod)
	end
	-- Sort by level
	table.sort(all_modifiers, function(a, b)
		return a.level < b.level
	end)

	for _, mod in ipairs(all_modifiers) do
	end

	-- Build combined_modifiers - simply use all_modifiers directly
	-- The vanilla system can show multiple modifiers at once
	-- If level 20 has both Loud + Stealth, both appear in the popup
	local combined_modifiers = {}

	for i, mod in ipairs(all_modifiers) do
		table.insert(combined_modifiers, mod)
	end

	-- Apply modifiers
	self.modifiers.forced = combined_modifiers
	self.modifiers.stealth = {} -- Unused
	-- self.modifiers.loud is already set to player_buffs above (line 48) - DO NOT OVERWRITE!

	-- repeating_modifiers - for the "FORCED MODIFIERS" popup (all real modifiers)
	self.repeating_modifiers = self.repeating_modifiers or {}
	self.repeating_modifiers.forced = all_modifiers

	-- Populate persistent lookup table (old IDs keep data across seed regenerations)
	_G.CSR_ForcedModifierLookup = _G.CSR_ForcedModifierLookup or {}
	for _, mod in ipairs(all_modifiers) do
		if mod.id then
			_G.CSR_ForcedModifierLookup[mod.id] = mod
		end
	end

	-- Final log

	-- === UPDATE SEED FILE IF REGENERATION OCCURRED ===
	if needs_regeneration then
		local update_file = io.open(SEED_FILE, "w")
		if update_file then
			update_file:write(tostring(current_seed) .. "\n")
			update_file:write(current_difficulty .. "\n")
			update_file:write(CURRENT_VERSION .. "\n")
			-- Preserve lines 4-7 from original file
			if _extra_lines then
				for _, line in ipairs(_extra_lines) do
					update_file:write(line .. "\n")
				end
			else
				update_file:write("0\n\n\n0.01|0")
			end
			update_file:close()
		end
	end

	-- === EXPORT REGENERATION FUNCTION FOR SEED_MANAGER ===
	-- Closure captures all local variables (modifier tables, helpers)
	_G.CSR_RegenerateForcedMods = function(new_seed, difficulty)
		local regen_diff = difficulty or CSR_CurrentDifficulty or "normal"
		local regen_valid = count_valid_modifiers(vanilla_loud_modifiers, regen_diff)

		-- Detailed list of valid/invalid modifiers
		for i, template in ipairs(vanilla_loud_modifiers) do
			local is_valid = not is_modifier_redundant(template, regen_diff, {})
		end

		local regen_max_level = regen_valid * 100

		local regen_all = {} -- All modifiers (for modifiers.forced)
		local regen_stealth_mods = {} -- Stealth only (for repeating_modifiers.stealth)
		local regen_loud_mods = {} -- Loud only (for repeating_modifiers.forced)
		local regen_stealth = { less_pagers = 0, civilian_alarm = 0, less_concealment = 0 }
		local regen_max_stealth = total_stealth_tiers * STEALTH_INTERVAL + STEALTH_START
		local regen_max_gen = math.min(math.max(regen_max_level, regen_max_stealth), 1000)

		local regen_loud_set = {}
		for l = LOUD_INTERVAL, regen_max_level, LOUD_INTERVAL do
			regen_loud_set[l] = true
		end

		local regen_stealth_set = {}
		for l = STEALTH_START, regen_max_gen, STEALTH_INTERVAL do
			regen_stealth_set[l] = true
		end

		for level = 1, regen_max_gen do
			-- If the level matches both intervals, add BOTH modifiers
			local regen_stealth_added = false

			if regen_stealth_set[level] then
				-- STEALTH
				local all_exhausted = true
				for _, st in ipairs(stealth_types) do
					if regen_stealth[st] < #stealth_progressions[st] then
						all_exhausted = false
						break
					end
				end

				if not all_exhausted then
					local ti = deterministic_index(level, #stealth_types, new_seed)
					local mtn = stealth_types[ti]
					local ct = regen_stealth[mtn]
					local prog = stealth_progressions[mtn]

					if ct >= #prog then
						for _, st in ipairs(stealth_types) do
							if regen_stealth[st] < #stealth_progressions[st] then
								mtn = st
								ct = regen_stealth[st]
								prog = stealth_progressions[st]
								break
							end
						end
					end

					if ct < #prog then
						local nt = ct + 1
						regen_stealth[mtn] = nt
						local tmpl = prog[nt]
						local mod = {
							id = tmpl.id,
							class = tmpl.class,
							icon = tmpl.icon,
							level = level,
							data = tmpl.data,
						}
						table.insert(regen_all, mod)
						table.insert(regen_stealth_mods, clone(mod))
						regen_stealth_added = true
						-- else: all tiers exhausted, skip (HP/DMG applied via snapshots)
					end
					-- else: all stealth exhausted, skip (HP/DMG applied via snapshots)
				end
			end

			if regen_loud_set[level] then
				-- LOUD
				local idx = deterministic_index(level, #vanilla_loud_modifiers, new_seed)
				local tmpl = vanilla_loud_modifiers[idx]

				-- Check redundancy and class duplication
				if
					is_modifier_redundant(tmpl, regen_diff, regen_all) or is_class_already_used(tmpl.class, regen_all)
				then
					local attempts = 0
					repeat
						idx = (idx % #vanilla_loud_modifiers) + 1
						tmpl = vanilla_loud_modifiers[idx]
						attempts = attempts + 1
					until (
							not is_modifier_redundant(tmpl, regen_diff, regen_all)
							and not is_class_already_used(tmpl.class, regen_all)
						) or attempts >= #vanilla_loud_modifiers

					if attempts >= #vanilla_loud_modifiers then
						-- All vanilla modifiers redundant, skip (HP/DMG applied via snapshots)
					else
						local mod = {
							id = tmpl.id .. "_" .. level,
							class = tmpl.class,
							icon = tmpl.icon,
							level = level,
							data = tmpl.data,
						}
						table.insert(regen_all, mod)
						table.insert(regen_loud_mods, clone(mod))
					end
				else
					local mod = {
						id = tmpl.id .. "_" .. level,
						class = tmpl.class,
						icon = tmpl.icon,
						level = level,
						data = tmpl.data,
					}
					table.insert(regen_all, mod)
					table.insert(regen_loud_mods, clone(mod))
				end

				-- else: HP/DMG every level, skip here (applied via snapshots)
			end
		end

		-- Build flat list of all modifiers
		local regen_all = {}
		for _, mod in ipairs(regen_stealth_mods) do
			table.insert(regen_all, mod)
		end
		for _, mod in ipairs(regen_loud_mods) do
			table.insert(regen_all, mod)
		end
		table.sort(regen_all, function(a, b)
			return a.level < b.level
		end)

		-- Use real modifiers directly (no dummy padding).
		-- Our _get_modifiers override reads from repeating_modifiers.forced,
		-- so modifiers.forced only needs to satisfy vanilla guard checks.
		tweak_data.crime_spree.modifiers.forced = regen_all
		tweak_data.crime_spree.modifiers.stealth = {}
		tweak_data.crime_spree.modifiers.loud = player_buffs
		tweak_data.crime_spree.repeating_modifiers = tweak_data.crime_spree.repeating_modifiers or {}
		tweak_data.crime_spree.repeating_modifiers.forced = regen_all

		-- Populate persistent lookup table (old IDs keep data across seed regenerations)
		_G.CSR_ForcedModifierLookup = _G.CSR_ForcedModifierLookup or {}
		for _, mod in ipairs(regen_all) do
			if mod.id then
				_G.CSR_ForcedModifierLookup[mod.id] = mod
			end
		end
	end

	-- Export redundancy check function for use in crimespree_filter.lua
	_G.CSR_IsModifierRedundant = is_modifier_redundant

	-- === SETTINGS ===
	self.start_levels = self.start_levels or {}
	self.start_levels.loud = 0 -- Player items
	self.start_levels.stealth = 0 -- Unused
	self.start_levels.forced = 0 -- Stealth+Loud combined

	self.modifier_levels = self.modifier_levels or {}
	self.modifier_levels.loud = 20 -- Player items (chosen). Must match LOUD_INTERVAL above.
	self.modifier_levels.stealth = 9999 -- Unused
	self.modifier_levels.forced = 20 -- Stealth+Loud combined (both every 20 levels)

	-- Starting level selection buttons restored
	-- Will be used in the future to start from higher levels
	self.starting_levels = { 0, 50, 100, 200, 500 }
	self.allow_highscore_continue = false -- Disabled for now

	-- Free starting levels: zero out the cost so vanilla never deducts coins
	self.initial_cost = 0
	self.cost_per_level = 0

	-- === DIFFICULTY REWARD MODIFICATION ===
	-- Keys are DISPLAY names (stored in seed file), not internal game IDs
	local difficulty = current_difficulty or "normal"

	-- Cash multipliers (separate table for future tuning)
	local cash_multipliers = {
		normal = 0.12,
		hard = 0.25,
		very_hard = 0.52,
		overkill = 1.0,
		mayhem = 1.28,
		death_wish = 1.41,
		death_sentence = 1.68,
	}

	-- XP/Coins multipliers (normalized to Overkill = 1.0)
	local xp_multipliers = {
		normal = 0.12,
		hard = 0.25,
		very_hard = 0.52,
		overkill = 1.0,
		mayhem = 1.28,
		death_wish = 1.41,
		death_sentence = 1.68,
	}

	local cash_mult = cash_multipliers[difficulty] or 1.0
	local xp_mult = xp_multipliers[difficulty] or 1.0

	-- Apply per-reward-type multipliers directly to tweakdata
	-- This is the ONLY place rewards are scaled — no runtime override needed
	if self.rewards then
		for _, reward in ipairs(self.rewards) do
			if reward.id == "cash" then
				reward.amount = reward.amount * cash_mult
			elseif reward.id == "experience" or reward.id == "continental_coins" then
				reward.amount = reward.amount * xp_mult
			elseif reward.id == "loot_drop" then
				-- 10 CS points = 1 card
				reward.amount = 0.1
			end
		end
	end
end)
