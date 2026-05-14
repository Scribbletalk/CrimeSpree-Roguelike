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
_G.CSR_BonusDropChance = _G.CSR_BonusDropChance or 0.01
_G.CSR_BonusDropCount = _G.CSR_BonusDropCount or 0
-- Per-peer Gage Shop purchase counter. Subtracted from milestone accounting in
-- crimespree_filter.lua:modifiers_to_select so shop buys don't cap rank grants.
_G.CSR_ShopItemsBought = _G.CSR_ShopItemsBought or {}
-- Per-peer late-join catchup grant counter. Same exemption pattern as shop:
-- catchup-granted items don't count toward the milestone selection-popup quota.
_G.CSR_CatchupItemsReceived = _G.CSR_CatchupItemsReceived or {}
-- Host-only: maps each joiner's Steam user_id to the host_earned value at the
-- time of their last catchup grant. Survives peer disconnects (which wipe
-- CSR_PlayerItems[peer_id]) so a reconnecting player can't farm items by
-- repeatedly rejoining within the same CS run.
_G.CSR_HostCatchupSnapshots = _G.CSR_HostCatchupSnapshots or {}

-- Function to read seed, difficulty AND MODIFIERS from file
function CSR_LoadSeed()
	local file = io.open(SEED_FILE, "r")
	if file then
		local seed_line = file:read("*line")
		local difficulty_line = file:read("*line")
		local version_line = file:read("*line")
		local mission_selection_line = file:read("*line") -- Line 4: mission_selection_level
		local forced_mods_line = file:read("*line") -- Line 5: forced modifiers
		local player_items_line = file:read("*line") -- Line 6: player items
		local bonus_chance_line = file:read("*line") -- Line 7: accumulated bonus drop chance
		local printer_line = file:read("*line") -- Line 8: printer state (tier~offer_prefix or empty)
		local tokens_line = file:read("*line") -- Line 9: Gage Tokens balance (may be nil on old files)
		local shop_line = file:read("*line") -- Line 10: Gage Shop state (may be nil on old files)
		local shop_bought_line = file:read("*line") -- Line 11: local peer's Gage Shop purchase count (nil on old files)
		local host_earned_line = file:read("*line") -- Line 12: host cumulative tokens earned (nil on old files)
		local catchup_budget_line = file:read("*line") -- Line 13: local peer's catchup_received_budget (nil on old files)
		local catchup_received_line = file:read("*line") -- Line 14: local peer's CSR_CatchupItemsReceived (nil on old files)
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
							level = tonumber(level),
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
							level = tonumber(level),
						})
					end
				end
			end

			-- Populate the per-player item store for singleplayer (peer_id = 1)
			local player_items_for_store = {}
			for _, mod in ipairs(_G.CSR_SavedModifiers) do
				if mod.id and string.find(mod.id, "^player_") then
					table.insert(player_items_for_store, { id = mod.id, level = mod.level or 0 })
				end
			end

			-- MP clients: seed file has no player items (CSR_SaveSeed skips clients).
			-- Check session file for better data — it persists items across Lua reloads.
			-- ONLY restore items during Lua reload (is_playing = true), not on fresh lobby
			-- connects. Fresh connects get items via handshake — loading here would inject
			-- stale items from a previous run that the handshake would have to clear.
			local is_reload = Global.game_settings and Global.game_settings.is_playing
			if CSR_LoadSessions then
				local sessions = CSR_LoadSessions()
				local today = os.date("%Y-%m-%d")
				local best = nil
				for _, s in pairs(sessions) do
					if s.my_items and #s.my_items > 0 and s.last_played == today then
						if not best or #s.my_items > #best.my_items then
							best = s
						end
					end
				end
				if best then
					-- Always stash metadata for multiplayer_sync.lua init recovery
					_G.CSR_MP_SessionTotalDrops = best.total_drops
					_G.CSR_MP_SessionRunSeed = best.seed
					-- Only restore items during Lua reload (mid-heist transition)
					if is_reload and #best.my_items > #player_items_for_store then
						player_items_for_store = best.my_items
					end
				end
			end

			if CSR_InitLocalPlayer then
				CSR_InitLocalPlayer(player_items_for_store, nil, CSR_CurrentDifficulty, nil)
			end

			-- Restore Gage Tokens. Seed file line 9 is the primary source for
			-- hosts; the session file (best.my_tokens) is the fallback for MP
			-- clients whose seed file is skipped by CSR_SaveSeed. Seed file wins
			-- if present because it's written on every autosave for hosts.
			local restored_tokens = tonumber(tokens_line)
			if restored_tokens == nil and best and best.my_tokens then
				restored_tokens = best.my_tokens
			end
			if restored_tokens and _G.CSR_PlayerItems then
				local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local data = _G.CSR_PlayerItems[local_peer]
				if data then
					data.tokens = restored_tokens
				end
			end

			-- Restore Gage Shop state. Seed file line 10 for hosts; session
			-- file (best.my_shop) as fallback for MP clients. Seed wins.
			if shop_line and shop_line ~= "" and CSR_ShopDeserialize then
				CSR_ShopDeserialize(shop_line)
			elseif best and best.my_shop and CSR_ShopDeserializeFromJson then
				CSR_ShopDeserializeFromJson(best.my_shop)
			end

			-- Line 7: accumulated bonus drop chance + drop count (format: "chance|count")
			local C = _G.CSR_ItemConstants or {}
			local min_chance = C.bonus_drop_min_chance or 0.01
			if bonus_chance_line and bonus_chance_line ~= "" then
				local chance_str, count_str = bonus_chance_line:match("([^|]+)|?([^|]*)")
				_G.CSR_BonusDropChance = tonumber(chance_str) or min_chance
				_G.CSR_BonusDropCount = tonumber(count_str) or 0
			else
				_G.CSR_BonusDropChance = min_chance
				_G.CSR_BonusDropCount = 0
			end

			-- Line 11: local peer's Gage Shop purchase count. Used by the
			-- modifiers_to_select filter to keep shop items out of the milestone
			-- quota so rank grants keep firing after a reload.
			do
				local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local shop_bought = tonumber(shop_bought_line) or 0
				_G.CSR_ShopItemsBought = _G.CSR_ShopItemsBought or {}
				_G.CSR_ShopItemsBought[local_peer] = shop_bought
			end

			-- Line 12: host cumulative tokens earned. Restores the monotonic counter
			-- so late-join catchup math continues correctly after a game restart.
			-- Only the host writes and reads this; MP clients get it via TOKEN_STATE RPC.
			do
				local earned = tonumber(host_earned_line) or 0
				_G.CSR_HostTokensEarned = earned
			end

			-- Line 13: local peer's catchup_received_budget snapshot.
			-- Restores the per-peer budget watermark so a re-joining peer is not
			-- double-granted after a host game restart.
			do
				local budget = tonumber(catchup_budget_line) or 0
				local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[local_peer]
				if pdata then
					pdata.catchup_received_budget = budget
				end
			end

			-- Line 14: local peer's CSR_CatchupItemsReceived counter. Without this,
			-- a Lua reload mid-CS drops catchup count to 0 -> milestone_selected
			-- jumps up by the lost amount -> SELECT MODIFIER button is suppressed
			-- until the rank passes the new (inflated) milestone_selected value.
			-- Bug: Zeon 2026-05-03, milestone-popup-not-firing at high rank.
			do
				local received = tonumber(catchup_received_line) or 0
				local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				_G.CSR_CatchupItemsReceived = _G.CSR_CatchupItemsReceived or {}
				_G.CSR_CatchupItemsReceived[local_peer] = received
			end

			-- Line 8: printer state
			if printer_line and printer_line ~= "" then
				local tier, offer_prefix = printer_line:match("^([^~]+)~(.+)$")
				if tier and offer_prefix then
					_G.CSR_Printer = { available = true, tier = tier, offer_prefix = offer_prefix }
				end
			end

			-- NOTE: CSR_LastShownForcedLevel will be restored in _setup hook
			-- (considering current CS level, in case player died and went back)

			return seed, CSR_CurrentDifficulty
		end
	end

	-- No seed file (or invalid seed) — still check session file for MP clients.
	-- CSR_SaveSeed skips clients, so they often have no seed file at all.
	-- Without this, the session recovery above (inside the seed block) never runs.
	-- ONLY restore items during Lua reload (is_playing = true) to avoid injecting
	-- stale items from a previous run when joining a new lobby.
	local is_reload = Global.game_settings and Global.game_settings.is_playing
	if CSR_LoadSessions then
		local sessions = CSR_LoadSessions()
		local today = os.date("%Y-%m-%d")
		local best = nil
		for _, s in pairs(sessions) do
			if s.my_items and #s.my_items > 0 and s.last_played == today then
				if not best or #s.my_items > #best.my_items then
					best = s
				end
			end
		end
		if best then
			_G.CSR_MP_SessionTotalDrops = best.total_drops
			_G.CSR_MP_SessionRunSeed = best.seed
			-- Only restore items during Lua reload (mid-heist transition)
			if is_reload and CSR_InitLocalPlayer then
				CSR_InitLocalPlayer(best.my_items, nil, nil, nil)
				-- Restore Gage Tokens alongside the items.
				if best.my_tokens and _G.CSR_PlayerItems then
					local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
					local data = _G.CSR_PlayerItems[local_peer]
					if data then
						data.tokens = best.my_tokens
					end
				end
			end
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

	-- Clients in foreign runs save to csr_mp_sessions.json (handled elsewhere).
	-- If client, skip seed file save entirely.
	if _G.CSR_MP and _G.CSR_MP.is_client and CSR_MP.is_client() then
		return false
	end
	local file = io.open(SEED_FILE, "w")
	if file then
		file:write(tostring(seed) .. "\n")
		file:write(tostring(difficulty or "normal") .. "\n")
		file:write(tostring(_G.CSR_MOD_VERSION or "unknown") .. "\n")

		-- Line 4: mission_selection_level (vanilla variable to prevent item duplication)
		local cs = managers.crime_spree
		local mission_selection_level = 0
		if cs and cs._global and cs._global.mission_selection_level then
			mission_selection_level = cs._global.mission_selection_level
		end
		file:write(tostring(mission_selection_level) .. "\n")

		-- Forced mods come from the modifiers parameter (still in _global.modifiers).
		-- Player items come from CSR_PlayerItems (the new per-player store).
		if modifiers and #modifiers > 0 then
			local forced_mods = {}
			for _, mod in ipairs(modifiers) do
				if mod.id and mod.level then
					-- Only include non-player modifiers (forced/CS mods)
					if not string.find(mod.id, "^player_") then
						table.insert(forced_mods, mod.id .. ":" .. tostring(mod.level))
					end
				end
			end

			-- Line 5: forced modifiers (HP/DMG, Loud, Stealth)
			file:write(table.concat(forced_mods, "|") .. "\n")

			-- Line 6: player items from the per-player store
			local player_item_parts = {}
			local local_items = _G.CSR_PlayerItems and CSR_GetLocalItems and CSR_GetLocalItems() or {}
			for _, item in ipairs(local_items) do
				if item.id and item.level then
					table.insert(player_item_parts, item.id .. ":" .. tostring(item.level))
				end
			end
			file:write(table.concat(player_item_parts, "|") .. "\n")

			-- Line 7: accumulated bonus drop chance
			file:write(tostring(_G.CSR_BonusDropChance or 0.01) .. "|" .. tostring(_G.CSR_BonusDropCount or 0) .. "\n")

			-- Line 8: printer state
			local printer = _G.CSR_Printer
			if printer and printer.available and printer.tier and printer.offer_prefix then
				file:write(printer.tier .. "~" .. printer.offer_prefix)
			end
			file:write("\n")

			-- Line 9: Gage Tokens (local player's current balance)
			local _peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			local _data = _G.CSR_PlayerItems and _G.CSR_PlayerItems[_peer]
			file:write(tostring((_data and _data.tokens) or 0))
			file:write("\n")

			-- Line 10: Gage Shop state (serialized chests + last_purchased_prefix)
			local _shop_str = (CSR_ShopSerialize and CSR_ShopSerialize()) or ""
			file:write(_shop_str)
			file:write("\n")

			-- Line 11: local peer's Gage Shop purchase count (scalar)
			do
				local _peer2 = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local _sb = (_G.CSR_ShopItemsBought and _G.CSR_ShopItemsBought[_peer2]) or 0
				file:write(tostring(_sb))
			end
			file:write("\n")

			-- Line 12: host-only cumulative tokens earned (CSR_HostTokensEarned)
			file:write(tostring(_G.CSR_HostTokensEarned or 0))
			file:write("\n")

			-- Line 13: local peer's late-join catchup budget snapshot (catchup_received_budget)
			do
				local _peer3 = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local _pd = _G.CSR_PlayerItems and _G.CSR_PlayerItems[_peer3]
				file:write(tostring((_pd and _pd.catchup_received_budget) or 0))
			end
			file:write("\n")

			-- Line 14: local peer's CSR_CatchupItemsReceived counter (scalar).
			-- Used by crimespree_filter.lua:modifiers_to_select to exempt catchup
			-- grants from the milestone quota; must persist across Lua reloads.
			do
				local _peer4 = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local _cr = (_G.CSR_CatchupItemsReceived and _G.CSR_CatchupItemsReceived[_peer4]) or 0
				file:write(tostring(_cr))
			end
		else
			file:write("\n") -- Empty line 5 (forced mods)
			-- Line 6: player items from the per-player store (may have items even if no forced mods)
			local player_item_parts = {}
			local local_items = _G.CSR_PlayerItems and CSR_GetLocalItems and CSR_GetLocalItems() or {}
			for _, item in ipairs(local_items) do
				if item.id and item.level then
					table.insert(player_item_parts, item.id .. ":" .. tostring(item.level))
				end
			end
			file:write(table.concat(player_item_parts, "|") .. "\n")
			file:write(tostring(_G.CSR_BonusDropChance or 0.01) .. "|" .. tostring(_G.CSR_BonusDropCount or 0) .. "\n") -- Line 7

			-- Line 8: printer state
			local printer = _G.CSR_Printer
			if printer and printer.available and printer.tier and printer.offer_prefix then
				file:write(printer.tier .. "~" .. printer.offer_prefix)
			end
			file:write("\n")

			-- Line 9: Gage Tokens (local player's current balance)
			local _peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			local _data = _G.CSR_PlayerItems and _G.CSR_PlayerItems[_peer]
			file:write(tostring((_data and _data.tokens) or 0))
			file:write("\n")

			-- Line 10: Gage Shop state (serialized chests + last_purchased_prefix)
			local _shop_str = (CSR_ShopSerialize and CSR_ShopSerialize()) or ""
			file:write(_shop_str)
			file:write("\n")

			-- Line 11: local peer's Gage Shop purchase count (scalar)
			do
				local _peer2 = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local _sb = (_G.CSR_ShopItemsBought and _G.CSR_ShopItemsBought[_peer2]) or 0
				file:write(tostring(_sb))
			end
			file:write("\n")

			-- Line 12: host-only cumulative tokens earned (CSR_HostTokensEarned)
			file:write(tostring(_G.CSR_HostTokensEarned or 0))
			file:write("\n")

			-- Line 13: local peer's late-join catchup budget snapshot (catchup_received_budget)
			do
				local _peer3 = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local _pd = _G.CSR_PlayerItems and _G.CSR_PlayerItems[_peer3]
				file:write(tostring((_pd and _pd.catchup_received_budget) or 0))
			end
			file:write("\n")

			-- Line 14: local peer's CSR_CatchupItemsReceived counter (scalar).
			do
				local _peer4 = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local _cr = (_G.CSR_CatchupItemsReceived and _G.CSR_CatchupItemsReceived[_peer4]) or 0
				file:write(tostring(_cr))
			end
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

	-- Persisted sources take priority over the volatile UI global (CSR_SelectedDifficulty).
	-- CSR_SelectedDifficulty is initialised with an "overkill" fallback when the CS menu first
	-- opens, which can beat the correctly-saved difficulty if the menu inits before the variable
	-- is set from save data.  _global and the seed file are always correct at this point.
	local difficulty = (
		managers.crime_spree
		and managers.crime_spree._global
		and managers.crime_spree._global.selected_difficulty
	)
		or CSR_CurrentDifficulty -- loaded from seed file at startup
		or _G.CSR_SelectedDifficulty
		or "normal"

	-- Reset bonus drop chance and drop count for new run.
	-- Also reset CSR_HostTokensEarned and CSR_PrinterUses — without these, prior
	-- run state leaks into the new run: host_earned funds free late-join catchup
	-- grants, printer uses keep their permanent damage-taken bonus.
	local C = _G.CSR_ItemConstants or {}
	_G.CSR_BonusDropChance = C.bonus_drop_min_chance or 0.01
	_G.CSR_BonusDropCount = 0
	_G.CSR_ShopItemsBought = {}
	_G.CSR_CatchupItemsReceived = {}
	_G.CSR_WildcardReplacements = {}
	_G.CSR_HostCatchupSnapshots = {}
	_G.CSR_HostTokensEarned = 0
	_G.CSR_PrinterUses = {}
	if CSR_TokensManager and CSR_TokensManager.set_host_earned then
		CSR_TokensManager.set_host_earned(0)
	end

	-- Clear player items and printer for new run
	if CSR_InitLocalPlayer then
		CSR_InitLocalPlayer({}, nil, difficulty, nil)
	end
	_G.CSR_Printer = { available = false, tier = nil, offer_prefix = nil }
	if CSR_ShopReset then
		CSR_ShopReset()
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
Hooks:PostHook(CrimeSpreeManager, "enable_crime_spree_gamemode", "CSR_NewSeedOnEnable", function(self)
	if not self._global then
		return
	end

	-- AUTO-DETECT INFLATION: pre-6.1.2, a client joining a higher-difficulty host
	-- earned thousands of ranks from a single heist because cash_per_rank looked up
	-- the client's stored difficulty (often "normal", 7500) instead of the host's.
	-- Once the bug fired, vanilla persisted the inflated rank to disk, so victims
	-- launch the game and find rank 5000+ with nothing to show for it. If we see
	-- a high rank with zero items and zero forced modifiers — i.e. no progression
	-- evidence at all — snap rank back to 0 so the player can start fresh.
	-- Strict triple-condition gate avoids false-positives on long-running saves.
	local pre_snap = self._global.spree_level or 0
	if pre_snap > 500 then
		local local_pid = (_G.CSR_LocalPeerId and CSR_LocalPeerId()) or 1
		local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[local_pid]
		local items_count = (pdata and pdata.items and #pdata.items) or 0
		local mods_count = (self._global.modifiers and #self._global.modifiers) or 0
		if items_count == 0 and mods_count == 0 then
			log(
				"[CSR INFLATION SNAP] rank="
					.. tostring(pre_snap)
					.. " items=0 mods=0 — likely client cash_per_rank inflation; snapping to 0"
			)
			self._global.spree_level = 0
			self._global.reward_level = 0
			-- Clear queued rewards: the bug accumulated thousands of ranks worth of
			-- unshown coins/XP/cash via vanilla's `unshown_rewards[id] += bonus * amount`
			-- in on_mission_completed. Without this clear, the next end-screen would
			-- dispense the inflated amount as phantom rewards.
			self._global.unshown_rewards = {}
			-- Reset all-time peak too — vanilla's _check_highest_level fired on the
			-- inflated rank and persisted highest_level to the same wrong value.
			self._global.highest_level = 0
		end
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

	-- ALWAYS restore difficulty to both storage locations
	self._global.selected_difficulty = difficulty
	if Global.crime_spree then
		Global.crime_spree.selected_difficulty = difficulty
	end

	-- If this is NEW Crime Spree (level = 0), generate new seed
	-- SKIP for MP clients: they use the host's run seed and items.
	-- CSR_GenerateNewSeed() calls CSR_InitLocalPlayer({}) which wipes all items.
	-- During lobby→heist transition, enable_crime_spree_gamemode fires again and the
	-- client's own spree_level is still 0, causing all picked items to be destroyed.
	-- Also skip if ANY player has items — means this is a transition, not a fresh start.
	-- (reset_crime_spree already clears items before a genuine new CS.)
	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
	local has_any_items = false
	for _, data in pairs(_G.CSR_PlayerItems or {}) do
		if data and data.items and #data.items > 0 then
			has_any_items = true
			break
		end
	end
	if current_level == 0 and not is_client and not has_any_items then
		-- Clear any stale forced mods from a previous run that vanilla didn't clear.
		-- reset_crime_spree() is not guaranteed to wipe _global.modifiers.
		self._global.modifiers = {}

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
					if
						not string.find(mod.id, "player_", 1, true)
						and not string.find(mod.id, "csr_enemy_hp_damage", 1, true)
					then
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

-- Starting-rank grant: when host (or SP player) starts a CS at level > 0,
-- award random items + leftover tokens equivalent to what a player would
-- have if they had earned their way to that rank organically. Mirrors the
-- late-join catchup flow so future joiners see the correct host_earned delta.
-- Host-only / SP-only — clients join an existing run via lobby, not via
-- start_crime_spree.
Hooks:PostHook(CrimeSpreeManager, "start_crime_spree", "CSR_StartingRankGrant", function(self, starting_level)
	if not starting_level or starting_level <= 0 then
		return
	end
	if CSR_LateJoinCatchup and CSR_LateJoinCatchup.run_for_starting_level then
		CSR_LateJoinCatchup.run_for_starting_level(starting_level)
	end
end)

-- Clear player items when Crime Spree is reset (stop/abandon)
Hooks:PostHook(CrimeSpreeManager, "reset_crime_spree", "CSR_ClearItemsOnReset", function(self)
	if CSR_InitLocalPlayer then
		CSR_InitLocalPlayer({}, nil, nil, nil)
	end
	if CSR_ShopReset then
		CSR_ShopReset()
	end
	if CSR_InvalidateModifierCache then
		CSR_InvalidateModifierCache()
	end
	_G.CSR_CachedModifierOffer = nil
	_G.CSR_BonusDropChance = (_G.CSR_ItemConstants or {}).bonus_drop_min_chance or 0.01
	_G.CSR_BonusDropCount = 0
	_G.CSR_ShopItemsBought = {}
	_G.CSR_CatchupItemsReceived = {}
	_G.CSR_WildcardReplacements = {}
	_G.CSR_HostCatchupSnapshots = {}
	_G.CSR_CarriedCash = 0
	_G.CSR_HostTokensEarned = 0
	-- CSR_PrinterUses feeds the permanent damage-taken bonus in the virtual
	-- HP/DMG modifier; if we don't clear it on reset, prior-run usage compounds
	-- forever. Same reason CSR_GenerateNewSeed clears it.
	_G.CSR_PrinterUses = {}
	if CSR_TokensManager and CSR_TokensManager.set_host_earned then
		CSR_TokensManager.set_host_earned(0)
	end
end)

-- Load seed on startup
CSR_LoadSeed()

-- Register Gage package CONTOUR material_config overrides when Half-a-Glass is present.
-- Uses DB:create_entry (SuperBLT) instead of BeardLib to avoid overriding mod_overrides.
-- Callable at any time: on mod load (from seed file) or mid-session (after picking the item).
-- Contour visibility is guarded at runtime in halfaglass_pickup.lua.
_G.CSR_HalfAGlass_MaterialRegistered = _G.CSR_HalfAGlass_MaterialRegistered or false

-- Save ModPath at load time (other mods can overwrite the global later)
local CSR_SAVED_MOD_PATH = ModPath

function CSR_RegisterGageContourMaterials()
	if _G.CSR_HalfAGlass_MaterialRegistered then
		return
	end

	local ok, err = pcall(function()
		local colors = { "blue", "green", "purple", "red", "yellow" }
		for _, color in ipairs(colors) do
			local name = "gen_pku_gage_" .. color
			local game_path = "units/pd2_dlc_gage_jobs/pickups/" .. name .. "/" .. name
			local file_path = CSR_SAVED_MOD_PATH
				.. "assets/units/pd2_dlc_gage_jobs/pickups/"
				.. name
				.. "/"
				.. name
				.. ".material_config"
			local ext_ids = Idstring("material_config")
			local path_ids = Idstring(game_path)
			if blt and blt.db_create_entry then
				blt:db_create_entry(ext_ids, path_ids, file_path, { recode_type = "scriptdata" })
			else
				DB:create_entry(ext_ids, path_ids, file_path)
			end
		end
		_G.CSR_HalfAGlass_MaterialRegistered = true
		log("[CSR] Gage package contour material_configs registered")
	end)
	if not ok then
		log("[CSR] Gage contour material registration failed: " .. tostring(err))
	end
end

-- Try registering on mod load if Half-a-Glass is already in the save
pcall(function()
	local has_half_a_glass = false
	if _G.CSR_SavedModifiers then
		for _, mod in ipairs(_G.CSR_SavedModifiers) do
			if mod.id and string.find(mod.id, "player_half_a_glass_", 1, true) then
				has_half_a_glass = true
				break
			end
		end
	end
	if has_half_a_glass then
		CSR_RegisterGageContourMaterials()
	end
end)

-- CRITICAL: Regenerate forced modifiers IMMEDIATELY on mod load
-- (so repeating_modifiers.forced is populated before game requests modifiers)
if CSR_CurrentSeed then
	local difficulty = CSR_CurrentDifficulty or "normal"
	CSR_RegenerateForcedModifiers(CSR_CurrentSeed, difficulty)
else
end
