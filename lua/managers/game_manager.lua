-- CSRGameManager — single source of truth for Crime Spree Roguelike state.
-- Hierarchical singleton: _meta (persists across runs), _state (active run), _registry (static content).

CSRGameManager = CSRGameManager or class()
CSRGameManager.VERSION = "U1-alpha"

local SAVE_FILE = "csr_save.json"
local LEGACY_SETTINGS_FILE = "crime_spree_roguelike.json"
local LEGACY_MP_SESSIONS_FILE = "csr_mp_sessions.json"

-- False until init() loads settings; kept in sync by set_setting.
_G.CSR_DEBUG = _G.CSR_DEBUG or false

_G.csr_log = function(msg)
	if _G.CSR_DEBUG then
		log(msg)
	end
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

local function default_meta()
	return {
		version = CSRGameManager.VERSION,
		stats = {},
		unlocks = {},
		settings = {},
		-- Per-host guest inventories, keyed by "h<seed>". In _meta so they survive own start/end_run; pruned by age.
		mp_sessions = {},
		-- Bucket B: rewards earned while guesting. Accumulates across hosts; claimed at own End Spree as A+B.
		mp_earnings = { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 },
	}
end

local function default_state()
	return {
		is_active = false,
		rank = 0,
		-- Tracked separately from rank because rank may have multiple sources.
		missions_completed = 0,
		-- A failed run stays active but locked until the player pays Continue or ends the run.
		failed = false,
		-- Internal difficulty id (e.g. "overkill_145"); nil until start_run seeds it.
		difficulty = nil,
		seed = nil,
		mission_set = {}, -- array of mission ids currently offered in the lobby
		current_mission = nil, -- id of the mission the player picked to play next
		peer_items = {},
		-- Accumulated looted cash toward the next loot-rank; remainder carries across heists.
		loot_rank_cash = 0,
		milestones = {},
		spawners = { copiers = {}, scrappers = {} },
		mp_session = {},
	}
end

local function default_registry()
	return {
		items = {},
		by_type = {}, -- [type] = entry
		by_kind = {}, -- [effect.kind] = { entry, ... }
		callback_items = {}, -- items with on_apply/on_remove/on_tick
		modifiers = {
			loud = {},
			stealth_families = {},
			by_id = {},
		},
		constants = {
			dog_tags_hp_bonus = 0.10,
			rank_per_heist = 1,
			-- Continue cost = continue_cost_base + continue_cost_per_mission * missions_completed
			continue_cost_base = 10,
			continue_cost_per_mission = 10,
		},
	}
end

function CSRGameManager:init()
	self._meta = default_meta()
	self._state = default_state()
	self._registry = default_registry()
	-- Remote peers' synced item counts for MP visibility: { [peer_id] = { counts, name } }.
	-- Runtime-only (filled by mp_sync.lua, read via player_items) -- never saved to csr_save.json.
	self._remote_peer_items = {}
	self._callbacks = {
		on_mission_started = {},
		on_mission_completed = {},
		on_item_added = {},
		on_item_removed = {},
	}
	self:_migrate_legacy_save()
	self:load()
	self._debug = (self._meta.settings and self._meta.settings.debug_mode) == true
	_G.CSR_DEBUG = self._debug
	-- Replay registrations into the fresh _registry every init (idempotent, never drains).
	if _G.CSR and _G.CSR._apply_registrations then
		_G.CSR._apply_registrations(self)
	end
	if _G.CSR and _G.CSR._apply_modifier_registrations then
		_G.CSR._apply_modifier_registrations(self)
	end
	-- Drop owned items whose addon is no longer registered; re-arms the lobby pick reminder.
	self:_drop_orphan_items()
	self:_prune_expired_sessions()
	-- Wire reconcile to every ownership/run transition so on_apply fires on save-reload too.
	-- Fresh _callbacks table each init prevents stacking duplicate listeners.
	self._applied_callbacks = {}
	local function reconcile_cb()
		self:reconcile_callback_items()
	end
	self:on_mission_started(reconcile_cb)
	self:on_mission_completed(reconcile_cb)
	self:on_item_added(reconcile_cb)
	self:on_item_removed(reconcile_cb)
	self:reconcile_callback_items()
	self:_setup_temporary_job()
	-- MissionAssetsManager:init() ran before our narrative chain was set, so the Assets tab stayed empty.
	-- Re-run _setup_mission_assets manually; clear first because it appends (would duplicate on re-init).
	if self:is_run_active() and managers.assets and managers.assets._setup_mission_assets then
		if managers.assets._global then
			managers.assets._global.assets = {}
		end
		managers.assets:_setup_mission_assets()
	end
	log_csr("CSRGameManager initialised; version=" .. tostring(self._meta.version))
