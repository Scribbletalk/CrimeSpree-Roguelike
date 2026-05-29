-- In-world copy-machine ("printer") spawner + exchange flow.
-- Architecture detail: csr_in_world_props_architecture.md.

if not RequiredScript then
	return
end

local COPIER_DBPATH = "units/payday2/props/off_prop_copy_machine_smuggle/off_prop_copy_machine_smuggle"
local UNIT_EXT = Idstring("unit")
local UNIT_NAME = Idstring(COPIER_DBPATH)
local PKG_NAME = (DynamicResourceManager and DynamicResourceManager.DYN_RESOURCES_PACKAGE) or "packages/dyn_resources"

-- Billboard icon constants.
local BILLBOARD_WORLD_SIZE = 64
local BILLBOARD_PANEL_PX = 128
-- Matches Items-tab frame:icon ratio so in-world icon looks like the menu.
local ITEMS_TAB_FRAME_PX = 74
local ITEMS_TAB_ICON_PX = 38
local BILLBOARD_ICON_PX = math.floor(BILLBOARD_PANEL_PX * ITEMS_TAB_ICON_PX / ITEMS_TAB_FRAME_PX)
local BILLBOARD_Z_ABOVE_CENTER = 100
local BILLBOARD_SIDE_OFFSET = 50 -- cm along copier's local -X (player's left)
local BILLBOARD_SPAWN_DELAY = 2.0 -- defer past lid-open animation

-- Single csr_frame texture tinted per rarity.
local RARITY_FRAMES = {
	common = { frame = "csr_frame", color = Color.white },
	uncommon = { frame = "csr_frame", color = Color(1, 0, 0.95, 0) },
	rare = { frame = "csr_frame", color = Color(1, 0.3, 0.7, 1) },
	contraband = { frame = "csr_frame", color = Color(1, 1, 0.4, 0) },
	wildcard = { frame = "csr_frame", color = Color(1, 1, 0.3, 0.8) },
}

local BASE_OBJ_NAME = Idstring("g_printer_base")
local LID_ANIM = Idstring("open_lid")

_G.CSR_Copiers = _G.CSR_Copiers or {}

-- CSR-heist gate; shared with scrapper_spawner / combat_modifiers.
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

local function debug_log(msg)
	local mgr = managers and managers.csr
	if mgr and mgr.debug_enabled and mgr:debug_enabled() then
		log(msg)
	end
end

