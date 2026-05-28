-- Crime Spree Roguelike - in-world copy-machine (printer) spawner + exchange flow.
--   F6 = debug spawn at nav cover closest to player (iterate placement math).
--   F7 = debug spawn at crosshair (rolls a random item for that copier).
--   Auto-spawn = 1..3 copiers per CS heist at cop cover points (host-authoritative).
--   Use = PD2-native interaction via CrimeSpreeCopierInteractionExt; this file
--         exposes use_copier as _G.CSR_UseCopier for the subclass to call.
-- Unit + assets are injected via supermod.xml (see assets/ in mod root).
-- Lid animation uses anim_play_to with a SIGNED speed (1 forward, -1 reverse) —
-- matches the vanilla WeaponUnderbarrel pattern. No custom sequence_manager needed.
if not RequiredScript then
	return
end

local COPIER_DBPATH = "units/payday2/props/off_prop_copy_machine_smuggle/off_prop_copy_machine_smuggle"
local UNIT_EXT = Idstring("unit")
local UNIT_NAME = Idstring(COPIER_DBPATH)
local PKG_NAME = (DynamicResourceManager and DynamicResourceManager.DYN_RESOURCES_PACKAGE) or "packages/dyn_resources"

-- === BILLBOARD ICON (Doom-style 3D quad) ===
-- Vanilla pattern: coremissionelement.lua:93-97 (mission-element editor icons).
-- Fixing the drift we saw earlier requires TWO things the previous attempts
-- got wrong:
--   1. The quad's CENTER must sit on desired_center, not its top-left. Do this
--      by subtracting half of each basis from pos:
--        pos = desired_center - x_basis*0.5 - y_basis*0.5
--      BILLBOARD_BOTH then rotates the quad around its center to face camera,
--      keeping the icon visibly at desired_center from every angle.
--   2. Snapshot the anchor AFTER the lid-open animation settles. During the
--      open cycle, unit:oobb() and the animated sub-objects' bounds drift —
--      any pos taken mid-animation is a transient value. A 2s DelayedCall
--      pushes creation past the open cycle (open at t+0.05, length ~0.4s).
local BILLBOARD_WORLD_SIZE = 64 -- cm side length of the billboard quad (frame spans this)
local BILLBOARD_PANEL_PX = 128 -- matches csr_* icon texture_rect {0,0,128,128}
-- Match the ITEMS tab's frame:icon ratio (items_page.lua:398-402 ships with
-- DEFAULT_FRAME=74, icon_size=38). Derived symbolically so any future tweak
-- on the ITEMS tab ratio can be mirrored by updating those two constants.
local ITEMS_TAB_FRAME_PX = 74
local ITEMS_TAB_ICON_PX = 38
local BILLBOARD_ICON_PX = math.floor(BILLBOARD_PANEL_PX * ITEMS_TAB_ICON_PX / ITEMS_TAB_FRAME_PX)
local BILLBOARD_Z_ABOVE_CENTER = 100 -- cm above base oobb center
-- Side offset (cm) along the copier's LOCAL -X axis. The copier is spawned
-- with yaw = camera yaw, so its back faces the player → local -X is the
-- player's left when looking at it. Positive value shifts icon left; flip
-- sign if it ends up on the right instead.
local BILLBOARD_SIDE_OFFSET = 50
local BILLBOARD_SPAWN_DELAY = 2.0 -- seconds after unit spawn before creating

-- Single csr_frame texture tinted per rarity (only csr_frame.dds exists on
-- disk; rarity is carried by the Color tint). 4-arg Color = (alpha, r, g, b).
local RARITY_FRAMES = {
	common = { frame = "csr_frame", color = Color.white },
	uncommon = { frame = "csr_frame", color = Color(1, 0, 0.95, 0) },
	rare = { frame = "csr_frame", color = Color(1, 0.3, 0.7, 1) },
	contraband = { frame = "csr_frame", color = Color(1, 1, 0.4, 0) },
	wildcard = { frame = "csr_frame", color = Color(1, 1, 0.3, 0.8) },
}

-- Named sub-objects from off_prop_copy_machine_smuggle.object:
--   g_printer_base — static base mesh, never animates (billboard anchor)
--   rp_copy_machine_smuggle — orientation_object (same transform as unit pivot)
--   a_lid / g_printer_lid — animated top cover, avoid anchoring to this
local BASE_OBJ_NAME = Idstring("g_printer_base")

local LID_ANIM = Idstring("open_lid")

_G.CSR_Copiers = _G.CSR_Copiers or {}

-- SP/host-only port: the MP client spawn-sync layer (pending-payload queue,
-- session-loaded latch, late-join replay, the CSR_CopierSpawn RPC) is deferred
-- with the rest of the MP slice. Copiers spawn host-locally; clients seeing
-- them lands when MP sync ports.

-- Gate shared with combat_modifiers.lua / mission_lifecycle.lua: a CSR heist is
-- the temp "crime_spree" job WITH vanilla Crime Spree NOT active. Does NOT leak
-- into vanilla heists the way the persisted managers.csr:is_active() flag does
-- (feedback_csr_only_no_vanilla_leak).
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

-- === PRINTER SOUND ===
-- Clips registered in lua/core/sound.lua; played 3D-anchored to the unit via
-- _G.CSR.play_sound (single-sound source, auto-plays + auto-closes).
local function play_printer_sound(unit)
	if not (_G.CSR and _G.CSR.play_sound and alive(unit)) then
		return
	end
	_G.CSR.play_sound("printer_working", { unit = unit, volume = 0.5 })
end

local function play_printer_starting(unit)
	if not (_G.CSR and _G.CSR.play_sound and alive(unit)) then
		return
	end
	_G.CSR.play_sound("printer_starting", { unit = unit, volume = 0.5 })
end

local function hint(text, time)
	if managers and managers.hud and managers.hud.show_hint then
		managers.hud:show_hint({ text = text, time = time or 3 })
	end
	csr_log("[CSR Copier] " .. tostring(text))
end

local function is_ready()
	return managers and managers.dyn_resource and managers.dyn_resource:is_resource_ready(UNIT_EXT, UNIT_NAME, PKG_NAME)
end

-- Verbose log gated on the debug_mode setting. Used by the placement probes
-- which can emit 50+ lines per spawn -- useful while iterating on placement
-- math but noise in normal play. Toggled in the mod options debug submenu.
local function debug_log(msg)
	local mgr = managers and managers.csr
	if mgr and mgr.debug_enabled and mgr:debug_enabled() then
		log(msg)
	end
end

-- Printer offer roll: weighted by RARITY (mirrors the U1 selection roller's
-- rarity-then-uniform model in game_manager), never wildcard, never scrap,
-- never contraband. Contraband is exclusively a Black Market shop offering.
local PRINTER_RARITY_WEIGHTS = {
	common = 80,
	uncommon = 40,
	rare = 4,
}

