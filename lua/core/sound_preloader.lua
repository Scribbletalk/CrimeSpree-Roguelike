-- Crime Spree Roguelike — centralized sound preloader.
--
-- Replaces the prior pattern of 4 separate files each running their own
-- DelayedCalls(1s) → blt.xaudio.setup() → XAudio.Buffer:new juggling.
--
-- Two known failure modes the prior pattern produced:
--   1. Silent miss: the 1s DelayedCall fires before SuperBLT's xaudio module
--      registers _G.blt.xaudio. Buffer never loads. User reports "no sound";
--      restart shuffles load order, it works.
--   2. Glitchy playback: rapid-fire stop()/close() + new XAudio.Source:new on
--      the same buffer, with no centralized lifecycle, leaves stale decoder
--      state. User reports "sounds like glass breaking / loud creaking."
--
-- Fixes here:
--   - Retry loop instead of fixed delay — polls until _G.blt.xaudio appears,
--     then runs setup() once globally, then loads every registered sound.
--   - Single registry of every CSR sound. ONE source of truth for paths.
--   - When BeardLib is present, buffers also register in
--     BeardLib.Managers.Sound — gives engine-managed buffer lifecycle so
--     close/cleanup is properly sequenced.
--   - _G.CSR_PlaySound(name, opts) — unified play API, picks the right
--     XAudio source type (2D / positional / unit-attached) based on opts.

if not RequiredScript then
	return
end

if _G._csr_sound_preloader_loaded then
	return
end
_G._csr_sound_preloader_loaded = true

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR Sound] " .. tostring(msg))
	end
end

-- Force-on errors: even when debug_mode is off, sound load failures must be
-- visible because they're the actionable symptom users report.
local function CSR_log_force(msg)
	log("[CSR Sound] " .. tostring(msg))
end

-- ============================================================================
-- REGISTRY — every CSR sound, one place.
-- ============================================================================
-- Each entry:
--   path          = single relative path (under mod root)
--   pattern + n   = numbered variants (chip_proc_1.ogg ... chip_proc_N.ogg)
--                   loaded as an array; CSR_PlaySound picks one randomly
local CSR_SOUND_REGISTRY = {
	the_edge_activate = { path = "assets/sounds/the_edge_activate.ogg" },
	plush_shark_activate = { pattern = "assets/sounds/shark/plush_shark_activate_$.ogg", n = 5 },
	bonnie_chip = { pattern = "assets/sounds/chip/chip_proc_$.ogg", n = 4 },
	printer_working = { path = "assets/sounds/printer/printer_working.ogg" },
	printer_starting = { path = "assets/sounds/printer/printer_starting.ogg" },
	gup_charge = { path = "assets/sounds/gup/gup_charge_attack.ogg" },
	gup_attack = { pattern = "assets/sounds/gup/gup_attack_$.ogg", n = 5 },
	gup_cooldown = { pattern = "assets/sounds/gup/gup_cooldown_$.ogg", n = 9 },
	turron_activate = { pattern = "assets/sounds/turron/turron_activate_$.ogg", n = 2 },
	turron_recharge = { path = "assets/sounds/turron/turron_recharge.ogg" },
}

-- Save ModPath at file-load time. Other mods (BeardLib, ProjectCellBeta) can
-- overwrite the global ModPath later — by retry time it would point to the
-- wrong mod and every load would fail silently.
local SAVED_MOD_PATH = ModPath

-- ============================================================================
-- BUFFER CACHE — _G.CSR_Sounds[name] = single buffer or { buf1, buf2, ... }
-- ============================================================================
_G.CSR_Sounds = _G.CSR_Sounds or {}

-- Active sources kept alive to prevent GC stop. Indexed by ascending id.
-- Entries are pruned lazily during play (closed sources removed).
-- Used for non-unit sources only (2D / positional). Unit-attached sources
-- live in CSR_UnitSources, see below.
_G.CSR_SoundSources = _G.CSR_SoundSources or {}
local _next_source_id = 0
local _next_ramp_id = 0

-- Per-unit source registry. Mirrors Restoration's _active_sources[unit_key]
-- pattern — lets us close a stale source on a unit before spawning a new one
-- on the same buffer, which is the documented fix for the rapid Source:new +
-- shared-buffer "loud crack" symptom (see pd2_xaudio_buffer_lifecycle memory).
--   structure: _G.CSR_UnitSources[unit_key][source_key] = XAudio source
_G.CSR_UnitSources = _G.CSR_UnitSources or {}

