-- Public CSR API shim. Defines _G.CSR so addon mods can register items / modifiers
-- / sounds regardless of load order. Hooked on three early targets so this runs
-- before any other CSR file (see csr_log_bootstrap_timing); _bootstrapped guards
-- against re-init.

if not RequiredScript then
	return
end

if _G.CSR and _G.CSR._bootstrapped then
	return
end

_G.CSR = _G.CSR or {}
_G.CSR._bootstrapped = true
-- Bump on any breaking change to the register_* contract.
_G.CSR.API_VERSION = 1

_G.CSR_DEBUG = _G.CSR_DEBUG or false
if not _G.csr_log then
	_G.csr_log = function(msg)
		if _G.CSR_DEBUG then
			log(msg)
		end
	end
end

-- Persistent lists. CSRGameManager:init() runs multiple times per session and
-- builds an empty _registry each time, so every init must replay these.
_G.CSR._registrations = _G.CSR._registrations or {}
_G.CSR._modifier_registrations = _G.CSR._modifier_registrations or {}
_G.CSR._sound_registrations = _G.CSR._sound_registrations or {}

-- Item-hook dispatcher: item_dispatch.lua hooks `*` and calls on_script_loaded
-- on every engine script load. We install matching item/modifier hooks then.
_G.CSR._hooks_by_req = _G.CSR._hooks_by_req or {} -- [req_lower] = { {type=, fn=}, ... }
_G.CSR._installed_hooks = _G.CSR._installed_hooks or {} -- ["type|req"] = true
_G.CSR._loaded_reqs = _G.CSR._loaded_reqs or {} -- [req_lower] = true

local function manager_ready()
	return managers and managers.csr and managers.csr.register_item ~= nil
end

function _G.CSR._install_hook(item_type, req_lower, fn)
	local gkey = tostring(item_type) .. "|" .. req_lower
	if _G.CSR._installed_hooks[gkey] then
		return
	end
	_G.CSR._installed_hooks[gkey] = true
	local ok, err = pcall(fn)
	if not ok then
		log("[CSR][api] hook for '" .. tostring(item_type) .. "' @ " .. req_lower .. " failed: " .. tostring(err))
	end
end

function _G.CSR.on_script_loaded(req)
	if type(req) ~= "string" then
		return
	end
	local key = req:lower()
	_G.CSR._loaded_reqs[key] = true
	local bucket = _G.CSR._hooks_by_req[key]
	if not bucket then
		return
	end
	for i = 1, #bucket do
		_G.CSR._install_hook(bucket[i].type, key, bucket[i].fn)
	end
end

-- Dedup key falls back to def.id for modifiers (no def.type) — must be unique
-- across modifiers hooking the same script.
local function index_item_hooks(def)
	if type(def.hooks) ~= "table" then
		return
	end
	local owner = def.type or def.id
	for req, fn in pairs(def.hooks) do
		if type(req) == "string" and type(fn) == "function" then
			local key = req:lower()
			local bucket = _G.CSR._hooks_by_req[key]
			if not bucket then
				bucket = {}
				_G.CSR._hooks_by_req[key] = bucket
			end
			bucket[#bucket + 1] = { type = owner, fn = fn }
			if _G.CSR._loaded_reqs[key] then
				_G.CSR._install_hook(owner, key, fn)
			end
		end
	end
end

function _G.CSR.register_item(def)
	if type(def) ~= "table" then
		log("[CSR][api] register_item: definition must be a table -- ignored")
		return false
	end
	table.insert(_G.CSR._registrations, def)
	if manager_ready() then
		managers.csr:register_item(def)
	end
	index_item_hooks(def)
	return true
end

function _G.CSR.register_modifier(def)
	if type(def) ~= "table" then
		log("[CSR][api] register_modifier: definition must be a table -- ignored")
		return false
	end
	table.insert(_G.CSR._modifier_registrations, def)
	if managers and managers.csr and managers.csr.register_modifier then
		managers.csr:register_modifier(def)
	end
	-- Modifiers without a vanilla ModifierX class (e.g. Guilty Conscience) hand-roll
	-- their effect via behavior hooks, same as items.
	index_item_hooks(def)
	return true
end

function _G.CSR._apply_modifier_registrations(mgr)
	for _, def in ipairs(_G.CSR._modifier_registrations) do
		mgr:register_modifier(def)
	end
end

function _G.CSR._apply_registrations(mgr)
	for _, def in ipairs(_G.CSR._registrations) do
		mgr:register_item(def)
	end
end

-- def = { path = "<rel.ogg>" } or { pattern = "<rel_$.ogg>", n = <count> }.
-- Safe to call any time — sound.lua installs the loader and sweeps registrations
-- when its XAudio retry loop succeeds.
function _G.CSR.register_sound(name, def)
	if type(name) ~= "string" or type(def) ~= "table" then
		log("[CSR][api] register_sound: (name string, def table) required -- ignored")
		return false
	end
	_G.CSR._sound_registrations[name] = def
	if _G.CSR._sound_loader_ready and _G.CSR._load_sound then
		_G.CSR._load_sound(name, def)
	end
	return true
end

function _G.CSR.play_sound(name, opts)
	if _G.CSR._play_sound then
		return _G.CSR._play_sound(name, opts)
	end
	return nil
end

-- Recursively dofile every .lua under `dir`. Files self-register (PD2's dofile
-- returns nothing), exactly as an addon mod would.
local function run_lua_dir(dir, label)
	local count = 0
	local names = file.GetFiles(dir)
	if names then
		for _, name in pairs(names) do
			if type(name) == "string" and name:sub(-4) == ".lua" then
				local ok, err = pcall(dofile, dir .. name)
				if ok then
					count = count + 1
				else
					log("[CSR][api] " .. label .. ": '" .. tostring(name) .. "' failed to load: " .. tostring(err))
				end
			end
		end
	end
	local subdirs = file.GetDirectories and file.GetDirectories(dir)
	if subdirs then
		for _, sub in pairs(subdirs) do
			if type(sub) == "string" then
				count = count + run_lua_dir(dir .. sub .. "/", label)
			end
		end
	end
	return count
end

-- Drop a .lua under lua/items/ to add an item; no mod.txt edit needed.
local function load_item_defs()
	if not (file and file.GetFiles and ModPath) then
		log("[CSR][api] items: file API or ModPath unavailable -- skipped")
		return
	end
	local count = run_lua_dir(ModPath .. "lua/items/", "items")
	csr_log("[CSR][api] items: ran " .. count .. " item file(s)")
end

local function load_modifier_defs()
	if not (file and file.GetFiles and ModPath) then
		log("[CSR][api] modifiers: file API or ModPath unavailable -- skipped")
		return
	end
	local count = run_lua_dir(ModPath .. "lua/modifiers/", "modifiers")
	csr_log("[CSR][api] modifiers: ran " .. count .. " modifier file(s)")
end

load_item_defs()
load_modifier_defs()

-- Drain engine scripts that the wildcard delegator buffered before _G.CSR existed
-- (engine classes loaded inside lib/entry's body, e.g. PlayerManager). The hook
-- index is now built, so install any of their hooks.
if _G.__CSR_pending_reqs then
	local pending = _G.__CSR_pending_reqs
	_G.__CSR_pending_reqs = nil
	for i = 1, #pending do
		_G.CSR.on_script_loaded(pending[i])
	end
end

csr_log("[CSR] extension_api.lua loaded (API v" .. tostring(_G.CSR.API_VERSION) .. ")")
