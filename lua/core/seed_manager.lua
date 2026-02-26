-- Crime Spree Roguelike - Seed Manager
-- Manages seed for random modifier generation

if not RequiredScript then
	return
end



-- Path to seed file (in BLT saves folder)
local SEED_FILE = SavePath .. "crime_spree_seed.txt"

-- Global variables for seed and difficulty
CSR_CurrentSeed = CSR_CurrentSeed or nil
CSR_CurrentDifficulty = CSR_CurrentDifficulty or nil

-- Function to read seed, difficulty AND MODIFIERS from file
function CSR_LoadSeed()
	local file = io.open(SEED_FILE, "r")
	if file then
		local seed_line = file:read("*line")
		local difficulty_line = file:read("*line")
		local version_line = file:read("*line")
		local mission_selection_line = file:read("*line")  -- Line 4: mission_selection_level
		local forced_mods_line = file:read("*line")  -- Line 5: forced modifiers
		local player_items_line = file:read("*line") -- Line 6: player items
		file:close()

		local seed = tonumber(seed_line)
		if seed then
			CSR_CurrentSeed = seed
			CSR_CurrentDifficulty = difficulty_line or "normal"

			-- Restore mission_selection_level to prevent item duplication
			local mission_selection_level = tonumber(mission_selection_line) or 0
			if managers.crime_spree and managers.crime_spree._global then
				managers.crime_spree._global.mission_selection_level = mission_selection_level
			end

			-- Parse modifiers from both lines
			_G.CSR_SavedModifiers = {}

			-- Line 5: forced modifiers (HP/DMG, Loud, Stealth)
			if forced_mods_line and forced_mods_line ~= "" then
				for mod_str in string.gmatch(forced_mods_line, "[^|]+") do
					local id, level = string.match(mod_str, "([^:]+):(%d+)")
					if id and level then
						table.insert(_G.CSR_SavedModifiers, {
							id = id,
							level = tonumber(level)
						})
					end
				end
			end

			-- Line 6: player items
			if player_items_line and player_items_line ~= "" then
				for mod_str in string.gmatch(player_items_line, "[^|]+") do
					local id, level = string.match(mod_str, "([^:]+):(%d+)")
					if id and level then
						table.insert(_G.CSR_SavedModifiers, {
							id = id,
							level = tonumber(level)
						})
					end
				end
			end


			-- NOTE: CSR_LastShownForcedLevel will be restored in _setup hook
			-- (considering current CS level, in case player died and went back)

			return seed, CSR_CurrentDifficulty
		end
	end
	return nil, nil
end

-- Function to save seed, difficulty AND MODIFIERS to file
function CSR_SaveSeed(seed, difficulty, modifiers)

	-- Safety check: seed must not be nil
	if not seed then
		return false
	end

	local file = io.open(SEED_FILE, "w")
	if file then
		file:write(tostring(seed) .. "\n")
		file:write(tostring(difficulty or "normal") .. "\n")
		file:write("v2.45\n")  -- version bump for mission_selection_level support

		-- Line 4: mission_selection_level (vanilla variable to prevent item duplication)
		local cs = managers.crime_spree
		local mission_selection_level = 0
		if cs and cs._global and cs._global.mission_selection_level then
			mission_selection_level = cs._global.mission_selection_level
		end
		file:write(tostring(mission_selection_level) .. "\n")

		-- Split modifiers into forced (line 5) and player items (line 6)
		if modifiers and #modifiers > 0 then
			local forced_mods = {}  -- HP/DMG, Loud, Stealth
			local player_items = {} -- Player items

			for _, mod in ipairs(modifiers) do
				if mod.id and mod.level then
					local mod_string = mod.id .. ":" .. tostring(mod.level)
					-- Player items start with "player_"
					if string.find(mod.id, "^player_") then
						table.insert(player_items, mod_string)
					else
						table.insert(forced_mods, mod_string)
					end
				end
			end

			-- Line 5: forced modifiers (HP/DMG, Loud, Stealth)
			local forced_line = table.concat(forced_mods, "|")
			file:write(forced_line .. "\n")

			-- Line 6: player items
			local items_line = table.concat(player_items, "|")
			file:write(items_line)
		else
			file:write("\n") -- Empty line 4
		end

		file:close()
		CSR_CurrentSeed = seed
		CSR_CurrentDifficulty = difficulty or "normal"
		if modifiers then
		end
		return true
	end
	return false
end

