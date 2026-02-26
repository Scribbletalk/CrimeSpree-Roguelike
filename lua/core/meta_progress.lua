-- Crime Spree Roguelike - Meta Progress Manager
-- Tracks player statistics across runs

if not RequiredScript then
	return
end



-- Save file path (in Documents to survive Windows reinstalls)
local DOCUMENTS_PATH = os.getenv("USERPROFILE") .. "\\Documents\\PAYDAY 2\\"
local SAVE_PATH = DOCUMENTS_PATH .. "crime_spree_meta_progress.json"

-- NOTE: Do NOT use os.execute() — it minimizes the game window!
-- The Documents\PAYDAY 2 folder already exists (created by the game itself)

-- Global object for storing meta-progress
CSR_MetaProgress = CSR_MetaProgress or {}

-- Difficulty order (lowest to highest)
local DIFFICULTY_ORDER = {
	"normal",         -- 1
	"hard",           -- 2
	"very_hard",      -- 3
	"overkill",       -- 4
	"mayhem",         -- 5 (aliases: overkill_145, easy_wish)
	"death_wish",     -- 6 (aliases: overkill_290)
	"death_sentence"  -- 7 (aliases: sm_wish)
}

-- Alias mapping to canonical difficulty IDs
local DIFFICULTY_ALIASES = {
	overkill_145 = "mayhem",
	easy_wish = "mayhem",
	overkill_290 = "death_wish",
	sm_wish = "death_sentence"
}

-- Default data structure
local DEFAULT_DATA = {
	-- Cumulative stats across all runs
	total_kills = 0,
	total_bags = 0,
	total_missions = 0,
	total_coins_earned = 0,
	total_cash_earned = 0,

	-- Records (shared highest_level kept for backwards compatibility)
	highest_level = 0,
	longest_streak = 0,  -- Longest mission streak without failing

	-- Per-difficulty records
	highest_level_per_difficulty = {
		normal = 0,
		hard = 0,
		very_hard = 0,
		overkill = 0,
		mayhem = 0,
		death_wish = 0,
		death_sentence = 0
	},

	-- Item statistics
	items_collected = {},  -- { dog_tags = 15, wolfs_toolbox = 3, ... }

	-- Achievements (for future unlocks)
	achievements = {
		plush_shark_saves = 0,
		bonnie_instakills = 0,
		level_500_reached = false,
		level_1000_reached = false
	},

	-- Unlocked upgrades (for future use)
	unlocked_upgrades = {},
	unlocked_items = {},

	-- Version for compatibility
	version = "1.1"
}

-- Load data from file
function CSR_MetaProgress:Load()
	local file = io.open(SAVE_PATH, "r")
	if file then
		local content = file:read("*all")
		file:close()

		local success, data = pcall(json.decode, content)
		if success and data then
			-- Copy loaded data into self
			for k, v in pairs(data) do
				self[k] = v
			end
			return true
		else
		end
	else
	end

	-- File missing or load failed — fall back to default values
	for k, v in pairs(DEFAULT_DATA) do
		if self[k] == nil then
			if type(v) == "table" then
				self[k] = clone(v)
			else
				self[k] = v
			end
		end
	end

	return false
end

-- Save data to file
function CSR_MetaProgress:Save()
	local data = {}

	-- Copy all fields (skip functions)
	for k, v in pairs(self) do
		if type(v) ~= "function" then
			data[k] = v
		end
	end

	local file = io.open(SAVE_PATH, "w")
	if file then
		local json_data = json.encode(data)
		file:write(json_data)
		file:close()
		return true
	else
		return false
	end
end

-- Add kills to the total
function CSR_MetaProgress:AddKills(count)
	self.total_kills = (self.total_kills or 0) + count
end

-- Add bags to the total
function CSR_MetaProgress:AddBags(count)
	self.total_bags = (self.total_bags or 0) + count
end

-- Increment mission count
function CSR_MetaProgress:AddMission()
	self.total_missions = (self.total_missions or 0) + 1
end

-- Add cash earned
function CSR_MetaProgress:AddCash(amount)
	self.total_cash_earned = (self.total_cash_earned or 0) + amount
end

-- Add continental coins earned
function CSR_MetaProgress:AddCoins(amount)
	self.total_coins_earned = (self.total_coins_earned or 0) + amount
end

-- Update overall highest level (DEPRECATED - use UpdateHighestLevelForDifficulty instead)
function CSR_MetaProgress:UpdateHighestLevel(level)
	if level > (self.highest_level or 0) then
		self.highest_level = level

		-- Check achievements
		if level >= 500 then
			self.achievements.level_500_reached = true
		end
		if level >= 1000 then
			self.achievements.level_1000_reached = true
		end
	end
end

-- Update the highest level for a specific difficulty
function CSR_MetaProgress:UpdateHighestLevelForDifficulty(difficulty, level)
	-- Normalize alias (overkill_145 -> mayhem, sm_wish -> death_sentence)
	local normalized_diff = DIFFICULTY_ALIASES[difficulty] or difficulty

	-- Initialize table if missing
	if not self.highest_level_per_difficulty then
		self.highest_level_per_difficulty = {}
	end

	-- Update the record for this difficulty
	local current = self.highest_level_per_difficulty[normalized_diff] or 0
	if level > current then
		self.highest_level_per_difficulty[normalized_diff] = level
	end

	-- Update shared highest_level (for backwards compatibility)
	if level > (self.highest_level or 0) then
		self.highest_level = level

		-- Check achievements
		if level >= 500 then
			self.achievements.level_500_reached = true
		end
		if level >= 1000 then
			self.achievements.level_1000_reached = true
		end
	end
end

-- Get the highest level for a given difficulty, including all higher difficulties
-- e.g. GetHighestLevelForDifficulty("hard") returns MAX across hard, very_hard, overkill, ..., death_sentence
-- Rationale: clearing level 200 on Death Wish means everything available on DW+ is also accessible on Hard
function CSR_MetaProgress:GetHighestLevelForDifficulty(difficulty)
	-- Normalize alias
	local normalized_diff = DIFFICULTY_ALIASES[difficulty] or difficulty

	-- Initialize table if missing
	if not self.highest_level_per_difficulty then
		self.highest_level_per_difficulty = {}
	end

	-- Find the index of the requested difficulty
	local current_index = nil
	for i, diff in ipairs(DIFFICULTY_ORDER) do
		if diff == normalized_diff then
			current_index = i
			break
		end
	end

	if not current_index then
		return 0
	end

	-- Find the highest level across the requested difficulty and all harder ones
	local max_level = 0
	for i = current_index, #DIFFICULTY_ORDER do
		local diff = DIFFICULTY_ORDER[i]
		local level = self.highest_level_per_difficulty[diff] or 0
		if level > max_level then
			max_level = level
		end
	end

	return max_level
end

-- Record an item pickup in statistics
function CSR_MetaProgress:AddItem(item_type)
	if not self.items_collected then
		self.items_collected = {}
	end
	self.items_collected[item_type] = (self.items_collected[item_type] or 0) + 1
end

-- Get statistics for display in UI
function CSR_MetaProgress:GetStats()
	return {
		total_kills = self.total_kills or 0,
		total_bags = self.total_bags or 0,
		total_missions = self.total_missions or 0,
		total_coins = self.total_coins_earned or 0,
		total_cash = self.total_cash_earned or 0,
		highest_level = self.highest_level or 0,
		longest_streak = self.longest_streak or 0
	}
end

-- Load on startup
CSR_MetaProgress:Load()

