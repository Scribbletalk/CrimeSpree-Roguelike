-- HIPPOCRATIC OATH — Wildcard passive item.
-- Spawns a Medic enemy unit and immediately converts it to a joker that runs
-- to the player (vanilla joker AI). While the player is within 3m of the
-- medic, they regenerate 1% max HP per second. On medic death, a 6-minute
-- respawn cooldown ticks, then a fresh medic spawns. No per-heist cap.
--
-- Stealth-blocked: spawn fires only on loud transition (set_assault_mode true)
-- or loud-from-start (on_simulation_started checks whisper_mode).
--
-- Authority model:
--   Host: spawns + tracks medics, runs aura distance check, runs respawn timer.
--   Clients: receive OATH_HEAL packets and heal locally on their own player.
-- The medic unit itself is replicated to every peer via vanilla AI sync.
--
-- Joker cap bump: PostHook on the three upgrade_value paths
-- (PlayerManager / PlayerBase / HuskPlayerBase) returns +1 for
-- "convert_enemies_max_minions" when the player owns this item. This lets
-- convert_hostage_to_criminal succeed even without Mastermind ace, and stacks
-- with vanilla Mastermind cap.

if not RequiredScript then
	return
end

ModifierHippocraticOath = ModifierHippocraticOath or class(CSRBaseModifier)
ModifierHippocraticOath.desc_id = "csr_hippocratic_oath_desc"
ModifierHippocraticOath.icon = "csr_hippocratic_oath"

local function const(key, default)
	local t = _G.CSR_ItemConstants or {}
	if t[key] ~= nil then
		return t[key]
	end
	return default
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR HippocraticOath] " .. tostring(msg))
	end
end

-- ene_medic_r870 is base-game (no DLC). Always available.
local MEDIC_UNIT_PATH = "units/payday2/characters/ene_medic_r870/ene_medic_r870"

-- Per-peer state: { medic_unit_key, medic_unit, respawn_at, last_aura_t }.
-- Reset on heist start. Host-only authoritative; clients see only OATH_HEAL pings.
-- pulse_state is per-machine — drives the local expanding-ring visual on heal.
_G.CSR_HippocraticOath = _G.CSR_HippocraticOath
	or {
		state = {}, -- [peer_id] = { medic_unit, medic_unit_key, respawn_at }
		last_tick = 0,
		pulse_state = { active = false, start_t = 0, medic_unit = nil },
	}

-- Find the local player's medic joker (any peer's machine). Returns the unit or nil.
-- Used by clients to locate their own medic for the pulse visual on OATH_HEAL.
-- Exposed as _G so multiplayer_sync.lua's OATH_HEAL handler can reach it.
function _G.CSR_HippocraticOath_FindLocalMedic()
	if not (managers.groupai and managers.groupai:state()) then
		return nil
	end
	local groupai_state = managers.groupai:state()
	local converted = groupai_state._converted_police
	if not converted then
		return nil
	end
	local local_player = managers.player and managers.player:player_unit()
	if not alive(local_player) then
		return nil
	end
	-- _converted_police[u_key] = unit. Filter to medics — character_name "medic" is
	-- only emitted by the ene_medic_* family in vanilla tweak_data.character.
	for _, u in pairs(converted) do
		if alive(u) and u.base and u:base() then
			local name = u:base()._tweak_table or u:base().char_tweak_name
			if type(name) == "string" and string.find(name, "medic", 1, true) then
				return u
			end
		end
	end
	return nil
end

-- Trigger the expanding-ring visual at the medic's position. Called locally by
-- the host when its own player heals, and locally by clients on OATH_HEAL.
function _G.CSR_HippocraticOath_StartPulse(medic_unit)
	if not alive(medic_unit) then
		return
	end
	_G.CSR_HippocraticOath.pulse_state.active = true
	_G.CSR_HippocraticOath.pulse_state.start_t = TimerManager:game():time()
	_G.CSR_HippocraticOath.pulse_state.medic_unit = medic_unit
end