local function _close_source_safely(src)
	if not src then
		return
	end
	pcall(function()
		if not src:is_closed() then
			src:stop()
			src:close()
		end
	end)
end

-- ============================================================================
-- LOADER — runs after _G.blt.xaudio appears, retries until ready.
-- ============================================================================

local function _resolve_path(rel)
	local base_path = Application:base_path() or ""
	if base_path:sub(-1) ~= "/" and base_path:sub(-1) ~= "\\" then
		base_path = base_path .. "/"
	end
	local mod_rel = (SAVED_MOD_PATH or "mods/CrimeSpree-Roguelike/") .. rel

	-- Verify on disk via io.open. If the absolute path opens, prefer it; else
	-- try the relative path (some installs resolve relative paths from the PD2
	-- exe dir directly). Returns the path that opened, or nil.
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

local function _load_buffer_raw(rel_path, sound_id)
	local resolved = _resolve_path(rel_path)
	if not resolved then
		CSR_log_force("FILE NOT FOUND: " .. tostring(rel_path) .. " (sound_id=" .. tostring(sound_id) .. ")")
		return nil
	end

	-- BeardLib first. AddBuffer internally creates the XAudio.Buffer and registers
	-- it in BeardLib's lifecycle (close-on-shutdown, dedupe, etc). We use the
	-- buffer it returns so playback flows through BeardLib-owned state instead
	-- of double-buffering.
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
		-- AddBuffer can return nil for `load_on_play` entries; we don't pass
		-- that flag, so a nil return here means BeardLib decided to skip it.
		-- Fall through to SuperBLT fallback.
		CSR_log("BeardLib AddBuffer returned nil for " .. tostring(rel_path) .. ", falling back to SuperBLT")
	end

	-- SuperBLT fallback when BeardLib is unavailable or refused the buffer.
	local ok, buf = pcall(function()
		return XAudio.Buffer:new(resolved)
	end)
	if not ok or not buf then
		CSR_log_force("BUFFER FAILED for " .. tostring(resolved) .. ": " .. tostring(buf))
		return nil
	end
	return buf
end

