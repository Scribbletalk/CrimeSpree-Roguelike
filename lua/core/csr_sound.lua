-- Crime Spree Roguelike — sound system (U1).
--
-- Plays CSR's custom OGG clips through one public API: _G.CSR.play_sound(name,
-- opts). Item code registers a clip (via _G.CSR.register_sound, see
-- csr_extension_api.lua) and plays it by name.
--
-- Buffers load through BeardLib (primary) — BeardLib.Managers.Sound:AddBuffer
-- creates the XAudio.Buffer and owns its lifecycle (close-on-shutdown, dedupe).
-- Raw XAudio.Buffer:new is the fallback when BeardLib is absent.
--
-- Playback is intentionally minimal: XAudio.Source:new(buffer) enables
-- single-sound mode, so the source plays itself on the next XAudio update and
-- closes itself when the clip ends. Setting the volume BEFORE that first update
-- means the engine pushes the correct gain and THEN auto-plays (see the order in
-- XAudioSource:update) — no manual play(), no gain ramp, no force-setgain. Don't
-- reinvent what XAudio already does.
--
-- A retry loop waits for SuperBLT's XAudio Lua wrappers, then loads every clip.
-- Inter-mod load order is non-deterministic, so we poll instead of a fixed delay.
--
-- Loaded once: hooked on lib/setups/setup, fenced by _G._CSR_SOUND_LOADED. The
-- buffer cache is a file-local (single load); only the public API lives on _G.CSR.

if not RequiredScript then
	return
end

if _G._CSR_SOUND_LOADED then
	return
end
_G._CSR_SOUND_LOADED = true

_G.CSR = _G.CSR or {}
_G.CSR._sound_registrations = _G.CSR._sound_registrations or {}

local function snd_dbg(msg)
	local mgr = managers and managers.csr
	if mgr and mgr.debug_enabled and mgr:debug_enabled() then
		log("[CSR][snd] " .. tostring(msg))
	end
end

-- Always-on: a clip that fails to load is the actionable symptom users report.
-- Bounded to a handful of lines at boot (feedback_keep_rare_event_logs).
local function snd_err(msg)
	log("[CSR][snd] " .. tostring(msg))
end

-- Save ModPath at file-load time. Other mods can overwrite the global ModPath
-- later — by retry time it would point at the wrong mod and loads would fail.
local SAVED_MOD_PATH = ModPath

-- name -> single buffer, or { buf1, buf2, ... } for numbered variants.
local loaded_buffers = {}

local function master_volume()
	local mgr = managers and managers.csr
	local v = mgr and mgr.setting and mgr:setting("sfx_volume")
	if v == nil then
		return 1.0
	end
	return v
end

-- ============================================================================
-- LOADER
-- ============================================================================

-- Resolve a mod-relative path to one XAudio.Buffer can open: absolute first
-- (base_path + ModPath + rel), else the mod-relative path. Returns whichever
-- io.open succeeds on, or nil.
local function resolve_path(rel)
	local base_path = (Application and Application:base_path()) or ""
	if base_path ~= "" and base_path:sub(-1) ~= "/" and base_path:sub(-1) ~= "\\" then
		base_path = base_path .. "/"
	end
	local mod_rel = (SAVED_MOD_PATH or "mods/CrimeSpree-Roguelike/") .. rel

	local absolute = base_path .. mod_rel
	local fh = io.open(absolute, "rb")
	if fh then
		fh:close()
		return absolute
	end
	fh = io.open(mod_rel, "rb")
	if fh then
		fh:close()
		return mod_rel
	end
	return nil
end

local function load_buffer_raw(rel_path, sound_id)
	local resolved = resolve_path(rel_path)
	if not resolved then
		snd_err("FILE NOT FOUND: " .. tostring(rel_path) .. " (id=" .. tostring(sound_id) .. ")")
		return nil
	end

	-- BeardLib first: AddBuffer creates the XAudio.Buffer and owns its lifecycle.
	-- It returns that XAudio.Buffer, so playback below treats it exactly like a
	-- raw one (feedback_beardlib_first_superblt_backup).
	if BeardLib and BeardLib.Managers and BeardLib.Managers.Sound and BeardLib.Managers.Sound.AddBuffer then
		local ok, beard_buf = pcall(function()
			return BeardLib.Managers.Sound:AddBuffer({
				id = "csr_" .. tostring(sound_id),
				full_path = resolved,
				close_previous = true,
			})
		end)
		if ok and beard_buf then
			return beard_buf
		end
		snd_dbg("BeardLib AddBuffer returned nil for " .. tostring(rel_path) .. ", falling back to SuperBLT")
	end

	-- SuperBLT fallback.
	local ok, buf = pcall(function()
		return XAudio.Buffer:new(resolved)
	end)
	if not ok or not buf then
		snd_err("BUFFER FAILED for " .. tostring(resolved) .. ": " .. tostring(buf))
		return nil
	end
	return buf
end

