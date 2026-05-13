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
-- Run lifecycle (alpha stubs)
-- =====================================================

function CSRGameManager:start_run()
	if self._state.is_active then
		log_csr("start_run: a run is already active (rank=" .. tostring(self._state.rank) .. "); ignored")
		return false
	end
	self._state.is_active = true
	self._state.rank = 0
	self._state.difficulty = self._state.difficulty or "overkill"
	self._state.seed = math.random(1, 2 ^ 30)
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
