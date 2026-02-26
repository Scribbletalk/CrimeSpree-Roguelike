-- Crime Spree Roguelike - Difficulty Reward System
-- Reward multiplier depends on the starting difficulty of Crime Spree

if not RequiredScript then
	return
end



-- Reward multipliers based on vanilla values (average Exp + Loot Bags + Loose Loot), normalized to Overkill = 1.0
local DIFFICULTY_REWARD_MULTIPLIERS = {
	normal = 0.12,           -- -88% vs Overkill (vanilla baseline)
	hard = 0.25,             -- -75% vs Overkill
	very_hard = 0.52,        -- -48% vs Overkill
	overkill = 1.0,          -- Crime Spree baseline (vanilla average: 8.1)
	overkill_145 = 1.28,     -- Mayhem, +28% vs Overkill
	mayhem = 1.28,           -- Alias for Mayhem
	easy_wish = 1.28,        -- Mayhem internal name
	overkill_290 = 1.41,     -- Death Wish, +41% vs Overkill
	death_wish = 1.41,       -- Alias for Death Wish
	sm_wish = 1.68,          -- Death Sentence, +68% vs Overkill (×14 UI)
	death_sentence = 1.68    -- Alias for Death Sentence
}

-- Override reward_level() to apply the difficulty multiplier
local original_reward_level = CrimeSpreeManager.reward_level
function CrimeSpreeManager:reward_level()
	local base_reward_level = original_reward_level(self)

	-- If Crime Spree is not active, return as-is
	if base_reward_level == -1 then
		return base_reward_level
	end

	-- Get selected difficulty (from Global -> from file -> default)
	local difficulty = self._global.selected_difficulty or CSR_CurrentDifficulty or "normal"

	-- Debug: log where the difficulty was sourced from
	if not self._global.selected_difficulty then
		-- Attempt to restore it into Global
		self._global.selected_difficulty = difficulty
	end

	local multiplier = DIFFICULTY_REWARD_MULTIPLIERS[difficulty]

	if not multiplier then
		multiplier = 0.4
	end

	-- Apply the multiplier
	local modified_reward_level = math.floor(base_reward_level * multiplier)


	return modified_reward_level
end

