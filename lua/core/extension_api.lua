-- Public CSR API shim. Defines _G.CSR for addon mods; _bootstrapped guards against re-init.

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

-- Persistent lists — replayed into each fresh CSRGameManager:init() registry.
_G.CSR._registrations = _G.CSR._registrations or {}
_G.CSR._modifier_registrations = _G.CSR._modifier_registrations or {}
_G.CSR._sound_registrations = _G.CSR._sound_registrations or {}

-- Hook dispatch tables — populated by register_item/modifier, fired by on_script_loaded.
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

-- Dedup key: modifiers use def.id (no def.type); must be unique per script target.
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
	-- Class-less modifiers (e.g. Guilty Conscience) use behavior hooks, same as items.
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

-- def = { path = "<rel.ogg>" } or { pattern = "<rel_$.ogg>", n = <count> }. Safe to call any time.
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

-- Recursively dofile every .lua under `dir`; files self-register via register_item/modifier.
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

-- User addon drop-in folder. Lives under mods/saves/ (SavePath) so CSR updates never
-- wipe it (updates replace the mod folder, not saves). For now we only ensure the
-- folder + README exist; the loader that reads addons from here lands in a later slice.
local ADDON_FOLDER_NAME = "CSR Addons"
local ADDON_README_TEXT = [[CSR Addons
==========

This folder is where you install add-ons for Crime Spree Roguelike.

How to install an add-on:
  - Each add-on is its OWN folder placed directly inside this folder.
  - Example:  CSR Addons/My-Super-CoolAddon/main.lua
  - Do NOT drop loose files or archives (.zip, .7z, ...) directly here -- they are ignored.

Each add-on folder runs its "main.lua" on launch, which registers the add-on's
items/modifiers through the CSR API. Restart the game after adding or removing an add-on.

You can safely delete this README. It is only regenerated if the whole "CSR Addons"
folder is missing on launch.
]]

-- Idempotent: bails when the folder already exists, so a user-deleted README is not
-- regenerated unless the whole folder was removed (matches the ACH addon-folder model).
local function ensure_addon_folder()
	if not SavePath then
		log("[CSR][api] addon folder: SavePath unavailable -- skipped")
		return
	end

	local base = SavePath .. ADDON_FOLDER_NAME .. "/"
	if Application and Application.nice_path then
		base = Application:nice_path(base, true)
	end

	if file and file.DirectoryExists and file.DirectoryExists(base) then
		return
	end

	if not (SystemFS and SystemFS.make_dir) then
		log("[CSR][api] addon folder: SystemFS:make_dir unavailable -- skipped")
		return
	end
	SystemFS:make_dir(base)

	local readme = io.open(base .. "README.txt", "w+")
	if readme then
		readme:write(ADDON_README_TEXT)
		readme:close()
		csr_log("[CSR][api] created addon folder + README at " .. base)
	else
		log("[CSR][api] addon folder: failed to write README at " .. base)
	end
end

load_item_defs()
load_modifier_defs()
ensure_addon_folder()

-- Drain scripts buffered before _G.CSR existed (loaded inside lib/entry before this ran).
if _G.__CSR_pending_reqs then
	local pending = _G.__CSR_pending_reqs
	_G.__CSR_pending_reqs = nil
	for i = 1, #pending do
		_G.CSR.on_script_loaded(pending[i])
	end
end

csr_log("[CSR] extension_api.lua loaded (API v" .. tostring(_G.CSR.API_VERSION) .. ")")