-- Play the medic's heal voiceline if (a) the heal actually restored HP, AND
-- (b) the per-machine throttle has elapsed. Each peer tracks its own
-- _last_voice_t in CSR_HippocraticOath.last_voice_t so the throttle is local
-- to the player who got healed (no cross-peer interference).
-- Sync flag = true so the say event replicates to all peers seeing the medic.
function _G.CSR_HippocraticOath_TryPlayVoice(medic_unit, hp_before, hp_after)
	if not alive(medic_unit) then
		return
	end
	if not (hp_before and hp_after) or hp_after <= hp_before then
		return -- no actual heal happened (full HP, or healing failed)
	end
	local now = TimerManager:game():time()
	local last = _G.CSR_HippocraticOath.last_voice_t or 0
	local throttle = const("hippocratic_voice_throttle", 30)
	if now - last < throttle then
		return
	end
	_G.CSR_HippocraticOath.last_voice_t = now
	local event = const("hippocratic_voice_event", "f47")
	pcall(function()
		medic_unit:sound():say(event, true)
	end)
end

-- Returns whether the given peer_id owns at least one Hippocratic Oath.
-- Wraps CSR_CountStacksForPeer (array iteration with prefix match — see
-- player_items_store.lua:cached_count for the canonical implementation).
local function peer_owns_oath(peer_id)
	if not _G.CSR_CountStacksForPeer then
		return false
	end
	return CSR_CountStacksForPeer(peer_id, "player_hippocratic_oath_") > 0
end

local function local_peer_id()
	if managers.network and managers.network:session() and managers.network:session():local_peer() then
		return managers.network:session():local_peer():id()
	end
	return 1
end

-- Resolve a peer_id to their player_unit. Works for local + husks.
local function get_peer_player_unit(peer_id)
	local session = managers.network and managers.network:session()
	if not session then
		return nil
	end
	local lp = session:local_peer()
	if lp and peer_id == lp:id() then
		return managers.player and managers.player:player_unit()
	end
	local peer = session:peer(peer_id)
	if peer and peer.unit then
		return peer:unit()
	end
	return nil
end

