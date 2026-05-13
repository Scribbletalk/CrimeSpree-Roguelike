-- CSRGameManager — single source of truth for Crime Spree Roguelike state.
--
-- Replaces every _G.CSR_* global and the four legacy persistence surfaces
-- (crime_spree_roguelike.json, csr_mp_sessions.json, crime_spree_seed.txt,
-- and our slice of Global.crime_spree) with one hierarchical singleton:
--   managers.csr._meta      (carries across runs and mod updates)
--   managers.csr._state     (active run, resets between runs)
--   managers.csr._registry  (static authored content, read-only after init)
--
-- This file is the alpha skeleton. Methods are stubbed; only save/load and the
-- legacy-save scout are wired. Item logic, MP, and rolling come in later phases.

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
		peer_items = {},
		milestones = {},
		spawners = { copiers = {}, scrappers = {} },
		mp_session = {},
	}
end

local function default_registry()
	return {
		items = {},
		by_type = {},
		by_prefix = {},
		constants = {},
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
	local loaded = self:load()
	if not loaded then
		log_csr("init: no prior save; writing initial save to validate roundtrip")
		self:save()
	end
	log_csr("CSRGameManager initialised; version=" .. tostring(self._meta.version))
end

-- =====================================================
-- Run-state queries (replace managers.crime_spree:* reads)
-- =====================================================

function CSRGameManager:is_run_active()
	return self._state.is_active == true
end

function CSRGameManager:rank()
	return self._state.rank or 0
end

function CSRGameManager:difficulty()
	return self._state.difficulty
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
-- Items (replace _G.CSR_PlayerItems reads)
-- =====================================================

function CSRGameManager:player_items(peer_id)
	local entry = self._state.peer_items[peer_id]
	return entry and entry.items or {}
end

function CSRGameManager:item_count(peer_id, prefix)
	-- TODO[alpha-port]: count items in player_items(peer_id) whose id starts with prefix.
	return 0
end

function CSRGameManager:has_item(peer_id, item_type)
	-- TODO[alpha-port]: scan player_items(peer_id) for any entry whose type field matches item_type.
	return false
end

function CSRGameManager:add_item(peer_id, item_id)
	-- TODO[alpha-port]: append item_id, fire on_item_added callbacks, save, broadcast (host).
end

function CSRGameManager:remove_item(peer_id, item_id)
	-- TODO[alpha-port]: remove first matching entry, fire on_item_removed callbacks, save, broadcast (host).
end

function CSRGameManager:roll_item_pool(peer_id, count)
	-- TODO[alpha-port]: replaces crimespree_filter.lua overrides. Roll `count` items from
	-- _registry.items for peer_id, respecting rarity weights, per-peer caps, and shop exemptions.
	return {}
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
-- Event registration (replaces PostHook(CrimeSpreeManager, ...) chains)
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
-- Legacy-save migrator
--
-- Stub. Reports which legacy files are present on disk so we know what to
-- consume in the next session. Does NOT touch the legacy files; meta
-- population happens after the migrator is fleshed out.
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

	-- Note: crime_spree_seed.txt lives under <PD2 root>/mods/saves/, not SavePath.
	-- That probe needs the BLT ModPath helper and is deferred to the full migrator pass.

	log_csr("migrator: stub run complete; legacy files untouched")
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