local function roll_offer()
	local mgr = managers.csr
	if not (mgr and mgr.registered_items) then
		return nil
	end
	-- Bucket eligible registry items by rarity (skip wildcard + scrap).
	local buckets = {}
	for _, def in ipairs(mgr:registered_items()) do
		local r = def.rarity
		if r and not def.is_scrap and PRINTER_RARITY_WEIGHTS[r] then
			buckets[r] = buckets[r] or {}
			table.insert(buckets[r], def)
		end
	end
	-- Live weights over rarities that actually have items this session.
	local weights, total = {}, 0
	for r, w in pairs(PRINTER_RARITY_WEIGHTS) do
		if buckets[r] and #buckets[r] > 0 then
			weights[r] = w
			total = total + w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	local acc, chosen = 0, nil
	for r, w in pairs(weights) do
		acc = acc + w
		if roll <= acc then
			chosen = r
			break
		end
	end
	if not chosen then
		-- Float-tail fallback: take any rarity that has items.
		chosen = next(weights)
	end
	local bucket = buckets[chosen]
	return bucket[math.random(#bucket)]
end

-- Display name of an item: first line of its localized name, falling back to type.
local function offer_display_name(offer_def)
	if not offer_def then
		return "(unknown)"
	end
	if offer_def.name and managers.localization then
		local full = managers.localization:text(offer_def.name)
		local first = full and full:match("^([^\n]+)")
		if first and first ~= "" then
			return first
		end
	end
	return offer_def.type or "(unknown)"
end

local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}

-- Local player's owned registry defs of a given rarity tier (count > 0).
local function owned_defs_of_tier(tier)
	local mgr = managers.csr
	if not (mgr and mgr.registered_items) then
		return {}
	end
	local owned = mgr:player_items(mgr:local_peer_id()) -- { [type] = count }
	local list = {}
	for _, def in ipairs(mgr:registered_items()) do
		if def.rarity == tier and (owned[def.type] or 0) > 0 then
			list[#list + 1] = def
		end
	end
	return list
end

-- Pick an owned item of `tier` to sacrifice. Priority:
--   1. Scrap of the tier (is_scrap) -- it exists precisely to be eaten here.
--   2. A real item whose type differs from the offer (getting back the same
--      item you gave feels worse than any swap).
--   3. A real item matching the offer (last resort).
-- Returns the chosen registry def, or nil if the player owns nothing of `tier`.
local function pick_sacrifice(tier, offer_type)
	local list = owned_defs_of_tier(tier)
	if #list == 0 then
		return nil
	end
	local scraps, others, same = {}, {}, {}
	for _, def in ipairs(list) do
		if def.is_scrap then
			table.insert(scraps, def)
		elseif def.type == offer_type then
			table.insert(same, def)
		else
			table.insert(others, def)
		end
	end
	if #scraps > 0 then
		return scraps[math.random(#scraps)]
	end
	if #others > 0 then
		return others[math.random(#others)]
	end
	return same[math.random(#same)]
end

-- anim_play_to(name, target_time, speed). Speed is signed:
--   speed>0 + target=length -> play forward to end (lid opens)
--   speed<0 + target=0      -> play backward to start (lid closes)
-- Vanilla pattern from WeaponUnderbarrel:play_anim.
local OPEN_SPEED = 5
local CLOSE_SPEED = -5
-- Print cycle timing (tuned by ear, not ogg duration — the working.ogg file
-- has trailing silence that makes the stream longer than the audible tail).
--   t=0.0 -> lid closes + printer_starting.ogg
--   t=1.0 -> printer_working.ogg
--   t=2.6 -> lid reopens
local WORKING_SOUND_DELAY = 0.5
local REOPEN_DELAY = 2.0

local function play_lid(unit, direction)
	if not alive(unit) then
		return
	end
	local ok_len, len = pcall(function()
		return unit:anim_length(LID_ANIM)
	end)
	if not ok_len or not len or len <= 0 then
		return
	end
	local target = (direction == "forward") and len or 0
	local speed = (direction == "forward") and OPEN_SPEED or CLOSE_SPEED
	pcall(function()
		unit:anim_play_to(LID_ANIM, target, speed)
	end)
end

local function play_open(unit)
	play_lid(unit, "forward")
end

local function play_close(unit)
	play_lid(unit, "reverse")
end

local function create_billboard(unit, icon_name, tier)
	if not alive(unit) then
		log("[CSR Copier] create_billboard: unit not alive")
		return nil
	end

	local fd = (tweak_data and tweak_data.hud_icons and icon_name) and tweak_data.hud_icons[icon_name] or nil
	local frame_info = RARITY_FRAMES[tier]
	local frame_fd = (frame_info and tweak_data and tweak_data.hud_icons) and tweak_data.hud_icons[frame_info.frame]
		or nil

	local base = unit:get_object(BASE_OBJ_NAME)
	local orient = unit:orientation_object()
	if not base or not orient then
		log("[CSR Copier] create_billboard: missing base or orientation object")
		return nil
	end

	-- Steady-state anchor (called after 2s, lid fully open). base:oobb():center
	-- is the static mesh center in world space; orient:rotation():z() is the
	-- copier's local +Z so the offset stays "above" even on tilted surfaces.
	-- Side offset: -orient:rotation():x() = copier's local -X, which is the
	-- player's left when the copier is spawned with its back toward the player.
	local base_center = base:oobb():center()
	local local_up = orient:rotation():z()
	local local_right = orient:rotation():x()
	local desired_center = base_center + local_up * BILLBOARD_Z_ABOVE_CENTER - local_right * BILLBOARD_SIDE_OFFSET

	-- Panel basis vectors. Initial orientation is flat in world XZ (vertical
	-- plane); BILLBOARD_BOTH rotates the whole quad around its center to face
	-- camera, so the choice of initial orientation is cosmetic.
	local x_basis = Vector3(BILLBOARD_WORLD_SIZE, 0, 0)
	local y_basis = Vector3(0, 0, -BILLBOARD_WORLD_SIZE)
	-- Centering: subtract half of each basis from pos so the workspace's
	-- mid-point (not its top-left corner) lands on desired_center. This is
	-- the `unit:position() - Vector3(iconsize/2, iconsize/2, 0)` form from
	-- coremissionelement.lua:94, adapted for a vertical basis.
	local pos = desired_center - x_basis * 0.5 - y_basis * 0.5

	csr_log(
		string.format(
			"[CSR Copier] billboard anchors: pivot=%s base_pos=%s base_center=%s desired_center=%s ws_pos=%s",
			tostring(unit:position()),
			tostring(base:position()),
			tostring(base_center),
			tostring(desired_center),
			tostring(pos)
		)
	)

	local gui = World:newgui()
	local ws
	local ok, err = pcall(function()
		ws = gui:create_linked_workspace(BILLBOARD_PANEL_PX, BILLBOARD_PANEL_PX, base, pos, x_basis, y_basis)
		ws:set_billboard(Workspace.BILLBOARD_BOTH)
		-- Transparent layout anchor (vanilla mission editor uses a core gui,
		-- but bare bitmaps need a panel to attach to — this rect provides it).
		ws:panel():rect({
			name = "csr_copier_bg",
			color = Color(0, 0, 0, 0),
			w = BILLBOARD_PANEL_PX,
			h = BILLBOARD_PANEL_PX,
			layer = 10000,
		})
		if frame_fd then
			ws:panel():bitmap({
				name = "csr_copier_frame",
				texture = frame_fd.texture,
				texture_rect = frame_fd.texture_rect,
				color = (frame_info and frame_info.color) or Color.white,
				w = BILLBOARD_PANEL_PX,
				h = BILLBOARD_PANEL_PX,
				layer = 15000,
			})
		end
		if fd then
			-- Centered within the panel: (panel - icon)/2 on each axis so the
			-- rarity frame remains visible around all four sides of the icon.
			local icon_offset = (BILLBOARD_PANEL_PX - BILLBOARD_ICON_PX) * 0.5
			ws:panel():bitmap({
				name = "csr_copier_icon",
				texture = fd.texture,
				texture_rect = fd.texture_rect,
				color = Color.white,
				x = icon_offset,
				y = icon_offset,
				w = BILLBOARD_ICON_PX,
				h = BILLBOARD_ICON_PX,
				layer = 20000,
			})
		end
	end)
	if not ok then
		log("[CSR Copier] create_billboard THREW: " .. tostring(err))
		return nil
	end
	return { ws = ws, gui = gui }
end

local function destroy_billboard(bb)
	if not bb then
		return
	end
	pcall(function()
		if bb.gui and bb.ws then
			bb.gui:destroy_workspace(bb.ws)
		end
	end)
end

local function use_copier(c)
	if not c.offer_type or not c.tier then
		hint("Copier has no offer", 2)
		return
	end
	if c.cycling then
		-- Silent no-op during close→reopen cycle; don't spam the user with hints.
		return
	end

	local mgr = managers.csr
	if not (mgr and mgr.add_item and mgr.remove_item) then
		hint("Item store unavailable", 5)
		return
	end

	-- Pick the sacrifice up front so we can bail before animating if there's
	-- nothing eligible to give up.
	local sacrifice = pick_sacrifice(c.tier, c.offer_type)
	if not sacrifice then
		hint("No " .. tostring(c.tier) .. " items in your inventory to sacrifice", 4)
		return
	end

	-- Kick off the close animation IMMEDIATELY. Sacrifice removal + its chat line
	-- fire NOW (player gave the item up, printer is processing it). The offer +
	-- "printed!" line wait for the lid to reopen (prize dispensed).
	c.cycling = true
	play_close(c.unit)
	play_printer_starting(c.unit)
	local unit_ref = c.unit
	local color = RARITY_COLORS[c.tier] or Color.white
	local pid = mgr:local_peer_id()
	local sacrifice_name = offer_display_name(sacrifice)

	-- Main whir queued to start when the starting cue ends.
	DelayedCalls:Add("CSR_CopierMainSound_" .. tostring(unit_ref:key()), WORKING_SOUND_DELAY, function()
		if alive(unit_ref) then
			play_printer_sound(unit_ref)
		end
	end)

	-- === Sacrifice: immediate on interact. (add/remove auto-reconcile owned
	-- item effects via the on_item_added/removed callbacks in game_manager.) ===
	local removed = mgr:remove_item(pid, sacrifice.type)
	if not removed then
		hint("Failed to remove sacrifice item " .. tostring(sacrifice.type), 5)
		-- Still reopen the lid so the printer doesn't stay stuck closed.
		DelayedCalls:Add("CSR_CopierReopen_" .. tostring(unit_ref:key()), REOPEN_DELAY, function()
			c.cycling = false
			if alive(unit_ref) then
				play_open(unit_ref)
			end
		end)
		return
	end

	if managers.chat then
		managers.chat:_receive_message(1, tostring(sacrifice_name), "sacrificed!", color)
	end

	-- === Offer: awarded when the lid reopens (animation complete). ===
	DelayedCalls:Add("CSR_CopierReopen_" .. tostring(unit_ref:key()), REOPEN_DELAY, function()
		c.cycling = false
		if alive(unit_ref) then
			play_open(unit_ref)
			-- Cycling ended: if the player is still looking at this copier, refresh
			-- the hover prompt directly (text_dirty is unreliable across frames).
			local int_ext = unit_ref:interaction()
			if int_ext and managers.interaction and managers.interaction:active_unit() == unit_ref then
				local local_player = managers.player and managers.player:player_unit()
				if local_player and int_ext.update_show_interact then
					int_ext:update_show_interact(local_player)
				end
			end
		end

		mgr:add_item(pid, c.offer_type)
		csr_log("[CSR Copier] Exchange: " .. tostring(sacrifice.type) .. " -> " .. tostring(c.offer_type))

		-- MP: our counts changed (sacrifice removed, offer added) -- tell the other
		-- peers so their items panel converges. Self-gates on multiplayer (SP no-op).
		if _G.CSR_MP and _G.CSR_MP.broadcast_own_items then
			_G.CSR_MP.broadcast_own_items()
		end

		if managers.chat then
			managers.chat:_receive_message(1, tostring(c.offer_name or c.offer_type), "printed!", color)
		end
	end)
end

-- Host -> all: mirror a just-spawned copier so every client spawns a local copy
-- showing the SAME offer. The host unit key doubles as a dedup token (real-time
-- broadcast vs late-join replay); pos/rot are serialised in full (the placement
-- rotation is Rotation(-normal_flat, math.UP), not just a yaw) and round-trip
-- exactly through Rotation(yaw, pitch, roll). Self-gates to host-in-MP inside
-- CSR_MP.broadcast_prop, so the client's own _spawn_copier never re-broadcasts.
local function broadcast_copier_spawn(unit, pos, rot, offer_type)
	if not (_G.CSR_MP and _G.CSR_MP.broadcast_prop and _G.CSR_MP.MSG) then
		return
	end
	if not (alive(unit) and pos and rot) then
		return
	end
	local payload = string.format(
		"%s~%.2f~%.2f~%.2f~%.4f~%.4f~%.4f~%s",
		tostring(unit:key()),
		pos.x,
		pos.y,
		pos.z,
		rot:yaw(),
		rot:pitch(),
		rot:roll(),
		tostring(offer_type or "")
	)
	_G.CSR_MP.broadcast_prop(_G.CSR_MP.MSG.COPIER_SPAWN, payload)
end

-- Shared spawn core. Caller supplies position + rotation + offer_def. Returns
-- the copier entry (with unit ref + offer metadata) or nil on failure.
local function _spawn_copier(pos, rot, offer_def)
	-- The unit's package is mounted at mod init (supermod.xml dyn_package), so by
	-- heist time DB:has + is_ready are true (callers gate on DB:has). pcall guards
	-- the rare spawn failure; a native AV here can't be caught regardless.
	local ok, unit = pcall(World.spawn_unit, World, UNIT_NAME, pos, rot)
	if not ok or not alive(unit) then
		log("[CSR Copier] Spawn failed: " .. tostring(unit))
		return nil
	end

	-- Make the copier non-solid to the player mover. The unit ships on slot 1
	-- (dynamics, player-blocking); zipline's set_collisions_enabled alone isn't
	-- enough for this slot, so we stack three disables:
	--   1. set_enabled(false) removes each body from physics simulation entirely
	--      (same call enemymanager.lua:1475 uses on cop corpse mover_blocker bodies)
	--   2. set_collisions_enabled(false) as belt-and-braces in case set_enabled
	--      isn't honored on all body types in this prop
	--   3. Move the whole unit to slot 11 (statics) with bodies already disabled
	--      — matches enemymanager.lua:1614 on dropped magazines to get them out
	--      of slot 1's dynamic-collision path.
	-- Interaction is handled by CrimeSpreeCopierInteractionExt (native PD2 extend),
	-- so body disables don't break the interact flow.
	-- SIDE EFFECT: cops and the player walk straight through the printer because
	-- no collision + not in the pre-baked nav mesh. Accepted as cosmetic for now.
	-- See bugs_todo.md "💡 Suggestions (backlog)" for the nav-obstacle follow-up.
	pcall(function()
		local nr = unit:num_bodies()
		csr_log("[CSR Copier] disabling collision: num_bodies=" .. tostring(nr))
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

	local offer_name = offer_display_name(offer_def)
	local tier = offer_def and offer_def.rarity or "common"

	local copier_entry = {
		unit = unit,
		offer_type = offer_def and offer_def.type,
		offer_name = offer_name,
		tier = tier,
		billboard_ws = nil,
	}
	table.insert(_G.CSR_Copiers, copier_entry)

	-- "Ready" pose (lid open). Short delay lets the unit settle before anim ops.
	DelayedCalls:Add("CSR_CopierSpawnOpen_" .. tostring(unit:key()), 0.05, function()
		if alive(unit) then
			play_open(unit)
		end
	end)

	-- Billboard deferred past the open animation (see BILLBOARD_SPAWN_DELAY doc).
	local offer_icon = offer_def and offer_def.icon
	DelayedCalls:Add("CSR_CopierBillboard_" .. tostring(unit:key()), BILLBOARD_SPAWN_DELAY, function()
		if not alive(unit) then
			return
		end
		copier_entry.billboard_ws = create_billboard(unit, offer_icon, tier)
	end)

	-- MP: mirror to clients (host-only; self-gated, so a client's own spawn from
	-- a received CSR_CopierSpawn does not echo back out).
	broadcast_copier_spawn(unit, pos, rot, offer_def and offer_def.type)

	return copier_entry
end

local function spawn_at_crosshair()
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
	local offer_def = roll_offer()
	local entry = _spawn_copier(pos, rot, offer_def)
	if entry then
		hint(string.format("Copier spawned — will print: %s (%s)", entry.offer_name, entry.tier), 4)
	end
end

-- Forward declaration: cover_to_placement is defined further down (alongside
-- pick_cover_spawns, where it naturally lives), but spawn_at_closest_cover
-- below needs to call it. Declaring the local name here lets both spawners
-- close over the same upvalue; the assignment fills it in at file-load time
-- well before any F6 keypress can fire.
local cover_to_placement

-- Minimum spacing between copiers (cm). The prop itself is ~120cm wide, so
-- anything under ~180cm means visible overlap. 250cm leaves a clear gap and
-- still allows two copiers in the same medium-sized room.
local MIN_COPIER_SEPARATION = 250

-- True if pos is within MIN_COPIER_SEPARATION of any already-alive copier.
-- Shared by F6 debug and auto-spawn so both paths honor the same spacing rule.
-- extra_positions lets auto-spawn also check against placements accepted
-- earlier in the SAME batch (those copiers haven't spawned yet, so they're
-- not in _G.CSR_Copiers when we're still picking the set).
-- Declared HERE (above spawn_at_closest_cover) rather than alongside the other
-- placement helpers below: Lua resolves identifiers at compile time, so if this
-- sat further down the file, spawn_at_closest_cover would resolve the name to a
-- global (nil at runtime → crash on F6). Any helper called from an earlier
-- function must be declared before that earlier function.
local function too_close_to_existing(pos, extra_positions)
	local min_sq = MIN_COPIER_SEPARATION * MIN_COPIER_SEPARATION
	for _, c in ipairs(_G.CSR_Copiers or {}) do
		if c.unit and alive(c.unit) then
			if mvector3.distance_sq(c.unit:position(), pos) < min_sq then
				return true
			end
		end
	end
	-- Also reject placements within MIN_COPIER_SEPARATION of any already-
	-- spawned scrapper (CSR_DebugSpawnedUnits is populated in
	-- scrapper_spawner.lua). Keeps the printer auto-spawn from landing on top
	-- of a scrapper that auto-spawned earlier this heist, and (since the
	-- scrapper auto-spawn calls the same pick_cover_spawns helper that uses
	-- this function) the scrapper auto-spawn naturally avoids printers too.
	for _, u in ipairs(_G.CSR_DebugSpawnedUnits or {}) do
		if alive(u) then
			if mvector3.distance_sq(u:position(), pos) < min_sq then
				return true
			end
		end
	end
	if extra_positions then
		for _, other_pos in ipairs(extra_positions) do
			if mvector3.distance_sq(other_pos, pos) < min_sq then
				return true
			end
		end
	end
	return false
end

-- Player-reachability check. Cop covers are placed for cops, so some sit in
-- AI-only zones (behind one-way bars, on roof shelves, in fenced patrol pens)
-- that the player can never walk to. PD2's nav system tracks per-segment
-- access bitmasks; players share the "teamAI*" access slot family with bot
-- teammates, so a coarse path under "teamAI4" is the closest proxy for "could
-- a player walk from here to there." This is the same check GroupAI uses to
-- decide whether to assign a cop to chase a player vs idle.
--
-- search_coarse is synchronous when called without a results_clbk (returns
-- the path directly), so we can call it inline at heist-start spawn time
-- without setting up a callback dance. Cost: one BFS over nav segments per
-- candidate. Heist start happens once per mission, with players already
-- waiting on a fade-in, so a few ms here is invisible.
local PLAYER_NAV_ACCESS = "teamAI4"

-- Returns the nav segment id the host's local player is standing on, or nil
-- if nav data isn't ready or the player isn't spawned yet.
local function get_player_nav_seg()
	if not (managers.navigation and managers.navigation:is_data_ready()) then
		return nil
	end
	local player = managers.player and managers.player:local_player()
	if not alive(player) then
		return nil
	end
	local ok, seg = pcall(function()
		return managers.navigation:get_nav_seg_from_pos(player:position())
	end)
	if ok then
		return seg
	end
	return nil
end

-- True if a coarse nav path exists from player_seg to target_seg under player
-- access. Caches per target_seg in `cache` so a batch of N candidates only
-- pays the search cost for unique target segments.
--
-- "player_ground_check" slot mask = world_geometry (slots 1, 11) PLUS slot 15
-- (player-only blockers added by mission script — the "invisible walls"
-- players hit on Transport: Downtown and similar maps) PLUS slot 39 (vehicles).
-- world_geometry alone misses these, which is why a navmesh path can exist
-- through geometry the player physically can't traverse: the navmesh is baked
-- against AI-graph obstacles and runtime-added slot-15 blockers don't always
-- invalidate baked paths. Raycasting with this mask + ray_type "walk" is the
-- canonical "could player movement get from A to B" test (it's what
-- huskplayermovement uses for its own ground-check casts).
local _slotmask_player_walk_cache = nil
local function get_player_walk_mask()
	if not _slotmask_player_walk_cache then
		_slotmask_player_walk_cache = managers.slot:get_mask("player_ground_check")
	end
	return _slotmask_player_walk_cache
end

-- Walks the coarse path (output of search_coarse) and raycasts each consecutive
-- pair under the player-walk mask. Hops are lifted 60cm so the cast travels at
-- chest height — clears floor seams and small ramps that would graze the ground
-- without missing wall-tall blockers (player blockers extend full height).
-- Tradeoff: distant nav-seg-center pairs that connect through a curved corridor
-- may be wrongly flagged blocked because the straight line crosses a real wall.
-- We accept some false negatives in exchange for catching the user-reported
-- "navmesh says yes, player can't reach" case (blocker between segments).
local function walk_path_player_clear(path, target_seg_for_log)
	if not path or #path < 2 then
		return true
	end
	local nav_segs = managers.navigation._nav_segments
	local mask = get_player_walk_mask()
	local prev_pos = nil
	local prev_seg = nil
	for hop_idx, node in ipairs(path) do
		local seg_id = node[1]
		local pos = node[2] -- 2-tuple entries (post-start) carry an explicit pos
		if not pos then
			-- Start node is just {seg_id}; use the seg's own center.
			local seg = nav_segs and nav_segs[seg_id]
			pos = seg and seg.pos
		end
		if not pos then
			return true -- can't validate this hop, fail open
		end
		if prev_pos then
			local from = prev_pos + Vector3(0, 0, 60)
			local to = pos + Vector3(0, 0, 60)
			local ok, hit = pcall(function()
				return World:raycast("ray", from, to, "slot_mask", mask, "ray_type", "walk")
			end)
			if ok and hit then
				-- Diesel body objects expose no :slot() method — that's a Unit
				-- method. Pull the unit through the body to read slot, and pcall
				-- the whole formatter so a malformed hit table can't crash spawn.
				local hit_slot = "?"
				pcall(function()
					if hit.unit then
						hit_slot = tostring(hit.unit:slot())
					elseif hit.body and hit.body.unit then
						local u = hit.body:unit()
						hit_slot = tostring(u and u:slot())
					end
				end)
				debug_log(
					string.format(
						"[CSR Copier] reach reject: target_seg=%s blocked at hop %d->%d (seg %s -> seg %s, dist %.0fcm, hit_slot=%s)",
						tostring(target_seg_for_log),
						hop_idx - 1,
						hop_idx,
						tostring(prev_seg),
						tostring(seg_id),
						(pos - prev_pos):length(),
						hit_slot
					)
				)
				return false
			end
		end
		prev_pos = pos
		prev_seg = seg_id
	end
	return true
end

local function is_seg_player_reachable(player_seg, target_seg, cache)
	if not (player_seg and target_seg) then
		return true -- nav not ready -> don't gate, fall back to old behavior
	end
	if player_seg == target_seg then
		return true
	end
	if cache and cache[target_seg] ~= nil then
		return cache[target_seg]
	end
	local ok, path = pcall(function()
		return managers.navigation:search_coarse({
			from_seg = player_seg,
			to_seg = target_seg,
			access_pos = PLAYER_NAV_ACCESS,
		})
	end)
	local reachable = false
	if ok and path then
		reachable = walk_path_player_clear(path, target_seg)
	elseif not ok or not path then
		debug_log(
			string.format(
				"[CSR Copier] reach reject: target_seg=%s no coarse path under access=%s",
				tostring(target_seg),
				tostring(PLAYER_NAV_ACCESS)
			)
		)
	end
	if cache then
		cache[target_seg] = reachable
	end
	return reachable
end

-- F6 debug: find the nav cover nearest to the local player and spawn a copier
-- there using the same raycast-based placement logic auto-spawn uses. Lets us
-- iterate on cover placement without having to search the map for an auto-
-- spawned copier each run.
local function spawn_at_closest_cover()
	if not (managers.navigation and managers.navigation:is_data_ready()) then
		hint("Navigation not ready", 3)
		return
	end
	local covers = managers.navigation._covers
	if not covers or #covers == 0 then
		hint("No cover points in this heist", 3)
		return
	end
	local player = managers.player and managers.player:local_player()
	if not alive(player) then
		hint("No local player", 3)
		return
	end
	local player_pos = player:position()

	-- Build a distance-sorted list of covers so we can walk outward until we
	-- find one that (a) produces a valid wall placement and (b) doesn't overlap
	-- an already-spawned copier. Previously we only picked the single closest,
	-- which meant F6-twice-without-moving always stacked two copiers on the
	-- exact same cover. PD2's Vector3 has no :length_sq() instance method so we
	-- use mvector3.distance_sq for the sort key and compare magnitudes directly.
	local sorted = {}
	for _, cover in ipairs(covers) do
		if cover[1] then
			table.insert(sorted, { cover = cover, d_sq = mvector3.distance_sq(cover[1], player_pos) })
		end
	end
	if #sorted == 0 then
		hint("No usable cover found", 3)
		return
	end
	table.sort(sorted, function(a, b)
		return a.d_sq < b.d_sq
	end)

	local player_seg = get_player_nav_seg()
	local reach_cache = {}
	local chosen_placement, chosen_dist = nil, nil
	local skipped_occupied, skipped_unreachable, skipped_blocked = 0, 0, 0
	for _, entry in ipairs(sorted) do
		-- cover[3] is a nav_tracker (NOT a seg id directly). Call :nav_segment()
		-- to get the int seg id for search_coarse. pcall guards against engine
		-- edge cases where the tracker has been freed.
		local cover_seg = nil
		if entry.cover[3] then
			local ok, seg = pcall(function()
				return entry.cover[3]:nav_segment()
			end)
			if ok then
				cover_seg = seg
			end
		end
		if player_seg and cover_seg and not is_seg_player_reachable(player_seg, cover_seg, reach_cache) then
			skipped_unreachable = skipped_unreachable + 1
		else
			local placement = cover_to_placement(entry.cover)
			if placement and cover_seg and not is_placement_in_seg_walkable(cover_seg, placement.pos) then
				skipped_blocked = skipped_blocked + 1
				placement = nil
			end
			if placement and not is_placement_los_from_player(placement.pos) then
				skipped_blocked = skipped_blocked + 1
				placement = nil
			end
			if placement then
				if too_close_to_existing(placement.pos) then
					skipped_occupied = skipped_occupied + 1
				else
					chosen_placement = placement
					chosen_dist = math.sqrt(entry.d_sq)
					break
				end
			end
		end
	end
	if not chosen_placement then
		if skipped_occupied > 0 then
			hint(string.format("All nearby covers already have a copier (%d skipped)", skipped_occupied), 4)
		elseif skipped_unreachable > 0 or skipped_blocked > 0 then
			hint(
				string.format(
					"No reachable cover with a usable wall (%d unreachable, %d blocked skipped)",
					skipped_unreachable,
					skipped_blocked
				),
				4
			)
		else
			hint("No cover with a usable wall nearby", 4)
		end
		return
	end

	local offer_def = roll_offer()
	local entry = _spawn_copier(chosen_placement.pos, chosen_placement.rot, offer_def)
	if entry then
		local label = skipped_occupied > 0
				and string.format(
					"Copier spawned (%.1fm, skipped %d occupied) — will print: %s (%s)",
					chosen_dist / 100,
					skipped_occupied,
					entry.offer_name,
					entry.tier
				)
			or string.format(
				"Copier spawned at closest cover (%.1fm) — will print: %s (%s)",
				chosen_dist / 100,
				entry.offer_name,
				entry.tier
			)
		hint(label, 4)
	end
end

-- === AUTO-SPAWN ON HEIST START (host-authoritative) ===
-- Picks up to N random cover points across the loaded nav segments. Covers
-- are validated placement targets: cops use them, so they're guaranteed
-- walkable and adjacent to playable space. cover[1] = field_position (floor),
-- cover[2] = forward direction (the open side cops face toward).
-- One cover per nav segment so the N copiers aren't clustered in one room.
-- Per-heist count is rolled in [AUTO_SPAWN_COUNT_MIN, AUTO_SPAWN_COUNT_MAX]
-- inclusive. MIN=1 guarantees at least one copier whenever the party is
-- eligible (someone holds an item to sacrifice); MAX=3 caps clustering.
local AUTO_SPAWN_COUNT_MIN = 1
local AUTO_SPAWN_COUNT_MAX = 3

-- Printers are only useful once the party has begun receiving items, so gate
-- auto-spawn on the host having reached the first-item rank. In U1 every
-- completed heist grants a rank (one item pick), so rank >= 1 means "items are
-- in play". host_rank() is the run's authoritative rank.
local FIRST_ITEM_RANK = 1
local function host_reached_item_threshold()
	local mgr = managers.csr
	local level = (mgr and mgr.host_rank and mgr:host_rank()) or 0
	return level >= FIRST_ITEM_RANK, FIRST_ITEM_RANK, level
end
-- Cops stand close to cover surfaces, so a full-sized prop pivoted at its base
-- center half-clips into the wall if spawned at cover[1] directly. We raycast
-- outward from the cover position to find the actual wall surface, then push
-- the prop away from that surface along the hit normal — avoids the ambiguity
-- of cover[2] direction (which varies per map) and gives us a real wall normal
-- to align rotation against.
local COVER_AWAY_OFFSET = 100 -- cm, push prop away from the hit surface along its normal
local COVER_RAY_REACH = 200 -- cm, how far we look for a wall from cover[1]
-- After we find a candidate hit, probe past the surface to check for a SECOND
-- surface behind it. A second hit within this range means the first was a
-- crate/locker/container sitting against a real wall — placing against the
-- crate would bury the copier in the wall behind it. Rejecting the cover and
-- letting the caller try another is cleaner than eyeballing a bigger offset.
-- 150cm covers props as deep as PD2 ships (cargo containers, big lockers).
-- Going much higher risks false rejects in narrow rooms (probe hits the
-- opposite wall of a tight corridor and treats it as wall-behind-crate).
local COVER_CLEARANCE_BEHIND = 150 -- cm, max gap between "crate face" and "wall behind"
-- Clearance radii for the surrounding-walls check, split by probe geometry.
--
-- LATERAL probes (pure right/left): perpendicular to normal_flat, so they have
-- ZERO component in the wall direction and can never false-positive against
-- our own placement wall. Free to make these long — only constrained by "too
-- far rejects covers in narrow rooms unnecessarily". 200cm catches L-corner
-- placements where the player would otherwise see the prop's wide side
-- clipping into a perpendicular wall.
--
-- BACK-DIAGONAL probes (back-left, back-right at 45°): have SOME component
-- toward the placement wall. Max reach in the wall direction = radius *
-- cos(45°), so the radius MUST stay below COVER_AWAY_OFFSET / cos(45°) ≈
-- 141cm or we'd start rejecting every legitimate against-wall placement (own
-- wall hit).
local COVER_LATERAL_CLEAR = 200
local COVER_DIAG_CLEAR = 120
-- FRONT probe (pure +normal_flat): same "no component toward our own wall"
-- property as the lateral probes — can never false-positive against the
-- placement wall, only bounded by narrow-room rejects. Catches placements
-- facing into a second wall (alcove, narrow corridor) where the prop's
-- operator face would clip.
local COVER_FRONT_CLEAR = 100
-- FRONT-DIAGONAL probes (front-left, front-right at 45°): like LATERAL and
-- FRONT, the wall-direction component is AWAY from the placement wall (the
-- +normal_flat component is positive), so no false-positive risk against the
-- placement wall. Reuses COVER_DIAG_CLEAR (120cm) for symmetry with the back-
-- diagonals — gives consistent diagonal rejection radius in all 4 quadrants
-- minus direct back. Going to the full COVER_LATERAL_CLEAR (200cm) would
-- over-reject in normal 200cm-wide corridors: a front-diagonal at 200cm range
-- hits the opposite wall at t = sqrt(2) * (corridor_width - COVER_AWAY_OFFSET)
-- = ~141cm in a 200cm corridor, and 141cm < 200cm = REJECT. 120cm radius
-- gives ~85cm lateral and ~85cm forward reach, which catches L-shaped corner
-- intrusions (a wall meeting our placement wall at 45° instead of 90°, an
-- adjacent prop sitting at the diagonal) without false-rejecting tight
-- corridors. Closes the front hemisphere of the probe sphere — combined with
-- the existing 5 probes, we now cover 7 of 8 horizontal compass directions
-- (everything except direct -normal_flat, which IS the placement wall).
-- MIN_COPIER_SEPARATION + too_close_to_existing live above spawn_at_closest_cover
-- (see the comment there for why); they'd belong here with the other placement
-- constants if not for Lua's top-down identifier resolution.

-- Given a raw nav cover (cover[1] = position, cover[2] = direction), run the
-- raycast wall-finding + prop placement math and return { pos = ..., rot = ... }
-- or nil if no suitable wall was found. Shared by pick_cover_spawns (auto) and
-- the F6 debug "spawn at closest cover" handler.
-- Assigned (not `local function`) because cover_to_placement is forward-declared
-- earlier in the file so spawn_at_closest_cover can close over it as an upvalue.
cover_to_placement = function(cover)
	if not (cover and cover[1] and cover[2]) then
		return nil
	end
	-- Raycast for the real wall: start slightly above cover[1] so the ray
	-- doesn't hit the floor, shoot in cover[2] direction first, and if nothing
	-- is there try the opposite direction (cover[2] direction is inconsistent
	-- per map). The hit normal is the wall's outward direction, independent of
	-- nav-cover convention.
	local mask = managers.slot:get_mask("world_geometry")
	local ray_origin = cover[1] + Vector3(0, 0, 50)
	local fwd_flat = Vector3(cover[2].x, cover[2].y, 0):normalized()
	local ray = World:raycast("ray", ray_origin, ray_origin + fwd_flat * COVER_RAY_REACH, "slot_mask", mask)
	if not ray then
		ray = World:raycast("ray", ray_origin, ray_origin - fwd_flat * COVER_RAY_REACH, "slot_mask", mask)
	end
	if not ray then
		return nil
	end
	-- Flatten the normal to the horizontal plane; we only care about yaw.
	-- If the ray grazed a non-vertical surface (floor/ceiling) the flat normal
	-- is near-zero — skip this cover.
	local normal_flat = Vector3(ray.normal.x, ray.normal.y, 0)
	if normal_flat:length() <= 0.1 then
		return nil
	end
	normal_flat = normal_flat:normalized()

	-- Clearance probe: step a little INTO the first surface, then cast further
	-- along the same inward direction. If this second ray hits anything within
	-- COVER_CLEARANCE_BEHIND, the first hit was a thin object (crate, pillar,
	-- pallet) with MORE geometry right behind it — i.e., a prop sitting against
	-- a wall. Placing against the prop's face would bury the copier in the wall
	-- behind, so we bail and let the caller try another cover.
	--
	-- Starting 5cm inside the surface avoids the degenerate "ray hits the very
	-- surface we started on" case: Diesel's raycast from inside a body exits
	-- the body (solid→void, no hit) and then hits the next entry (void→solid),
	-- which is exactly what we want for the wall-behind-the-crate check.
	local into_surface = -normal_flat
	local probe_origin = ray.position + into_surface * 5
	local probe_end = probe_origin + into_surface * COVER_CLEARANCE_BEHIND
	local probe = World:raycast("ray", probe_origin, probe_end, "slot_mask", mask)
	if probe then
		-- Filter out Diesel's "started inside a solid body" artifact: when the
		-- probe origin is inside a thick wall, raycast returns an immediate hit
		-- at distance ~0 against the SAME body, not the wall behind. Empirical
		-- evidence (logs from 2026-04-22): ~70% of rejections were at 0.0cm,
		-- corresponding to thick walls being mistaken for crate-against-wall.
		-- A real crate-against-wall produces a probe hit at the gap distance
		-- (typical 7-130cm in observed data), well above the 5cm filter floor.
		-- Cost of the filter: we miss the very rare case of an obstacle thinner
		-- than 5cm with a wall right behind it (would still be a 0.0cm hit if
		-- the probe origin landed inside the wall after exiting the obstacle).
		local probe_dist = (probe.position - probe_origin):length()
		if probe_dist > 5 then
			debug_log(
				string.format(
					"[CSR Copier] probe rejected cover: surface->wall gap %.1fcm at %s",
					probe_dist,
					tostring(ray.position)
				)
			)
			return nil
		end
	end

	-- PD2's raycast returns the surface normal pointing AWAY from the hit
	-- surface (standard convention), so ADD along it to push the prop into the
	-- open room. Use ray.position for X/Y (wall-surface horizontal coords) but
	-- take Z from cover[1] — ray.position.z is cover[1].z + 50 because we cast
	-- the ray from a raised origin to avoid hitting the floor, so anchoring to
	-- ray.position.z directly makes the prop hover. cover[1] is floor-anchored;
	-- the -8 bias nudges into the floor to hide the nav-mesh height gap.
	local pos = Vector3(ray.position.x, ray.position.y, cover[1].z - 8) + normal_flat * COVER_AWAY_OFFSET

	-- Surrounding-walls clearance: cast rays from `pos` in horizontal directions
	-- OTHER than toward the placement wall (-normal_flat). Any hit within the
	-- per-probe distance means the prop would clip into a wall corner, an
	-- L-shaped wall flank, or an adjacent prop. right_dir = perpendicular to
	-- normal_flat in the horizontal plane (sign doesn't matter since we probe
	-- both ±). Distances differ by probe geometry — see the constant block above.
	--
	-- Probe origin is LIFTED 50cm above pos. pos.z = cover[1].z - 8, which puts
	-- pos 8cm INSIDE the floor body — and Diesel's raycast from inside a body
	-- returns an immediate 0.0cm hit artifact (same root cause we filter for in
	-- the behind-probe). Logs from 2026-04-22 showed the right probe firing
	-- 0.0cm rejections for the vast majority of covers because of this.
	-- Lifting to pos.z + 50 puts the origin in clean air; walls extend well
	-- above 50cm so we still detect them, and we no longer false-reject covers
	-- whose only crime was sitting on a floor body extending downward.
	local surround_origin = pos + Vector3(0, 0, 50)
	local right_dir = normal_flat:cross(math.UP):normalized()
	local surround_probes = {
		{ dir = right_dir, label = "right", dist = COVER_LATERAL_CLEAR },
		{ dir = -right_dir, label = "left", dist = COVER_LATERAL_CLEAR },
		{ dir = normal_flat, label = "front", dist = COVER_FRONT_CLEAR },
		{ dir = (normal_flat + right_dir):normalized(), label = "front-right", dist = COVER_DIAG_CLEAR },
		{ dir = (normal_flat - right_dir):normalized(), label = "front-left", dist = COVER_DIAG_CLEAR },
		{ dir = (-normal_flat + right_dir):normalized(), label = "back-right", dist = COVER_DIAG_CLEAR },
		{ dir = (-normal_flat - right_dir):normalized(), label = "back-left", dist = COVER_DIAG_CLEAR },
	}
	for _, p in ipairs(surround_probes) do
		local hit = World:raycast("ray", surround_origin, surround_origin + p.dir * p.dist, "slot_mask", mask)
		if hit then
			local d = (hit.position - surround_origin):length()
			-- Same > 5cm filter as the behind-probe: defends against any
			-- residual same-body artifact (e.g. probe origin happens to land
			-- inside an overhanging shelf or low ceiling). Real walls always
			-- produce non-trivial distances.
			if d > 5 then
				debug_log(
					string.format(
						"[CSR Copier] probe rejected cover: %s clearance %.1fcm at %s",
						p.label,
						d,
						tostring(ray.position)
					)
				)
				return nil
			end
		end
	end

	-- Rotate the prop PARALLEL to the wall (long side flush against it), with
	-- its operator face toward the open room. Aligning forward-Y to the wall
	-- normal puts the short axis perpendicular to the wall (good); sign choice
	-- `-normal_flat` (not `+`) points +Y AWAY from the wall into the open room
	-- so the prop's front faces the player approach rather than the wall.
	local rot = Rotation(-normal_flat, math.UP)
	return { pos = pos, rot = rot }
end

-- Per-cover walkability check that catches the "intra-seg ledge" case the
-- seg-level filter (is_seg_player_reachable) can't see. Panic Room's rooftop
-- is ONE nav seg containing both the walkable deck AND the cop-only AC unit
-- ledges; the seg passes seg-level reachability (because the deck is reachable)
-- and a cover anchored on the ledge slips through.
--
-- Multi-sample: we collect up to 5 walkable anchor points inside the cover's
-- own seg (1 canonical seg center + up to 4 random points), raycast each to
-- placement.pos at chest height under player_ground_check, and reject if 2 or
-- more anchors are blocked. Single-sample (the prior implementation) missed
-- the case where the random sample happened to land on the SAME side of an
-- intra-seg railing as the cover — both points sit in the cop-only sub-zone,
-- LOS is clear, and the unreachable placement passes through. With multiple
-- anchors, as long as a few of them land on the player-walkable side of the
-- barrier, the barrier shows up as repeated blockage.
--
-- "≥2 blocked = reject" threshold over 5 samples: tolerates one false-positive
-- blockage from a stray prop in a long, narrow seg, but rejects on systematic
-- blockage. Player preference is reachable-printer > many-printers, so we err
-- toward rejection.
local PLACEMENT_SAMPLE_REJECT_THRESHOLD = 2
local function is_placement_in_seg_walkable(seg_id, target_pos)
	if not (seg_id and target_pos) then
		return true
	end
	local nav = managers.navigation
	if not (nav and nav.is_data_ready and nav:is_data_ready()) then
		return true
	end
	local mask = get_player_walk_mask()
	if not mask then
		return true
	end

	-- Collect anchors: seg.pos (canonical walkable center used by vanilla
	-- search_coarse itself) plus up to 4 random in-seg points. Both can be nil
	-- for unusual segs, hence the pcall + length check.
	local anchors = {}
	local nav_segs = nav._nav_segments
	local seg = nav_segs and nav_segs[seg_id]
	if seg and seg.pos then
		table.insert(anchors, seg.pos)
	end
	for _ = 1, 4 do
		local ok, p = pcall(function()
			return nav:find_random_position_in_segment(seg_id)
		end)
		if ok and p then
			table.insert(anchors, p)
		end
	end
	if #anchors == 0 then
		return true
	end

	local to = target_pos + Vector3(0, 0, 60)
	local blocked = 0
	for _, anchor in ipairs(anchors) do
		local from = anchor + Vector3(0, 0, 60)
		local hit = World:raycast("ray", from, to, "slot_mask", mask, "ray_type", "walk")
		if hit then
			blocked = blocked + 1
			if blocked >= PLACEMENT_SAMPLE_REJECT_THRESHOLD then
				return false
			end
		end
	end
	return true
end

-- End-to-end LOS sanity check from the host's actual local player position to
-- the placement. Only meaningful when the player is reasonably close — beyond
-- ~25m a straight LOS naturally hits walls/floors/props the player walks
-- around, so a long-distance LOS fail is not informative. Within the range
-- threshold, a blocked LOS commonly indicates the placement is on the far side
-- of a railing/glass/inaccessible alcove from where the host is standing.
--
-- This is a SUPPLEMENTARY filter; the heavy lifting is done by the seg-level
-- reachability search and the multi-sample intra-seg LOS above. Use case:
-- placements in the same room or adjacent room as the spawn lobby that the
-- in-seg multi-sample misses (e.g. a tiny cop-only alcove the random samples
-- all happened to land inside).
local PLAYER_LOS_RANGE_SQ = 2500 * 2500
local function is_placement_los_from_player(target_pos)
	if not target_pos then
		return true
	end
	local player = managers.player and managers.player:local_player()
	if not alive(player) then
		return true
	end
	local mask = get_player_walk_mask()
	if not mask then
		return true
	end
	local p_pos = player:position()
	if mvector3.distance_sq(p_pos, target_pos) > PLAYER_LOS_RANGE_SQ then
		return true
	end
	local from = p_pos + Vector3(0, 0, 60)
	local to = target_pos + Vector3(0, 0, 60)
	local hit = World:raycast("ray", from, to, "slot_mask", mask, "ray_type", "walk")
	return not hit
end

local function pick_cover_spawns(n)
	if not managers.navigation or not managers.navigation:is_data_ready() then
		return {}
	end
	local nav_segs = managers.navigation._nav_segments
	if not nav_segs or not next(nav_segs) then
		return {}
	end

	local seg_ids = {}
	for id, seg in pairs(nav_segs) do
		if not seg.disabled then
			table.insert(seg_ids, id)
		end
	end
	if #seg_ids == 0 then
		return {}
	end

	-- Fisher-Yates shuffle so the picks are from random segments, not the
	-- first N in pairs() order (which tends to cluster near the heist entry).
	for i = #seg_ids, 2, -1 do
		local j = math.random(i)
		seg_ids[i], seg_ids[j] = seg_ids[j], seg_ids[i]
	end

	-- Player reachability prefilter (see helper docs). Built once per batch.
	-- player_seg may be nil if the host player isn't spawned yet; in that case
	-- is_seg_player_reachable returns true for everything (legacy behavior).
	local player_seg = get_player_nav_seg()
	local reach_cache = {}
	local skipped_unreachable = 0
	-- Per-placement intra-seg rejections (the "Panic Room rooftop ledge"
	-- pattern: seg passes seg-level reachability but the cover itself sits
	-- behind a railing inside that same seg). Tracked separately from the
	-- seg-level skip count so a future spike here flags an intra-seg filter
	-- regression specifically.
	local skipped_blocked_placement = 0
	-- Player-LOS rejections (placement near host but no straight LOS — typical
	-- "behind glass / railing in same starting room" pattern). Tracked
	-- separately so a future spike here flags player-LOS regressions vs the
	-- intra-seg multi-sample.
	local skipped_blocked_player_los = 0

	local results = {}
	-- Parallel list of just the pos vectors, passed to too_close_to_existing so
	-- placements picked earlier in THIS batch block placements picked later.
	-- Without this, two adjacent nav segments can raycast to the same wall and
	-- produce two near-identical placements (same bug as F6-at-same-spot, just
	-- across segs instead of across keypresses).
	local accepted_positions = {}
	for _, seg_id in ipairs(seg_ids) do
		if #results >= n then
			break
		end
		if player_seg and not is_seg_player_reachable(player_seg, seg_id, reach_cache) then
			skipped_unreachable = skipped_unreachable + 1
		else
			local cover = managers.navigation:find_cover_in_nav_seg_1(seg_id)
			local placement = cover_to_placement(cover)
			if placement and not is_placement_in_seg_walkable(seg_id, placement.pos) then
				skipped_blocked_placement = skipped_blocked_placement + 1
				placement = nil
			end
			if placement and not is_placement_los_from_player(placement.pos) then
				skipped_blocked_player_los = skipped_blocked_player_los + 1
				placement = nil
			end
			if placement and not too_close_to_existing(placement.pos, accepted_positions) then
				table.insert(results, placement)
				table.insert(accepted_positions, placement.pos)
			end
		end
	end

	if skipped_unreachable > 0 then
		csr_log(string.format("[CSR Copier] auto-spawn: skipped %d player-unreachable segments", skipped_unreachable))
	end
	if skipped_blocked_placement > 0 then
		csr_log(
			string.format(
				"[CSR Copier] auto-spawn: skipped %d cover placement(s) blocked from intra-seg walkable area (rooftop ledge / railing)",
				skipped_blocked_placement
			)
		)
	end
	if skipped_blocked_player_los > 0 then
		csr_log(
			string.format(
				"[CSR Copier] auto-spawn: skipped %d nearby placement(s) blocked from host player straight LOS",
				skipped_blocked_player_los
			)
		)
	end

	-- Cover-less fallback: if we WANTED copiers but found NOTHING via covers,
	-- at least spawn one at a known walkable point. Zero-cover maps are rare
	-- (some community heists), and we'd rather have one awkward spawn than
	-- none. Gated on n > 0 so a rolled-zero-this-heist still means zero.
	-- The fallback walks the shuffled seg_ids honoring the same reachability
	-- filter — picking seg_ids[1] blindly could land us in the exact AI-only
	-- zone we just filtered out of the main loop. We prefer seg.pos (the
	-- canonical walkable center vanilla search_coarse uses) over a random
	-- in-seg point, because random points can land in cop-only sub-areas of
	-- multi-zone segs that the seg-level reachability filter can't see.
	if n > 0 and #results == 0 then
		local nav_segs = managers.navigation._nav_segments
		for _, seg_id in ipairs(seg_ids) do
			if not player_seg or is_seg_player_reachable(player_seg, seg_id, reach_cache) then
				local seg = nav_segs and nav_segs[seg_id]
				local pos = (seg and seg.pos) or managers.navigation:find_random_position_in_segment(seg_id)
				if pos then
					table.insert(results, {
						pos = pos - Vector3(0, 0, 8),
						rot = Rotation(math.random(0, 359), 0, 0),
					})
					break
				end
			end
		end
	end

	return results
end

local do_auto_spawn_host -- forward decl for self-retry after DB load
do_auto_spawn_host = function()
	if not (DB and DB.has and DB:has(UNIT_EXT, UNIT_NAME)) then
		log("[CSR Copier] auto-spawn: unit not in DB, aborting")
		return
	end
	if not is_ready() then
		managers.dyn_resource:load(UNIT_EXT, UNIT_NAME, PKG_NAME, function(status)
			if status then
				do_auto_spawn_host()
			end
		end)
		return
	end

	local reached, threshold, level = host_reached_item_threshold()
	if not reached then
		csr_log(
			string.format("[CSR Copier] auto-spawn: host rank %d below first-item rank %d, skipping", level, threshold)
		)
		return
	end

	-- Roll this heist's count in [MIN, MAX] inclusive.
	local desired = math.random(AUTO_SPAWN_COUNT_MIN, AUTO_SPAWN_COUNT_MAX)

	local spawns = pick_cover_spawns(desired)
	if #spawns == 0 then
		log("[CSR Copier] auto-spawn: no cover point available, skipping")
		return
	end

	for i, s in ipairs(spawns) do
		local offer_def = roll_offer()
		if offer_def then
			local entry = _spawn_copier(s.pos, s.rot, offer_def)
			if entry then
				csr_log(
					string.format(
						"[CSR Copier] auto-spawn %d/%d: %s (%s) at %s",
						i,
						#spawns,
						tostring(entry.offer_name),
						tostring(entry.tier),
						tostring(s.pos)
					)
				)
			end
		end
	end
end

_G.CSR_AutoCopierSpawned = _G.CSR_AutoCopierSpawned or false

-- One-shot host-authoritative auto-spawn per CS heist. Nav data isn't ready the
-- frame GameSetupUpdate starts firing, so re-check every frame and spawn as soon
-- as the gate opens. Network:is_server() is true in SP too. csr_heist_active()
-- is the no-leak CSR-heist signal (job == crime_spree, vanilla CS not active).
Hooks:Add("GameSetupUpdate", "CSR_CopierSpawner_Input", function(_t, _dt)
	if _G.CSR_AutoCopierSpawned then
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
	_G.CSR_AutoCopierSpawned = true -- latch BEFORE async load to prevent re-entry
	do_auto_spawn_host()
end)

-- Debug spawn entry points exposed for SuperBLT keybinds. They handle the
-- DB-presence check and lazy package load, then route to the existing host
-- spawn helpers. Kept as globals so the lua/debug/keybind_*.lua files (which
-- run in a sandboxed scope per keypress) can reach them.
local function _ensure_loaded_then(callback, key_label)
	local db_has = DB and DB.has and DB:has(UNIT_EXT, UNIT_NAME)
	if not db_has then
		hint("Copier asset not registered — supermod.xml load failed", 6)
		return
	end
	if not is_ready() then
		managers.dyn_resource:load(UNIT_EXT, UNIT_NAME, PKG_NAME, function(status)
			if status then
				hint("Copier loaded — press " .. tostring(key_label) .. " again to spawn", 3)
			end
		end)
		hint("Loading copier… press " .. tostring(key_label) .. " again shortly", 3)
		return
	end
	callback()
end

_G.CSR_SpawnPrinterAtClosestCover = function()
	_ensure_loaded_then(spawn_at_closest_cover, "the printer-cover key")
end

_G.CSR_SpawnPrinterAtCrosshair = function()
	_ensure_loaded_then(spawn_at_crosshair, "the printer-crosshair key")
end

-- Purge copier list across heists -- the units die with the world. Destroy
-- billboard workspaces so they don't leak, and re-arm the auto-spawner. (CSR
-- sound sources are single-sound and auto-close, so no manual cleanup here.)
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_CopierSpawner_SessionReset", function()
	for _, c in ipairs(_G.CSR_Copiers or {}) do
		destroy_billboard(c.billboard_ws)
	end
	_G.CSR_Copiers = {}
	-- Drop the client-side spawn dedup set so next heist's mirrored copiers spawn.
	_G.CSR_SeenCopierSpawns = {}
	-- Re-arm the auto-spawner; GameSetupUpdate re-latches once nav data is ready
	-- and the CSR-heist gate opens.
	_G.CSR_AutoCopierSpawned = false
end)

-- Globals exposed for CrimeSpreeCopierInteractionExt (lua/core/copier_interaction_ext.lua).
-- The subclass runs inside the Diesel engine's extension dispatch and has no
-- access to this file's locals; the globals are the bridge. Same pattern as
-- _G.CSR_Copiers / _G.CSR_CopierProxState above.
_G.CSR_UseCopier = use_copier

_G.CSR_FindCopierByUnit = function(unit)
	if not alive(unit) then
		return nil
	end
	for _, c in ipairs(_G.CSR_Copiers or {}) do
		if c.unit == unit then
			return c
		end
	end
	return nil
end

-- True if the local player owns any item of `tier` (the offer's rarity) to
-- sacrifice. Read by CrimeSpreeCopierInteractionExt:_interact_blocked.
_G.CSR_CopierHasSacrifice = function(tier)
	return #owned_defs_of_tier(tier) > 0
end

-- Proximity-gated yellow contour. Same pattern as scrapper_spawner.lua —
-- the csr_yellow_interactable palette is registered in
-- lua/tweakdata/copier_interaction.lua; this hook toggles its opacity per
-- frame based on player distance.
-- Hand-tuned by feel because vanilla's "can-press-F" gate uses a raycast from
-- the player camera (~165 cm above the feet) against the prop body, while
-- this hook measures feet-to-pivot distance. Auto-deriving from
-- csr_copier.interact_distance (250) was tried and didn't visually align —
-- the camera-height offset plus the prop body extent shift the practical
-- threshold below 250 in feet-distance terms. Bump this number until the
-- contour pops on at the same moment the "Hold F" prompt becomes pressable.
local CSR_PROX_RANGE = 240 -- centimeters; manual. Slightly over the practical interact threshold so the contour acts as a "you're getting close" cue before F becomes pressable — intentional.
local CSR_PROX_RANGE_SQ = CSR_PROX_RANGE * CSR_PROX_RANGE
-- Exposed globally so CrimeSpreeCopierInteractionExt:set_contour (in
-- copier_interaction_ext.lua) can read the per-unit range state and force
-- opacity=0 when out-of-range, regardless of which code path calls set_contour
-- (our prox hook, vanilla's selected/unselect, Clientsided Uppers wrappers,
-- etc.). Weak-keyed so dead units fall out automatically.
_G.CSR_CopierProxState = _G.CSR_CopierProxState or setmetatable({}, { __mode = "k" })

Hooks:Add("GameSetupUpdate", "CSR_CopierProximityContour", function(t, dt)
	local list = _G.CSR_Copiers
	if not list or #list == 0 then
		return
	end
	local pu = managers and managers.player and managers.player:player_unit()
	if not (pu and alive(pu)) then
		return
	end
	local ppos = pu:position()
	for _, c in ipairs(list) do
		local u = c and c.unit
		if u and alive(u) then
			local dist_sq = mvector3.distance_sq(ppos, u:position())
			local in_range = dist_sq <= CSR_PROX_RANGE_SQ
			if _G.CSR_CopierProxState[u] ~= in_range then
				_G.CSR_CopierProxState[u] = in_range
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

-- Expose for scrapper_spawner.lua's auto-spawn flow. Reusing this function
-- (instead of duplicating the cover-find/separation/reachability logic) means
-- any future tweak to placement rules (rejection radii, fallback behavior,
-- player-reachability gating) is applied uniformly to printers AND scrappers.
_G.CSR_PickCoverSpawns = pick_cover_spawns

-- === M3: client-side mirror of host-spawned copiers ===
-- The host broadcasts each spawn (broadcast_copier_spawn); a client spawns its
-- own local copy from the synced pos/rot/offer and registers it in CSR_Copiers,
-- so the existing interaction (_is_csr_owned -> CSR_FindCopierByUnit) lights up
-- and the exchange runs against this peer's own (guest-session) inventory.

-- Resolve a registry def by its item type (for the synced offer). Cheap: one
-- scan per mirrored spawn (a handful per heist), not a hot path.
local function find_def_by_type(item_type)
	local mgr = managers.csr
	if not (item_type and item_type ~= "" and mgr and mgr.registered_items) then
		return nil
	end
	for _, def in ipairs(mgr:registered_items()) do
		if def.type == item_type then
			return def
		end
	end
	return nil
end

-- Client dedup: the real-time broadcast and the late-join replay can both carry
-- the same spawn; key on the host unit key so each copier spawns exactly once.
_G.CSR_SeenCopierSpawns = _G.CSR_SeenCopierSpawns or {}

local function on_copier_spawn(payload)
	-- Mirror only on a real client; SP/host spawn natively and never receive this.
	if not (_G.CSR_MP and _G.CSR_MP.is_client and _G.CSR_MP.is_client()) then
		return
	end
	local key, x, y, z, yaw, pitch, roll, offer_type =
		string.match(tostring(payload), "^([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]+)~([^~]*)$")
	if not key then
		log("[CSR Copier] on_copier_spawn: parse fail '" .. tostring(payload) .. "'")
		return
	end
	if _G.CSR_SeenCopierSpawns[key] then
		return
	end
	-- Asset must be registered (a mismatched client install can lack it).
	if not (DB and DB.has and DB:has(UNIT_EXT, UNIT_NAME)) then
		log("[CSR Copier] on_copier_spawn: copier unit not in DB, skipping")
		return
	end

	_G.CSR_SeenCopierSpawns[key] = true
	local pos = Vector3(tonumber(x), tonumber(y), tonumber(z))
	local rot = Rotation(tonumber(yaw), tonumber(pitch), tonumber(roll))
	local offer_def = find_def_by_type(offer_type)

	local function do_spawn()
		-- Native-AV guard: spawning a unit whose package isn't mounted AVs in C++
		-- (pcall can't catch it). supermod.xml mounts ours on every client, but a
		-- partial/mismatched install might not -- PackageManager:has + skip is the
		-- only safe net. Client-path only; the host keeps its proven is_ready gate.
		if PackageManager and PackageManager.has and not PackageManager:has(UNIT_EXT, UNIT_NAME) then
			log("[CSR Copier] on_copier_spawn: package not mounted, skipping (native-AV guard)")
			return
		end
		_spawn_copier(pos, rot, offer_def)
	end

	-- Same load gate the host's auto-spawn uses: spawn now if the dyn resource is
	-- ready, else lazy-load then spawn in the callback.
	if is_ready() then
		do_spawn()
	elseif managers.dyn_resource then
		managers.dyn_resource:load(UNIT_EXT, UNIT_NAME, PKG_NAME, function(status)
			if status then
				do_spawn()
			end
		end)
	end
end

if _G.CSR_MP and _G.CSR_MP.register_handler and _G.CSR_MP.MSG then
	_G.CSR_MP.register_handler(_G.CSR_MP.MSG.COPIER_SPAWN, function(sender, data)
		on_copier_spawn(data)
	end)
end

csr_log("[CSR Copier] copier_spawner.lua loaded — F7 spawn, interact key to use")
