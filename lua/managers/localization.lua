-- Crime Spree Roguelike - Localization loader
-- U1 refactor: static strings live in loc/english.json (BAI-style flat-file
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
log("[CSR LOC] localization.lua loaded; LocalizationManagerPostInit hook + text override registered")
