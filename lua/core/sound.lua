-- CSR sound system. Plays custom OGG clips through _G.CSR.play_sound(name, opts).
-- Item code registers a clip via _G.CSR.register_sound (extension_api.lua) and
-- plays it by name. BeardLib loads buffers when present; raw XAudio is the fallback.

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

local function snd_err(msg)
	log("[CSR][snd] " .. tostring(msg))
end

-- Snapshot ModPath at load — other mods can overwrite the global later.
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

	-- BeardLib AddBuffer manages the XAudio.Buffer lifecycle; returns the buffer
	-- so playback treats it identically to a raw one.
	if BeardLib and BeardLib.Managers and BeardLib.Managers.Sound and BeardLib.Managers.Sound.AddBuffer then
		local ok, beard_buf = pcall(function()
			return BeardLib.Managers.Sound:AddBuffer({
				id = "" .. tostring(sound_id),
				full_path = resolved,
				close_previous = true,
			})
		end)
		if ok and beard_buf then
			return beard_buf
		end
		snd_dbg("BeardLib AddBuffer returned nil for " .. tostring(rel_path) .. ", falling back to SuperBLT")
	end

	local ok, buf = pcall(function()
		return XAudio.Buffer:new(resolved)
	end)
	if not ok or not buf then
		snd_err("BUFFER FAILED for " .. tostring(resolved) .. ": " .. tostring(buf))
		return nil
	end
	return buf
end

-- Public: exposed so a late register_sound (addon loaded after the retry loop)
-- loads on the spot.
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

-- _G.CSR._play_sound(name, opts). opts = {
--   unit         = unit ref  -> XAudio.UnitSource (3D, follows the unit)
--   position     = Vector3   -> XAudio.Source + set_position (3D static)
--   (neither)                -> XAudio.Source + set_relative(true) (2D)
--   volume       = 0..1  (multiplied by the master sfx_volume setting)
--   min_distance / max_distance = spatial falloff range
-- }
-- The source is single-sound: auto-plays, auto-closes. Caller doesn't stop it.
function _G.CSR._play_sound(name, opts)
	opts = opts or {}
	local entry = loaded_buffers[name]
	if not entry then
		snd_dbg("play: '" .. tostring(name) .. "' not loaded")
		return nil
	end

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
		-- Set gain BEFORE the first XAudio update; single-sound sources push gain
		-- then auto-play, so the clip starts at the correct volume.
		src:set_volume(vol)
	end)

	if not ok then
		snd_err("play FAILED for '" .. tostring(name) .. "': " .. tostring(err))
		return nil
	end
	snd_dbg(string.format("play '%s' vol=%.2f (src=%s)", tostring(name), vol, tostring(src ~= nil)))
	return src
end

-- Inter-mod load order is non-deterministic; poll for XAudio wrappers, then load.
local retry_count = 0
local function try_load()
	if _G.CSR._sound_loader_ready then
		return
	end
	if not (_G.XAudio and XAudio.Buffer and XAudio.Source) then
		retry_count = retry_count + 1
		if retry_count >= 12 then
			snd_err("XAudio never became available after 12 retries -- sounds disabled")
			_G.CSR._sound_loader_ready = true
			return
		end
		DelayedCalls:Add("LoadSounds_Retry_" .. retry_count, 0.5, try_load)
		return
	end

	load_all_registered()
	_G.CSR._sound_loader_ready = true
	snd_dbg("loader complete (" .. retry_count .. " retries)")
end

DelayedCalls:Add("LoadSounds_Initial", 0.5, try_load)

-- Built-in CSR sound registry. Paths are mod-relative under assets/sounds.
_G.CSR.register_sound("bonnie_chip", { pattern = "assets/sounds/chip/chip_activate_$.ogg", n = 17 })
_G.CSR.register_sound("the_edge_activate", { path = "assets/sounds/the_edge_activate.ogg" })
_G.CSR.register_sound("plush_shark_activate", { pattern = "assets/sounds/shark/plush_shark_activate_$.ogg", n = 5 })
_G.CSR.register_sound("printer_starting", { path = "assets/sounds/printer/printer_starting.ogg" })
_G.CSR.register_sound("printer_working", { path = "assets/sounds/printer/printer_working.ogg" })

snd_dbg("sound.lua loaded (mod_path=" .. tostring(SAVED_MOD_PATH) .. ")")
