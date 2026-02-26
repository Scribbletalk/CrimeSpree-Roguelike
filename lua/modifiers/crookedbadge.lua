-- CROOKED BADGE
-- Bonus: after each assault, X% chance to restore downs (hyperbolic, 50% -> 400%)
-- Penalty: bleedout timer reduced by Y seconds (hyperbolic, -10s -> -25s, min 5s)
-- Contraband rarity
--
-- Loaded TWICE via mod.txt:
--   1. lib/units/beings/player/playerdamage      -> PlayerDamage hooks
--   2. lib/managers/group_ai_states/groupaistatebesiege -> GroupAI hooks

if not RequiredScript then
	return
end

local required = RequiredScript

local function is_debug()
	return CSR_Settings and CSR_Settings.values and CSR_Settings.values.debug_mode
end


-- ============================================================
-- SHARED: class, constants, functions (idempotent)
-- ============================================================
ModifierCrookedBadge = ModifierCrookedBadge or class(CSRBaseModifier)
ModifierCrookedBadge.desc_id = "csr_crooked_badge_desc"

_G.CSR_CrookedBadge_Assaults = _G.CSR_CrookedBadge_Assaults or 0

local CB_K = 0.05

local function cb_revive_chance(stacks)
	return 400 - 370 / (1 + CB_K * (stacks - 1))
end

local function cb_bleedout_penalty(stacks)
	return 25 - 15 / (1 + CB_K * (stacks - 1))
end

local function cb_try_add_revive(pd)
	local ok, current = pcall(function()
		return Application:digest_value(pd._revives, false)
	end)
	if not ok or type(current) ~= "number" then
		return false
	end

	local bonus = 0
	pcall(function()
		bonus = managers.player:upgrade_value("player", "additional_lives", 0)
	end)
	local max_revives = pd._lives_init + bonus

	if current >= max_revives then
		return false
	end

	-- Direct assignment (add_revive() does NOT exist in vanilla PD2, only in RM)
	local new_val = math.min(max_revives, current + 1)
	pd._revives = Application:digest_value(new_val, true)
	pcall(function() pd:_send_set_revives() end)
	return true
end

-- ============================================================
-- LOAD 1: PlayerDamage hooks (init + bleedout penalty)
-- ============================================================
if required == "lib/units/beings/player/playerdamage" then

	if PlayerDamage then
		-- Reset assault counter on mission start
		Hooks:PostHook(PlayerDamage, "init", "CSR_CrookedBadge_Init", function(self)
			if not CSR_ActiveBuffs or not CSR_ActiveBuffs.crooked_badge then return end
			_G.CSR_CrookedBadge_Assaults = 0
		end)

		-- Override down_time() to reduce bleedout duration
		-- down_time() is used by vanilla for: _downed_timer, network sync, AND HUD display
		-- Overriding it fixes all three at once (unlike PostHook on _check_bleed_out which misses HUD)
		-- Guard: only override once (prevent double penalty if file loads twice)
		if not _G.CSR_CrookedBadge_DownTimeHooked then
			_G.CSR_CrookedBadge_DownTimeHooked = true
			local original_down_time = PlayerDamage.down_time
			function PlayerDamage:down_time()
				local base = original_down_time(self)
				if not CSR_ActiveBuffs or not CSR_ActiveBuffs.crooked_badge then return base end
				local stacks = CSR_ActiveBuffs.crooked_badge
				local penalty = cb_bleedout_penalty(stacks)
				local result = math.max(5, base - penalty)
				return result
			end
		end

	else
	end
end

-- ============================================================
-- LOAD 2: GroupAIStateBesiege hooks (revive after assault)
-- ============================================================
if required == "lib/managers/group_ai_states/groupaistatebesiege" then

	if GroupAIStateBesiege then
		Hooks:PostHook(GroupAIStateBesiege, "_begin_regroup_task", "CSR_CrookedBadge_Regroup", function(self)
			if not CSR_ActiveBuffs or not CSR_ActiveBuffs.crooked_badge then return end

			_G.CSR_CrookedBadge_Assaults = (_G.CSR_CrookedBadge_Assaults or 0) + 1

			local stacks = CSR_ActiveBuffs.crooked_badge
			local chance = cb_revive_chance(stacks)

			local player_unit = managers.player and managers.player:player_unit()
			if not player_unit then
				return
			end

			local pd = player_unit:character_damage()
			if not pd then
				return
			end

			local guaranteed = math.floor(chance / 100)
			local extra_chance = (chance / 100) - guaranteed


			for i = 1, guaranteed do
				cb_try_add_revive(pd)
			end
			if math.random() < extra_chance then
				cb_try_add_revive(pd)
			end
		end)

	else
	end
end
