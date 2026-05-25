-- Crime Spree Roguelike - Debug prop spawner.
-- Originally just for the evidence shredder ("scrapper"); now a generic
-- registry of debug-spawn props (currently shredder + printer) shared by both
-- the auto-spawn-at-cover flow and the manual debug keybinds.
--
-- Three SuperBLT keybinds drive this:
--   crosshair key → _G.CSR_SpawnDebugPropAtCrosshair() — spawns CURRENT prop at crosshair
--   cover key     → _G.CSR_SpawnDebugPropAtCover()      — spawns CURRENT prop at the nearest cop cover
--   cycle key     → _G.CSR_CycleDebugProp()             — advance to next prop in registry
--
-- For props with a dispatch_<mode> field (the printer), the keybind delegates
-- to the named global in copier_spawner.lua so the prop's full registration
-- flow (CSR_Copiers entry, offer, billboard, MP broadcast) is preserved.
if not RequiredScript then
	return
end

local PKG_NAME = (DynamicResourceManager and DynamicResourceManager.DYN_RESOURCES_PACKAGE) or "packages/dyn_resources"
local UNIT_EXT = Idstring("unit")
local SPAWN_AUTO_DELAY = 0.5

-- Per-prop config:
--   anim_seq: sequence to fire after spawn so the prop's visible animation
--     plays for the user; nil = no animation (spawn-only).
--   dispatch_crosshair / dispatch_cover: optional names of GLOBAL functions to
--     delegate to instead of using the generic spawn path in this file. This
--     lets a prop opt into another subsystem's full registration flow (e.g.
--     the printer needs CSR_Copiers + offer + billboard setup that lives in
--     copier_spawner.lua — calling its existing crosshair/cover globals
--     reuses that logic instead of duplicating it here).
-- Order in this list = cycle order.
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

-- Pre-cache the Idstring per entry so we don't reconstruct it on every press.
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
	log("[CSR DebugProp] " .. tostring(text))
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

-- Shared spawn core. Caller supplies pos+rot+def. Returns the spawned unit or
-- nil on failure. Used by both the crosshair-debug path and the auto-spawn
-- flow at the bottom of this file.
local function spawn_at(pos, rot, def)
	local ok, unit = pcall(World.spawn_unit, World, def.unit_idstring, pos, rot)
	if not ok or not alive(unit) then
		log("[CSR DebugProp] Spawn failed for " .. tostring(def.key) .. ": " .. tostring(unit))
		return nil
	end

	-- Make the prop non-solid to the player mover. The shredder ships on slot 1
	-- (dynamics, player-blocking); same triple-disable the copier uses (see
	-- copier_spawner.lua for the why):
	--   1. set_enabled(false) drops every body out of the physics sim
	--   2. set_collisions_enabled(false) belt-and-braces for body types where
	--      set_enabled isn't honored
	--   3. Move unit to slot 11 (statics) so it's out of slot 1's collision path
	-- Interaction handled by CrimeSpreeScrapperInteractionExt (native PD2 path),
	-- so disabling bodies doesn't affect the hover prompt or hold-to-use.
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

	-- Yaw-only rotation; props expect upright placement.
	local rot = Rotation(cam:rotation():yaw(), 0, 0)
	local unit = spawn_at(pos, rot, def)
	if not unit then
		hint(def.label .. " spawn failed (see log)", 4)
		return
	end
	hint(def.label .. " spawned", 3)
end

-- Cover-spawn helper for props that don't delegate (i.e. the scrapper). Reuses
-- CSR_PickCoverSpawns from copier_spawner.lua (same helper the auto-spawn loop
-- uses) so manual cover-spawn placements honor MIN_COPIER_SEPARATION and avoid
-- landing on top of an existing printer or scrapper. Picks ONE cover and
-- spawns there. Returns nothing — `hint()` reports outcome to the player.
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

-- Generic spawn dispatcher used by both the crosshair keybind and the cover
-- keybind. `at_cover` selects between crosshair and cover mode. When the
-- current def has a dispatch_<mode> entry, the corresponding global is invoked
-- instead of the generic path — that's how the printer reuses copier_spawner's
-- own spawn flow (which registers the unit with CSR_Copiers, attaches an
-- offer, etc.).
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
	-- Trust DB:has over is_ready: if the unit is in DB it was injected via
	-- supermod.xml and auto-mounted into packages/dyn_resources at SuperBLT
	-- init; is_ready can lie and report false even when the asset is live.
	-- Same workaround the printer uses. Spawn directly.
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

-- Backwards-compat alias kept so the existing keybind file doesn't need
-- changes if SuperBLT had cached its callback global. Both names route through
-- the same dispatcher.
_G.CSR_SpawnScrapperAtCrosshair = _G.CSR_SpawnDebugPropAtCrosshair

