-- CSR sound system: register_sound + play_sound; BeardLib buffers first, raw XAudio fallback.

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

-- base_dir (optional) = an add-on folder; sounds bundled with an add-on resolve
-- relative to it. Built-in CSR sounds pass nil and resolve against the mod folder.
local function resolve_path(rel, base_dir)
	local base_path = (Application and Application:base_path()) or ""
	if base_path ~= "" and base_path:sub(-1) ~= "/" and base_path:sub(-1) ~= "\\" then
		base_path = base_path .. "/"
	end
	local fh

	if base_dir then
		local abs = base_dir .. rel
		fh = io.open(abs, "rb")
		if fh then
			fh:close()
			return abs
		end
		fh = io.open(base_path .. abs, "rb")
		if fh then
			fh:close()
			return base_path .. abs
		end
	end

	local mod_rel = (SAVED_MOD_PATH or "mods/CrimeSpree-Roguelike/") .. rel
	local absolute = base_path .. mod_rel
	fh = io.open(absolute, "rb")
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

local function load_buffer_raw(rel_path, sound_id, base_dir)
	local resolved = resolve_path(rel_path, base_dir)
	if not resolved then
		snd_err("FILE NOT FOUND: " .. tostring(rel_path) .. " (id=" .. tostring(sound_id) .. ")")
		return nil
	end

	-- BeardLib manages the XAudio.Buffer lifecycle; returned buffer is drop-in compatible.
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

-- Public: lets a late register_sound (addon loaded after retry loop) load immediately.
function _G.CSR._load_sound(name, def)
	if not def then
		return
	end
	local base_dir = def._addon_dir -- set for add-on sounds; nil for built-in CSR sounds
	if def.path then
		local buf = load_buffer_raw(def.path, name, base_dir)
		if buf then
			loaded_buffers[name] = buf
			snd_dbg("loaded " .. name)
		end
	elseif def.pattern and def.n then
		local buffers = {}
		for i = 1, def.n do
			local rel = def.pattern:gsub("%$", tostring(i))
			local buf = load_buffer_raw(rel, name .. "_" .. i, base_dir)
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

-- opts: unit=UnitSource(3D), position=static-3D, neither=2D; volume scaled by sfx_volume setting.
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
		-- Must set gain before first XAudio update or clip starts at wrong volume.
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
_G.CSR.register_sound("aloe_leaf_activate", { path = "assets/sounds/aloe_leaf_activate.ogg" })
_G.CSR.register_sound("plush_shark_activate", { pattern = "assets/sounds/shark/plush_shark_activate_$.ogg", n = 5 })
_G.CSR.register_sound("printer_starting", { path = "assets/sounds/printer/printer_starting.ogg" })
_G.CSR.register_sound("printer_working", { path = "assets/sounds/printer/printer_working.ogg" })

-- Wildcard actives. Familiar Friend (gup) + Turron.
_G.CSR.register_sound("gup_attack", { pattern = "assets/sounds/gup/gup_activate_$.ogg", n = 5 })
_G.CSR.register_sound("gup_charge", { path = "assets/sounds/gup/gup_charge.ogg" })
_G.CSR.register_sound("gup_cooldown", { pattern = "assets/sounds/gup/gup_cooldown_$.ogg", n = 9 })
_G.CSR.register_sound("turron_activate", { pattern = "assets/sounds/turron/turron_activate_$.ogg", n = 2 })
_G.CSR.register_sound("turron_recharge", { path = "assets/sounds/turron/turron_cooldown.ogg" })

snd_dbg("sound.lua loaded (mod_path=" .. tostring(SAVED_MOD_PATH) .. ")")
