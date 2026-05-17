-- CSRGameManager — single source of truth for Crime Spree Roguelike state.
--
-- Replaces every _G.CSR_* global and the four legacy persistence surfaces
-- (crime_spree_roguelike.json, csr_mp_sessions.json, crime_spree_seed.txt,
-- and our slice of Global.crime_spree) with one hierarchical singleton:
--   managers.csr._meta      (carries across runs and mod updates)
--   managers.csr._state     (active run, resets between runs)
--   managers.csr._registry  (static authored content, read-only after init)
--
-- Alpha skeleton with the first pilot item (Dog Tags) wired in. Items are
-- stored as { id = "<prefix>N", type = "<type>" } entries under
-- _state.peer_items[peer_id].items — same shape the legacy player_items_store
-- used, so the future migrator can map across without reshaping.

CSRGameManager = CSRGameManager or class()
CSRGameManager.VERSION = "6.6.6-alpha.0"

local SAVE_FILE = "csr_save.json"
local LEGACY_SETTINGS_FILE = "crime_spree_roguelike.json"
local LEGACY_MP_SESSIONS_FILE = "csr_mp_sessions.json"

local function log_csr(msg)
	log("[CSR] " .. tostring(msg))
end

local function default_meta()
	return {
		version = CSRGameManager.VERSION,
		stats = {},
		unlocks = {},
		settings = {},
	}
end

local function default_state()
	return {
		is_active = false,
		rank = 0,
		difficulty = "overkill",
		seed = nil,
		mission_set = {}, -- array of mission ids currently offered in the lobby
		current_mission = nil, -- id of the mission the player picked to play next
		peer_items = {},
		milestones = {},
		spawners = { copiers = {}, scrappers = {} },
		mp_session = {},
	}
end

local function default_registry()
	local items_list = {
		{
			type = "dog_tags",
			id_prefix = "player_health_boost_",
			rarity = "common",
		},
	}
	local by_type = {}
	local by_prefix = {}
	for _, item in ipairs(items_list) do
		by_type[item.type] = item
		by_prefix[item.id_prefix:sub(1, -2)] = item -- strip trailing underscore
	end
	return {
		items = items_list,
		by_type = by_type,
		by_prefix = by_prefix,
		constants = {
			dog_tags_hp_bonus = 0.10, -- +10% max HP per stack (additive)
			rank_per_heist = 1, -- rebalance: every completed heist grants exactly 1 rank
		},
	}
end

function CSRGameManager:init()
	self._meta = default_meta()
	self._state = default_state()
	self._registry = default_registry()
	self._callbacks = {
		on_mission_started = {},
		on_mission_completed = {},
		on_item_added = {},
		on_item_removed = {},
	}
	self:_migrate_legacy_save()
	self:load()
	self:_pilot_seed_dog_tags()
	log_csr("CSRGameManager initialised; version=" .. tostring(self._meta.version))
end

-- =====================================================
-- Run-state queries
-- =====================================================

function CSRGameManager:is_run_active()
	-- Alpha pilot stub: always active so item hooks never bail. Real run
	-- gating lands when we port the mission-state machinery in beta.
	return true
end

function CSRGameManager:is_active()
	-- Honest accessor for `_state.is_active` (the field flipped by start_run /
	-- end_run). Use this when a hook genuinely needs to know "is a CSR run
	-- currently in flight" -- e.g. mission lifecycle, save migrations, MP
	-- session bring-up. Items keep using is_run_active() per the stub above.
	return self._state.is_active == true
end

function CSRGameManager:rank()
	return self._state.rank or 0
end

function CSRGameManager:difficulty()
	-- CSR has no bespoke difficulty system: a spree runs on a vanilla difficulty.
	-- The difficulty-selection slice is not ported yet, so the truthful "current
	-- difficulty" is the vanilla one select_mission() forces the heist to load
	-- at, sourced from tweak_data.crime_spree.base_difficulty (see
	-- :select_mission). _state.difficulty is a not-yet-wired stub; only fall back
	-- to it if tweak_data is not up yet (early-load nil guard). When the
	-- difficulty-selection slice lands it reworks this accessor to return the
	-- player's chosen vanilla difficulty.
	local cs_td = tweak_data and tweak_data.crime_spree
	return (cs_td and cs_td.base_difficulty) or self._state.difficulty
