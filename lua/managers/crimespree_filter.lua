-- Crime Spree Roguelike Alpha 1 - Item filter for UI only

if not RequiredScript then
	return
end


-- Function to check if modifier is our item
local function is_player_item(mod_id)
	if not mod_id then return false end
	return string.find(mod_id, "player_health_boost", 1, true) ~= nil or
	       string.find(mod_id, "player_damage_boost", 1, true) ~= nil or
	       string.find(mod_id, "player_dozer_guide", 1, true) ~= nil or
	       string.find(mod_id, "player_bonnie_chip", 1, true) ~= nil or
	       string.find(mod_id, "player_glass_pistol", 1, true) ~= nil or
	       string.find(mod_id, "player_car_keys", 1, true) ~= nil or
	       string.find(mod_id, "player_plush_shark", 1, true) ~= nil or
	       string.find(mod_id, "player_wolfs_toolbox", 1, true) ~= nil or
	       string.find(mod_id, "player_duct_tape", 1, true) ~= nil or
	       string.find(mod_id, "player_escape_plan", 1, true) ~= nil or
	       string.find(mod_id, "player_worn_bandaid", 1, true) ~= nil or
	       string.find(mod_id, "player_rebar_", 1, true) ~= nil or
	       string.find(mod_id, "player_overkill_rush_", 1, true) ~= nil or
	       string.find(mod_id, "player_pink_slip_", 1, true) ~= nil or
	       string.find(mod_id, "player_jiro_last_wish_", 1, true) ~= nil or
	       string.find(mod_id, "player_dearest_possession_", 1, true) ~= nil or
	       string.find(mod_id, "player_viklund_vinyl_", 1, true) ~= nil or
	       string.find(mod_id, "player_equalizer_", 1, true) ~= nil or
	       string.find(mod_id, "player_crooked_badge_", 1, true) ~= nil or
	       string.find(mod_id, "player_dead_mans_trigger_", 1, true) ~= nil
end

-- Global flag for filtering (enabled only in UI)
CSR_FilterForUI = false

