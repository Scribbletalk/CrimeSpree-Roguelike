-- CSR public extension API — bootstrap shim.
--
-- Defines _G.CSR as early as possible (hooked on lib/entry) so a SEPARATE
-- addon mod can call CSR.register_item{...} at its own file load regardless of
-- SuperBLT's non-deterministic inter-mod order.
--
-- Registrations are kept in a PERSISTENT list (_registrations), NOT a
-- drain-once queue. CSRGameManager:init() runs more than once per session
-- (MenuSetup AND GameSetup, and again on return-to-menu — see that file's
-- header), and each init rebuilds an EMPTY _registry. So every init must
-- REPLAY the full registration list, not consume it once. register_item also
-- applies immediately if the manager is already up (addon loaded late), and
-- still records into the list so the next init replays it. CSRGameManager's
-- own by_type check makes a replay idempotent within a manager instance.
--
-- This file owns ONLY the public surface + the persistent list. The registry,
-- validation and mechanic dispatch live in CSRGameManager (single source of
-- truth) — the same path CSR's own items use (dogfooded; see
-- csr_builtin_items.lua).
--
-- Design record: projects/Crime Spree Roguelike/csr_mod_extension_api_design.md

if not RequiredScript then
	return
end

if _G.CSR and _G.CSR._bootstrapped then
	return
end

_G.CSR = _G.CSR or {}
_G.CSR._bootstrapped = true
-- Integer API version. Addons may gate on it; bump on any breaking change to
-- the register_* contract (design open item O2).
_G.CSR.API_VERSION = 1
-- Persistent: never cleared. Replayed into every CSRGameManager instance.
_G.CSR._registrations = _G.CSR._registrations or {}
_G.CSR._modifier_registrations = _G.CSR._modifier_registrations or {}
-- Persistent sound registry, keyed by name (re-registration dedupes). Owned
-- here so an addon can register a sound before sound.lua loads (SuperBLT
-- inter-mod order is non-deterministic, same reason _registrations exists).
-- sound.lua loads every entry once blt.xaudio is up, and a registration
-- that arrives AFTER that load is loaded immediately (see register_sound).
_G.CSR._sound_registrations = _G.CSR._sound_registrations or {}

-- Behavior-hook index for the per-item file model. An item def may carry a
-- `hooks` table { ["<RequiredScript path>"] = function() ... end }; each function
-- runs ONCE, when that engine script loads (the wildcard delegator
-- lua/core/item_dispatch.lua calls on_script_loaded on every load). Kept here,
-- not on the manager, so hook timing is independent of manager init.
_G.CSR._hooks_by_req = _G.CSR._hooks_by_req or {} -- [req_lower] = { {type=, fn=}, ... }
_G.CSR._installed_hooks = _G.CSR._installed_hooks or {} -- ["type|req"] = true (install-once)
_G.CSR._loaded_reqs = _G.CSR._loaded_reqs or {} -- [req_lower] = true (script seen this session)

local function manager_ready()
	return managers and managers.csr and managers.csr.register_item ~= nil
end

-- Install one item's hook for a script exactly once. pcall-isolated: a buggy
-- (addon) hook is logged, never crashes the engine's script-load path.
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

-- Called by the wildcard delegator after every engine script load. Records the
-- script as seen and installs any item hooks registered for it.
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

-- Index an item def's behavior hooks. If the target script already loaded this
-- session (e.g. an addon registered late), install immediately.
local function index_item_hooks(def)
	if type(def.hooks) ~= "table" then
		return
	end
	for req, fn in pairs(def.hooks) do
		if type(req) == "string" and type(fn) == "function" then
			local key = req:lower()
			local bucket = _G.CSR._hooks_by_req[key]
			if not bucket then
				bucket = {}
				_G.CSR._hooks_by_req[key] = bucket
			end
			bucket[#bucket + 1] = { type = def.type, fn = fn }
			if _G.CSR._loaded_reqs[key] then
				_G.CSR._install_hook(def.type, key, fn)
			end
		end
	end
end

function _G.CSR.register_item(def)
	if type(def) ~= "table" then
		log("[CSR][api] register_item: definition must be a table -- ignored")
		return false
	end
	-- Record first so any later manager re-init replays it...
	table.insert(_G.CSR._registrations, def)
	-- ...and apply to the live manager now if it already exists (addon loaded
	-- after the manager). Harmless if it re-applies on a later init: the
	-- manager rejects a duplicate type within its (freshly empty) instance.
	if manager_ready() then
		managers.csr:register_item(def)
	end
	-- Index this item's behavior hooks for the wildcard dispatcher (independent
	-- of manager state -- hooks must install as engine classes load).
	index_item_hooks(def)
	return true
end

function _G.CSR.register_modifier(def)
	if type(def) ~= "table" then
		log("[CSR][api] register_modifier: definition must be a table -- ignored")
		return false
	end
	-- Record first so any later manager re-init replays it...
	table.insert(_G.CSR._modifier_registrations, def)
	-- ...and apply to the live manager now if it already exists (addon loaded
	-- after the manager). Idempotent: the manager dedupes by id within its
	-- (freshly empty) instance, so a replay on the next init is harmless.
	if managers and managers.csr and managers.csr.register_modifier then
		managers.csr:register_modifier(def)
	end
	return true