end

-- Re-establish the crime_spree narrative chain from Global.game_settings.level_id each time managers init.
-- Without this the game-side manager has an empty chain (set by select_mission only on menu-side),
-- causing nil-crashes in HUDMissionBriefing / MissionBriefingGui on heist launch.
function CSRGameManager:_setup_temporary_job()
	-- Not gated on is_active() — a guest has is_active=false but still needs the chain for briefing surfaces.
	local gs = Global and Global.game_settings
	local level_id = gs and gs.level_id
	if not level_id then
		return
	end
	local narrative = tweak_data and tweak_data.narrative
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if not narrative or not narrative.jobs or not narrative.jobs.crime_spree or type(cs_missions) ~= "table" then
		return
	end
	local want_mission = gs.mission or "none"
	local fallback_level = nil
	for _, tier in ipairs(cs_missions) do
		for _, m in ipairs(tier) do
			if m.level and m.level.level_id == level_id then
				-- Exact match wins; keep a level-only fallback in case the variant string drifted.
				if (m.mission or "none") == want_mission then
					narrative.jobs.crime_spree.chain = { m.level }
					log_csr("_setup_temporary_job: chain set from level_id=" .. tostring(level_id))
					return
				end
				fallback_level = fallback_level or m.level
			end
		end
	end
	if fallback_level then
		narrative.jobs.crime_spree.chain = { fallback_level }
		log_csr("_setup_temporary_job: chain set (level-only) from level_id=" .. tostring(level_id))
	end
end

-- =====================================================
-- Run-state queries
-- =====================================================

function CSRGameManager:is_run_active()
	-- Alpha stub: always true so item hooks never bail.
	return true
end

function CSRGameManager:is_active()
	-- True only while a CSR run is actually in flight (flipped by start_run/end_run).
	return self._state.is_active == true
end

-- True only while the local player is actually INSIDE a CSR heist (temp crime_spree job loaded).
-- THIS is the gate for every gameplay stat/buff hook so nothing leaks into vanilla heists.
-- Works for guests too: they load the same crime_spree job, even though is_active() is false for them.
-- Note: real vanilla Crime Spree also uses job_id "crime_spree"; CSR runs the STANDARD gamemode, so a
-- truthy crime_spree:is_active() means we're in actual CS (not CSR) -> bail. (Mirrors csr_heist_active().)
function CSRGameManager:in_csr_heist()
	if not (managers and managers.job and managers.job.current_job_id) then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree.is_active and managers.crime_spree:is_active() then
		return false
	end
	return true
end

function CSRGameManager:rank()
	return self._state.rank or 0
end

function CSRGameManager:missions_completed()
	return self._state.missions_completed or 0
end

function CSRGameManager:_default_difficulty()
	-- Remembered preference -> CS base difficulty -> hardcoded fallback.
	local cs_td = tweak_data and tweak_data.crime_spree
	local remembered = self._meta.settings and self._meta.settings.last_difficulty
	return remembered or (cs_td and cs_td.base_difficulty) or "overkill_145"
end

function CSRGameManager:difficulty()
	return self._state.difficulty or self:_default_difficulty()
end

function CSRGameManager:set_difficulty(diff)
	-- Also persists as the remembered preference for the next contract open. Rejects unknown ids.
	if type(diff) ~= "string" then
		return false
	end
	local diffs = tweak_data and tweak_data.difficulties
	if type(diffs) == "table" and not table.contains(diffs, diff) then
		log("[CSR] set_difficulty: unknown difficulty '" .. tostring(diff) .. "' — ignored")
		return false
	end
	self._state.difficulty = diff
	self._meta.settings = self._meta.settings or {}
	self._meta.settings.last_difficulty = diff
	self:save()
	log_csr("set_difficulty: " .. diff)
	return true
end

-- [Tier 1 split] end-of-run rewards + guest earnings + MP host-state mirror -> managers/game_manager/gm_rewards.lua