local function _load_all_sounds()
	for name, entry in pairs(CSR_SOUND_REGISTRY) do
		if entry.path then
			local buf = _load_buffer_raw(entry.path, name)
			if buf then
				_G.CSR_Sounds[name] = buf
				CSR_log("Loaded " .. name)
			end
		elseif entry.pattern and entry.n then
			local buffers = {}
			for i = 1, entry.n do
				local rel = entry.pattern:gsub("%$", tostring(i))
				local buf = _load_buffer_raw(rel, name .. "_" .. i)
				if buf then
					table.insert(buffers, buf)
				end
			end
			if #buffers > 0 then
				_G.CSR_Sounds[name] = buffers
				CSR_log("Loaded " .. name .. " (" .. #buffers .. "/" .. entry.n .. " variants)")
			else
				CSR_log_force("ZERO variants loaded for " .. name)
			end
		end
	end
end

-- Retry loop. Tries every 0.5s up to 12 attempts (= 6s). Most cold boots
-- have _G.blt.xaudio ready within 1-2s; this handles the long tail.
local _retry_count = 0
local function _try_load()
	if _G._csr_sound_loaded then
		return
	end
	if not (_G.blt and _G.blt.xaudio) then
		_retry_count = _retry_count + 1
		if _retry_count >= 12 then
			CSR_log_force("XAudio never became available after 12 retries — sounds disabled")
			_G._csr_sound_loaded = true
			return
		end
		DelayedCalls:Add("CSR_LoadSounds_Retry_" .. _retry_count, 0.5, _try_load)
		return
	end

	-- xaudio.setup is idempotent and global — calling it multiple times across
	-- mods is the documented pattern.
	pcall(function()
		blt.xaudio.setup()
	end)

	_load_all_sounds()
	_G._csr_sound_loaded = true
	CSR_log("Preloader complete (" .. _retry_count .. " retries)")
end

DelayedCalls:Add("CSR_LoadSounds_Initial", 0.5, _try_load)

-- ============================================================================
-- PLAY API — _G.CSR_PlaySound(name, opts)
-- ============================================================================
--
-- name = key in CSR_SOUND_REGISTRY
-- opts = {
--   unit       = unit ref          -> XAudio.UnitSource (3D, attached to unit)
--   position   = Vector3           -> XAudio.Source + set_position (3D static)
--   relative   = true (default)    -> XAudio.Source + set_relative(true) (2D)
--   volume     = number 0..1       -> overrides settings
--   volume_key = string            -> reads CSR_Settings.values[volume_key]
--                                     for the per-sound user volume slider;
--                                     fallback 1.0
--   cleanup_old = source ref       -> stops + closes the previous source
--                                     before starting the new one
--   source_key = string            -> per-unit slot identifier; defaults to
--                                     `name`. Only meaningful when `unit` is
--                                     set. If a source already exists at the
--                                     same (unit, source_key), it is stopped
--                                     and closed before the new one starts.
-- }
-- Returns the new source (or nil on failure).
function _G.CSR_PlaySound(name, opts)
	opts = opts or {}
	local entry = _G.CSR_Sounds[name]
	if not entry then
		CSR_log("PlaySound: '" .. tostring(name) .. "' not loaded")
		return nil
	end

	-- Resolve buffer (single or random pick from variants array)
	local buf
	if type(entry) == "table" and entry[1] then
		buf = entry[math.random(#entry)]
	else
		buf = entry
	end
	if not buf then
		return nil
	end

	-- Resolve volume
	local vol = opts.volume
	if vol == nil and opts.volume_key then
		local sv = _G.CSR_Settings and _G.CSR_Settings.values
		vol = sv and sv[opts.volume_key]
	end
	if vol == nil then
		vol = 1.0
	end

	-- Cleanup old source if caller passed one (typical for 1-shot effects
	-- that re-fire before previous instance ends, e.g. The Edge re-trigger
	-- after cooldown).
	if opts.cleanup_old then
		_close_source_safely(opts.cleanup_old)
	end

	-- Per-unit close-before-new. For unit-attached sources, look up the prior
	-- source on the same (unit, source_key) and stop+close it. Prevents two
	-- sources holding the same shared XAudio.Buffer mid-decode, which is the
	-- root cause of the "loud crack instead of correct sound" symptom.
	local unit_key = nil
	local source_key = opts.source_key or name
	if opts.unit and alive(opts.unit) then
		local ok_key, k = pcall(function()
			return opts.unit:key()
		end)
		if ok_key and k then
			unit_key = k
			local unit_table = _G.CSR_UnitSources[unit_key]
			if unit_table then
				_close_source_safely(unit_table[source_key])
				unit_table[source_key] = nil
			else
				unit_table = {}
				_G.CSR_UnitSources[unit_key] = unit_table
				-- Register destroy listener once per unit. Ensures every source
				-- attached to this unit is closed when the unit is destroyed,
				-- rather than relying on XAudio's auto-close (which can race
				-- with manager unload during heist transitions).
				pcall(function()
					local base = opts.unit:base()
					if base and base.add_destroy_listener then
						base:add_destroy_listener("CSR_CloseSoundSources", function()
							local sources = _G.CSR_UnitSources[unit_key]
							if sources then
								for _, s in pairs(sources) do
									_close_source_safely(s)
								end
								_G.CSR_UnitSources[unit_key] = nil
							end
						end)
					end
				end)
			end
		end
	end

	-- Pick source type. Volume starts at 0 and is bumped to target on the next
	-- frame — masks the "click at sample start" artifact some OGGs produce when
	-- the waveform's first sample is non-zero (gup_attack_*.ogg is the motivator).
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
		src:set_volume(0)
		src:play()
	end)

	if not ok then
		CSR_log_force("PlaySound FAILED for '" .. tostring(name) .. "': " .. tostring(err))
		return nil
	end

	if src then
		_next_ramp_id = _next_ramp_id + 1
		local ramp_src = src
		local target_vol = vol
		DelayedCalls:Add("CSR_VolRamp_" .. _next_ramp_id, 0.016, function()
			pcall(function()
				if not ramp_src:is_closed() then
					ramp_src:set_volume(target_vol)
				end
			end)
		end)
	end

	if unit_key then
		-- Stash in per-unit registry. Replaces flat-table tracking for
		-- unit-attached sources to avoid double-bookkeeping.
		_G.CSR_UnitSources[unit_key][source_key] = src
	else
		-- Non-unit source — flat table with lazy prune.
		_next_source_id = _next_source_id + 1
		_G.CSR_SoundSources[_next_source_id] = src
		if _next_source_id % 32 == 0 then
			for id, s in pairs(_G.CSR_SoundSources) do
				local closed_ok, closed = pcall(function()
					return s:is_closed()
				end)
				if closed_ok and closed then
					_G.CSR_SoundSources[id] = nil
				end
			end
		end
	end

	return src
end

CSR_log("sound_preloader.lua loaded (mod_path=" .. tostring(SAVED_MOD_PATH) .. ")")
