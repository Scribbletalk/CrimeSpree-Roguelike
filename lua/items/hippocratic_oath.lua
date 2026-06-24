-- Hippocratic Oath (wildcard): on loud, spawns a Medic offscreen, converts it to a leashed joker,
-- and pulses a heal aura. On medic death a respawn timer ticks, then a fresh one spawns. Stealth-blocked.
-- Host spawns/tracks every owner's medic and runs the aura/respawn/DR; owners heal locally (remote
-- owners via an OATH_HEAL ping). HUD respawn timer via CSR_SetWildcardCooldown.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

-- Balance (matches the logbook string: 5m aura, 5s pulse, 5% heal, 6-min respawn).
local AURA_RADIUS = 500 -- 5m (PD2 units: 1m = 100)
local AURA_TICK = 5.0 -- seconds between heal pulses
local HEAL_PCT = 0.05 -- 5% of max HP per pulse
local RESPAWN_DELAY = 360 -- 6 minutes between deaths
local SPAWN_MIN_DIST = 1500 -- spawn 15-40m from the owner (offscreen, but reachable)
local SPAWN_MAX_DIST = 4000
local SPAWN_CHECK_INTERVAL = 2.0
local MEDIC_DR = 0.80 -- 80% incoming damage reduction on the medic
local RELOCATE_DISTANCE = 250 -- idle follow leash: re-path the medic past this to stay in heal range
local LEASH_DISTANCE = AURA_RADIUS -- yank the medic out of any fight once it leaves heal range
local LEASH_CHECK_INTERVAL = 0.5 -- leash check cadence
local PULSE_DURATION = 0.5 -- expanding-ring visual lifetime per heal pulse
local PULSE_ALPHA = 0.06 -- peak ring opacity (opacity_add blend)
local VOICE_EVENT = "f47" -- medic heal shout (vanilla priority_shout)
local VOICE_THROTTLE = 30 -- min seconds between heal voicelines per machine

-- ene_medic_r870 is base-game (no DLC) — always mountable.
local MEDIC_UNIT_PATH = "units/payday2/characters/ene_medic_r870/ene_medic_r870"