-- Pick a spawn position 15-40m from the owner using the level's registered
-- cop spawn points. Iterates BOTH:
--   * `area.spawn_points[i].pos`   — SpawnEnemyDummy mission elements
--   * `area.spawn_groups[i].spawn_pts[j].pos` — SpawnEnemyGroup elements
-- Modern heists use spawn_groups almost exclusively; older or auxiliary
-- routes can still use spawn_points. Both paths' positions were validated
-- against the navmesh at registration time (groupaistatebase.lua:4271 and
-- :4321), so anything returned here is engine-validated for cop spawns.
-- Returns nil if nothing is in the desired distance band — caller's
-- spawn-check tick retries every ~2s.
local function pick_spawn_position(owner_unit)
	local min_d = const("hippocratic_spawn_min_distance", 1500)
	local max_d = const("hippocratic_spawn_max_distance", 4000)

	if not owner_unit or not owner_unit:movement() then
		return nil
	end
	local owner_pos = owner_unit:movement():m_pos()

	local groupai = managers.groupai and managers.groupai:state()
	if not groupai or not groupai._area_data then
		return nil
	end

	local candidates = {}
	local function consider(pos)
		if not pos then
			return
		end
		local d = mvector3.distance(owner_pos, pos)
		if d >= min_d and d <= max_d then
			table.insert(candidates, pos)
		end
	end

	for _, area in pairs(groupai._area_data) do
		if area.spawn_points then
			for _, sp_data in ipairs(area.spawn_points) do
				consider(sp_data and sp_data.pos)
			end
		end
		if area.spawn_groups then
			for _, group_data in ipairs(area.spawn_groups) do
				if group_data and group_data.spawn_pts then
					for _, sp_data in ipairs(group_data.spawn_pts) do
						consider(sp_data and sp_data.pos)
					end
				end
			end
		end
	end

	if #candidates > 0 then
		return candidates[math.random(#candidates)]
	end
	return nil
end

local function send_oath_heal(peer_id)
	if not (LuaNetworking and _G.CSR_MP and CSR_MP.MSG and CSR_MP.MSG.OATH_HEAL) then
		return
	end
	pcall(function()
		LuaNetworking:SendToPeer(peer_id, CSR_MP.MSG.OATH_HEAL, "")
	end)
end

local function fire_hud_event_for(peer_id, event_name, payload)
	if peer_id ~= local_peer_id() then
		return
	end
	if CSR_VHUDPlusEvent then
		pcall(CSR_VHUDPlusEvent, "timed_buff", event_name, "csr_hippocratic_oath", payload or {})
	end
	if CSR_WFHudEvent then
		pcall(CSR_WFHudEvent, event_name, "csr_hippocratic_oath", payload or {})
	end
	if CSR_PocoHudEvent then
		pcall(CSR_PocoHudEvent, event_name, "csr_hippocratic_oath", payload or {})
	end
end

-- True only when the player is in actual heist gameplay (not pre-planning,
-- not loading, not menus, not end screens). Required for any code that calls
-- World:spawn_unit, character_damage:restore_health, etc. — those primitives
-- can deadlock or no-op if the level isn't fully loaded.
local function is_actually_playing()
	if not (managers.player and alive(managers.player:player_unit())) then
		return false
	end
	if not (managers.crime_spree and managers.crime_spree:is_active()) then
		return false
	end
	if not game_state_machine then
		return false
	end
	local s = game_state_machine:current_state_name()
	return s == "ingame_standard" or s == "ingame_waiting_for_players"
end

-- Host-only: spawn one medic for the given peer and convert to joker.
-- Returns the spawned unit or nil on failure.
local function spawn_medic_for(peer_id)
	if not Network:is_server() then
		return nil
	end
	if not is_actually_playing() then
		return nil
	end
	-- Stealth gate: never spawn during whisper_mode.
	if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
		return nil
	end

	local owner_unit = get_peer_player_unit(peer_id)
	if not alive(owner_unit) then
		return nil
	end

	local spawn_pos = pick_spawn_position(owner_unit)
	if not spawn_pos then
		return nil
	end

	-- Verify the unit asset is loaded before spawning. SuperBLT auto-mounts
	-- ene_medic_r870 since it's base-game, but DB:has is the authoritative
	-- check per pd2_dyn_resource_db_has_authoritative.md.
	local unit_id = Idstring(MEDIC_UNIT_PATH)
	if not (DB and DB.has and DB:has(Idstring("unit"), unit_id)) then
		CSR_log("Medic unit not in DB — skipping spawn for peer " .. tostring(peer_id))
		return nil
	end

	local spawned
	local ok = pcall(function()
		spawned = World:spawn_unit(unit_id, spawn_pos, Rotation())
	end)
	if not ok or not alive(spawned) then
		CSR_log("World:spawn_unit failed for peer " .. tostring(peer_id))
		return nil
	end

	-- Wait one frame for managers.enemy to register the unit in _police
	-- (vanilla register hook fires in :added(unit) on enemy spawn).
	DelayedCalls:Add("CSR_OathConvert_" .. tostring(peer_id) .. "_" .. tostring(spawned:key()), 0.1, function()
		if not alive(spawned) then
			return
		end
		local groupai = managers.groupai and managers.groupai:state()
		if not groupai then
			return
		end
		-- For client-owner, peer_unit must be the husk player unit on host.
		local peer_unit = nil
		if peer_id ~= local_peer_id() then
			peer_unit = get_peer_player_unit(peer_id)
			if not alive(peer_unit) then
				CSR_log("Owner unit not alive at conversion time, peer " .. tostring(peer_id))
				return
			end
		end

		local conv_ok = pcall(function()
			groupai:convert_hostage_to_criminal(spawned, peer_unit)
		end)
		if not conv_ok then
			CSR_log("convert_hostage_to_criminal pcall failed for peer " .. tostring(peer_id))
			return
		end

		-- HP stays vanilla (difficulty-scales naturally via the engine's enemy
		-- HP multiplier). DR is applied via a PreHook on CopDamage damage
		-- funnels — see the registration block at the bottom of this file.

		_G.CSR_HippocraticOath.state[peer_id] = {
			medic_unit = spawned,
			medic_unit_key = spawned:key(),
			respawn_at = nil,
		}

		fire_hud_event_for(peer_id, "activate", { duration = 0 })
		CSR_log("Medic spawned and converted for peer " .. tostring(peer_id))
	end)

	return spawned
end

-- Host-only: check each peer who owns Oath, spawn if they don't have a living medic.
local function host_check_spawns()
	if not Network:is_server() then
		return
	end
	if not is_actually_playing() then
		return
	end

	local session = managers.network and managers.network:session()
	if not session then
		return
	end

	-- Check local host player.
	local host_pid = session:local_peer():id()
	if peer_owns_oath(host_pid) then
		local s = _G.CSR_HippocraticOath.state[host_pid]
		if not s or not (s.medic_unit and alive(s.medic_unit)) then
			if not s or not s.respawn_at or s.respawn_at <= TimerManager:game():time() then
				spawn_medic_for(host_pid)
			end
		end
	end

	-- Check each connected client.
	for _, peer in pairs(session:peers()) do
		local pid = peer:id()
		if peer_owns_oath(pid) then
			local s = _G.CSR_HippocraticOath.state[pid]
			if not s or not (s.medic_unit and alive(s.medic_unit)) then
				if not s or not s.respawn_at or s.respawn_at <= TimerManager:game():time() then
					spawn_medic_for(pid)
				end
			end
		end
	end
end

-- Host-only: heal aura tick for each living medic.
local function host_aura_tick()
	if not Network:is_server() then
		return
	end
	if not is_actually_playing() then
		return
	end
	local radius = const("hippocratic_aura_radius", 500)
	local heal_pct = const("hippocratic_heal_pct_per_tick", 0.005)

	for peer_id, s in pairs(_G.CSR_HippocraticOath.state) do
		if s and s.medic_unit and alive(s.medic_unit) and s.medic_unit:movement() then
			local owner_unit = get_peer_player_unit(peer_id)
			if alive(owner_unit) and owner_unit:movement() then
				local d = mvector3.distance(owner_unit:movement():m_pos(), s.medic_unit:movement():m_pos())
				if d <= radius then
					if peer_id == local_peer_id() then
						local cdmg = owner_unit:character_damage()
						if cdmg and cdmg.restore_health then
							-- Snapshot HP so we can detect whether the heal
							-- actually restored anything (no voiceline at full HP).
							local hp_before = cdmg.get_real_health and cdmg:get_real_health() or nil
							pcall(cdmg.restore_health, cdmg, heal_pct, false)
							local hp_after = cdmg.get_real_health and cdmg:get_real_health() or nil
							_G.CSR_HippocraticOath_TryPlayVoice(s.medic_unit, hp_before, hp_after)
						end
						-- Local pulse visual at the medic.
						_G.CSR_HippocraticOath_StartPulse(s.medic_unit)
					else
						send_oath_heal(peer_id)
					end
				end
			end
		end
	end
end

-- Reset state at heist start.
local function reset_state()
	_G.CSR_HippocraticOath.state = {}
	_G.CSR_HippocraticOath.last_tick = 0
	-- Clear pulse state too — stale medic_unit references from a prior heist
	-- would otherwise sit in the table until a new pulse fires.
	_G.CSR_HippocraticOath.pulse_state = { active = false, start_t = 0, medic_unit = nil }
	_G.CSR_HippocraticOath.last_voice_t = 0
end

-- Called when a minion dies. Identify if it was an Oath medic and start cooldown.
-- Hooked from groupai's clbk_minion_dies AFTER vanilla logic runs, so the unit
-- is still alive-enough to read its key.
local function on_minion_died(player_key, minion_unit)
	if not Network:is_server() then
		return
	end
	if not alive(minion_unit) then
		return
	end
	local minion_key = minion_unit:key()
	for peer_id, s in pairs(_G.CSR_HippocraticOath.state) do
		if s and s.medic_unit_key == minion_key then
			local delay = const("hippocratic_respawn_delay", 360)
			s.medic_unit = nil
			s.medic_unit_key = nil
			s.respawn_at = TimerManager:game():time() + delay
			fire_hud_event_for(peer_id, "deactivate", {})
			fire_hud_event_for(peer_id, "activate", { duration = delay, name_id = "csr_hippocratic_oath_cd" })
			CSR_log("Medic died for peer " .. tostring(peer_id) .. ", respawn in " .. tostring(delay) .. "s")
			return
		end
	end
end

-- Throttled host tick. ~0.5s for aura, ~5s for spawn check.
if not _G._CSR_HIPPOCRATIC_TICK_HOOKED then
	_G._CSR_HIPPOCRATIC_TICK_HOOKED = true
	_G.CSR_HippocraticOath._next_aura_t = 0
	_G.CSR_HippocraticOath._next_spawn_t = 0

	Hooks:Add("GameSetupUpdate", "CSR_HippocraticOath_Tick", function(t, dt)
		if not Network:is_server() then
			return
		end
		if not (managers.crime_spree and managers.crime_spree:is_active()) then
			return
		end

		local aura_interval = const("hippocratic_aura_tick", 0.5)
		if t >= (_G.CSR_HippocraticOath._next_aura_t or 0) then
			_G.CSR_HippocraticOath._next_aura_t = t + aura_interval
			pcall(host_aura_tick)
		end
		-- Spawn check less frequent — 2s.
		if t >= (_G.CSR_HippocraticOath._next_spawn_t or 0) then
			_G.CSR_HippocraticOath._next_spawn_t = t + 2.0
			pcall(host_check_spawns)
		end
	end)
end

-- Per-frame draw of the heal-pulse expanding ring (all peers).
-- Mirrors the Sixth Sense Visual Effect mod's Draw:brush:cylinder pattern but
-- as a one-shot fade rather than an infinite recurring loop. Active only while
-- pulse_state.active and within hippocratic_pulse_duration of the heal moment.
if not _G._CSR_HIPPOCRATIC_PULSE_DRAW_HOOKED then
	_G._CSR_HIPPOCRATIC_PULSE_DRAW_HOOKED = true
	Hooks:Add("GameSetupUpdate", "CSR_HippocraticOath_PulseDraw", function(t, dt)
		local ps = _G.CSR_HippocraticOath and _G.CSR_HippocraticOath.pulse_state
		if not ps or not ps.active then
			return
		end
		local duration = const("hippocratic_pulse_duration", 0.7)
		local elapsed = t - (ps.start_t or 0)
		if elapsed >= duration or not alive(ps.medic_unit) or not ps.medic_unit:movement() then
			ps.active = false
			return
		end
		local progress = elapsed / duration
		local radius = const("hippocratic_aura_radius", 500) * progress
		-- Peak alpha lives in CSR_ItemConstants for live tuning. `add` blend
		-- already brightens the ground, so values around 0.05-0.15 read as a
		-- soft glow rather than a hard overlay. m_pos is read fresh every
		-- frame so the cylinder tracks the medic as they move.
		local alpha = const("hippocratic_pulse_alpha", 0.08) * (1 - progress)
		local pos = ps.medic_unit:movement():m_pos()
		local color = Color(alpha, 0.35, 1.0, 0.55)
		local brush = Draw:brush(color)
		brush:set_blend_mode("add")
		brush:cylinder(pos, pos + Vector3(0, 0, 6), radius)
	end)
end

-- Hook minion death to identify Oath-medic deaths.
if GroupAIStateBase and not _G._CSR_HIPPOCRATIC_DEATH_HOOKED then
	_G._CSR_HIPPOCRATIC_DEATH_HOOKED = true
	Hooks:PostHook(
		GroupAIStateBase,
		"clbk_minion_dies",
		"CSR_HippocraticOath_DeathDetect",
		function(self, player_key, minion_unit)
			pcall(on_minion_died, player_key, minion_unit)
		end
	)
end

-- Damage reduction: PreHook every CopDamage funnel and scale attack_data.damage
-- by (1 - DR) when the target is one of our medic units. Mirrors equalizer.lua's
-- 4-method coverage (bullet / melee / explosion / dot).
local function is_oath_medic(cdmg)
	if not cdmg or not cdmg._unit then
		return false
	end
	local key = cdmg._unit:key()
	for _, s in pairs(_G.CSR_HippocraticOath.state) do
		if s and s.medic_unit_key == key then
			return true
		end
	end
	return false
end

if CopDamage and not _G._CSR_HIPPOCRATIC_DR_HOOKED then
	_G._CSR_HIPPOCRATIC_DR_HOOKED = true
	local function dr_pre(self, attack_data)
		if not attack_data or not attack_data.damage then
			return
		end
		if not is_oath_medic(self) then
			return
		end
		local dr = const("hippocratic_medic_dr", 0.50)
		attack_data.damage = attack_data.damage * (1 - dr)
	end
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_HippocraticOath_DR_Bullet", dr_pre)
	Hooks:PreHook(CopDamage, "damage_melee", "CSR_HippocraticOath_DR_Melee", dr_pre)
	Hooks:PreHook(CopDamage, "damage_explosion", "CSR_HippocraticOath_DR_Explosion", dr_pre)
	Hooks:PreHook(CopDamage, "damage_dot", "CSR_HippocraticOath_DR_Dot", dr_pre)
end

-- Reset state on heist start.
if not _G._CSR_HIPPOCRATIC_RESET_HOOKED then
	_G._CSR_HIPPOCRATIC_RESET_HOOKED = true
	if BaseNetworkSession then
		Hooks:PostHook(BaseNetworkSession, "load_complete", "CSR_HippocraticOath_LoadReset", function(self)
			pcall(reset_state)
		end)
	end
	if PlayerManager then
		Hooks:PostHook(PlayerManager, "spawned_player", "CSR_HippocraticOath_SpawnReset", function(self)
			-- Don't blow away host state when local player respawns; only reset
			-- if there's no state at all yet (first heist of session).
			if not _G.CSR_HippocraticOath.state[local_peer_id()] then
				CSR_log("Local player spawned, ensuring state is initialized")
			end
		end)
	end
end

-- Joker cap bump: PostHook all three upgrade_value paths so
-- "convert_enemies_max_minions" returns base + 1 for Oath owners.
local function bump_for_oath(peer_id, value)
	if not peer_owns_oath(peer_id) then
		return value
	end
	return (value or 0) + 1
end

if PlayerManager and not _G._CSR_HIPPOCRATIC_PM_UPGRADE_HOOKED then
	_G._CSR_HIPPOCRATIC_PM_UPGRADE_HOOKED = true
	local original = PlayerManager.upgrade_value
	function PlayerManager:upgrade_value(category, upgrade, default)
		local v = original(self, category, upgrade, default)
		if category == "player" and upgrade == "convert_enemies_max_minions" then
			return bump_for_oath(local_peer_id(), v)
		end
		return v
	end
end

if PlayerBase and not _G._CSR_HIPPOCRATIC_PB_UPGRADE_HOOKED then
	_G._CSR_HIPPOCRATIC_PB_UPGRADE_HOOKED = true
	local original = PlayerBase.upgrade_value
	function PlayerBase:upgrade_value(category, upgrade)
		local v = original(self, category, upgrade)
		if category == "player" and upgrade == "convert_enemies_max_minions" then
			-- PlayerBase is the local player's base; resolve peer_id from it.
			local pid = local_peer_id()
			return bump_for_oath(pid, v)
		end
		return v
	end
end

if HuskPlayerBase and not _G._CSR_HIPPOCRATIC_HPB_UPGRADE_HOOKED then
	_G._CSR_HIPPOCRATIC_HPB_UPGRADE_HOOKED = true
	local original = HuskPlayerBase.upgrade_value
	function HuskPlayerBase:upgrade_value(category, upgrade)
		local v = original(self, category, upgrade)
		if category == "player" and upgrade == "convert_enemies_max_minions" then
			-- Husk base — find the owning peer via the unit.
			local session = managers.network and managers.network:session()
			if session and self._unit then
				for _, peer in pairs(session:peers()) do
					if peer:unit() == self._unit then
						return bump_for_oath(peer:id(), v)
					end
				end
			end
		end
		return v
	end
end
