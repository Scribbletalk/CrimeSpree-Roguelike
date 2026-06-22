-- CSRGameManager mission set & selection (Tier 1 split from game_manager.lua).
if not CSRGameManager then
	return
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

-- Per-heist rank override by mission id (overrides the length-tier default in rank_for_mission).
local RANK_OVERRIDE = {
	vit = 4, -- White House (added via extra_heists, id = stage_id "vit")
	cook_off = 1, -- Cook Off
	cane = 1, -- Santa's Workshop
	peta_1 = 4, -- This Was Not The Deal (Goat Sim day 1; added via extra_heists, id = stage_id "peta_1"; add=14 would be +3)
	peta_2 = 4, -- Dirty Work (Goat Sim day 2; added via extra_heists, id = stage_id "peta_2")
	crojob2_d = 2, -- Bomb: Forest (added via extra_heists, id = stage_id "crojob2_d"; level_id crojob3; add=14 would be +3)
	watchdogs_2_d = 1, -- Watchdogs day 2 "Boat load" (added via extra_heists, id = stage_id "watchdogs_2_d"; level_id watchdogs_2_day; add=6 would be +2)
	brb = 2, -- Brooklyn Bank (base CS mission, id "brb"; add=8 would be +3)
	pines = 1, -- White Xmas (base CS mission, id "pines"; add=7 would be +2)
}

-- 3-tier mission list from tweak_data with DLC filter. Cached because the reroll animation queries it per-frame.
function CSRGameManager:_mission_lists()
	if self._mission_lists_cache then
		return self._mission_lists_cache
	end
	local lists = {}
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return lists -- tweak_data not ready yet; do not poison the cache
	end
	for index, mission_list in ipairs(cs_missions) do
		lists[index] = {}
		for _, mission in ipairs(mission_list) do
			local lvl = mission.level
			local dlc = lvl and lvl.dlc
			local dlc_unlocked = not dlc or (managers.dlc and managers.dlc:is_dlc_unlocked(dlc))
			local should_hide = dlc and managers.dlc and managers.dlc:should_hide_unavailable(dlc) or false
			if dlc_unlocked or not should_hide then
				table.insert(lists[index], mission)
			end
		end
	end
	self._mission_lists_cache = lists
	return lists
end

function CSRGameManager:get_mission(mission_id)
	mission_id = mission_id or self:current_mission()
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return nil
	end
	for _, tbl in pairs(cs_missions) do
		for _, data in pairs(tbl) do
			if data.id == mission_id then
				return data
			end
		end
	end
	return nil
end

-- Rank for completing a mission: short(add≤5)=1, medium(≤7)=2, long=3.
-- Uses the same thresholds as CrimeSpreeMissionButton so rank matches the clock icon.
function CSRGameManager:rank_for_mission(mission_id)
	if mission_id and RANK_OVERRIDE[mission_id] then
		return RANK_OVERRIDE[mission_id]
	end
	local m = self:get_mission(mission_id)
	local add = m and m.add
	if type(add) ~= "number" then
		return self:constant("rank_per_heist") or 1
	end
	if add <= 5 then
		return 1
	elseif add <= 7 then
		return 2
	end
	return 3
end

-- Rank for the just-played heist. Resolves from Global.game_settings.level_id because
-- current_mission() is already cleared by the time the end screen builds.
function CSRGameManager:rank_for_current_level()
	local gs = Global and Global.game_settings
	local level_id = gs and gs.level_id
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if not level_id or type(cs_missions) ~= "table" then
		return self:constant("rank_per_heist") or 1
	end
	local want_mission = gs.mission or "none"
	local fallback_id = nil
	for _, tier in ipairs(cs_missions) do
		for _, m in ipairs(tier) do
			if m.level and m.level.level_id == level_id then
				if (m.mission or "none") == want_mission then
					return self:rank_for_mission(m.id)
				end
				fallback_id = fallback_id or m.id
			end
		end
	end
	if fallback_id then
		return self:rank_for_mission(fallback_id)
	end
	return self:constant("rank_per_heist") or 1
end