-- Load one registration into loaded_buffers[name]. Exposed so a post-load
-- register_sound (addon loaded after the retry finished) loads on the spot.
function _G.CSR._load_sound(name, def)
	if not def then
		return
	end
	if def.path then
		local buf = load_buffer_raw(def.path, name)
		if buf then
			loaded_buffers[name] = buf
			snd_dbg("loaded " .. name)
		end
	elseif def.pattern and def.n then
		local buffers = {}
		for i = 1, def.n do
			local rel = def.pattern:gsub("%$", tostring(i))
			local buf = load_buffer_raw(rel, name .. "_" .. i)
			if buf then
				buffers[#buffers + 1] = buf
			end
		end
		if #buffers > 0 then
			loaded_buffers[name] = buffers
			snd_dbg("loaded " .. name .. " (" .. #buffers .. "/" .. def.n .. " variants)")
		else
			snd_err("ZERO variants loaded for " .. name)
		end
	end
end

local function load_all_registered()
	for name, def in pairs(_G.CSR._sound_registrations) do
		_G.CSR._load_sound(name, def)
	end
end

-- ============================================================================
-- PLAY — _G.CSR._play_sound(name, opts) (public via _G.CSR.play_sound)
-- ============================================================================
--
-- name = a registered sound name. opts = {
--   unit         = unit ref  -> XAudio.UnitSource (3D, follows the unit)
--   position     = Vector3   -> XAudio.Source + set_position (3D static)
--   (neither)                -> XAudio.Source + set_relative(true) (2D)
--   volume       = number 0..1  (multiplied by the master sfx_volume setting)
--   min_distance / max_distance = numbers -> spatial falloff range (engine API)
-- }
-- The source is single-sound: it auto-plays and auto-closes, so the caller does
-- not track or stop it. Returns the source (or nil if not loaded / failed).
function _G.CSR._play_sound(name, opts)
	opts = opts or {}
	local entry = loaded_buffers[name]
	if not entry then
		snd_dbg("play: '" .. tostring(name) .. "' not loaded")
		return nil
	end

	-- Single buffer or random pick from the variants array.
	local buf
	if type(entry) == "table" and entry[1] then
		buf = entry[math.random(#entry)]
	else
		buf = entry
	end
	if not buf then
		return nil
	end

	local vol = (opts.volume or 1.0) * master_volume()

	local src
	local ok, err = pcall(function()
		if opts.unit and alive(opts.unit) then
			src = XAudio.UnitSource:new(opts.unit, buf)
		elseif opts.position then
			src = XAudio.Source:new(buf)
			src:set_position(opts.position)
		else
			src = XAudio.Source:new(buf)
			src:set_relative(true)
		end
		if opts.min_distance and src.set_min_distance then
			src:set_min_distance(opts.min_distance)
		end
		if opts.max_distance and src.set_max_distance then
			src:set_max_distance(opts.max_distance)
		end
		-- Set the gain before the first update; XAudio pushes it and THEN
		-- auto-plays (single-sound), so the clip starts at the right volume.
		src:set_volume(vol)
	end)

	if not ok then
		snd_err("play FAILED for '" .. tostring(name) .. "': " .. tostring(err))
		return nil
	end
	snd_dbg(string.format("play '%s' vol=%.2f (src=%s)", tostring(name), vol, tostring(src ~= nil)))
	return src
end

-- ============================================================================
-- RETRY LOOP — runs once SuperBLT's XAudio wrappers exist.
-- ============================================================================

local retry_count = 0
local function try_load()
	if _G.CSR._sound_loader_ready then
		return
	end
	-- req/xaudio/XAudio.lua defines _G.XAudio.Buffer/.Source (the classes we call)
	-- and initialises the native blt.xaudio side as it loads, so their presence
	-- is the readiness signal. (There is no blt.xaudio.setup() — that was a
	-- phantom call in the pre-refactor code; XAudio self-initialises on require.)
	if not (_G.XAudio and XAudio.Buffer and XAudio.Source) then
		retry_count = retry_count + 1
		if retry_count >= 12 then
			snd_err("XAudio never became available after 12 retries -- sounds disabled")
			_G.CSR._sound_loader_ready = true
			return
		end
		DelayedCalls:Add("CSR_LoadSounds_Retry_" .. retry_count, 0.5, try_load)
		return
	end

	load_all_registered()
	_G.CSR._sound_loader_ready = true
	snd_dbg("loader complete (" .. retry_count .. " retries)")
end

DelayedCalls:Add("CSR_LoadSounds_Initial", 0.5, try_load)

-- ============================================================================
-- BUILT-IN CSR SOUNDS — registered here, loaded by the retry loop above.
-- Paths are the on-disk filenames under assets/sounds (the source of truth).
-- Add an entry when an item's sound is wired. (gup / turron / printer clips
-- exist on disk but are registered when their items port.)
-- ============================================================================
_G.CSR.register_sound("bonnie_chip", { pattern = "assets/sounds/chip/chip_activate_$.ogg", n = 17 })
_G.CSR.register_sound("the_edge_activate", { path = "assets/sounds/the_edge_activate.ogg" })
_G.CSR.register_sound("plush_shark_activate", { pattern = "assets/sounds/shark/plush_shark_activate_$.ogg", n = 5 })

snd_dbg("csr_sound.lua loaded (mod_path=" .. tostring(SAVED_MOD_PATH) .. ")")
