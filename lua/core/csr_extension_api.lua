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
-- here so an addon can register a sound before csr_sound.lua loads (SuperBLT
-- inter-mod order is non-deterministic, same reason _registrations exists).
-- csr_sound.lua loads every entry once blt.xaudio is up, and a registration
-- that arrives AFTER that load is loaded immediately (see register_sound).
_G.CSR._sound_registrations = _G.CSR._sound_registrations or {}

local function manager_ready()
	return managers and managers.csr and managers.csr.register_item ~= nil
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
	return true
end

function _G.CSR.register_modifier(def)
	-- Parity stub for slice 1: recorded, applied by the manager when the
	-- modifier registry lands (design migration step 5). Accepted now so an
	-- addon written against the API does not error before that slice exists.
	if type(def) ~= "table" then
		log("[CSR][api] register_modifier: definition must be a table -- ignored")
		return false
	end
	table.insert(_G.CSR._modifier_registrations, def)
	return true
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
-- and the actual XAudio buffer is loaded by csr_sound.lua (now if its loader is
-- already up, otherwise when it finishes its retry loop).
function _G.CSR.register_sound(name, def)
	if type(name) ~= "string" or type(def) ~= "table" then
		log("[CSR][api] register_sound: (name string, def table) required -- ignored")
		return false
	end
	_G.CSR._sound_registrations[name] = def
	-- _load_sound is installed by csr_sound.lua once its loader is ready; a late
	-- (post-load) registration is loaded on the spot, an early one is picked up
	-- by the loader's pass over _sound_registrations.
	if _G.CSR._sound_loader_ready and _G.CSR._load_sound then
		_G.CSR._load_sound(name, def)
	end
	return true
end

-- Play a registered sound. opts shape is documented in csr_sound.lua (which
-- installs _play_sound). A no-op returning nil until that file's loader runs,
-- so callers never need to guard for "sound system not up yet".
function _G.CSR.play_sound(name, opts)
	if _G.CSR._play_sound then
		return _G.CSR._play_sound(name, opts)
	end
	return nil
end

log("[CSR] csr_extension_api.lua loaded (public _G.CSR shim, API v" .. tostring(_G.CSR.API_VERSION) .. ")")