_G.CSR_CycleDebugProp = function()
	_G.CSR_DebugCurrentPropIdx = (_G.CSR_DebugCurrentPropIdx % #DEBUG_PROPS) + 1
	local def = current_def()
	hint(string.format("Debug prop selected: %s [%d/%d]", def.label, _G.CSR_DebugCurrentPropIdx, #DEBUG_PROPS), 3)
end

-- Units die with the world; clear our weak reference list each heist and re-arm
-- the auto-spawn latch so the next heist rolls a fresh count.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_ScrapperSpawner_SessionReset", function()
	_G.CSR_DebugSpawnedUnits = {}
	_G.CSR_AutoScrapperSpawned = false
end)

-- SP/host-only port: the MP client spawn-sync layer (pending-payload queue,
-- the CSR_ScrapperSpawn RPC, late-join replay) is deferred with the rest of the
-- MP slice. Shredders spawn host-locally.

-- CSR-heist gate shared with copier_spawner.lua / combat_modifiers.lua: temp
-- "crime_spree" job WITH vanilla Crime Spree NOT active -- the no-leak CSR-heist
-- signal (feedback_csr_only_no_vanilla_leak).
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

-- Per-heist auto-spawn count rolled in [SCRAPPER_AUTO_MIN, SCRAPPER_AUTO_MAX]
-- inclusive. MIN=0 is intentional -- the scrapper has a valid "zero this heist"
-- outcome.
local SCRAPPER_AUTO_MIN = 0
local SCRAPPER_AUTO_MAX = 2
-- Same gate as the printer (copier_spawner.lua FIRST_ITEM_RANK): scrappers, like
-- printers, only appear once the host has earned at least one item pick.
local FIRST_ITEM_RANK = 1

-- Host-only. Picks 0-2 cover-anchored placements (via the printer's exposed
-- pick_cover_spawns helper, so scrapper placements honor MIN_COPIER_SEPARATION
-- and avoid landing on top of any printer that auto-spawned earlier this heist)
-- and spawns a shredder at each.
local function do_auto_spawn_scrapper()
	-- Shredder is the first entry in DEBUG_PROPS.
	local def = DEBUG_PROPS[1]
	if not def then
		return
	end
	if not (DB and DB.has and DB:has(UNIT_EXT, def.unit_idstring)) then
		return
	end

	-- Same first-item rank gate as the printer: nothing until rank >= 1.
	local mgr = managers.csr
	local rank = (mgr and mgr.host_rank and mgr:host_rank()) or 0
	if rank < FIRST_ITEM_RANK then
		log(
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

-- One-shot host-authoritative scrapper auto-spawn under the SAME condition as
-- the printer: Network:is_server + CSR heist + nav ready, then rank >= 1 inside
-- do_auto_spawn_scrapper. NOT gated on the printer having spawned. Cover
-- separation from printers is still guaranteed by the shared pick_cover_spawns /
-- too_close_to_existing check (mutual -- it inspects both CSR_Copiers and
-- CSR_DebugSpawnedUnits; the printer's hook also runs first each frame), so no
-- explicit ordering dependency is needed.
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
	_G.CSR_AutoScrapperSpawned = true -- latch BEFORE spawn so any failure doesn't re-fire
	do_auto_spawn_scrapper()
end)

-- Proximity-gated yellow contour. The csr_yellow_interactable palette is
-- registered in lua/tweakdata/scrapper_interaction.lua; this hook drives
-- visibility per-frame via set_contour. Per-unit cache prevents the per-frame
-- call from redundantly poking materials when nothing changed.
-- Hand-tuned by feel because vanilla's "can-press-F" gate uses a raycast from
-- the player camera (~165 cm above the feet) against the prop body, while
-- this hook measures feet-to-pivot distance. Auto-deriving from
-- csr_scrapper.interact_distance (250) was tried and didn't visually align —
-- the camera-height offset plus the prop body extent shift the practical
-- threshold below 250 in feet-distance terms. Bump this number until the
-- contour pops on at the same moment the "Hold F" prompt becomes pressable.
local PROX_RANGE = 240 -- centimeters; manual. Slightly over the practical interact threshold so the contour acts as a "you're getting close" cue before F becomes pressable — intentional.
local PROX_RANGE_SQ = PROX_RANGE * PROX_RANGE
-- Exposed globally so CrimeSpreeScrapperInteractionExt:set_contour (in
-- scrapper_interaction_ext.lua) can read the per-unit range state and force
-- opacity=0 when out-of-range, regardless of which code path calls set_contour
-- (our prox hook, vanilla's selected/unselect, Clientsided Uppers wrappers,
-- etc.). Mirrors the pattern in copier_spawner.lua.
_G.CSR_ScrapperProxState = _G.CSR_ScrapperProxState or setmetatable({}, { __mode = "k" })

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