-- No wildcard / scrap / contraband — contraband is BM-shop-only.
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
	local buckets = {}
	for _, def in ipairs(mgr:registered_items()) do
		local r = def.rarity
		if r and not def.is_scrap and PRINTER_RARITY_WEIGHTS[r] then
			buckets[r] = buckets[r] or {}
			table.insert(buckets[r], def)
		end
	end
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
		chosen = next(weights)
	end
	local bucket = buckets[chosen]
	return bucket[math.random(#bucket)]
end

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

local function owned_defs_of_tier(tier)
	local mgr = managers.csr
	if not (mgr and mgr.registered_items) then
		return {}
	end
	local owned = mgr:player_items(mgr:local_peer_id())
	local list = {}
	for _, def in ipairs(mgr:registered_items()) do
		if def.rarity == tier and (owned[def.type] or 0) > 0 then
			list[#list + 1] = def
		end
	end
	return list
end

-- Sacrifice priority: scrap → different type → same type (last resort).
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

-- Signed speed: positive = forward, negative = reverse (anim_play_to convention).
local OPEN_SPEED = 5
local CLOSE_SPEED = -5
local WORKING_SOUND_DELAY = 0.5 -- tuned by ear; ogg has trailing silence
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

	-- Anchor above+beside the base mesh; subtract half-basis so desired_center is the quad center.
	local base_center = base:oobb():center()
	local local_up = orient:rotation():z()
	local local_right = orient:rotation():x()
	local desired_center = base_center + local_up * BILLBOARD_Z_ABOVE_CENTER - local_right * BILLBOARD_SIDE_OFFSET

	local x_basis = Vector3(BILLBOARD_WORLD_SIZE, 0, 0)
	local y_basis = Vector3(0, 0, -BILLBOARD_WORLD_SIZE)
	local pos = desired_center - x_basis * 0.5 - y_basis * 0.5

	local gui = World:newgui()
	local ws
	local ok, err = pcall(function()
		ws = gui:create_linked_workspace(BILLBOARD_PANEL_PX, BILLBOARD_PANEL_PX, base, pos, x_basis, y_basis)
		ws:set_billboard(Workspace.BILLBOARD_BOTH)
		-- Transparent anchor — bitmaps need a panel parent.
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

-- Exchange: sacrifice removed immediately, lid reopens + offer awarded after REOPEN_DELAY.
local function use_copier(c)
	if not c.offer_type or not c.tier then
		hint("Copier has no offer", 2)
		return
	end
	if c.cycling then
		return
	end

	local mgr = managers.csr
	if not (mgr and mgr.add_item and mgr.remove_item) then
		hint("Item store unavailable", 5)
		return
	end

	local sacrifice = pick_sacrifice(c.tier, c.offer_type)
	if not sacrifice then
		hint("No " .. tostring(c.tier) .. " items in your inventory to sacrifice", 4)
		return
	end

	c.cycling = true
	play_close(c.unit)
	play_printer_starting(c.unit)
	local unit_ref = c.unit
	local color = RARITY_COLORS[c.tier] or Color.white
	local pid = mgr:local_peer_id()
	local sacrifice_name = offer_display_name(sacrifice)

	DelayedCalls:Add("CSR_CopierMainSound_" .. tostring(unit_ref:key()), WORKING_SOUND_DELAY, function()
		if alive(unit_ref) then
			play_printer_sound(unit_ref)
		end
	end)

	-- Remove sacrifice immediately on interact.
	local removed = mgr:remove_item(pid, sacrifice.type)
	if not removed then
		hint("Failed to remove sacrifice item " .. tostring(sacrifice.type), 5)
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

	-- Award offer when lid finishes reopening.
	DelayedCalls:Add("CSR_CopierReopen_" .. tostring(unit_ref:key()), REOPEN_DELAY, function()
		c.cycling = false
		if alive(unit_ref) then
			play_open(unit_ref)
			-- Force prompt refresh; text_dirty alone is unreliable across frames.
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

		if _G.CSR_MP and _G.CSR_MP.broadcast_own_items then
			_G.CSR_MP.broadcast_own_items()
		end

		if managers.chat then
			managers.chat:_receive_message(1, tostring(c.offer_name or c.offer_type), "printed!", color)
		end
	end)
end

-- Broadcast a just-spawned copier to all clients.
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

-- Shared spawn core; triple-disables collision so it doesn't push players.
local function _spawn_copier(pos, rot, offer_def)
	local ok, unit = pcall(World.spawn_unit, World, UNIT_NAME, pos, rot)
	if not ok or not alive(unit) then
		log("[CSR Copier] Spawn failed: " .. tostring(unit))
		return nil
	end

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

	DelayedCalls:Add("CSR_CopierSpawnOpen_" .. tostring(unit:key()), 0.05, function()
		if alive(unit) then
			play_open(unit)
		end
	end)

	local offer_icon = offer_def and offer_def.icon
	DelayedCalls:Add("CSR_CopierBillboard_" .. tostring(unit:key()), BILLBOARD_SPAWN_DELAY, function()
		if not alive(unit) then
			return
		end
		copier_entry.billboard_ws = create_billboard(unit, offer_icon, tier)
	end)

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

-- Forward decl; assigned further down (used by spawn_at_closest_cover closure).
local cover_to_placement

local MIN_COPIER_SEPARATION = 250

-- Must live above spawn_at_closest_cover (Lua compile-time identifier resolution).
local function too_close_to_existing(pos, extra_positions)
	local min_sq = MIN_COPIER_SEPARATION * MIN_COPIER_SEPARATION
	for _, c in ipairs(_G.CSR_Copiers or {}) do
		if c.unit and alive(c.unit) then
			if mvector3.distance_sq(c.unit:position(), pos) < min_sq then
				return true
			end
		end
	end
	-- Also separate from scrappers.
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

-- teamAI4 = player + bot navmesh access family; search_coarse is synchronous.
local PLAYER_NAV_ACCESS = "teamAI4"

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

-- player_ground_check includes slot 15 (mission blockers) + slot 39 (vehicles) that navmesh misses.
local _slotmask_player_walk_cache = nil
local function get_player_walk_mask()
	if not _slotmask_player_walk_cache then
		_slotmask_player_walk_cache = managers.slot:get_mask("player_ground_check")
	end
	return _slotmask_player_walk_cache
end

-- Raycast each coarse-path hop at chest height; catches blockers navmesh adjacency misses.
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
		local pos = node[2] -- post-start entries carry an explicit pos
		if not pos then
			local seg = nav_segs and nav_segs[seg_id]
			pos = seg and seg.pos
		end
		if not pos then
			return true -- fail open if pos unknown
		end
		if prev_pos then
			local from = prev_pos + Vector3(0, 0, 60)
			local to = pos + Vector3(0, 0, 60)
			local ok, hit = pcall(function()
				return World:raycast("ray", from, to, "slot_mask", mask, "ray_type", "walk")
			end)
			if ok and hit then
				-- Body objects have no :slot(); go through the unit.
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
		return true
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

-- F6 debug: walk covers outward from the player, pick first valid un-occupied placement.
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
		-- cover[3] is a nav_tracker; call :nav_segment() to get the int id.
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

-- Per-heist printer count; MIN=1 guarantees at least one when eligible.
local AUTO_SPAWN_COUNT_MIN = 1
local AUTO_SPAWN_COUNT_MAX = 3

-- Don't spawn until the host has earned at least one item pick.
local FIRST_ITEM_RANK = 1
local function host_reached_item_threshold()
	local mgr = managers.csr
	local level = (mgr and mgr.host_rank and mgr:host_rank()) or 0
	return level >= FIRST_ITEM_RANK, FIRST_ITEM_RANK, level
end

-- Placement probe constants (derivation in csr_in_world_props_architecture.md).
local COVER_AWAY_OFFSET = 100
local COVER_RAY_REACH = 200
local COVER_CLEARANCE_BEHIND = 150
local COVER_LATERAL_CLEAR = 200
local COVER_FRONT_CLEAR = 100
-- Diagonal MUST be < COVER_AWAY_OFFSET/cos(45°) ≈ 141cm or wall placements false-reject.
local COVER_DIAG_CLEAR = 120

cover_to_placement = function(cover)
	if not (cover and cover[1] and cover[2]) then
		return nil
	end
	-- cover[2] direction is per-map inconsistent; try the opposite direction if the first ray misses.
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
	-- Flatten the normal; near-zero means we grazed a non-vertical surface.
	local normal_flat = Vector3(ray.normal.x, ray.normal.y, 0)
	if normal_flat:length() <= 0.1 then
		return nil
	end
	normal_flat = normal_flat:normalized()

	-- Clearance-behind probe: reject wall-buried placement (e.g. crate flush against wall).
	-- 5cm-into-surface origin avoids the "started inside solid" 0.0cm raycast artifact.
	local into_surface = -normal_flat
	local probe_origin = ray.position + into_surface * 5
	local probe_end = probe_origin + into_surface * COVER_CLEARANCE_BEHIND
	local probe = World:raycast("ray", probe_origin, probe_end, "slot_mask", mask)
	if probe then
		-- >5cm filters the 0.0cm same-body artifact; real obstructions are 7-130cm.
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

	-- Z from cover[1] (floor), not ray.position.z; -8 hides the navmesh gap.
	local pos = Vector3(ray.position.x, ray.position.y, cover[1].z - 8) + normal_flat * COVER_AWAY_OFFSET

	-- Surrounding probes from +50cm to avoid the 0.0cm floor-body artifact.
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

	-- +Y points away from wall so the long side sits flush against it.
	local rot = Rotation(-normal_flat, math.UP)
	return { pos = pos, rot = rot }
end

-- Multi-sample LOS check within a seg; catches segs that span both walkable + cop-only areas.
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

-- Player LOS check; skipped beyond 25m (too far to matter).
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

	-- Fisher-Yates shuffle to avoid clustering near heist entry (pairs() order bias).
	for i = #seg_ids, 2, -1 do
		local j = math.random(i)
		seg_ids[i], seg_ids[j] = seg_ids[j], seg_ids[i]
	end

	local player_seg = get_player_nav_seg()
	local reach_cache = {}
	local skipped_unreachable = 0
	local skipped_blocked_placement = 0
	local skipped_blocked_player_los = 0

	local results = {}
	-- Track accepted positions so earlier picks in this batch block later duplicates.
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
		csr_log(string.format("[CSR Copier] auto-spawn: skipped %d intra-seg blocked", skipped_blocked_placement))
	end
	if skipped_blocked_player_los > 0 then
		csr_log(string.format("[CSR Copier] auto-spawn: skipped %d player-LOS blocked", skipped_blocked_player_los))
	end

	-- Fallback: place on any reachable walkable seg center if no cover was found.
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

local do_auto_spawn_host
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

-- Nav data isn't ready on the first GameSetupUpdate frame; re-check each frame.
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
	_G.CSR_AutoCopierSpawned = true -- latch before async load to prevent re-entry
	do_auto_spawn_host()
end)

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

Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_CopierSpawner_SessionReset", function()
	for _, c in ipairs(_G.CSR_Copiers or {}) do
		destroy_billboard(c.billboard_ws)
	end
	_G.CSR_Copiers = {}
	_G.CSR_SeenCopierSpawns = {}
	_G.CSR_AutoCopierSpawned = false
end)

-- Expose to interaction subclass (CrimeSpreeCopierInteractionExt can't see our locals).
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

_G.CSR_CopierHasSacrifice = function(tier)
	return #owned_defs_of_tier(tier) > 0
end

-- Proximity range tuned so the contour pops exactly when "Hold F" becomes pressable.
local CSR_PROX_RANGE = 240
local CSR_PROX_RANGE_SQ = CSR_PROX_RANGE * CSR_PROX_RANGE
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

-- Shared with scrapper_spawner for its auto-spawn.
_G.CSR_PickCoverSpawns = pick_cover_spawns

-- Client mirror of host-broadcast copier spawns.
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

_G.CSR_SeenCopierSpawns = _G.CSR_SeenCopierSpawns or {}

local function on_copier_spawn(payload)
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
	if not (DB and DB.has and DB:has(UNIT_EXT, UNIT_NAME)) then
		log("[CSR Copier] on_copier_spawn: copier unit not in DB, skipping")
		return
	end

	_G.CSR_SeenCopierSpawns[key] = true
	local pos = Vector3(tonumber(x), tonumber(y), tonumber(z))
	local rot = Rotation(tonumber(yaw), tonumber(pitch), tonumber(roll))
	local offer_def = find_def_by_type(offer_type)

	local function do_spawn()
		-- pcall can't catch native AVs; must check package before spawn.
		if PackageManager and PackageManager.has and not PackageManager:has(UNIT_EXT, UNIT_NAME) then
			log("[CSR Copier] on_copier_spawn: package not mounted, skipping (native-AV guard)")
			return
		end
		_spawn_copier(pos, rot, offer_def)
	end

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

csr_log("[CSR Copier] copier_spawner.lua loaded")
