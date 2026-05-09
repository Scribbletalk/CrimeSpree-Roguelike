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

-- Units die with the world; just clear our weak reference list each heist.
-- Also clear the auto-spawn latch + per-heist payload stash so the next heist
-- can roll a fresh count and late-joiners see the new heist's placements.
--
-- IMPORTANT: do NOT wipe _G.CSR_PendingClientScrappers here. Late-join RPCs
-- can arrive BEFORE this hook fires (host sends ~1s after handshake). Mirrors
-- the same constraint copier_spawner.lua documents at its session reset hook.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_ScrapperSpawner_SessionReset", function()
	_G.CSR_DebugSpawnedUnits = {}
	_G.CSR_AutoScrapperSpawned = false
	_G.CSR_LastScrapperPayloads = {}
	_G.CSR_ScrapperGateLogged = false -- re-arm one-shot gate diagnostic for next heist
end)

-- FIFO queue of scrapper spawn payloads that arrived on the client before the
-- heist was ready (pre-planning, mid-load, or late-join replay firing before
-- GameSetup settles). Drained from GameSetupUpdate once the gate opens.
-- Mirrors _G.CSR_PendingClientCopiers in copier_spawner.lua — same race, same
-- defense. Each entry is { pos = Vector3, rot = Rotation, def = DEBUG_PROPS[i] }.
_G.CSR_PendingClientScrappers = _G.CSR_PendingClientScrappers or {}
_G.CSR_PendingScrapperSince = _G.CSR_PendingScrapperSince or nil
_G.CSR_PendingScrapperLastLog = _G.CSR_PendingScrapperLastLog or 0