end

function CSRGameManager:seed()
	return self._state.seed
end

function CSRGameManager:host_rank()
	local mp = self._state.mp_session
	if mp and mp.host_rank then
		return mp.host_rank
	end
	return self._state.rank or 0
end

-- =====================================================
-- Peer ID
-- =====================================================

function CSRGameManager:local_peer_id()
	local nm = managers and managers.network
	if nm and nm.session then
		local session = nm:session()
		if session and session.local_peer then
			local peer = session:local_peer()
			if peer and peer.id then
				return peer:id()
			end
		end
	end
	return 1
end

-- =====================================================
-- Items
-- =====================================================

local function get_or_create_peer_entry(state, peer_id)
	local entry = state.peer_items[peer_id]
	if not entry then
		entry = { items = {} }
		state.peer_items[peer_id] = entry
	end
	return entry
end

function CSRGameManager:player_items(peer_id)
	local entry = self._state.peer_items[peer_id]
	return entry and entry.items or {}
end

function CSRGameManager:item_count(peer_id, prefix)
	local entry = self._state.peer_items[peer_id]
	if not entry or not entry.items then
		return 0
	end
	local count = 0
	for _, item in ipairs(entry.items) do
		if item.id and string.find(item.id, prefix, 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

function CSRGameManager:has_item(peer_id, item_type)
	local def = self._registry.by_type[item_type]
	if not def then
		return false
	end
	return self:item_count(peer_id, def.id_prefix) > 0
end

function CSRGameManager:add_item(peer_id, item_type)
	local def = self._registry.by_type[item_type]
	if not def then
		log_csr("add_item: unknown type '" .. tostring(item_type) .. "' — ignored")
		return false
	end
	local entry = get_or_create_peer_entry(self._state, peer_id)
	local next_n = self:item_count(peer_id, def.id_prefix) + 1
	local item = {
		id = def.id_prefix .. tostring(next_n),
		type = item_type,
	}
	table.insert(entry.items, item)
	for _, fn in ipairs(self._callbacks.on_item_added) do
		fn(peer_id, item)
	end
	self:save()
	log_csr("add_item: peer=" .. tostring(peer_id) .. " id=" .. item.id)
	return true
end

function CSRGameManager:remove_item(peer_id, item_type)
	local entry = self._state.peer_items[peer_id]
	if not entry or not entry.items then
		return false
	end
	for i, item in ipairs(entry.items) do
		if item.type == item_type then
			local removed = table.remove(entry.items, i)
			for _, fn in ipairs(self._callbacks.on_item_removed) do
				fn(peer_id, removed)
			end
			self:save()
			log_csr("remove_item: peer=" .. tostring(peer_id) .. " id=" .. removed.id)
			return true
		end
	end
	return false
end

function CSRGameManager:roll_item_pool(peer_id, count)
	-- TODO[beta]: replaces crimespree_filter.lua overrides.
	return {}
end

-- =====================================================
-- Mission set & selection
--
-- Replaces vanilla CrimeSpreeManager's mission-set machinery
-- (generate_new_mission_set / get_random_missions / select_mission /
-- _setup_mission_lists / get_mission / current_mission).
--
-- The mission POOL is pure static config read straight from
-- tweak_data.crime_spree.missions (3 tier buckets). Only the *chosen* set and
-- the current pick are run state, stored as ids in _state so the save stays
-- JSON-serialisable (tweak_data entries hold engine refs that must not be
-- serialised). The launch path (narrative chain, JobManager temp job,
-- Global.game_settings) is Diesel/tweak_data surface and is mirrored 1:1 from
-- vanilla per REFACTOR_PLAN non-goals (we do not replace the engine surface).
-- =====================================================

-- Build the 3 tier lists from tweak_data, applying the same DLC visibility
-- filter vanilla's _setup_mission_lists uses. Cached after the first successful
-- build: the pool is static config and DLC ownership does not change
-- mid-session (vanilla likewise builds these once in _setup_mission_lists). The
-- cache keeps the reroll spin animation -- which queries random missions
-- per-frame -- free of the ~50-entry rebuild it would otherwise incur each call.
function CSRGameManager:_mission_lists()
	if self._mission_lists_cache then
		return self._mission_lists_cache
	end
	local lists = {}
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return lists -- tweak_data not ready yet; do not poison the cache
	end
	for index, mission_list in ipairs(cs_missions) do
		lists[index] = {}
		for _, mission in ipairs(mission_list) do
			local lvl = mission.level
			local dlc = lvl and lvl.dlc
			local dlc_unlocked = not dlc or (managers.dlc and managers.dlc:is_dlc_unlocked(dlc))
			local should_hide = dlc and managers.dlc and managers.dlc:should_hide_unavailable(dlc) or false
			if dlc_unlocked or not should_hide then
				table.insert(lists[index], mission)
			end
		end
	end
	self._mission_lists_cache = lists
	return lists
end

function CSRGameManager:get_mission(mission_id)
	mission_id = mission_id or self:current_mission()
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return nil
	end
	for _, tbl in pairs(cs_missions) do
		for _, data in pairs(tbl) do
			if data.id == mission_id then
				return data
			end
		end
	end
	return nil
end

function CSRGameManager:get_random_missions()
	local lists = self:_mission_lists()
	local set = {}
	for i = 1, 3 do
		local list = lists[i]
		if list and #list > 0 then
			set[i] = list[math.random(1, #list)]
		end
	end
	return set
end

-- Single random mission (used by the card spin-animation flavor text).
-- Mirrors vanilla get_random_mission = table.random(get_random_missions()).
function CSRGameManager:get_random_mission()
	local set = self:get_random_missions()
	local pool = {}
	for i = 1, 3 do
		if set[i] then
			pool[#pool + 1] = set[i]
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- Roll a fresh set of mission ids and clear the current pick. Ids are stored
-- DENSELY (no nil holes): a missing tier is skipped, not left as a gap, so
-- #_state.mission_set is meaningful and table.concat can't error on a hole.
function CSRGameManager:generate_mission_set()
	local missions = self:get_random_missions()
	local ids = {}
	for i = 1, 3 do
		local m = missions[i]
		if m and m.id then
			ids[#ids + 1] = m.id
		end
	end
	self._state.mission_set = ids
	self._state.current_mission = nil
	log_csr("generate_mission_set: " .. table.concat(ids, ", "))
	self:save()
	return ids
end

function CSRGameManager:reroll_mission_set()
	-- Free reroll for the alpha mission-select slice (no continental-coin cost;
	-- vanilla's escalating-cost reroll economy is intentionally dropped here).
	return self:generate_mission_set()
end

-- Guarantee a non-empty set exists before the lobby renders. Covers old saves
-- (csr_save.json written before mission_set existed) and any path where
-- start_run() early-returned on an already-active loaded state, leaving the set
-- empty -> the missions panel built empty cards and crashed (see
-- crash_report_2026_05_16_19_45). Idempotent: a populated set is left as-is, so
-- reopening the contract does NOT reroll the player's missions.
function CSRGameManager:ensure_mission_set()
	local set = self._state.mission_set
	if type(set) ~= "table" or #set == 0 then
		self:generate_mission_set()
	end
end

-- Resolve the stored ids back to full tweak_data mission tables for the UI.
-- Unresolvable slots return nil (NOT {}), so the panel can skip them rather
-- than build a card with nil .add/.level.
function CSRGameManager:mission_set()
	local out = {}
	for i = 1, 3 do
		local id = (self._state.mission_set or {})[i]
		out[i] = id and self:get_mission(id) or nil
	end
	return out
end

function CSRGameManager:current_mission()
	return self._state.current_mission
end

function CSRGameManager:select_mission(mission_id)
	if mission_id == false then
		self._state.current_mission = nil
		return
	end
	local mission_data = self:get_mission(mission_id)
	if not mission_data then
		log_csr("select_mission: unknown mission id '" .. tostring(mission_id) .. "' — ignored")
		return
	end
	self._state.current_mission = mission_data.id

	-- Engine / tweak_data wiring — mirrors vanilla CrimeSpreeManager:select_mission
	-- (_setup_temporary_job + activate_temporary_job + _setup_global_from_mission_id).
	-- Difficulty is forced to the vanilla CS base difficulty here; CSR's own
	-- difficulty system is a separate REWRITE slice (crimespree_difficulty.lua).
	local narrative_job = tweak_data
		and tweak_data.narrative
		and tweak_data.narrative.jobs
		and tweak_data.narrative.jobs.crime_spree
	if narrative_job and mission_data.level then
		narrative_job.chain = { mission_data.level }
	end
	if managers.job and mission_data.level then
		managers.job:activate_temporary_job("crime_spree", mission_data.level.level_id)
	end
	if Global and Global.game_settings and mission_data.level then
		Global.game_settings.difficulty = tweak_data.crime_spree.base_difficulty
		Global.game_settings.one_down = false
		Global.game_settings.level_id = mission_data.level.level_id
		Global.game_settings.mission = mission_data.mission or "none"
	end
	if Network:is_server() and MenuCallbackHandler and MenuCallbackHandler.update_matchmake_attributes then
		MenuCallbackHandler:update_matchmake_attributes()
	end

	log_csr(
		"select_mission: "
			.. tostring(mission_data.id)
			.. " (level="
			.. tostring(mission_data.level and mission_data.level.level_id)
			.. ")"
	)
	-- No self:save() here: the missions panel calls select_mission on every
	-- card click, which would thrash csr_save.json to disk. current_mission is
	-- transient run state -- it is persisted by start_run / generate_mission_set
	-- / progress_rank, and an alpha run resets it on the next start anyway.
end

-- =====================================================
-- Run lifecycle (alpha stubs)
-- =====================================================

function CSRGameManager:start_run()
	-- Accepting a contract is an explicit "begin a NEW run" intent, so this
	-- ALWAYS resets run progress -- it never continues a leftover run. This is
	-- deliberate: a rank carried over from an old/stale save (a pre-rebalance
	-- csr_save.json, or one where start_run previously early-returned on a
	-- loaded is_active=true) would wreck the new flat-1-rank balance. Per
	-- REFACTOR_PLAN §5.2 alpha resets current run progress; a stats-preserving
	-- legacy migrator (§5.3) is still future work in _migrate_legacy_save.
	-- There is no "continue run" flow in alpha, and start_run is only called
	-- from the contract-accept callbacks (user-initiated, once), so an
	-- unconditional reset is safe and correct here.
	if self._state.is_active then
		log_csr(
			"start_run: discarding a leftover active run (rank=" .. tostring(self._state.rank) .. ") and starting fresh"
		)
	end
	self._state.is_active = true
	self._state.rank = 0
	self._state.difficulty = self._state.difficulty or "overkill"
	self._state.seed = math.random(1, 2 ^ 30)
	self:generate_mission_set()
	log_csr(
		"start_run: new run begun (difficulty="
			.. tostring(self._state.difficulty)
			.. ", seed="
			.. tostring(self._state.seed)
			.. ")"
	)
	for _, fn in ipairs(self._callbacks.on_mission_started) do
		fn()
	end
	self:save()
	return true
end

function CSRGameManager:end_run()
	if not self._state.is_active then
		return false
	end
	self._state.is_active = false
	log_csr("end_run: run ended at rank=" .. tostring(self._state.rank))
	for _, fn in ipairs(self._callbacks.on_mission_completed) do
		fn()
	end
	self:save()
	return true
end

function CSRGameManager:progress_rank(amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return false
	end
	if not self._state.is_active then
		log_csr("progress_rank: no active run; ignored")
		return false
	end
	self._state.rank = (self._state.rank or 0) + amount
	log_csr("progress_rank: +" .. tostring(amount) .. " (now " .. tostring(self._state.rank) .. ")")
	self:save()
	return true
end

-- =====================================================
-- Registries & settings
-- =====================================================

function CSRGameManager:constant(name)
	return self._registry.constants and self._registry.constants[name]
end

function CSRGameManager:setting(key)
	return self._meta.settings[key]
end

function CSRGameManager:set_setting(key, value)
	self._meta.settings[key] = value
	self:save()
end

-- =====================================================
-- Event registration
-- =====================================================

local function register_callback(list, fn)
	if type(fn) == "function" then
		table.insert(list, fn)
	end
end

function CSRGameManager:on_mission_started(fn)
	register_callback(self._callbacks.on_mission_started, fn)
end

function CSRGameManager:on_mission_completed(fn)
	register_callback(self._callbacks.on_mission_completed, fn)
end

function CSRGameManager:on_item_added(fn)
	register_callback(self._callbacks.on_item_added, fn)
end

function CSRGameManager:on_item_removed(fn)
	register_callback(self._callbacks.on_item_removed, fn)
end

-- =====================================================
-- Save / load
-- =====================================================

local function save_path(name)
	return SavePath .. name
end

function CSRGameManager:save()
	local path = save_path(SAVE_FILE)
	local payload = {
		version = self._meta.version,
		meta = self._meta,
		state = self._state,
	}
	local encoded_ok, encoded = pcall(json.encode, payload)
	if not encoded_ok then
		log_csr("ERROR save: json.encode failed -> " .. tostring(encoded))
		return false
	end
	local f = io.open(path, "w")
	if not f then
		log_csr("ERROR save: could not open for write -> " .. path)
		return false
	end
	f:write(encoded)
	f:close()
	log_csr("save ok -> " .. path)
	return true
end

function CSRGameManager:load()
	local path = save_path(SAVE_FILE)
	local f = io.open(path, "r")
	if not f then
		log_csr("load: no save file at " .. path .. " (fresh install)")
		return false
	end
	local raw = f:read("*all")
	f:close()
	local decoded_ok, decoded = pcall(json.decode, raw)
	if not decoded_ok or type(decoded) ~= "table" then
		log_csr("ERROR load: json.decode failed -> " .. tostring(decoded))
		return false
	end
	if type(decoded.meta) == "table" then
		for k, v in pairs(decoded.meta) do
			self._meta[k] = v
		end
	end
	if type(decoded.state) == "table" then
		for k, v in pairs(decoded.state) do
			self._state[k] = v
		end
	end
	log_csr("load ok <- " .. path .. " (saved_version=" .. tostring(decoded.version) .. ")")
	return true
end

-- =====================================================
-- Legacy-save migrator (stub — logs only)
-- =====================================================

local function legacy_file_probe(path)
	local f = io.open(path, "r")
	if not f then
		return false, 0
	end
	local content = f:read("*all")
	f:close()
	return true, content and #content or 0
end

function CSRGameManager:_migrate_legacy_save()
	local legacy_settings = SavePath .. LEGACY_SETTINGS_FILE
	local legacy_mp = SavePath .. LEGACY_MP_SESSIONS_FILE

	local exists, size = legacy_file_probe(legacy_settings)
	if exists then
		log_csr("migrator: found legacy settings (" .. size .. " bytes) at " .. legacy_settings)
	else
		log_csr("migrator: no legacy settings at " .. legacy_settings)
	end

	exists, size = legacy_file_probe(legacy_mp)
	if exists then
		log_csr("migrator: found legacy MP-sessions (" .. size .. " bytes) at " .. legacy_mp)
	else
		log_csr("migrator: no legacy MP-sessions at " .. legacy_mp)
	end

	log_csr("migrator: stub run complete; legacy files untouched")
end

-- =====================================================
-- Pilot test seed (alpha-only)
--
-- Adds one Dog Tags item to peer 1 if absent. Idempotent — once the item is
-- in state and saved, subsequent launches load it from disk and this is a
-- no-op. Lets the player launch PD2 and verify the +10% max-HP bump in the
-- HUD without needing a debug keybind or UI plumbing.
-- =====================================================

function CSRGameManager:_pilot_seed_dog_tags()
	if self:has_item(1, "dog_tags") then
		log_csr("pilot seed: dog_tags already present for peer 1; skipping")
		return
	end
	log_csr("pilot seed: adding one dog_tags item to peer 1")
	self:add_item(1, "dog_tags")
end

-- =====================================================
-- Attach to managers table
--
-- PostHook on Setup:init_managers. Both MenuSetup and GameSetup inherit from
-- Setup and call Setup.init_managers(self, managers), so this single hook
-- covers main menu AND in-game setups (verified in lib/setups/menusetup.lua
-- and lib/setups/gamesetup.lua).
-- =====================================================

Hooks:PostHook(Setup, "init_managers", "CSR_AttachGameManager", function(self, managers)
	if managers.csr then
		return
	end
	managers.csr = CSRGameManager:new()
end)
