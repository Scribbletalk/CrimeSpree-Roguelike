-- In-world evidence shredder ("scrapper") spawner. Arch + MP notes in
-- csr_in_world_props_architecture.md.
--
-- Generic debug-prop registry shared with the printer:
--   crosshair key → CSR_SpawnDebugPropAtCrosshair() — current prop at crosshair
--   cover key     → CSR_SpawnDebugPropAtCover()     — current prop at nearest cop cover
--   cycle key     → CSR_CycleDebugProp()            — advance to next prop
-- A prop with dispatch_<mode> delegates to that named global (so the printer
-- reuses its full spawn flow in copier_spawner.lua).

if not RequiredScript then
	return
end

local PKG_NAME = (DynamicResourceManager and DynamicResourceManager.DYN_RESOURCES_PACKAGE) or "packages/dyn_resources"
local UNIT_EXT = Idstring("unit")
local SPAWN_AUTO_DELAY = 0.5

-- Order = cycle order.
local DEBUG_PROPS = {
	{
		key = "shredder",
		label = "Shredder",
		dbpath = "units/pd2_dlc_pex/props/pex_prop_evidence_shredder/pex_prop_evidence_shredder",
		anim_seq = "interact",
	},
	{
		key = "printer",
		label = "Printer",
		dbpath = "units/payday2/props/off_prop_copy_machine_smuggle/off_prop_copy_machine_smuggle",
		dispatch_crosshair = "CSR_SpawnPrinterAtCrosshair",
		dispatch_cover = "CSR_SpawnPrinterAtClosestCover",
	},
}

for _, def in ipairs(DEBUG_PROPS) do
	def.unit_idstring = Idstring(def.dbpath)
end

_G.CSR_DebugSpawnedUnits = _G.CSR_DebugSpawnedUnits or {}
_G.CSR_DebugCurrentPropIdx = _G.CSR_DebugCurrentPropIdx or 1

local function current_def()
	local idx = _G.CSR_DebugCurrentPropIdx
	if idx < 1 or idx > #DEBUG_PROPS then
		_G.CSR_DebugCurrentPropIdx = 1
		idx = 1
	end
	return DEBUG_PROPS[idx]
end

local function hint(text, time)
	if managers and managers.hud and managers.hud.show_hint then
		managers.hud:show_hint({ text = text, time = time or 3 })
	end
	csr_log("[CSR DebugProp] " .. tostring(text))
end

local function is_ready(def)
	return managers
		and managers.dyn_resource
		and managers.dyn_resource:is_resource_ready(UNIT_EXT, def.unit_idstring, PKG_NAME)
end

local function trigger_anim(unit, seq_name)
	if not seq_name or not alive(unit) then
		return
	end
	local damage_ext = unit:damage()
	if not (damage_ext and damage_ext.run_sequence_simple) then
		return
	end
	local ok, err = pcall(damage_ext.run_sequence_simple, damage_ext, seq_name)
	if not ok then
		log("[CSR DebugProp] run_sequence_simple('" .. tostring(seq_name) .. "') failed: " .. tostring(err))
	end
end

-- Host → all: mirror a just-spawned scrapper. Only the shredder syncs here —
-- the printer routes through copier_spawner's own spawn flow and never reaches
-- spawn_at, so this guards on def.key for safety.
local function broadcast_scrapper_spawn(unit, pos, rot, def)
	if not (def and def.key == "shredder") then
		return
	end
	if not (_G.CSR_MP and _G.CSR_MP.broadcast_prop and _G.CSR_MP.MSG) then
		return
	end
	if not (alive(unit) and pos and rot) then
		return
	end
	local payload = string.format(
		"%s~%.2f~%.2f~%.2f~%.4f~%.4f~%.4f",
		tostring(unit:key()),
		pos.x,
		pos.y,
		pos.z,
		rot:yaw(),
		rot:pitch(),
		rot:roll()
	)
	_G.CSR_MP.broadcast_prop(_G.CSR_MP.MSG.SCRAPPER_SPAWN, payload)
end

-- Shared spawn core. Triple-disables collision (see deep-dive doc).
local function spawn_at(pos, rot, def)
	local ok, unit = pcall(World.spawn_unit, World, def.unit_idstring, pos, rot)
	if not ok or not alive(unit) then
		log("[CSR DebugProp] Spawn failed for " .. tostring(def.key) .. ": " .. tostring(unit))
		return nil
	end

	pcall(function()
		local nr = unit:num_bodies()
		for i = 0, nr - 1 do
			local body = unit:body(i)
			if body then
				body:set_enabled(false)
				body:set_collisions_enabled(false)
			end
		end
		if unit:slot() == 1 then
			unit:set_slot(11)
		end
	end)

	table.insert(_G.CSR_DebugSpawnedUnits, unit)

	broadcast_scrapper_spawn(unit, pos, rot, def)

	return unit