-- Mirrors copier_spawner.lua's client_heist_ready(): require session-loaded
-- (packages mounted), CS active + current_mission + job_id == "crime_spree"
-- (6.0.2 leak guard so a stale is_active() carrying over from a prior CS run
-- can't drain pending scrapper payloads into a vanilla heist), and the local
-- player to be alive (rules out briefing/pre-planning UI). Returns
-- (ok, reason_when_not_ok) so the watchdog can log WHY it's waiting.
local function client_heist_ready()
	if not _G.CSR_ClientSessionLoaded then
		return false, "session_not_loaded"
	end
	if not (managers.crime_spree and managers.crime_spree:is_active()) then
		return false, "cs_not_active"
	end
	if not (managers.crime_spree.current_mission and managers.crime_spree:current_mission()) then
		return false, "cs_no_current_mission"
	end
	if not (managers.job and managers.job:current_job_id() == "crime_spree") then
		return false, "cs_job_mismatch"
	end
	local p = managers.player and managers.player:player_unit()
	if not alive(p) then
		return false, "no_player_unit"
	end
	return true
end

-- Per-heist auto-spawn count rolled in [SCRAPPER_AUTO_MIN, SCRAPPER_AUTO_MAX]
-- inclusive. MIN=0 is intentional — unlike the printer, the scrapper has a
-- valid "zero this heist" outcome. No item-threshold gate either: scrapping
-- is useful from heist one (lets the player commit to a strategy by trashing
-- off-build items even before they have many).
local SCRAPPER_AUTO_MIN = 0
local SCRAPPER_AUTO_MAX = 2

-- Per-heist payload stash for late-join replay. Mirrors CSR_LastCopierPayloads.
-- Cleared on BaseNetworkSessionOnLoadComplete (see existing reset hook above).
_G.CSR_LastScrapperPayloads = _G.CSR_LastScrapperPayloads or {}

-- Host-only. Picks 0-2 cover-anchored placements (via the printer's exposed
-- pick_cover_spawns helper, so scrapper placements honor MIN_COPIER_SEPARATION
-- AND avoid landing on top of any printer that auto-spawned earlier this
-- heist) and spawns a shredder at each. Broadcasts each placement to clients
-- via LuaNetworking and stashes the payloads for late-join replay.
local function do_auto_spawn_scrapper()
	-- Shredder is the first (and currently only) entry in DEBUG_PROPS.
	-- If more debug props are added later, this should look up by key.
	local def = DEBUG_PROPS[1]
	if not def then
		return
	end
	if not (DB and DB.has and DB:has(UNIT_EXT, def.unit_idstring)) then
		return
	end

	-- Reset stash FIRST so late-joiners on a 0-roll heist see zero scrappers
	-- (matches what the host's world has after the early-out below).
	_G.CSR_LastScrapperPayloads = {}

	local count = math.random(SCRAPPER_AUTO_MIN, SCRAPPER_AUTO_MAX)
	if count == 0 then
		return
	end

	local pick = _G.CSR_PickCoverSpawns
	if not pick then
		return
	end

	local spawns = pick(count)
	if #spawns == 0 then
		return
	end

	local is_mp = _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer() and LuaNetworking

	for _, s in ipairs(spawns) do
		local unit = spawn_at(s.pos, s.rot, def)
		if unit then
			-- Stash + broadcast. Payload is "x|y|z|yaw|key" — key lets future
			-- additions to DEBUG_PROPS resolve to the right def on client. The
			-- copier uses a richer payload (id_prefix|tier) because it has
			-- per-spawn offer state; the scrapper has none, just the prop.
			local payload = string.format(
				"%s|%s|%s|%s|%s",
				tostring(s.pos.x),
				tostring(s.pos.y),
				tostring(s.pos.z),
				tostring(s.rot:yaw()),
				tostring(def.key)
			)
			table.insert(_G.CSR_LastScrapperPayloads, payload)
			if is_mp then
				LuaNetworking:SendToPeers("CSR_ScrapperSpawn", payload)
			end
		end
	end
end

-- Client-side receive handler. multiplayer_sync.lua dispatches incoming
-- CSR_ScrapperSpawn messages here. Mirrors CSR_HandleCopierSpawn but with the
-- simpler "x|y|z|yaw|key" payload (no offer_def to reconstruct).
--
-- If the client isn't heist-ready yet (late-join replay / pre-planning), the
-- payload is queued and drained later from GameSetupUpdate — see
-- CSR_PendingClientScrappers and the drain block at the bottom of this file.
-- Same defense pattern as CSR_HandleCopierSpawn in copier_spawner.lua.
_G.CSR_HandleScrapperSpawn = function(payload)
	if type(payload) ~= "string" then
		return
	end
	local px, py, pz, yaw_s, key = payload:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
	local x, y, z, yaw = tonumber(px), tonumber(py), tonumber(pz), tonumber(yaw_s)
	if not (x and y and z and yaw and key) then
		return
	end

	-- Resolve def by key. Falls back to DEBUG_PROPS[1] if the key is unknown
	-- (forward-compat for clients on older mod versions).
	local def
	for _, d in ipairs(DEBUG_PROPS) do
		if d.key == key then
			def = d
			break
		end
	end
	def = def or DEBUG_PROPS[1]
	if not def then
		return
	end

	if not (DB and DB.has and DB:has(UNIT_EXT, def.unit_idstring)) then
		return
	end

	local pos = Vector3(x, y, z)
	local rot = Rotation(yaw, 0, 0)

	local ready, reason = client_heist_ready()
	if not ready then
		table.insert(_G.CSR_PendingClientScrappers, { pos = pos, rot = rot, def = def })
		-- Use Application:time() (wall-clock from engine start) rather than os.time()
		-- so the watchdog log measures real elapsed seconds even across save/load.
		if not _G.CSR_PendingScrapperSince then
			_G.CSR_PendingScrapperSince = (Application and Application:time()) or 0
		end
		log(
			"[CSR Scrapper] queued payload (reason="
				.. tostring(reason)
				.. ", queue_depth="
				.. tostring(#_G.CSR_PendingClientScrappers)
				.. ")"
		)
		return
	end

	spawn_at(pos, rot, def)
end

-- Host-only. Replays every scrapper auto-spawned this heist to a single peer.
-- Called from multiplayer_sync.lua during the post-HANDSHAKE delayed sync so
-- a late-joining client sees the same scrappers the rest of the party has.
_G.CSR_ScrapperSendToPeer = function(peer_id)
	if not (_G.CSR_MP and CSR_MP.is_host and CSR_MP.is_host()) then
		return
	end
	if not peer_id or not LuaNetworking then
		return
	end
	local payloads = _G.CSR_LastScrapperPayloads
	if not payloads or #payloads == 0 then
		return
	end
	for _, payload in ipairs(payloads) do
		LuaNetworking:SendToPeer(peer_id, "CSR_ScrapperSpawn", payload)
	end
end

_G.CSR_AutoScrapperSpawned = _G.CSR_AutoScrapperSpawned or false

-- Latched once-per-heist on the same nav-ready / CS-active gate the printer
-- uses. Additionally gated on _G.CSR_AutoCopierSpawned so the printer's
-- placements are already in CSR_Copiers before pick_cover_spawns runs for
-- the scrapper — that's how too_close_to_existing keeps the two off each
-- other's covers (see the matching block in copier_spawner.lua).
--
-- Also drains _G.CSR_PendingClientScrappers when the client gate opens —
-- mirrors the drain in copier_spawner.lua's GameSetupUpdate. Combined into
-- one Hooks:Add since both pieces want to fire on the same frame timer and
-- pay the same per-frame check cost.
Hooks:Add("GameSetupUpdate", "CSR_ScrapperAutoSpawn", function(_t, _dt)
	-- === Host-side: one-shot auto-spawn ===
	if not _G.CSR_AutoScrapperSpawned and _G.CSR_AutoCopierSpawned then
		local is_host = _G.CSR_MP and CSR_MP.is_host and CSR_MP.is_host()
		local cs_mgr = managers.crime_spree
		local cs_active = cs_mgr and cs_mgr:is_active()
		local cs_current_mission = cs_mgr and cs_mgr.current_mission and cs_mgr:current_mission()
		local job_id = managers.job and managers.job:current_job_id()
		local cs_job = job_id == "crime_spree"
		local nav_ready = managers.navigation and managers.navigation:is_data_ready()

		-- 6.0.2 leak guard mirror: dump every signal one-shot per heist so a
		-- future scrapper-leak report is diagnosable from logs alone (matches
		-- the [CSR Copier Gate] block in copier_spawner.lua).
		if is_host and not _G.CSR_ScrapperGateLogged then
			_G.CSR_ScrapperGateLogged = true
			log(
				"[CSR Scrapper Gate] is_host="
					.. tostring(is_host)
					.. " cs_active="
					.. tostring(cs_active)
					.. " cs_current_mission="
					.. tostring(cs_current_mission)
					.. " job_id="
					.. tostring(job_id)
					.. " cs_job="
					.. tostring(cs_job)
					.. " nav_ready="
					.. tostring(nav_ready)
					.. " auto_copier_spawned="
					.. tostring(_G.CSR_AutoCopierSpawned)
			)
		end

		if is_host and cs_active and cs_current_mission and cs_job and nav_ready then
			_G.CSR_AutoScrapperSpawned = true -- latch BEFORE spawn so any failure doesn't re-fire
			do_auto_spawn_scrapper()
		end
	end

	-- === Client-side: drain queued spawn payloads when heist is ready ===
	-- client_heist_ready() gates on session-loaded + nav + CS + local player
	-- alive so pre-planning / loading frames don't reach spawn_unit. Mirrors
	-- the drain in copier_spawner.lua.
	local pending = _G.CSR_PendingClientScrappers
	if pending and #pending > 0 then
		local ready, reason = client_heist_ready()
		if ready then
			_G.CSR_PendingClientScrappers = {}
			_G.CSR_PendingScrapperSince = nil
			_G.CSR_PendingScrapperLastLog = 0
			log("[CSR Scrapper] draining " .. tostring(#pending) .. " queued payload(s)")
			for _, q in ipairs(pending) do
				spawn_at(q.pos, q.rot, q.def)
			end
		else
			-- Watchdog: log once every 5s if we've been waiting a long time so
			-- a remote bug report can show "client never reached ready state"
			-- without needing additional debug instrumentation.
			local now = (Application and Application:time()) or 0
			if now - (_G.CSR_PendingScrapperLastLog or 0) > 5 then
				_G.CSR_PendingScrapperLastLog = now
				local since = _G.CSR_PendingScrapperSince or now
				log(
					"[CSR Scrapper] still waiting to drain queue (depth="
						.. tostring(#pending)
						.. ", reason="
						.. tostring(reason)
						.. ", waited="
						.. tostring(math.floor(now - since))
						.. "s)"
				)
			end
		end
	end
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
