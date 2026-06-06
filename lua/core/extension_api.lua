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

-- Active-wildcard registry. DEFINED HERE (not in wildcard_dispatcher.lua) because
-- items register their active from a lib/managers/playermanager hook, which fires
-- during lib/entry's body (PlayerManager is required in setup.lua) — BEFORE the
-- dispatcher's own lib/entry POST-hook loads. extension_api bootstraps first, so
-- defining the registrar here guarantees it exists when item hooks run. The
-- dispatcher only READS CSR_WildcardActives at key-press time (CSR_TriggerWildcard).
_G.CSR_WildcardActives = _G.CSR_WildcardActives or {}
function _G.CSR_RegisterWildcardActive(item_type, activate)
	if not item_type or type(activate) ~= "function" then
		return
	end
	_G.CSR_WildcardActives[item_type] = activate
end

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

-- Stamp the addon currently being loaded onto a def (load-order safe; nil outside addon load).
local function autostamp_addon(def)
	if def.addon == nil and _G.CSR._current_addon then
		def.addon = _G.CSR._current_addon
	end
end

function _G.CSR.register_item(def)
	if type(def) ~= "table" then
		log("[CSR][api] register_item: definition must be a table -- ignored")
		return false
	end
	autostamp_addon(def)
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
	autostamp_addon(def)
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
	-- Stamp the add-on folder so the loader resolves sound files relative to it
	-- (nil for built-in sounds, which resolve against the mod folder).
	if def._addon_dir == nil and _G.CSR._current_addon_dir then
		def._addon_dir = _G.CSR._current_addon_dir
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

-- Set while an addon's main.lua runs (see load_addons); nil otherwise.
function _G.CSR.addon_dir()
	return _G.CSR._current_addon_dir
end

function _G.CSR.addon_name()
	return _G.CSR._current_addon
end

-- Register an addon icon into the texture DB. db_path = the string the author puts in their
-- item's `icon` field (must contain "/" so icon surfaces treat it as a full DB path); rel_file
-- = .dds path RELATIVE to the addon folder. Addon-load-time only. Returns db_path on success.
function _G.CSR.register_texture(db_path, rel_file)
	if type(db_path) ~= "string" or type(rel_file) ~= "string" then
		log("[CSR][api] register_texture: (db_path string, rel_file string) required -- ignored")
		return nil
	end
	if not _G.CSR._current_addon_dir then
		log("[CSR][api] register_texture: no addon context (call from main.lua) -- ignored")
		return nil
	end
	local abs = _G.CSR._current_addon_dir .. rel_file
	if Application and Application.nice_path then
		abs = Application:nice_path(abs, false)
	end
	if DB and DB.create_entry then
		DB:create_entry(Idstring("texture"), Idstring(db_path), abs)
	else
		log("[CSR][api] register_texture: DB unavailable for '" .. db_path .. "' -- icon will be missing")
	end
	return db_path
end

-- Resolve an item/modifier icon to (texture, rect). A value containing "/" is a full
-- DB texture path (addon icon from register_texture, drawn whole at 128x128); anything
-- else is a built-in hud_icons id. Single source of truth for every CSR icon surface.
function _G.CSR.icon_data(raw)
	if type(raw) == "string" and raw:find("/", 1, true) then
		return raw, { 0, 0, 128, 128 }
	end
	return tweak_data.hud_icons:get_icon_data(raw)
end

-- Resolve an item/modifier loc key, substituting the def's number macros (def.loc_macros) so tuning
-- constants defined once in the item file auto-fill $macros in the localized desc/effect/notes.
-- `src` is any table carrying loc_macros (a registry entry / def / logbook item_data); nil-safe.
function _G.CSR.item_text(key, src)
	if not (managers and managers.localization) then
		return key or ""
	end
	return managers.localization:text(key, src and src.loc_macros or nil)
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

IMPORTANT: call CSR.register_item() / CSR.register_modifier() at the TOP LEVEL of main.lua
(i.e. not inside a Hooks:PostHook or DelayedCall). Items registered from deferred callbacks
run after the addon context is cleared and will NOT appear in the multiplayer add-on signature
check, so guests missing your add-on could join without being blocked. If you must defer,
pass addon = CSR.addon_name() explicitly in the definition table BEFORE the hook fires:
  local MY_ADDON = CSR.addon_name()   -- capture at top-level while context is set
  Hooks:PostHook(SomeClass, "init", "my_id", function()
    CSR.register_item({ addon = MY_ADDON, ... })
  end)

For item icons, call CSR.register_texture("your/db/path", "icons/your_icon.dds") in main.lua
(the file path is relative to your add-on folder) and set icon = "your/db/path" on the item.

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

-- Run each user addon's main.lua from mods/saves/<ADDON_FOLDER_NAME>/<addon>/. One main.lua
-- per addon folder (NOT recursive); the addon dofiles its own helpers via CSR.addon_dir().
-- Runs at hudiconstweakdata time, so DB is ready for register_texture inside main.lua.
local function load_addons()
	if not (file and file.GetDirectories and SavePath) then
		log("[CSR][api] addons: file API or SavePath unavailable -- skipped")
		return
	end

	local base = SavePath .. ADDON_FOLDER_NAME .. "/"
	if Application and Application.nice_path then
		base = Application:nice_path(base, true)
	end

	local dirs = file.GetDirectories(base)
	if not dirs then
		return
	end

	local count = 0
	for _, name in pairs(dirs) do
		if type(name) == "string" then
			local dir = base .. name .. "/"

			-- Skip folders without a main.lua so stray folders don't spam dofile errors.
			local has_main = false
			local names = file.GetFiles and file.GetFiles(dir)
			if names then
				for _, f in pairs(names) do
					if f == "main.lua" then
						has_main = true
						break
					end
				end
			end

			if has_main then
				_G.CSR._current_addon = name
				_G.CSR._current_addon_dir = dir
				local ok, err = pcall(dofile, dir .. "main.lua")
				if ok then
					count = count + 1
				else
					log("[CSR][api] addon '" .. name .. "': main.lua failed: " .. tostring(err))
				end
				_G.CSR._current_addon = nil
				_G.CSR._current_addon_dir = nil
			end
		end
	end

	csr_log("[CSR][api] addons: ran " .. count .. " addon main.lua file(s)")
end

load_item_defs()
load_modifier_defs()
ensure_addon_folder()
load_addons()

-- Drain scripts buffered before _G.CSR existed (loaded inside lib/entry before this ran).
if _G.__CSR_pending_reqs then
	local pending = _G.__CSR_pending_reqs
	_G.__CSR_pending_reqs = nil
	for i = 1, #pending do
		_G.CSR.on_script_loaded(pending[i])
	end
end

csr_log("[CSR] extension_api.lua loaded (API v" .. tostring(_G.CSR.API_VERSION) .. ")")