end

local function spawn_at_crosshair(def)
	local player = managers.player and managers.player:local_player()
	if not alive(player) then
		hint("No local player")
		return
	end
	local cam = player:camera()
	if not cam then
		hint("No camera")
		return
	end

	local from = cam:position()
	local dir = cam:forward()
	local to = from + dir * 5000
	local mask = managers.slot:get_mask("world_geometry")
	local ray = World:raycast("ray", from, to, "slot_mask", mask)

	local pos
	if ray then
		pos = ray.position + (ray.normal or Vector3(0, 0, 1)) * 2
	else
		pos = from + dir * 200
	end

	local rot = Rotation(cam:rotation():yaw(), 0, 0)
	local unit = spawn_at(pos, rot, def)
	if not unit then
		hint(def.label .. " spawn failed (see log)", 4)
		return
	end
	hint(def.label .. " spawned", 3)
end

-- Reuses CSR_PickCoverSpawns (printer-owned), so manual cover-spawn placements
-- honor MIN_COPIER_SEPARATION and avoid landing on existing printers/scrappers.
local function spawn_at_one_cover(def)
	local pick = _G.CSR_PickCoverSpawns
	if not pick then
		hint("Cover-spawn helper not loaded — try again after copier_spawner is up", 4)
		return
	end
	local spawns = pick(1)
	if #spawns == 0 then
		hint("No cover available within range", 4)
		return
	end
	local s = spawns[1]
	local unit = spawn_at(s.pos, s.rot, def)
	if not unit then
		hint(def.label .. " spawn failed (see log)", 4)
		return
	end
	hint(def.label .. " spawned at cover", 3)
end

-- Routes a keybind press to either the prop's dispatch_<mode> global (printer
-- delegates to copier_spawner) or the generic spawn path.
local function dispatch_spawn(at_cover)
	local def = current_def()
	local dispatch_name = at_cover and def.dispatch_cover or def.dispatch_crosshair
	if dispatch_name then
		local fn = _G[dispatch_name]
		if type(fn) ~= "function" then
			hint(def.label .. " dispatch global '" .. dispatch_name .. "' missing", 6)
			return
		end
		fn()
		return
	end

	local db_has = DB and DB.has and DB:has(UNIT_EXT, def.unit_idstring)
	if not db_has then
		hint(def.label .. " unit not in DB (asset path wrong?)", 6)
		return
	end
	-- Trust DB:has over is_ready: supermod.xml-mounted units are live even when
	-- is_ready reports false. Same workaround the printer uses.
	if at_cover then
		spawn_at_one_cover(def)
	else
		spawn_at_crosshair(def)
	end
end

_G.CSR_SpawnDebugPropAtCrosshair = function()
	dispatch_spawn(false)
end

_G.CSR_SpawnDebugPropAtCover = function()
	dispatch_spawn(true)
end

-- Back-compat alias in case a cached keybind callback references the old name.
_G.CSR_SpawnScrapperAtCrosshair = _G.CSR_SpawnDebugPropAtCrosshair