-- Function to generate new seed (preserving current difficulty)
function CSR_GenerateNewSeed()
	-- Unlock items seen in the previous run before resetting
	if _G.CSR_Logbook then
		_G.CSR_Logbook:unlock_seen()
	end

	local seed = os.time() + math.floor(math.random() * 1000000)

	-- PRIORITY: Read difficulty from seed file (if active CS exists)
	local difficulty = "normal"
	local seed_file = io.open(SEED_FILE, "r")
	if seed_file then
		seed_file:read("*line")  -- Skip seed
		local difficulty_line = seed_file:read("*line")
		seed_file:close()
		if difficulty_line then
			difficulty = difficulty_line
		end
	end

	-- Fallback: global variable
	if not difficulty or difficulty == "" then
		difficulty = _G.CSR_SelectedDifficulty or "normal"
	end

	-- Save seed with empty modifiers list (for new CS)
	CSR_SaveSeed(seed, difficulty, {})
	CSR_RegenerateForcedModifiers(seed, difficulty)
	return seed, difficulty
end

-- Function to regenerate forced modifiers with new seed
-- Delegates to global function CSR_RegenerateForcedMods (defined in crimespree.lua)
function CSR_RegenerateForcedModifiers(seed, difficulty)
	if not tweak_data or not tweak_data.crime_spree then
		return
	end

	if _G.CSR_RegenerateForcedMods then
		_G.CSR_RegenerateForcedMods(seed, difficulty)
	else
	end
end

-- Hook on new Crime Spree start
Hooks:PostHook(CrimeSpreeManager, "enable_crime_spree", "CSR_NewSeedOnEnable", function(self)

	if not self._global then
		return
	end

	local current_level = self._global.spree_level or 0

	-- Unlock items seen in the previous run (safe to call multiple times)
	if _G.CSR_Logbook then
		_G.CSR_Logbook:unlock_seen()
	end

	-- CRITICAL: Regenerate forced modifiers ON EVERY CS ENABLE
	-- (including when loading from save)
	local seed = CSR_CurrentSeed or os.time()
	local difficulty = self._global.selected_difficulty or CSR_CurrentDifficulty or "normal"
	CSR_RegenerateForcedModifiers(seed, difficulty)

	-- If this is NEW Crime Spree (level = 0), generate new seed
	if current_level == 0 then

		local new_seed, new_difficulty = CSR_GenerateNewSeed()

		-- SAVE DIFFICULTY to Global.crime_spree (for current session)
		if Global.crime_spree then
			Global.crime_spree.selected_difficulty = new_difficulty
		end
	else

		-- Restore CSR_LastShownForcedLevel from saved modifiers
		if current_level > 0 and self._global.modifiers then
			local last_forced_level = 0
			for _, mod in ipairs(self._global.modifiers) do
				if mod.id and mod.level then
					-- Find last level among NON-player modifiers
					if not string.find(mod.id, "player_", 1, true) and
					   not string.find(mod.id, "csr_enemy_hp_damage", 1, true) then
						if mod.level <= current_level and mod.level > last_forced_level then
							last_forced_level = mod.level
						end
					end
				end
			end

			if last_forced_level > 0 then
				_G.CSR_LastShownForcedLevel = last_forced_level
			else
				_G.CSR_LastShownForcedLevel = 0
			end
		end
	end
end)

-- Flag to prevent recursion
local CSR_SettingDebugLevel = false

-- Hook on starting level purchase (when player pays coins for high start)
-- ALSO called when starting new Crime Spree from level 0!
Hooks:PostHook(CrimeSpreeManager, "set_starting_level", "CSR_NewSeedOnBuyLevel", function(self, level)
	-- Skip if this is recursive call from our hook
	if CSR_SettingDebugLevel then
		return
	end

	-- IMPORTANT: Do NOT generate new seed if Crime Spree ALREADY ACTIVE
	-- (player just changing settings in menu, difficulty already saved)
	-- OR if level above 0 (loading from save)
	if self._global then
	end

	-- Check ANY of conditions:
	-- 1. Crime Spree active AND level > 0
	-- 2. Level > 0 (even if is_active = false - could be loading)
	-- 3. Has modifiers (means CS was already started)
	if self._global then
		local has_level = self._global.spree_level and self._global.spree_level > 0
		local has_mods = self._global.modifiers and #self._global.modifiers > 0

		if (self._global.is_active and has_level) or has_level or has_mods then
			return
		end
	end


	local seed, difficulty = CSR_GenerateNewSeed()

	-- Reset forced modifier cache so new seed's modifiers are used
	CSR_ForcedModifiersReturned = false
	CSR_ForcedModifiersCache = nil
	CSR_LastForcedLevel = 0
	_G.CSR_LastShownForcedLevel = 0

	-- SAVE DIFFICULTY to Global.crime_spree (for current session)
	if Global.crime_spree then
		Global.crime_spree.selected_difficulty = difficulty
	end

	-- DEBUG: If starting level 0, set to 100 with recursive call
end)


-- Load seed on startup
CSR_LoadSeed()

-- CRITICAL: Regenerate forced modifiers IMMEDIATELY on mod load
-- (so repeating_modifiers.forced is populated before game requests modifiers)
if CSR_CurrentSeed then
	local difficulty = CSR_CurrentDifficulty or "normal"
	CSR_RegenerateForcedModifiers(CSR_CurrentSeed, difficulty)
else
end