-- File-locals shared by every hook closure (file is dofile'd once). state is host-authoritative;
-- pulse/last_voice_t are per-machine (drive the local visual).
local state = {} -- [peer_id] = { medic_unit, medic_unit_key, respawn_at }
local pulse = { active = false, start_t = 0, medic_unit = nil }
local last_voice_t = 0
local next_aura_t = 0
local next_spawn_t = 0
local next_leash_t = 0

-- Follow-debug tracing, gated by the mod-wide _G.CSR_DEBUG toggle.
local function dbg(fmt, ...)
	if _G.CSR_DEBUG and csr_log then
		csr_log("[HO] " .. string.format(fmt, ...))
	end
end

-- =====================================================
-- Helpers
-- =====================================================

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

local function local_peer_id()
	local mgr = managers and managers.csr
	if mgr and mgr.local_peer_id then
		return mgr:local_peer_id()
	end
	return 1
end

-- True if the given peer owns Hippocratic Oath (local via owned(), remote via synced counts).
local function peer_owns_oath(peer_id)
	local mgr = managers and managers.csr
	if not mgr then
		return false
	end
	if peer_id == local_peer_id() then
		return (mgr.owned and mgr:owned("hippocratic_oath") or 0) > 0
	end
	local counts = mgr.player_items and mgr:player_items(peer_id)
	return type(counts) == "table" and (counts["hippocratic_oath"] or 0) > 0
end

-- Resolve a peer_id to their player_unit (local or husk). Host-side use.
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
	return peer and peer.unit and peer:unit() or nil
end

-- Pick a spawn pos 15-40m from the owner using the level's registered cop spawn points
-- (navmesh-validated at registration). Iterates both spawn_points and spawn_groups.
local function pick_spawn_position(owner_unit)
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
		if d >= SPAWN_MIN_DIST and d <= SPAWN_MAX_DIST then
			candidates[#candidates + 1] = pos
		end
	end

	for _, area in pairs(groupai._area_data) do
		if area.spawn_points then
			for _, sp in ipairs(area.spawn_points) do
				consider(sp and sp.pos)
			end
		end
		if area.spawn_groups then
			for _, grp in ipairs(area.spawn_groups) do
				if grp and grp.spawn_pts then
					for _, sp in ipairs(grp.spawn_pts) do
						consider(sp and sp.pos)
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

-- Find the local player's medic joker (for the client-side pulse/voice on OATH_HEAL).
local function find_local_medic()
	local groupai = managers.groupai and managers.groupai:state()
	local converted = groupai and groupai._converted_police
	if not converted then
		return nil
	end
	for _, u in pairs(converted) do
		if alive(u) and u:base() then
			local name = u:base()._tweak_table or u:base().char_tweak_name
			if type(name) == "string" and string.find(name, "medic", 1, true) then
				return u
			end
		end
	end
	return nil
end

local function start_pulse(medic_unit)
	if not alive(medic_unit) then
		return
	end
	pulse.active = true
	pulse.start_t = TimerManager:game():time()
	pulse.medic_unit = medic_unit
end

-- Play the medic's heal voiceline only if the heal restored HP and the per-machine
-- throttle elapsed. Sync flag true so the say replicates to peers seeing the medic.
local function try_play_voice(medic_unit, hp_before, hp_after)
	if not alive(medic_unit) then
		return
	end
	if not (hp_before and hp_after) or hp_after <= hp_before then
		return
	end
	local now = TimerManager:game():time()
	if now - last_voice_t < VOICE_THROTTLE then
		return
	end
	last_voice_t = now
	pcall(function()
		medic_unit:sound():say(VOICE_EVENT, true)
	end)
end

-- True only in actual CSR heist gameplay (level loaded). Required before World:spawn_unit /
-- restore_health, which can no-op or deadlock if the level isn't fully loaded.
local function is_playing()
	if not (managers.player and alive(managers.player:player_unit())) then
		return false
	end
	if not csr_mgr() then
		return false
	end
	if not game_state_machine then
		return false
	end
	local s = game_state_machine:current_state_name()
	return s == "ingame_standard" or s == "ingame_waiting_for_players"
end

local function send_oath_heal(peer_id)
	if not (LuaNetworking and _G.CSR_MP and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.OATH_HEAL) then
		return
	end
	pcall(function()
		LuaNetworking:SendToPeer(peer_id, CSR_MP.ITEM_MSG.OATH_HEAL, "")
	end)
end

-- Publish/clear the respawn timer on the U1 wildcard HUD slot (local owner only).
local function set_hud_cooldown(peer_id, ends)
	if peer_id ~= local_peer_id() or not _G.CSR_SetWildcardCooldown then
		return
	end
	_G.CSR_SetWildcardCooldown("hippocratic_oath", ends or 0, RESPAWN_DELAY)
end

-- =====================================================
-- Host-authoritative medic lifecycle
-- =====================================================

-- Re-path the medic to its owner. A fresh "follow" objective exits any fight back to "travel".
local function set_follow_objective(medic_unit, owner_unit)
	if not (alive(medic_unit) and medic_unit:brain() and alive(owner_unit)) then
		dbg("set_follow_objective SKIP medic=%s owner=%s", tostring(alive(medic_unit)), tostring(alive(owner_unit)))
		return
	end
	local ok = pcall(function()
		medic_unit:brain():set_objective({
			type = "follow",
			follow_unit = owner_unit,
			scan = true,
			is_default = true,
			haste = "run", -- jokers default to "walk" in cool stance; force run to keep pace with the owner
		})
	end)
	dbg("set_follow_objective DONE ok=%s logic_now=%s", tostring(ok), tostring(medic_unit:brain()._current_logic_name))
end

-- Spawn one medic for the given peer and convert it to a joker. Returns nothing.
local function spawn_medic_for(peer_id)
	if not Network:is_server() or not is_playing() then
		return
	end
	if managers.groupai:state():whisper_mode() then
		dbg("spawn SKIP whisper_mode peer=%s", tostring(peer_id))
		return -- stealth gate
	end

	local owner_unit = get_peer_player_unit(peer_id)
	if not alive(owner_unit) then
		dbg("spawn SKIP no owner peer=%s", tostring(peer_id))
		return
	end
	local spawn_pos = pick_spawn_position(owner_unit)
	if not spawn_pos then
		dbg("spawn SKIP no spawn_pos peer=%s", tostring(peer_id))
		return -- caller retries on the next spawn-check tick
	end
	dbg("spawn peer=%s spawn_dist=%.0f", tostring(peer_id), mvector3.distance(owner_unit:movement():m_pos(), spawn_pos))

	local unit_id = Idstring(MEDIC_UNIT_PATH)
	if not (DB and DB.has and DB:has(Idstring("unit"), unit_id)) then
		return
	end

	local spawned
	local ok = pcall(function()
		spawned = World:spawn_unit(unit_id, spawn_pos, Rotation())
	end)
	if not ok or not alive(spawned) then
		return
	end

	-- Raw World:spawn_unit leaves data.team nil → CopLogicTravel crash before convert.
	-- Set idle spawn AI + combatant team synchronously. See pd2_spawn_unit_needs_set_char_team.md.
	pcall(function()
		spawned:brain():set_spawn_ai({ init_state = "idle" })
		managers.groupai:state():set_char_team(spawned, tweak_data.levels:get_default_team_ID("combatant"))
	end)

	-- Wait one frame for managers.enemy to register the unit before converting.
	DelayedCalls:Add("CSR_OathConvert_" .. tostring(peer_id) .. "_" .. tostring(spawned:key()), 0.1, function()
		if not alive(spawned) then
			return
		end
		local groupai = managers.groupai and managers.groupai:state()
		if not groupai then
			return
		end
		-- Client owner: pass the husk player unit so the joker follows them.
		local peer_unit = nil
		if peer_id ~= local_peer_id() then
			peer_unit = get_peer_player_unit(peer_id)
			if not alive(peer_unit) then
				return
			end
		end
		local conv_ok = pcall(function()
			groupai:convert_hostage_to_criminal(spawned, peer_unit)
		end)
		dbg(
			"convert peer=%s ok=%s is_converted=%s logic=%s",
			tostring(peer_id),
			tostring(conv_ok),
			tostring(spawned:brain() and spawned:brain()._logic_data and spawned:brain()._logic_data.is_converted),
			tostring(spawned:brain() and spawned:brain()._current_logic_name)
		)
		if not conv_ok then
			return
		end
		state[peer_id] = { medic_unit = spawned, medic_unit_key = spawned:key(), respawn_at = nil }
		set_hud_cooldown(peer_id, 0) -- medic alive -> radial full
		-- Install the tight follow leash so the joker prioritises sticking to its owner.
		set_follow_objective(spawned, get_peer_player_unit(peer_id))
	end)
end

-- Spawn a medic for every owning peer that lacks a living one (respawn timer permitting).
local function host_check_spawns()
	if not Network:is_server() or not is_playing() then
		return
	end
	local session = managers.network and managers.network:session()
	if not session then
		return
	end

	local function check(pid)
		if not peer_owns_oath(pid) then
			return
		end
		local s = state[pid]
		if s and s.medic_unit and alive(s.medic_unit) then
			return
		end
		if s and s.respawn_at and s.respawn_at > TimerManager:game():time() then
			return
		end
		spawn_medic_for(pid)
	end

	check(session:local_peer():id())
	for _, peer in pairs(session:peers()) do
		check(peer:id())
	end
end

-- Heal aura tick: each living medic heals its owner if within radius.
local function host_aura_tick()
	if not Network:is_server() or not is_playing() then
		return
	end
	for peer_id, s in pairs(state) do
		if s and s.medic_unit and alive(s.medic_unit) and s.medic_unit:movement() then
			local owner_unit = get_peer_player_unit(peer_id)
			if alive(owner_unit) and owner_unit:movement() then
				local d = mvector3.distance(owner_unit:movement():m_pos(), s.medic_unit:movement():m_pos())
				if d <= AURA_RADIUS then
					if peer_id == local_peer_id() then
						local cdmg = owner_unit:character_damage()
						if cdmg and cdmg.restore_health then
							local hp_before = cdmg.get_real_health and cdmg:get_real_health() or nil
							pcall(cdmg.restore_health, cdmg, HEAL_PCT, false)
							local hp_after = cdmg.get_real_health and cdmg:get_real_health() or nil
							try_play_voice(s.medic_unit, hp_before, hp_after)
						end
						start_pulse(s.medic_unit)
					else
						send_oath_heal(peer_id)
					end
				end
			end
		end
	end
end

-- Leash tick: a medic past LEASH_DISTANCE and not already travelling gets re-issued a follow.
-- The "travel" guard avoids re-pathing every tick while it's already running home.
local function host_leash_tick()
	if not Network:is_server() or not is_playing() then
		return
	end
	for peer_id, s in pairs(state) do
		if s and s.medic_unit and alive(s.medic_unit) and s.medic_unit:movement() and s.medic_unit:brain() then
			local owner_unit = get_peer_player_unit(peer_id)
			if alive(owner_unit) and owner_unit:movement() then
				local d = mvector3.distance(owner_unit:movement():m_pos(), s.medic_unit:movement():m_pos())
				local logic = s.medic_unit:brain()._current_logic_name
				local reissue = d > LEASH_DISTANCE and logic ~= "travel"
				dbg(
					"leash peer=%s d=%.0f logic=%s reissue=%s",
					tostring(peer_id),
					d,
					tostring(logic),
					tostring(reissue)
				)
				if reissue then
					set_follow_objective(s.medic_unit, owner_unit)
				end
			end
		end
	end
end

-- A minion died: if it was an Oath medic, start its respawn timer.
local function on_minion_died(minion_unit)
	if not Network:is_server() or not alive(minion_unit) then
		return
	end
	local minion_key = minion_unit:key()
	for peer_id, s in pairs(state) do
		if s and s.medic_unit_key == minion_key then
			s.medic_unit = nil
			s.medic_unit_key = nil
			s.respawn_at = TimerManager:game():time() + RESPAWN_DELAY
			set_hud_cooldown(peer_id, s.respawn_at)
			return
		end
	end
end

local function reset_state()
	state = {}
	pulse = { active = false, start_t = 0, medic_unit = nil }
	last_voice_t = 0
	next_aura_t = 0
	next_spawn_t = 0
	next_leash_t = 0
	set_hud_cooldown(local_peer_id(), 0)
end

local function is_oath_medic(cdmg)
	if not cdmg or not cdmg._unit then
		return false
	end
	local key = cdmg._unit:key()
	for _, s in pairs(state) do
		if s and s.medic_unit_key == key then
			return true
		end
	end
	return false
end

-- Unit-keyed variant for the relocate override (which gets the AI unit, not its CopDamage).
local function is_oath_medic_unit(unit)
	if not alive(unit) then
		return false
	end
	local key = unit:key()
	for _, s in pairs(state) do
		if s and s.medic_unit_key == key then
			return true
		end
	end
	return false
end

-- Host-side: distance from an Oath medic to its owner, or nil if `unit` isn't our medic /
-- the owner is gone. Drives the combat leash (suppress target acquisition past LEASH_DISTANCE).
local function oath_medic_owner_dist(unit)
	if not (alive(unit) and unit:movement()) then
		return nil
	end
	local key = unit:key()
	for peer_id, s in pairs(state) do
		if s and s.medic_unit_key == key then
			local owner = get_peer_player_unit(peer_id)
			if alive(owner) and owner:movement() then
				return mvector3.distance(unit:movement():m_pos(), owner:movement():m_newest_pos())
			end
			return nil
		end
	end
	return nil
end

-- =====================================================
-- One-time global hooks (per-frame tick, pulse draw, per-heist reset, MP heal handler)
-- =====================================================

local mp_handler_registered = false
local function ensure_mp_handler()
	if mp_handler_registered then
		return
	end
	if not (_G.CSR_MP and CSR_MP.register_handler and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.OATH_HEAL) then
		return
	end
	mp_handler_registered = true
	-- Remote owner heals their own player on the host's ping; pulse/voice on the local medic.
	CSR_MP.register_handler(CSR_MP.ITEM_MSG.OATH_HEAL, function(sender, data, sender_num, is_from_host)
		if not is_from_host or not csr_mgr() then
			return
		end
		local pu = managers.player and managers.player:player_unit()
		if not alive(pu) then
			return
		end
		local cdmg = pu:character_damage()
		if not (cdmg and cdmg.restore_health) then
			return
		end
		if managers.csr and managers.csr:item_heal_blocked() then
			return
		end
		local hp_before = cdmg.get_real_health and cdmg:get_real_health() or nil
		pcall(cdmg.restore_health, cdmg, HEAL_PCT, false)
		local hp_after = cdmg.get_real_health and cdmg:get_real_health() or nil
		local medic = find_local_medic()
		if medic then
			start_pulse(medic)
			try_play_voice(medic, hp_before, hp_after)
		end
	end)
end

local function install_global_hooks()
	if _G._CSR_HIPPOCRATIC_GLOBAL_HOOKED then
		return
	end
	_G._CSR_HIPPOCRATIC_GLOBAL_HOOKED = true

	-- Host tick: aura every AURA_TICK, spawn-check every SPAWN_CHECK_INTERVAL. Both roles
	-- register the MP heal handler (clients are the receivers).
	Hooks:Add("GameSetupUpdate", "CSR_HippocraticOath_Tick", function(t, dt)
		ensure_mp_handler()
		if not Network:is_server() or not csr_mgr() then
			return
		end
		if t >= next_aura_t then
			next_aura_t = t + AURA_TICK
			pcall(host_aura_tick)
		end
		if t >= next_spawn_t then
			next_spawn_t = t + SPAWN_CHECK_INTERVAL
			pcall(host_check_spawns)
		end
		if t >= next_leash_t then
			next_leash_t = t + LEASH_CHECK_INTERVAL
			pcall(host_leash_tick)
		end
	end)

	-- Expanding heal ring at the medic (all peers, one-shot fade); opacity_add blend so alpha scales.
	Hooks:Add("GameSetupUpdate", "CSR_HippocraticOath_PulseDraw", function(t, dt)
		if not pulse.active then
			return
		end
		local elapsed = t - (pulse.start_t or 0)
		if elapsed >= PULSE_DURATION or not alive(pulse.medic_unit) or not pulse.medic_unit:movement() then
			pulse.active = false
			return
		end
		local progress = elapsed / PULSE_DURATION
		local radius = AURA_RADIUS * progress
		local alpha = PULSE_ALPHA * (1 - progress)
		local pos = pulse.medic_unit:movement():m_pos()
		local brush = Draw:brush(Color(alpha, 0.4, 0.85, 0.5))
		brush:set_blend_mode("opacity_add")
		brush:cylinder(pos, pos + Vector3(0, 0, 6), radius)
	end)

	-- Per-heist reset (fires on all peers at load).
	Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_HippocraticOath_Reset", function()
		pcall(reset_state)
	end)
end

-- =====================================================
-- Registration
-- =====================================================

_G.CSR.register_item({
	type = "hippocratic_oath",
	rarity = "wildcard",
	name = "csr_logbook_hippocratic_oath_name",
	desc = "csr_item_hippocratic_oath_desc",
	full_desc = "csr_logbook_hippocratic_oath_effect",
	notes = "csr_logbook_hippocratic_oath_notes",
	icon = "csr_hippocratic_oath",
	icon_scale = 0.9,

	-- $aura_radius / $tick_s / $heal_pct / $respawn_min fill csr_logbook_hippocratic_oath_effect.
	loc_macros = {
		aura_radius = string.format("%gm", AURA_RADIUS / 100),
		tick_s = string.format("%g", AURA_TICK),
		heal_pct = string.format("%g", HEAL_PCT * 100),
		respawn_min = string.format("%g", RESPAWN_DELAY / 60),
	},

	hooks = {
		["lib/managers/playermanager"] = function()
			-- PlayerManager always loads, so install the tick + pulse + reset + MP handler from here.
			install_global_hooks()

			-- Joker-cap bump for the host's own conversion (convert_hostage_to_criminal reads
			-- managers.player:upgrade_value when peer_unit is nil). Gated to CSR heists.
			if _G._CSR_HIPPOCRATIC_PM_UPGRADE_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_PM_UPGRADE_HOOKED = true
			local original = PlayerManager.upgrade_value
			function PlayerManager:upgrade_value(category, upgrade, default)
				local v = original(self, category, upgrade, default)
				if
					category == "player"
					and upgrade == "convert_enemies_max_minions"
					and csr_mgr()
					and peer_owns_oath(local_peer_id())
				then
					return (v or 0) + 1
				end
				return v
			end
		end,

		["lib/units/beings/player/huskplayerbase"] = function()
			-- Joker-cap bump for client owners: convert_hostage_to_criminal reads
			-- peer_unit:base():upgrade_value (a HuskPlayerBase) when converting their medic.
			if _G._CSR_HIPPOCRATIC_HPB_UPGRADE_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_HPB_UPGRADE_HOOKED = true
			local original = HuskPlayerBase.upgrade_value
			function HuskPlayerBase:upgrade_value(category, upgrade)
				local v = original(self, category, upgrade)
				if category == "player" and upgrade == "convert_enemies_max_minions" and csr_mgr() then
					local session = managers.network and managers.network:session()
					if session and self._unit then
						for _, peer in pairs(session:peers()) do
							if peer:unit() == self._unit and peer_owns_oath(peer:id()) then
								return (v or 0) + 1
							end
						end
					end
				end
				return v
			end
		end,

		["lib/managers/group_ai_states/groupaistatebase"] = function()
			-- Detect Oath-medic deaths to start the respawn timer.
			if _G._CSR_HIPPOCRATIC_DEATH_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_DEATH_HOOKED = true
			Hooks:PostHook(
				GroupAIStateBase,
				"clbk_minion_dies",
				"CSR_HippocraticOath_DeathDetect",
				function(self, player_key, minion_unit)
					pcall(on_minion_died, minion_unit)
				end
			)
		end,

		["lib/units/enemies/cop/copdamage"] = function()
			-- 80% damage reduction on the medic: scale attack_data.damage in every CopDamage
			-- funnel (bullet/melee/explosion/dot) when the target is one of our medics.
			if _G._CSR_HIPPOCRATIC_DR_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_DR_HOOKED = true
			local function dr_pre(self, attack_data)
				if not attack_data or not attack_data.damage then
					return
				end
				if not is_oath_medic(self) then
					return
				end
				attack_data.damage = attack_data.damage * (1 - MEDIC_DR)
			end
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_HippocraticOath_DR_Bullet", dr_pre)
			Hooks:PreHook(CopDamage, "damage_melee", "CSR_HippocraticOath_DR_Melee", dr_pre)
			Hooks:PreHook(CopDamage, "damage_explosion", "CSR_HippocraticOath_DR_Explosion", dr_pre)
			Hooks:PreHook(CopDamage, "damage_dot", "CSR_HippocraticOath_DR_Dot", dr_pre)
		end,

		["lib/units/player_team/logics/teamailogicidle"] = function()
			-- Idle follow leash: force a relocate for our medic past RELOCATE_DISTANCE (vanilla only
			-- trips much further out, so the medic loiters). Scoped by unit-key; other units untouched.
			if _G._CSR_HIPPOCRATIC_RELOCATE_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_RELOCATE_HOOKED = true
			local original = TeamAILogicIdle._check_should_relocate
			function TeamAILogicIdle._check_should_relocate(data, my_data, objective, ...)
				if
					data
					and alive(data.unit)
					and objective
					and alive(objective.follow_unit)
					and is_oath_medic_unit(data.unit)
				then
					local my_mov = data.unit:movement()
					local follow_mov = objective.follow_unit:movement()
					if my_mov and follow_mov then
						local d = mvector3.distance(my_mov:m_pos(), follow_mov:m_newest_pos())
						dbg("relocate-override HIT d=%.0f force=%s", d, tostring(d > RELOCATE_DISTANCE))
						if d > RELOCATE_DISTANCE then
							return true
						end
					end
				end
				return original(data, my_data, objective, ...)
			end
		end,

		["lib/units/enemies/cop/logics/coplogicidle"] = function()
			-- Combat leash: our medic only acquires targets within LEASH_DISTANCE of its owner.
			-- _get_priority_attention is the shared chokepoint for idle + attack, so returning nil past
			-- the leash keeps it from fighting (re-issuing follow alone loses to attack movement).
			-- Scoped by unit-key; other cops untouched. See pd2_converted_joker_combat_leash.md.
			if _G._CSR_HIPPOCRATIC_ATTN_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_ATTN_HOOKED = true
			local original = CopLogicIdle._get_priority_attention
			function CopLogicIdle._get_priority_attention(data, attention_objects, reaction_func)
				if data and data.unit then
					local d = oath_medic_owner_dist(data.unit)
					if d and d > LEASH_DISTANCE then
						dbg("attn-suppress d=%.0f -> drop target (combat leash)", d)
						return nil
					end
				end
				return original(data, attention_objects, reaction_func)
			end
		end,

		["lib/units/enemies/cop/logics/coplogictravel"] = function()
			-- "Follow more directly" (from Useful Bots, scoped to our medic): vanilla coarse pathing is
			-- async and stalls, then meanders to a stale owner pos. Replace with a synchronous direct
			-- two-node path to the owner's current nav segment. Non-medic units keep vanilla async.
			if _G._CSR_HIPPOCRATIC_COARSE_HOOKED then
				return
			end
			_G._CSR_HIPPOCRATIC_COARSE_HOOKED = true
			local original = CopLogicTravel._begin_coarse_pathing
			function CopLogicTravel._begin_coarse_pathing(data, my_data, ...)
				if not is_oath_medic_unit(data.unit) or (data.path_fail_t and data.t - data.path_fail_t < 2) then
					return original(data, my_data, ...)
				end
				local objective = data.objective
				if not (objective and alive(objective.follow_unit) and objective.follow_unit:movement()) then
					return original(data, my_data, ...)
				end
				local follow_tracker = objective.follow_unit:movement():nav_tracker()
				local nav_seg = follow_tracker and follow_tracker:nav_segment()
				local pos = follow_tracker and follow_tracker:field_position()
				if not nav_seg or not pos then
					return original(data, my_data, ...)
				end
				my_data.coarse_path_index = 1
				my_data.coarse_path = {
					{ data.unit:movement():nav_tracker():nav_segment(), mvector3.copy(data.m_pos) },
					{ nav_seg, pos },
				}
			end
		end,
	},
})