function CSRGameManager:mod_version()
	return (self._meta and self._meta.version) or "unknown"
end

-- =====================================================
-- Peer ID
-- =====================================================

function CSRGameManager:local_peer_id()
	-- Cached per session: the local peer id is stable for a session's lifetime, and
	-- this is queried per-hit by combat item hooks. Cache is cleared on session load
	-- (see CSR_ResetLocalPeerIdCache). Only a real resolved id is cached, never the
	-- fallback, so a pre-session call doesn't pin the cache to 1.
	if self._cached_local_peer_id then
		return self._cached_local_peer_id
	end
	local nm = managers and managers.network
	if nm and nm.session then
		local session = nm:session()
		if session and session.local_peer then
			local peer = session:local_peer()
			if peer and peer.id then
				local id = peer:id()
				self._cached_local_peer_id = id
				return id
			end
		end
	end
	return 1
end

-- [Tier 1 split] item inventory + peer counts + remote-peer mirror -> managers/game_manager/gm_inventory.lua

-- [Tier 1 split] item + modifier registration & enemy scaling -> managers/game_manager/gm_registry.lua

-- [Tier 1 split] stat helpers (items_of_kind / sum_stat_mul / combine_stat_hyperbolic) -> managers/game_manager/gm_stats.lua

-- [Tier 1 split] item callbacks (on_apply/remove/tick) + orphan/session maintenance -> managers/game_manager/gm_callbacks.lua

-- [Tier 1 split] item-pool roll + pending offers -> managers/game_manager/gm_offers.lua
-- [Tier 1 split] mission set & selection -> managers/game_manager/gm_missions.lua

-- =====================================================
-- Run lifecycle (alpha stubs)
-- =====================================================

function CSRGameManager:start_run()
	-- Always resets: no "continue" flow; a leftover rank from a stale save would break the flat-1-rank balance.
	if self._state.is_active then
		log_csr(
			"start_run: discarding a leftover active run (rank=" .. tostring(self._state.rank) .. ") and starting fresh"
		)
	end
	self._state.is_active = true
	self._state.failed = false
	self._state.rank = 0
	self._state.missions_completed = 0
	self._state.difficulty = self:_default_difficulty()
	self._state.seed = math.random(1, 2 ^ 30)
	-- Wipe inventory so Items panel doesn't carry stacks from a prior run.
	self._state.peer_items = {}
	self._state.loot_rank_cash = 0
	self._state.mp_session = {}
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
	self._state.failed = false
	-- Wipe inventory so UI doesn't render stale stacks after the run ends.
	self._state.peer_items = {}
	self._state.mp_session = {}
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

-- Increments missions_completed (tracked separately from rank because rank-per-heist is tunable).
function CSRGameManager:record_mission_completed()
	if not self._state.is_active then
		log_csr("record_mission_completed: no active run; ignored")
		return false
	end
	self._state.missions_completed = (self._state.missions_completed or 0) + 1
	log_csr("record_mission_completed: now " .. tostring(self._state.missions_completed))
	self:save()
	return true
end

-- =====================================================
-- Registries & settings
-- =====================================================

-- =====================================================
-- Failed-run state + continue cost (Slice B)
-- =====================================================

function CSRGameManager:has_failed()
	return self._state.failed == true
end

-- Flag the run as failed (locked until Continue or End Spree). Does not end the run.
function CSRGameManager:mark_failed()
	if not self._state.is_active then
		log_csr("mark_failed: no active run; ignored")
		return false
	end
	self._state.failed = true
	log_csr("mark_failed: run is now FAILED at rank=" .. tostring(self._state.rank))
	self:save()
	return true
end

-- Clear the failed flag after the player pays the Continue cost.
function CSRGameManager:clear_failed()
	if not self._state.failed then
		return false
	end
	self._state.failed = false
	log_csr("clear_failed: failed state cleared (run continues)")
	self:save()
	return true
end

function CSRGameManager:get_continue_cost()
	local base = self:constant("continue_cost_base") or 0
	local per = self:constant("continue_cost_per_mission") or 0
	return base + per * (self._state.missions_completed or 0)
end

function CSRGameManager:constant(name)
	return self._registry.constants and self._registry.constants[name]
end

function CSRGameManager:setting(key)
	return self._meta.settings[key]
end