_G.CSR_CycleDebugProp = function()
	_G.CSR_DebugCurrentPropIdx = (_G.CSR_DebugCurrentPropIdx % #DEBUG_PROPS) + 1
	local def = current_def()
	hint(string.format("Debug prop selected: %s [%d/%d]", def.label, _G.CSR_DebugCurrentPropIdx, #DEBUG_PROPS), 3)
end

Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_ScrapperSpawner_SessionReset", function()
	_G.CSR_DebugSpawnedUnits = {}
	_G.CSR_SeenScrapperSpawns = {}
	_G.CSR_AutoScrapperSpawned = false
end)

-- CSR-heist gate (no-leak signal): temp "crime_spree" job AND vanilla CS NOT active.
local function csr_heist_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

-- Per-heist count in [MIN, MAX] inclusive. MIN=0 → "zero this heist" is valid.
local SCRAPPER_AUTO_MIN = 0
local SCRAPPER_AUTO_MAX = 2
local FIRST_ITEM_RANK = 1

local function do_auto_spawn_scrapper()
	local def = DEBUG_PROPS[1]
	if not def then
		return
	end
	if not (DB and DB.has and DB:has(UNIT_EXT, def.unit_idstring)) then
		return
	end

	local mgr = managers.csr
	local rank = (mgr and mgr.host_rank and mgr:host_rank()) or 0
	if rank < FIRST_ITEM_RANK then
		csr_log(
			"[CSR Scrapper] auto-spawn: host rank "
				.. tostring(rank)
				.. " below first-item rank "
				.. FIRST_ITEM_RANK
				.. ", skipping"
		)
		return
	end

	local count = math.random(SCRAPPER_AUTO_MIN, SCRAPPER_AUTO_MAX)
	if count == 0 then
		return
	end

	local pick = _G.CSR_PickCoverSpawns
	if not pick then
		return
	end

	for _, s in ipairs(pick(count)) do
		spawn_at(s.pos, s.rot, def)
	end
end

_G.CSR_AutoScrapperSpawned = _G.CSR_AutoScrapperSpawned or false

Hooks:Add("GameSetupUpdate", "CSR_ScrapperAutoSpawn", function(_t, _dt)
	if _G.CSR_AutoScrapperSpawned then
		return
	end
	if not Network:is_server() then
		return
	end
	if not csr_heist_active() then
		return
	end
	if not (managers.navigation and managers.navigation:is_data_ready()) then
		return
	end
	_G.CSR_AutoScrapperSpawned = true -- latch BEFORE spawn so failures don't re-fire
	do_auto_spawn_scrapper()
end)

-- Manual: vanilla's "can-press-F" gate doesn't visually align with the contour;
-- bump until the contour pops on at the same moment "Hold F" becomes pressable.
local PROX_RANGE = 240
local PROX_RANGE_SQ = PROX_RANGE * PROX_RANGE
_G.CSR_ScrapperProxState = _G.CSR_ScrapperProxState or setmetatable({}, { __mode = "k" })

-- Client-side mirror of host-broadcast scrapper spawns.
_G.CSR_SeenScrapperSpawns = _G.CSR_SeenScrapperSpawns or {}

local function on_scrapper_spawn(payload)
	if not (_G.CSR_MP and _G.CSR_MP.is_client and _G.CSR_MP.is_client()) then
		return
	end
	local def = DEBUG_PROPS[1]
	if not def then
		return
	end
	local key, x, y, z, yaw, pitch, roll =
		string.match(tostring(payload), "^([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)$")
	if not key then
		log("[CSR DebugProp] on_scrapper_spawn: parse fail '" .. tostring(payload) .. "'")
		return
	end
	if _G.CSR_SeenScrapperSpawns[key] then
		return
	end
	if not (DB and DB.has and DB:has(UNIT_EXT, def.unit_idstring)) then
		log("[CSR DebugProp] on_scrapper_spawn: shredder unit not in DB, skipping")
		return
	end

	_G.CSR_SeenScrapperSpawns[key] = true
	local pos = Vector3(tonumber(x), tonumber(y), tonumber(z))
	local rot = Rotation(tonumber(yaw), tonumber(pitch), tonumber(roll))

	-- Native-AV guard before the direct spawn (pcall can't catch a native AV).
	if PackageManager and PackageManager.has and not PackageManager:has(UNIT_EXT, def.unit_idstring) then
		log("[CSR DebugProp] on_scrapper_spawn: package not mounted, skipping (native-AV guard)")
		return
	end
	spawn_at(pos, rot, def)
end

if _G.CSR_MP and _G.CSR_MP.register_handler and _G.CSR_MP.MSG then
	_G.CSR_MP.register_handler(_G.CSR_MP.MSG.SCRAPPER_SPAWN, function(sender, data)
		on_scrapper_spawn(data)
	end)
end

Hooks:Add("GameSetupUpdate", "CSR_ScrapperProximityContour", function(t, dt)
	local list = _G.CSR_DebugSpawnedUnits
	if not list or #list == 0 then
		return
	end
	local pu = managers and managers.player and managers.player:player_unit()
	if not (pu and alive(pu)) then
		return
	end
	local ppos = pu:position()
	for _, u in ipairs(list) do
		if alive(u) then
			local dist_sq = mvector3.distance_sq(ppos, u:position())
			local in_range = dist_sq <= PROX_RANGE_SQ
			if _G.CSR_ScrapperProxState[u] ~= in_range then
				_G.CSR_ScrapperProxState[u] = in_range
				local int_ext = u:interaction()
				if int_ext and int_ext.set_contour then
					pcall(function()
						int_ext:set_contour("standard_color", in_range and 1 or 0)
					end)
				end
			end
		end
	end
end)