-- Cache of offered items (so they don't change on cancel)
CSR_CachedModifierOffer = nil
-- Generation counter for unique seed
CSR_GenerationCounter = 0
-- Number of active modifiers for tracking selection
CSR_LastModifierCount = 0
-- Flag: first _get_modifiers call must initialize count without side effects
CSR_ModifierCountInitialized = false

-- Flag for forced modifiers (show only once on lobby creation)
CSR_ForcedModifiersReturned = false
CSR_ForcedModifiersCache = nil
CSR_LastForcedLevel = 0

-- Persistent lookup table: old modifier IDs keep their data across seed regenerations
_G.CSR_ForcedModifierLookup = _G.CSR_ForcedModifierLookup or {}

-- Function to get item type by id
local function get_item_type(mod_id)
	if not mod_id then return nil end
	if string.find(mod_id, "player_health_boost", 1, true) then
		return "health"
	elseif string.find(mod_id, "player_damage_boost", 1, true) then
		return "damage"
	elseif string.find(mod_id, "player_dozer_guide", 1, true) then
		return "dozer_guide"
	elseif string.find(mod_id, "player_bonnie_chip", 1, true) then
		return "bonnie_chip"
	elseif string.find(mod_id, "player_glass_pistol", 1, true) then
		return "glass_pistol"
	elseif string.find(mod_id, "player_car_keys", 1, true) then
		return "car_keys"
	elseif string.find(mod_id, "player_plush_shark", 1, true) then
		return "plush_shark"
	elseif string.find(mod_id, "player_wolfs_toolbox", 1, true) then
		return "wolfs_toolbox"
	elseif string.find(mod_id, "player_duct_tape", 1, true) then
		return "duct_tape"
	elseif string.find(mod_id, "player_escape_plan", 1, true) then
		return "escape_plan"
	elseif string.find(mod_id, "player_worn_bandaid", 1, true) then
		return "worn_bandaid"
	elseif string.find(mod_id, "player_rebar_", 1, true) then
		return "rebar"
	elseif string.find(mod_id, "player_overkill_rush_", 1, true) then
		return "overkill_rush"
	elseif string.find(mod_id, "player_pink_slip_", 1, true) then
		return "pink_slip"
	elseif string.find(mod_id, "player_jiro_last_wish_", 1, true) then
		return "jiro_last_wish"
	elseif string.find(mod_id, "player_dearest_possession_", 1, true) then
		return "dearest_possession"
	elseif string.find(mod_id, "player_viklund_vinyl_", 1, true) then
		return "viklund_vinyl"
	elseif string.find(mod_id, "player_equalizer_", 1, true) then
		return "equalizer"
	elseif string.find(mod_id, "player_crooked_badge_", 1, true) then
		return "crooked_badge"
	elseif string.find(mod_id, "player_dead_mans_trigger_", 1, true) then
		return "dead_mans_trigger"
	end
	return nil  -- Not our item
end

-- Hook on server_active_modifiers - filter ONLY when flag is enabled
if CrimeSpreeManager then
	local original_server_active_modifiers = CrimeSpreeManager.server_active_modifiers

	function CrimeSpreeManager:server_active_modifiers()
		local modifiers = original_server_active_modifiers(self)

		if not modifiers then return modifiers end

		-- Filter our items AND HP/DMG modifiers AND dummy modifiers
		-- Dummy modifiers filtered ALWAYS (not only in UI)
		local filtered = {}

		for _, mod_data in ipairs(modifiers) do
			-- Skip dummy modifiers (always, regardless of flag)
			if mod_data.id and string.find(mod_data.id, "csr_dummy", 1, true) then
				-- skip
			-- Filter everything else only when flag is enabled (for UI MODIFIERS tab)
			elseif CSR_FilterForUI then
				-- Skip HP/DMG modifiers (if there are old ones)
				if mod_data.id and string.find(mod_data.id, "csr_enemy_hp_damage", 1, true) then
					-- skip
				-- v2.49: Skip player items (DOG TAGS, GLASS PISTOL, etc.) - they have their own ITEMS tab
				elseif mod_data.id and string.find(mod_data.id, "player_", 1, true) then
					-- skip
				else
					table.insert(filtered, mod_data)
				end
			else
				-- Flag disabled - keep everything except dummy
				table.insert(filtered, mod_data)
			end
		end

		-- Add virtual HP/DMG modifier only if flag is enabled (for UI)
		if CSR_FilterForUI then
			-- Check if snapshots exist (instead of searching for HP/DMG in list)
			local hp_bonus, dmg_bonus = CSR_GetTotalHPDamageBonus()

			if hp_bonus > 0 or dmg_bonus > 0 then
				-- Add one virtual modifier for all snapshots
				table.insert(filtered, {
					id = "csr_enemy_hp_damage_total",
					class = "ModifierEnemyHealthAndDamage",
					icon = "crime_spree_health",
					level = 0,
					data = {
						-- For UI display
						total_hp = hp_bonus * 100,	-- In percentages
						total_dmg = dmg_bonus * 100	-- In percentages
					}
				})
			else
			end
		end

		return filtered
	end


	-- Override get_modifier: return data for the virtual HP/DMG combined modifier
	local original_get_modifier = CrimeSpreeManager.get_modifier

	function CrimeSpreeManager:get_modifier(id)
		if id == "csr_enemy_hp_damage_total" then
			return {
				id = "csr_enemy_hp_damage_total",
				class = "ModifierEnemyHealthAndDamage",
				icon = "crime_spree_health",
				level = 0,
				data = {}
			}
		end
		return original_get_modifier(self, id)
	end


	-- Override active_modifiers — strip dummy modifiers so the FORCED MODIFIERS popup works correctly
	local original_active_modifiers = CrimeSpreeManager.active_modifiers

	function CrimeSpreeManager:active_modifiers()
		local modifiers = original_active_modifiers(self)

		if not modifiers then return modifiers end

		-- Remove internal dummy padding modifiers before returning
		local filtered = {}
		for _, mod_data in ipairs(modifiers) do
			if mod_data.id and string.find(mod_data.id, "csr_dummy", 1, true) then
				-- skip dummy
			else
				table.insert(filtered, mod_data)
			end
		end

		return filtered
	end


	-- Override make_modifier_description
	-- PROBLEM: vanilla get_modifier() can't find our csr_*_20 modifiers because they have
	-- no suffix in tweakdata, so pairs(data.data) crashes on nil.
	-- FIX: for our modifiers we look up data in repeating_modifiers.forced instead
	local original_make_modifier_description = CrimeSpreeManager.make_modifier_description

	function CrimeSpreeManager:make_modifier_description(id, ...)
		-- Virtual HP/DMG display modifier (not a real modifier, just shows totals)
		if id == "csr_enemy_hp_damage_total" then
			local hp_bonus, dmg_bonus = CSR_GetTotalHPDamageBonus()
			local lang = CSR_Settings and CSR_Settings:GetLanguage() or "en"

			if lang == "ru" then
				return string.format("Здоровье врагов: +%.1f%%  |  Урон врагов: +%.1f%%", hp_bonus * 100, dmg_bonus * 100)
			else
				return string.format("Enemy HP: +%.1f%%  |  Enemy Damage: +%.1f%%", hp_bonus * 100, dmg_bonus * 100)
			end
		end


		-- Forced modifiers (csr_*) — look up data in the persistent lookup, then in repeating_modifiers.forced
		if string.find(id, "^csr_") then
			-- Check persistent lookup first — it retains data across seed regenerations
			local mod_data = _G.CSR_ForcedModifierLookup and _G.CSR_ForcedModifierLookup[id] or nil

			-- Fallback: search repeating_modifiers.forced
			if not mod_data then
				if tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.repeating_modifiers then
					local forced = tweak_data.crime_spree.repeating_modifiers.forced or {}
					for _, m in ipairs(forced) do
						if m.id == id then
							mod_data = m
							break
						end
					end
				end
			end

			if not mod_data then
				return ""  -- Not found — return empty string
			end

			-- Resolve the modifier class
			local modifier_class = _G[mod_data.class]
			if not modifier_class or not modifier_class.desc_id then
				return ""  -- Class missing or has no desc_id
			end

			-- Build params table from data (mirrors vanilla behaviour)
			local params = {}
			if mod_data.data then
				for key, dat in pairs(mod_data.data) do
					if type(dat) == "table" and dat[1] then
						params[key] = dat[1]
					end
				end
			end

			-- Return the localised description
			return managers.localization:text(modifier_class.desc_id, params)
		end

		-- Player items (player_*) — our custom items.
		-- Vanilla make_modifier_description() tries pairs(mod.data) from tweak_data,
		-- but player_* items don't exist there → crash.
		-- We resolve the description via the modifier class's desc_id instead.
		if string.find(id, "^player_") then
			-- Look up item data in the cached offer or in active_modifiers
			local mod_data = nil
			if CSR_CachedModifierOffer then
				for _, mod in ipairs(CSR_CachedModifierOffer) do
					if mod.id == id then
						mod_data = mod
						break
					end
				end
			end
			if not mod_data then
				for _, mod in ipairs(self:active_modifiers() or {}) do
					if mod.id == id then
						mod_data = mod
						break
					end
				end
			end

			if mod_data and mod_data.class then
				local modifier_class = _G[mod_data.class]
				if modifier_class and modifier_class.desc_id then
					return managers.localization:text(modifier_class.desc_id)
				end
			end

			return ""
		end

		return original_make_modifier_description(self, id, ...)
	end


	-- On-the-fly modifier factory: builds a fresh modifier table for the given item type
	local function generate_new_modifier(item_type, next_id)
		local class_map = {
			health = "ModifierDogTags",
			damage = "ModifierEvidenceRounds",
			dozer_guide = "ModifierDozerGuide",
			bonnie_chip = "ModifierBonniesLuckyChip",
			glass_pistol = "ModifierGlassCannon",
			car_keys = "ModifierCarKeys",
			plush_shark = "ModifierPlushShark",
			wolfs_toolbox = "ModifierWolfsToolbox",
			duct_tape = "ModifierDuctTape",
			escape_plan = "ModifierEscapePlan",
			worn_bandaid = "ModifierWornBandAid",
			overkill_rush = "ModifierOverkillRush",
			pink_slip = "ModifierPinkSlip",
			jiro_last_wish = "ModifierJiroLastWish",
			dearest_possession = "ModifierDearestPossession",
			viklund_vinyl = "ModifierViklundVinyl",
			rebar = "ModifierPieceOfRebar",
		equalizer = "ModifierEqualizer",
		crooked_badge = "ModifierCrookedBadge",
		dead_mans_trigger = "ModifierDeadMansTrigger"
		}
		local icon_map = {
			health = "csr_dog_tags",
			damage = "csr_bullets",
			dozer_guide = "crime_spree_more_dozers",
			bonnie_chip = "csr_bonnie_chip",
			glass_pistol = "csr_glass_pistol",
			car_keys = "csr_falcogini_keys",
			plush_shark = "csr_plush_shark",
			wolfs_toolbox = "csr_toolbox",
			duct_tape = "csr_duct_tape",
			escape_plan = "csr_escape_plan",
			worn_bandaid = "csr_worn_bandaid",
			overkill_rush = "csr_overkill_rush",
			pink_slip = "csr_pink_slip",
			jiro_last_wish = "csr_jiro_last_wish",
			dearest_possession = "csr_dearest_possession",
			viklund_vinyl = "csr_viklund_vinyl",
			rebar = "csr_rebar",
		equalizer = "csr_equalizer",
		crooked_badge = "csr_crooked_badge",
		dead_mans_trigger = "csr_dead_mans_trigger"
		}
		local id_prefix = {
			health = "player_health_boost_",
			damage = "player_damage_boost_",
			dozer_guide = "player_dozer_guide_",
			bonnie_chip = "player_bonnie_chip_",
			glass_pistol = "player_glass_pistol_",
			car_keys = "player_car_keys_",
			plush_shark = "player_plush_shark_",
			wolfs_toolbox = "player_wolfs_toolbox_",
			duct_tape = "player_duct_tape_",
			escape_plan = "player_escape_plan_",
			worn_bandaid = "player_worn_bandaid_",
			overkill_rush = "player_overkill_rush_",
			pink_slip = "player_pink_slip_",
			jiro_last_wish = "player_jiro_last_wish_",
			dearest_possession = "player_dearest_possession_",
			viklund_vinyl = "player_viklund_vinyl_",
			rebar = "player_rebar_",
		equalizer = "player_equalizer_",
		crooked_badge = "player_crooked_badge_",
		dead_mans_trigger = "player_dead_mans_trigger_"
		}

		if not class_map[item_type] then return nil end

		return {
			id = id_prefix[item_type] .. next_id,
			class = class_map[item_type],
			icon = icon_map[item_type],
			level = 0,  -- Player items have no level (chosen by the player, not scaled)
			data = {}
		}
	end

	-- Determine the next numeric ID suffix for a new copy of the given item type
	local function get_next_id(item_type)
		local active_mods = managers.crime_spree:active_modifiers() or {}
		local max_id = 0  -- Start from 0 (dynamic generation; no pre-seeded copies)

		local id_prefix = {
			health = "player_health_boost_",
			damage = "player_damage_boost_",
			bonnie_chip = "player_bonnie_chip_",
			dozer_guide = "player_dozer_guide_",
			glass_pistol = "player_glass_pistol_",
			car_keys = "player_car_keys_",
			plush_shark = "player_plush_shark_",
			wolfs_toolbox = "player_wolfs_toolbox_",
			duct_tape = "player_duct_tape_",
			escape_plan = "player_escape_plan_",
			worn_bandaid = "player_worn_bandaid_",
			overkill_rush = "player_overkill_rush_",
			pink_slip = "player_pink_slip_",
			jiro_last_wish = "player_jiro_last_wish_",
			dearest_possession = "player_dearest_possession_",
			viklund_vinyl = "player_viklund_vinyl_",
			rebar = "player_rebar_",
		equalizer = "player_equalizer_",
		crooked_badge = "player_crooked_badge_",
		dead_mans_trigger = "player_dead_mans_trigger_"
		}

		for _, mod_data in ipairs(active_mods) do
			if mod_data.id and string.find(mod_data.id, id_prefix[item_type], 1, true) then
				local num_str = string.match(mod_data.id, "_(%d+)$")
				if num_str then
					local num = tonumber(num_str)
					if num and num > max_id then
						max_id = num
					end
				end
			end
		end

		return max_id + 1
	end

	-- Returns true if the item type has Contraband rarity
	local function is_contraband(item_type)
		return item_type == "dozer_guide"
	end

	-- Fix 1: Override modifiers_to_select for "loud" — own count instead of vanilla
	-- Vanilla formula breaks because #modifiers.loud grows as we generate new items
	local original_modifiers_to_select = CrimeSpreeManager.modifiers_to_select
	function CrimeSpreeManager:modifiers_to_select(table_name, add_repeating)
		if table_name == "loud" then
			local level = (self.server_spree_level and self:server_spree_level()) or self:spree_level() or 0
			local expected = math.floor(level / 20)
			-- Count how many player_* items have already been chosen
			local selected = 0
			for _, mod in ipairs(self:active_modifiers() or {}) do
				if mod.id and string.find(mod.id, "player_", 1, true) == 1 then
					selected = selected + 1
				end
			end
			local result = math.max(expected - selected, 0)
			return result
		end
		return original_modifiers_to_select(self, table_name, add_repeating)
	end

	-- Override _get_modifiers — infinite item pool generation
	local original_get_modifiers = CrimeSpreeManager._get_modifiers

	function CrimeSpreeManager:_get_modifiers(table_name, max_count, add_repeating)
		-- v2.50: Debug logging for item generation

		-- Get vanilla result first
		local result = original_get_modifiers(self, table_name, max_count, add_repeating)
		
		-- Always strip dummy modifiers from the result regardless of table type
		if result and #result > 0 then
			local filtered = {}
			for _, mod_data in ipairs(result) do
				if not (mod_data.id and string.find(mod_data.id, "csr_dummy", 1, true)) then
					table.insert(filtered, mod_data)
				end
			end
			if #filtered ~= #result then
			end
			result = filtered
		end
		
		-- Handle "forced" table (HP/DMG + loud progression modifiers)
		if table_name == "forced" then
			local current_level = self:spree_level() or 0
			
			-- Invalidate cache when CS level changes
			if current_level ~= CSR_LastForcedLevel then
				CSR_ForcedModifiersReturned = false
				CSR_ForcedModifiersCache = nil
				CSR_LastForcedLevel = current_level
			end
			
			-- Return cached result — vanilla popup crashes if modifier list changes between calls
			if CSR_ForcedModifiersReturned and CSR_ForcedModifiersCache then
				return CSR_ForcedModifiersCache
			end
			

			-- Always rebuild from repeating_modifiers.forced — vanilla may return an incomplete list
			local repeating = tweak_data.crime_spree.repeating_modifiers and tweak_data.crime_spree.repeating_modifiers.forced or {}


			-- Track the highest level whose forced mods have already been shown
			_G.CSR_LastShownForcedLevel = _G.CSR_LastShownForcedLevel or 0
			local last_shown = _G.CSR_LastShownForcedLevel


			-- Collect all CS levels that have pending forced mods between last_shown and current
			local levels_with_mods = {}
			for _, mod in ipairs(repeating) do
				if mod.id and mod.level and mod.level > last_shown and mod.level <= current_level then
					if not levels_with_mods[mod.level] then
						levels_with_mods[mod.level] = true
					end
				end
			end

			-- Gather all forced mods from every pending level
			local forced_mods = {}
			for _, mod in ipairs(repeating) do
				if mod.id and mod.level and levels_with_mods[mod.level] then
					table.insert(forced_mods, mod)
				end
			end

			-- Populate persistent lookup with forced_mods (so old IDs keep their data)
			if _G.CSR_ForcedModifierLookup then
				for _, mod in ipairs(forced_mods) do
					if mod.id then
						_G.CSR_ForcedModifierLookup[mod.id] = mod
					end
				end
			end

			-- Filter out redundant modifiers (e.g. EnableBulldozers at Overkill difficulty)
			if _G.CSR_IsModifierRedundant and tweak_data.crime_spree.loud then
				local current_diff = Global.game_settings and Global.game_settings.difficulty or "normal"
				local vanilla_loud = tweak_data.crime_spree.loud or {}


				for i = #forced_mods, 1, -1 do
					local mod = forced_mods[i]
					-- Only process loud modifiers (not stealth / player items)
					if mod.class and not string.find(mod.id or "", "csr_", 1, true) and not string.find(mod.id or "", "player_", 1, true) then
						if _G.CSR_IsModifierRedundant(mod, current_diff, forced_mods) then

							-- Find a replacement from vanilla loud modifiers
							local replacement = nil
							for _, vanilla_mod in ipairs(vanilla_loud) do
								if not _G.CSR_IsModifierRedundant(vanilla_mod, current_diff, forced_mods) then
									-- Skip if a modifier of this class is already included
									local class_used = false
									for _, existing in ipairs(forced_mods) do
										if existing.class == vanilla_mod.class then
											class_used = true
											break
										end
									end

									if not class_used then
										replacement = vanilla_mod
										break
									end
								end
							end

							if replacement then
								-- Create a copy with the correct level from the original slot
								forced_mods[i] = {
									id = replacement.id .. "_" .. mod.level,
									class = replacement.class,
									icon = replacement.icon,
									level = mod.level,
									data = replacement.data
								}
							else
								-- No valid replacement — drop the redundant modifier
								table.remove(forced_mods, i)
							end
						end
					end
				end
			end

			-- Build sorted level list for updating CSR_LastShownForcedLevel
			local level_list = {}
			for level, _ in pairs(levels_with_mods) do
				table.insert(level_list, level)
			end
			table.sort(level_list)

			-- Advance CSR_LastShownForcedLevel immediately after generation —
			-- forced mods are applied automatically; the player never picks them.
			-- Only advance forward, never backward (guards against repeated calls)
			if #level_list > 0 then
				local max_level = level_list[#level_list]
				local current_last_shown = _G.CSR_LastShownForcedLevel or 0
				if max_level > current_last_shown then
					_G.CSR_LastShownForcedLevel = max_level
				else
				end
			end

			result = forced_mods

			
			-- Cache the result — vanilla popup requires identical modifiers on repeated calls
			CSR_ForcedModifiersReturned = true
			CSR_ForcedModifiersCache = result

			for i, mod in ipairs(result) do
			end
		end

		-- === AUTO-SAVE after every modifier change ===
		-- Read current modifier count for change detection
		local current_count = #(self:active_modifiers() or {})

		-- Track modifier count changes for auto-save and popup deduplication
		if not CSR_ModifierCountInitialized then
			-- First call: only initialise the counter, no side-effects.
			-- Prevents enemy forced mods (already in _global.modifiers on load) from
			-- falsely updating mission_selection_level and blocking the item popup.
			CSR_ModifierCountInitialized = true
		elseif current_count > CSR_LastModifierCount then

			-- Update mission_selection_level ONLY when the player picks a "loud" item.
			-- Do NOT update for "forced" (enemy mods) — otherwise vanilla sees
			-- mission_selection_level == spree_level and suppresses the item-selection popup.
			if table_name == "loud" then
				local current_level = self:spree_level()
				self._global.mission_selection_level = current_level

				CSR_CachedModifierOffer = nil
			end

			-- Auto-save: write to seed file after a short delay so the game has time to
			-- commit the new modifier to cs._global.modifiers before we read it
			DelayedCalls:Add("CSR_SaveAfterModifierSelection", 0.5, function()
				local cs = managers.crime_spree
				if cs and cs._global and cs._global.modifiers and #cs._global.modifiers > 0 then
					local seed = _G.CSR_CurrentSeed
					local difficulty = cs._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"

					if seed and CSR_SaveSeed then
						CSR_SaveSeed(seed, difficulty, cs._global.modifiers)

						-- Update the in-memory cache
						_G.CSR_SavedModifiers = {}
						for _, mod in ipairs(cs._global.modifiers) do
							table.insert(_G.CSR_SavedModifiers, {id = mod.id, level = mod.level})
						end
					end
				end
			end)
		end
		CSR_LastModifierCount = current_count

		-- Only the "loud" table uses our custom item-pool generator
		if table_name ~= "loud" then
			return result
		end


		-- Return cached offer if one exists (prevents re-rolling on subsequent calls)
		if CSR_CachedModifierOffer and #CSR_CachedModifierOffer > 0 then
			-- Trim the cache to max_count before returning
			if max_count and max_count > 0 and #CSR_CachedModifierOffer > max_count then
				local trimmed = {}
				for i = 1, max_count do
					trimmed[i] = CSR_CachedModifierOffer[i]
				end
				return trimmed
			end
			return CSR_CachedModifierOffer
		end

		-- Advance generation counter and seed the RNG
		CSR_GenerationCounter = (CSR_GenerationCounter or 0) + 1
		local unique_seed = os.clock() * 1000000 + current_count * 9999 + CSR_GenerationCounter
		math.randomseed(unique_seed)
		-- Warm up the RNG (first values after randomseed() can be predictable)
		for i = 1, 10 do math.random() end

		-- Fetch all available modifiers with no count limit
		local all_modifiers = original_get_modifiers(self, table_name, 9999, add_repeating)
		if not all_modifiers or #all_modifiers == 0 then
			all_modifiers = {}
		end
		
		-- Strip dummy modifiers from the full list
		local filtered_all = {}
		for _, mod_data in ipairs(all_modifiers) do
			if not (mod_data.id and string.find(mod_data.id, "csr_dummy", 1, true)) then
				table.insert(filtered_all, mod_data)
			end
		end
		all_modifiers = filtered_all
		

		-- Group available modifiers by item type
		local by_type = {
			health = {},
			damage = {},
			dozer_guide = {},
			bonnie_chip = {},
			glass_pistol = {},
			car_keys = {},
			plush_shark = {},
			wolfs_toolbox = {},
			duct_tape = {},
			escape_plan = {},
			worn_bandaid = {},
			overkill_rush = {},
			pink_slip = {},
			jiro_last_wish = {},
			dearest_possession = {},
			viklund_vinyl = {},
			rebar = {},
		equalizer = {},
		crooked_badge = {},
		dead_mans_trigger = {}
		}

		for _, mod_data in ipairs(all_modifiers) do
			local item_type = get_item_type(mod_data.id)
			if item_type and by_type[item_type] then
				table.insert(by_type[item_type], mod_data)
			end
		end

		-- INFINITE POOL: if any type has no entries, generate a fresh copy on the fly
		for type_name, items in pairs(by_type) do
			if #items == 0 then
				local next_id = get_next_id(type_name)
				local new_mod = generate_new_modifier(type_name, next_id)
				if new_mod then
					table.insert(items, new_mod)
				end
			end
		end

		-- Rarity weights for the weighted selection draw
		local rarity_weights = {
			health = 0.80,        -- Common (DOG TAGS)
			duct_tape = 0.80,     -- Common (DUCT TAPE)
			escape_plan = 0.80, -- Common (ESCAPE PLAN)
			worn_bandaid = 0.80,  -- Common (WORN BAND-AID)
			rebar = 0.80,         -- Common (PIECE OF REBAR)
			damage = 0.40,        -- Uncommon (EVIDENCE ROUNDS)
			car_keys = 0.40,      -- Uncommon (FALCOGINI KEYS)
			wolfs_toolbox = 0.40, -- Uncommon (WOLF'S TOOLBOX)
			overkill_rush = 0.40, -- Uncommon (OVERKILL RUSH)
			pink_slip = 0.40,     -- Uncommon (PINK SLIP)
			bonnie_chip = 0.04,        -- Rare (BONNIE'S LUCKY CHIP) - 4% chance
			plush_shark = 0.04,        -- Rare (PLUSH SHARK) - 4% chance
			jiro_last_wish = 0.04,     -- Rare (JIRO'S LAST WISH) - 4% chance
			dearest_possession = 0.04, -- Rare (DEAREST POSSESSION) - 4% chance
			viklund_vinyl = 0.04,      -- Rare (VIKLUND'S VINYL) - 4% chance
			dozer_guide = 0.08,        -- Contraband (DOZER GUIDE)
			glass_pistol = 0.08,       -- Contraband (GLASS PISTOL)
			equalizer = 0.08,          -- Contraband (EQUALIZER)
		crooked_badge = 0.08,      -- Contraband (CROOKED BADGE)
		dead_mans_trigger = 0.08   -- Contraband (DEAD MAN'S TRIGGER)
		}

		-- DEBUG MODE: Override individual item weights

		-- Weighted random draw helper
		local function weighted_random_choice(type_name, items)
			local weight = rarity_weights[type_name] or 1.0
			local roll = math.random()

			-- Roll succeeded — return a random item of this type
			if roll <= weight then
				local random_index = math.random(1, #items)
				return items[random_index]
			end

			return nil -- Did not win the roll
		end

		-- Fix 2: Weighted random WITHOUT replacement — guarantees 3 DIFFERENT item types
		-- Build a pool of {type, items, weight} entries for all types that have items
		local pool = {}
		for type_name, items in pairs(by_type) do
			if #items > 0 then
				table.insert(pool, {type = type_name, items = items, weight = rarity_weights[type_name] or 0.5})
			end
		end

		local result = {}
		for pick = 1, math.min(3, #pool) do
			-- Sum the weights of remaining pool entries
			local total_weight = 0
			for _, entry in ipairs(pool) do
				total_weight = total_weight + entry.weight
			end

			if total_weight <= 0 then break end

			-- Roll against cumulative weights
			local roll = math.random() * total_weight
			local cumulative = 0
			for idx, entry in ipairs(pool) do
				cumulative = cumulative + entry.weight
				if roll <= cumulative then
					-- Pick a random item from this type
					local random_item = entry.items[math.random(1, #entry.items)]
					table.insert(result, random_item)
					-- Remove this type from the pool (no duplicates)
					table.remove(pool, idx)
					break
				end
			end
		end

		-- Shuffle the final selection
		for i = #result, 2, -1 do
			local j = math.random(1, i)
			result[i], result[j] = result[j], result[i]
		end


		-- Trim to max_count — vanilla expects no more than 3 items in the popup
		if max_count and max_count > 0 and #result > max_count then
			local trimmed = {}
			for i = 1, max_count do
				trimmed[i] = result[i]
			end
			result = trimmed
		end

		-- Cache the offer for subsequent calls this popup cycle
		CSR_CachedModifierOffer = result

		-- Fix 1 (part 2): Do NOT push generated items back into tweak_data.crime_spree.modifiers.loud
		-- Previously that bloated the table and broke vanilla's modifiers_to_select count.
		-- New items are created via generate_new_modifier() above and only live in the returned list.

		return result
	end


	-- Hook on reset_crime_spree: clear caches before a new CS starts (prevents C++ popup crash)
	-- reset_crime_spree is called inside start_crime_spree BEFORE the popup is created
	Hooks:PostHook(CrimeSpreeManager, "reset_crime_spree", "CSR_ResetForcedCacheOnReset", function(self)
		CSR_ForcedModifiersReturned = false
		CSR_ForcedModifiersCache = nil
		CSR_LastForcedLevel = 0
		_G.CSR_LastShownForcedLevel = 0
		-- Reset modifier tracking (new CS run = start from zero)
		CSR_LastModifierCount = 0
		CSR_ModifierCountInitialized = false
	end)

end