end

-- Replay the full persistent modifier list into a fresh _registry on EVERY
-- CSRGameManager:init(); never clears it (mirrors _apply_registrations for items).
function _G.CSR._apply_modifier_registrations(mgr)
	for _, def in ipairs(_G.CSR._modifier_registrations) do
		mgr:register_modifier(def)
	end
end

-- Called by CSRGameManager:init() AFTER default_registry()+load(), on EVERY
-- init. Replays the full persistent list into the fresh _registry; never
-- clears it. Lives here so the contract stays with the API.
function _G.CSR._apply_registrations(mgr)
	for _, def in ipairs(_G.CSR._registrations) do
		mgr:register_item(def)
	end
end

-- Register a playable sound under `name`. def = { path = "<rel.ogg>" } for a
-- single clip, or { pattern = "<rel_$.ogg>", n = <count> } for numbered
-- variants ($ -> 1..n; play_sound picks one at random). Paths are relative to
-- the mod root. Safe to call at any time: the entry is recorded persistently
-- and the actual XAudio buffer is loaded by sound.lua (now if its loader is
-- already up, otherwise when it finishes its retry loop).
function _G.CSR.register_sound(name, def)
	if type(name) ~= "string" or type(def) ~= "table" then
		log("[CSR][api] register_sound: (name string, def table) required -- ignored")
		return false
	end
	_G.CSR._sound_registrations[name] = def
	-- _load_sound is installed by sound.lua once its loader is ready; a late
	-- (post-load) registration is loaded on the spot, an early one is picked up
	-- by the loader's pass over _sound_registrations.
	if _G.CSR._sound_loader_ready and _G.CSR._load_sound then
		_G.CSR._load_sound(name, def)
	end
	return true
end

-- Play a registered sound. opts shape is documented in sound.lua (which
-- installs _play_sound). A no-op returning nil until that file's loader runs,
-- so callers never need to guard for "sound system not up yet".
function _G.CSR.play_sound(name, opts)
	if _G.CSR._play_sound then
		return _G.CSR._play_sound(name, opts)
	end
	return nil
end

-- Auto-load CSR's own item definition files. Each lua/items/*.lua CALLS
-- _G.CSR.register_item({...}) itself (PD2's dofile does NOT return chunk values,
-- so we cannot rely on a `return {...}` -- the file registers directly, exactly
-- as an addon would from its own mod). Adding an item = drop a file here; no
-- mod.txt edit. Runs once (the whole file is guarded by _bootstrapped at the
-- top). file.* and ModPath are SuperBLT-provided and valid at this lib/entry load.
local function load_item_defs()
	if not (file and file.GetFiles and ModPath) then
		log("[CSR][api] items: file API or ModPath unavailable -- skipped")
		return
	end
	local dir = ModPath .. "lua/items/"
	local names = file.GetFiles(dir)
	if not names then
		return
	end
	local count = 0
	for _, name in pairs(names) do
		if type(name) == "string" and name:sub(-4) == ".lua" then
			local ok, err = pcall(dofile, dir .. name)
			if ok then
				count = count + 1
			else
				log("[CSR][api] items: '" .. tostring(name) .. "' failed to load: " .. tostring(err))
			end
		end
	end
	log("[CSR][api] items: ran " .. count .. " item file(s)")
end

-- Same auto-load for modifier passports: each lua/modifiers/<id>.lua CALLS
-- _G.CSR.register_modifier({...}) itself (PD2 dofile returns no chunk value).
-- Adding a modifier = drop a file here; no mod.txt edit (mirrors the items model).
local function load_modifier_defs()
	if not (file and file.GetFiles and ModPath) then
		log("[CSR][api] modifiers: file API or ModPath unavailable -- skipped")
		return
	end
	local dir = ModPath .. "lua/modifiers/"
	local names = file.GetFiles(dir)
	if not names then
		return
	end
	local count = 0
	for _, name in pairs(names) do
		if type(name) == "string" and name:sub(-4) == ".lua" then
			local ok, err = pcall(dofile, dir .. name)
			if ok then
				count = count + 1
			else
				log("[CSR][api] modifiers: '" .. tostring(name) .. "' failed to load: " .. tostring(err))
			end
		end
	end
	log("[CSR][api] modifiers: ran " .. count .. " modifier file(s)")
end

load_item_defs()
load_modifier_defs()

-- Drain the requires that the wildcard delegator buffered before this shim was
-- ready -- engine classes required during lib/entry's body, before this post-hook
-- ran. The hook index is built now (load_item_defs above), so install any of
-- their hooks (e.g. PlayerManager, which loaded inside lib/entry). Requires AFTER
-- this point reach on_script_loaded directly (the delegator's ready branch).
if _G.__CSR_pending_reqs then
	local pending = _G.__CSR_pending_reqs
	_G.__CSR_pending_reqs = nil
	for i = 1, #pending do
		_G.CSR.on_script_loaded(pending[i])
	end
end

log("[CSR] extension_api.lua loaded (public _G.CSR shim, API v" .. tostring(_G.CSR.API_VERSION) .. ")")