function CSRGameManager:set_setting(key, value)
	self._meta.settings[key] = value
	if key == "debug_mode" then
		self._debug = value == true
		_G.CSR_DEBUG = self._debug
	end
	self:save()
end

-- =====================================================
-- Debug logging
-- _debug_stat logs only on value change to avoid flooding per-frame stat bonuses.
-- =====================================================

function CSRGameManager:debug_enabled()
	return self._debug == true
end

function CSRGameManager:debug_log(msg)
	if self._debug then
		log("[CSR][dbg] " .. tostring(msg))
	end
end

function CSRGameManager:_debug_stat(group, stat, value)
	if not self._debug then
		return
	end
	local cache = self._dbg_stat
	if not cache then
		cache = {}
		self._dbg_stat = cache
	end
	local g = cache[group]
	if not g then
		g = {}
		cache[group] = g
	end
	if g[stat] ~= value then
		g[stat] = value
		log(string.format("[CSR][dbg] %s '%s' bonus -> %.4f", group, stat, value))
	end
end

-- Debug: grant one of every item to the peer (bypasses selection window).
function CSRGameManager:grant_all_items(peer_id)
	peer_id = peer_id or self:local_peer_id()
	local granted = 0
	for _, item in ipairs(self._registry.items) do
		if self:add_item(peer_id, item.type) then
			granted = granted + 1
		end
	end
	log_csr("grant_all_items: granted " .. granted .. " item type(s) to peer " .. tostring(peer_id))
	return granted
end

-- Debug: force the lobby to a single card for level_id (e.g. "red2") and pre-select it.
function CSRGameManager:debug_force_mission(level_id)
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		log_csr("debug_force_mission: CS missions not ready")
		return false
	end
	for _, tier in ipairs(cs_missions) do
		for _, m in ipairs(tier) do
			if m.id and m.level and m.level.level_id == level_id then
				self._state.mission_set = { m.id }
				self._state.current_mission = m.id
				self:save()
				log_csr("debug_force_mission: forced '" .. tostring(m.id) .. "' (level " .. tostring(level_id) .. ")")
				return true
			end
		end
	end
	log_csr("debug_force_mission: no CS mission for level '" .. tostring(level_id) .. "'")
	return false
end

-- =====================================================
-- Event registration
-- =====================================================

-- Registers fn and returns an unsubscribe token. UI components MUST call it on teardown
-- or closures stack up for every lobby open.
local function register_callback(list, fn)
	if type(fn) ~= "function" then
		return function() end
	end
	table.insert(list, fn)
	return function()
		for i = 1, #list do
			if list[i] == fn then
				table.remove(list, i)
				return
			end
		end
	end
end

function CSRGameManager:on_mission_started(fn)
	return register_callback(self._callbacks.on_mission_started, fn)
end

function CSRGameManager:on_mission_completed(fn)
	return register_callback(self._callbacks.on_mission_completed, fn)
end

function CSRGameManager:on_item_added(fn)
	return register_callback(self._callbacks.on_item_added, fn)
end

function CSRGameManager:on_item_removed(fn)
	return register_callback(self._callbacks.on_item_removed, fn)
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
		log("[CSR] ERROR save: json.encode failed -> " .. tostring(encoded))
		return false
	end
	local f = io.open(path, "w")
	if not f then
		log("[CSR] ERROR save: could not open for write -> " .. path)
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
		log("[CSR] ERROR load: json.decode failed -> " .. tostring(decoded))
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

-- Static setting read before managers.csr exists (MenuManager:init runs before init_managers PostHook).
function CSRGameManager.peek_setting(key)
	local f = io.open(save_path(SAVE_FILE), "r")
	if not f then
		return nil
	end
	local raw = f:read("*all")
	f:close()
	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local settings = decoded.meta and decoded.meta.settings
	return settings and settings[key]
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
-- Attach to managers table (covers both MenuSetup and GameSetup via Setup:init_managers)
-- =====================================================

Hooks:PostHook(Setup, "init_managers", "CSR_AttachGameManager", function(self, managers)
	if managers.csr then
		return
	end
	managers.csr = CSRGameManager:new()
end)

-- Peer ids are reassigned when a new network session loads (join/host). Drop the
-- cached local peer id so the next query re-resolves it for the new session.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_ResetLocalPeerIdCache", function()
	if managers and managers.csr then
		managers.csr._cached_local_peer_id = nil
	end
end)