-- Pick one random mission from `list` whose id is not in `used`. nil if all are taken.
local function pick_unused(list, used)
	local candidates = {}
	for _, m in ipairs(list) do
		if m.id and not used[m.id] then
			candidates[#candidates + 1] = m
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[math.random(1, #candidates)]
end

-- One mission per bucket (1=stealth, 2=short loud, 3=long loud), all 3 guaranteed
-- distinct. A heist can live in several buckets at once (loud+stealth, or add 9-10
-- spans short+long), so a naive per-bucket roll could repeat an id across slots.
-- exclude_id (optional): seed it as "used" so the just-completed heist is kept out of
-- the auto-rolled set. Reroll passes nothing, so the mission can return on a reroll.
function CSRGameManager:get_random_missions(exclude_id)
	local lists = self:_mission_lists()
	local set = {}
	local used = {}
	if exclude_id then
		used[exclude_id] = true
	end
	for i = 1, 3 do
		local list = lists[i]
		if list and #list > 0 then
			-- Bucket exhausted of unique ids: fall back to any unused mission across all
			-- buckets so the slot still fills (degenerate tiny-pool case only).
			local pick = pick_unused(list, used)
			if not pick then
				for j = 1, 3 do
					pick = pick_unused(lists[j] or {}, used)
					if pick then
						break
					end
				end
			end
			if pick then
				set[i] = pick
				used[pick.id] = true
			end
		end
	end
	return set
end

-- Single random mission for the card spin animation flavor text.
function CSRGameManager:get_random_mission()
	local set = self:get_random_missions()
	local pool = {}
	for i = 1, 3 do
		if set[i] then
			pool[#pool + 1] = set[i]
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- Roll a fresh set of mission ids (dense; no nil holes) and clear the current pick.
-- exclude_id (optional): the just-completed heist, kept out of this roll. Omitted by
-- reroll_mission_set, so a reroll can bring the completed mission back.
function CSRGameManager:generate_mission_set(exclude_id)
	local missions = self:get_random_missions(exclude_id)
	local ids = {}
	for i = 1, 3 do
		local m = missions[i]
		if m and m.id then
			ids[#ids + 1] = m.id
		end
	end
	self._state.mission_set = ids
	self._state.current_mission = nil
	log_csr("generate_mission_set: " .. table.concat(ids, ", "))
	self:save()
	-- Push full host-state, not just the set: this also clears the guest's host_current_mission
	-- (we just nilled current_mission), so a reroll/regen drops the stale selection highlight
	-- instead of leaving it pointing at an id no longer in the set. broadcast_host_state re-sends
	-- the mission set internally, so guests still get the new cards.
	if _G.CSR_MP and _G.CSR_MP.broadcast_host_state then
		_G.CSR_MP.broadcast_host_state()
	elseif _G.CSR_MP and _G.CSR_MP.broadcast_mission_set then
		_G.CSR_MP.broadcast_mission_set()
	end
	return ids
end

function CSRGameManager:reroll_mission_set()
	return self:generate_mission_set()
end

-- Ensure a non-empty set exists before the lobby renders (old saves + run that starts without rolling).
-- Guests skip: they mirror the host's set via MISSION_SET sync.
function CSRGameManager:ensure_mission_set()
	if self:_is_guesting() then
		return
	end
	local set = self._state.mission_set
	if type(set) ~= "table" or #set == 0 then
		self:generate_mission_set()
	end
end

-- Resolve stored ids to full tweak_data mission tables. Unresolvable slots return nil (panel skips them).
-- While guesting, mirrors the host's synced set.
function CSRGameManager:mission_set()
	local ids = self._state.mission_set
	if self:_is_guesting() then
		local mp = self._state.mp_session
		if mp and type(mp.host_mission_set) == "table" then
			ids = mp.host_mission_set
		end
	end
	local out = {}
	for i = 1, 3 do
		local id = (ids or {})[i]
		out[i] = id and self:get_mission(id) or nil
	end
	return out
end

function CSRGameManager:mission_set_ids()
	return self._state.mission_set or {}
end
function CSRGameManager:set_mp_host_mission_set(ids)
	self._state.mp_session = self._state.mp_session or {}
	self._state.mp_session.host_mission_set = type(ids) == "table" and ids or nil
end

-- Host's synced mission-set ids (for guest reroll-change detection); nil before first sync.
function CSRGameManager:mp_host_mission_set_ids()
	local mp = self._state.mp_session
	return mp and mp.host_mission_set or nil
end

-- Host's currently-selected mission id, synced for the guest's lobby highlight (display only).
function CSRGameManager:set_mp_host_current_mission(id)
	self._state.mp_session = self._state.mp_session or {}
	self._state.mp_session.host_current_mission = id
end

function CSRGameManager:current_mission()
	-- While guesting, mirror the host's synced pick (display only); own pick otherwise.
	if self:_is_guesting() then
		return self._state.mp_session and self._state.mp_session.host_current_mission or nil
	end
	return self._state.current_mission
end

function CSRGameManager:select_mission(mission_id)
	if mission_id == false then
		self._state.current_mission = nil
		self:save()
		return
	end
	local mission_data = self:get_mission(mission_id)
	if not mission_data then
		log_csr("select_mission: unknown mission id '" .. tostring(mission_id) .. "' — ignored")
		return
	end
	self._state.current_mission = mission_data.id

	-- Engine wiring: mirrors vanilla _setup_temporary_job + activate_temporary_job + _setup_global_from_mission_id.
	local narrative_job = tweak_data
		and tweak_data.narrative
		and tweak_data.narrative.jobs
		and tweak_data.narrative.jobs.crime_spree
	if narrative_job and mission_data.level then
		narrative_job.chain = { mission_data.level }
	end
	if managers.job and mission_data.level then
		managers.job:activate_temporary_job("crime_spree", mission_data.level.level_id)
	end
	if Global and Global.game_settings and mission_data.level then
		Global.game_settings.difficulty = self:difficulty()
		Global.game_settings.one_down = false
		Global.game_settings.level_id = mission_data.level.level_id
		Global.game_settings.mission = mission_data.mission or "none"
	end
	if Network:is_server() and MenuCallbackHandler and MenuCallbackHandler.update_matchmake_attributes then
		MenuCallbackHandler:update_matchmake_attributes()
	end
	-- Sync level selection to guests immediately so they load the same level on Start.
	if _G.CSR_MP and _G.CSR_MP.broadcast_host_state then
		_G.CSR_MP.broadcast_host_state()
	end

	log_csr(
		"select_mission: "
			.. tostring(mission_data.id)
			.. " (level="
			.. tostring(mission_data.level and mission_data.level.level_id)
			.. ")"
	)
	-- Save immediately; the in-game manager is a fresh init that reads from disk.
	self:save()
end
