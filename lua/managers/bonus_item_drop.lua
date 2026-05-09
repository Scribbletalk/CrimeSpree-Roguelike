-- Crime Spree Roguelike - Bonus Item Drop (Pity System)
-- Collecting instant cash during missions gives a chance for a bonus random item.
-- Chance accumulates across missions until an item drops, then resets to minimum.
-- Inspired by Rainbow Six Siege skin drop system.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("[CSR BonusDrop] Module loaded")

local C = _G.CSR_ItemConstants or {}

-- === SNAPSHOT INITIAL CASH AT MISSION START ===
Hooks:PostHook(CrimeSpreeManager, "on_mission_started", "CSR_SnapshotCashForDrop", function(self)
	if not self:is_active() then
		return
	end

	-- Snapshot total small loot value at mission start for delta calculation
	_G.CSR_InitialSmallLootValue = 0
	if managers.loot and managers.loot.get_real_total_small_loot_value then
		local ok, val = pcall(function()
			return managers.loot:get_real_total_small_loot_value()
		end)
		if ok and val then
			_G.CSR_InitialSmallLootValue = val
		end
	end

	CSR_log("[CSR BonusDrop] Mission start: initial small loot value = " .. tostring(_G.CSR_InitialSmallLootValue))
end)

-- === ROLL FOR BONUS ITEM AT MISSION END ===
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_BonusDropRoll", function(self, mission_id)
	if not self:is_active() or self:has_failed() then
		return
	end

	-- Skip for multiplayer clients (only host rolls)
	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
	if is_client then
		return
	end

	-- Compute instant cash collected THIS mission
	local current_cash = 0
	if managers.loot and managers.loot.get_real_total_small_loot_value then
		local ok, val = pcall(function()
			return managers.loot:get_real_total_small_loot_value()
		end)
		if ok and val then
			current_cash = val
		end
	end

	local initial_cash = _G.CSR_InitialSmallLootValue or 0
	local mission_cash = math.max(0, current_cash - initial_cash)

	CSR_log(
		"[CSR BonusDrop] Mission cash: "
			.. mission_cash
			.. " (current="
			.. current_cash
			.. " initial="
			.. initial_cash
			.. ")"
	)

	-- Calculate chance from this mission's cash (linear: every dollar counts)
	-- Escalation: each previous drop increases the 100% threshold by escalation amount
	local base_cash_per_percent = C.bonus_drop_cash_per_percent or 10000
	local escalation = C.bonus_drop_escalation or 200000
	local drop_count = _G.CSR_BonusDropCount or 0
	local min_chance = C.bonus_drop_min_chance or 0.01

	-- Effective cash_per_percent scales: base threshold + (drop_count * escalation / 100)
	-- At 0 drops: $10k = 1%, $1M = 100%
	-- At 1 drop:  $12k = 1%, $1.2M = 100%
	-- At 2 drops: $14k = 1%, $1.4M = 100%
	local cash_per_percent = base_cash_per_percent + drop_count * (escalation / 100)
	local mission_chance = mission_cash / cash_per_percent * 0.01

	-- Add to accumulated chance (pity system)
	local total_chance = (_G.CSR_BonusDropChance or min_chance) + mission_chance

	CSR_log(
		"[CSR BonusDrop] Chance: accumulated="
			.. tostring(_G.CSR_BonusDropChance)
			.. " + mission="
			.. string.format("%.2f%%", mission_chance * 100)
			.. " = "
			.. string.format("%.2f%%", total_chance * 100)
	)

	-- Roll
	local roll = math.random()
	local success = roll < total_chance

	CSR_log(
		"[CSR BonusDrop] Roll: "
			.. string.format("%.4f", roll)
			.. " < "
			.. string.format("%.4f", total_chance)
			.. " = "
			.. tostring(success)
	)

	if success then
		-- Pick a random item (no Contraband)
		local item = CSR_PickBonusDropItem()
		if item then
			_G.CSR_BonusDropResult = item
			CSR_log("[CSR BonusDrop] Winner: " .. item.type .. " (" .. item.rarity .. ")")

			-- Grant the item immediately (don't depend on UI popup)
			CSR_GrantBonusItem(item)
		end

		-- Increment drop count (escalates future thresholds)
		_G.CSR_BonusDropCount = (_G.CSR_BonusDropCount or 0) + 1
		CSR_log("[CSR BonusDrop] Drop count now: " .. tostring(_G.CSR_BonusDropCount))

		-- Reset chance to minimum
		_G.CSR_BonusDropChance = min_chance
	else
		-- Save accumulated chance for next mission
		_G.CSR_BonusDropChance = total_chance
	end

	-- Store for stats display
	_G.CSR_LastMissionCash = mission_cash
	_G.CSR_LastDropRoll = roll
	_G.CSR_LastDropChance = total_chance

	-- Autosave updated chance to seed file
	CSR_log(
		"[CSR BonusDrop] SaveSeed check: fn="
			.. tostring(CSR_SaveSeed ~= nil)
			.. " seed="
			.. tostring(_G.CSR_CurrentSeed)
	)
	if CSR_SaveSeed and _G.CSR_CurrentSeed then
		local difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"
		local mods = self._global.modifiers
		CSR_log(
			"[CSR BonusDrop] Saving seed: difficulty="
				.. tostring(difficulty)
				.. " mods="
				.. tostring(mods and #mods or "nil")
		)
		local ok, err = pcall(CSR_SaveSeed, _G.CSR_CurrentSeed, difficulty, mods)
		if not ok then
			log("[CSR BonusDrop] SaveSeed ERROR: " .. tostring(err))
		else
			CSR_log("[CSR BonusDrop] SaveSeed OK")
		end
	end
end)

-- === PICK A RANDOM ITEM BY RARITY WEIGHTS (no Contraband) ===
function CSR_PickBonusDropItem()
	local registry = _G.CSR_ITEM_REGISTRY
	if not registry then
		return nil
	end

	-- Build pool excluding Contraband
	local pool = {}
	for _, item in ipairs(registry) do
		if item.rarity ~= "contraband" then
			table.insert(pool, item)
		end
	end

	if #pool == 0 then
		return nil
	end

	-- Weighted random selection
	local total_weight = 0
	for _, item in ipairs(pool) do
		total_weight = total_weight + (item.weight or 0.5)
	end

	if total_weight <= 0 then
		return nil
	end

	local roll = math.random() * total_weight
	local cumulative = 0
	for _, item in ipairs(pool) do
		cumulative = cumulative + (item.weight or 0.5)
		if roll <= cumulative then
			return item
		end
	end

	-- Fallback: last item
	return pool[#pool]
end

-- === GRANT THE BONUS ITEM TO THE PLAYER ===
-- Called after the wheel animation finishes (or immediately on roll success).
function CSR_GrantBonusItem(item)
	if not item or not managers.crime_spree or not managers.crime_spree:is_active() then
		return false
	end

	local id_prefix = item.id_prefix
	if not id_prefix then
		log("[CSR BonusDrop] Grant failed: no id_prefix for item " .. tostring(item.type))
		return false
	end

	-- Add item via the per-player store
	local new_id = CSR_AddItem(id_prefix)

	-- Broadcast to peers in MP
	if _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer() and CSR_MP.broadcast_own_items then
		CSR_MP.broadcast_own_items()
	end

	-- Mark as seen in logbook
	if _G.CSR_Logbook then
		_G.CSR_Logbook:mark_seen(item.type)
	end

	-- Trigger save
	local cs = managers.crime_spree
	if cs and cs._global then
		local seed = _G.CSR_CurrentSeed or 0
		local difficulty = _G.CSR_CurrentDifficulty or "normal"
		if CSR_SaveSeed then
			CSR_SaveSeed(seed, difficulty, cs._global.modifiers)
		end
	end

	-- Save to session file for reconnect (if client in a foreign run)
	if _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and _G.CSR_MP_RunSeed and CSR_SaveSession then
		CSR_SaveSession(
			_G.CSR_MP_RunSeed,
			nil,
			CSR_GetLocalItems(),
			CSR_MP._get_total_drops and CSR_MP._get_total_drops() or nil
		)
	end

	CSR_log("[CSR BonusDrop] Granted: " .. new_id .. " at CS level " .. tostring(managers.crime_spree:spree_level()))
	return true
end

-- === FAIL-SAFE: Grant pending bonus item on CS enable ===
-- Catches the case where the roll succeeded but the item wasn't granted
-- (e.g. game restart between mission end and item grant)
Hooks:PostHook(CrimeSpreeManager, "enable_crime_spree_gamemode", "CSR_BonusDropFailsafe", function(self)
	if _G.CSR_BonusDropResult and self:is_active() then
		CSR_log("[CSR BonusDrop] Failsafe: granting pending item " .. tostring(_G.CSR_BonusDropResult.type))
		CSR_GrantBonusItem(_G.CSR_BonusDropResult)
		_G.CSR_BonusDropResult = nil
	end
end)
