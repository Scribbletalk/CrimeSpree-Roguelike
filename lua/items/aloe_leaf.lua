-- Aloe Leaf (common): stand still to bloom a heal zone at your feet, healing you + nearby allies.
-- Each peer detects its own standstill; owner self-heals, host heals everyone else (PD2 health is
-- owner-authoritative). See csr_aloe_leaf_item_plan.md for the full authority/network design.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

-- Balance constants (also feed the $-macros in the localized effect text).
local STILL_THRESHOLD = 1.0 -- seconds still before the zone blooms
local AURA_RADIUS = 300 -- PD2 units (1m = 100)
local HEAL_BASE = 0.02 -- max HP/sec at 1 stack
local HEAL_PER_STACK = 0.01 -- +per extra copy (linear)
local HEAL_CAP = 1.00 -- max HP/sec ceiling
local HEAL_TICK = 1.0 -- seconds between heal pulses

-- Standstill / visual tuning.
local STILL_EPS = 0 -- zero tolerance: any movement disarms
local GROW_TIME = 0.5 -- seconds to grow 0 -> AURA_RADIUS, then hold
local AURA_ALPHA = 0.06 -- held zone opacity (opacity_add blend)
local HEARTBEAT_TIMEOUT = HEAL_TICK * 1.6 -- remote zone expires this long after last AURA_PULSE
local ALLY_VOLUME = 0.25 -- bloom cue is quieter for allies than the owner

-- File-locals shared by every hook closure (file is dofile'd once).
local still_t = 0
local last_pos = nil
local next_heal_t = 0
local aura_active = false
local aura_start_t = 0
local remote_auras = {} -- [owner_pid] = { start_t = <game time>, last_seen = <game time> }

-- =====================================================
-- Helpers
-- =====================================================

local function gtime()
	return TimerManager:game():time()
end

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

local function local_peer_id()
	local mgr = managers and managers.csr
	return (mgr and mgr.local_peer_id and mgr:local_peer_id()) or 1
end

local function is_host()
	return _G.CSR_MP and CSR_MP.is_host and CSR_MP.is_host() or false
end

-- Stack count -> heal fraction of max HP per tick.
local function heal_pct_for(count)
	local pct = HEAL_BASE + (math.max(1, count) - 1) * HEAL_PER_STACK
	return math.min(HEAL_CAP, pct)
end

-- Heal the local player (authoritative for own health); skips if heal-blocked or downed/custody.
local function heal_local_player(pct)
	if managers.csr and managers.csr:item_heal_blocked() then
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
	if (cdmg.is_downed and cdmg:is_downed()) or (cdmg.arrested and cdmg:arrested()) then
		return -- no aura-revive while downed/arrested
	end
	pcall(cdmg.restore_health, cdmg, pct, false)
end

-- Heal one NPC ally (CopDamage/TeamAIDamage/SentryGunDamage share the _HEALTH_INIT/_health shape).
local function heal_npc(cd, pct)
	if not cd or cd._dead or cd._fatal then
		return
	end
	local max_hp = cd._HEALTH_INIT
	if not max_hp or max_hp <= 0 or not cd._health then
		return
	end
	cd._health = math.min(max_hp, cd._health + max_hp * pct)
	cd._health_ratio = cd._health / max_hp
end

local function in_radius(unit, center)
	if not (alive(unit) and unit:movement()) then
		return false
	end
	return mvector3.distance(unit:movement():m_pos(), center) <= AURA_RADIUS
end

-- Resolve a peer_id to its player_unit (local player, or husk for a remote peer).
local function peer_player_unit(pid)
	if pid == local_peer_id() then
		return managers.player and managers.player:player_unit()
	end
	local session = managers.network and managers.network:session()
	local peer = session and session.peer and session:peer(pid)
	return peer and peer.unit and peer:unit() or nil
end

-- Mark/refresh a remote owner's zone heartbeat. A new owner (or one past the timeout) restarts the
-- grow animation; otherwise just bump last_seen to keep it holding.
local function mark_remote_aura(pid)
	local t = gtime()
	local a = remote_auras[pid]
	if not a or (t - (a.last_seen or 0)) > HEARTBEAT_TIMEOUT then
		remote_auras[pid] = { start_t = t, last_seen = t } -- fresh bloom on this machine
		if _G.CSR and _G.CSR.play_sound then
			_G.CSR.play_sound("aloe_leaf_activate", { volume = ALLY_VOLUME })
		end
	else
		a.last_seen = t
	end
end

-- Draw the heal zone: a translucent disc growing 0 -> AURA_RADIUS over GROW_TIME, then holding.
local function draw_aura(pos, elapsed)
	local progress = math.min(1, (elapsed or 0) / GROW_TIME)
	local radius = AURA_RADIUS * progress
	local alpha = AURA_ALPHA * progress
	local brush = Draw:brush(Color(alpha, 0.4, 0.85, 0.5))
	brush:set_blend_mode("opacity_add")
	brush:cylinder(pos, pos + Vector3(0, 0, 6), radius)
end

local function send_aura_heal(peer_id, pct)
	if not (LuaNetworking and _G.CSR_MP and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.AURA_HEAL) then
		return
	end
	pcall(function()
		LuaNetworking:SendToPeer(peer_id, CSR_MP.ITEM_MSG.AURA_HEAL, tostring(pct))
	end)
end

-- Host authority: heal every ally in radius except the owner (self-heals locally), and fan the zone
-- heartbeat (AURA_PULSE) to all peers. Remote humans self-heal on a ping; bots/jokers/turrets the
-- host heals directly.
local function host_heal_others(center, pct, owner_pid)
	if not is_host() then
		return
	end
	local session = managers.network and managers.network:session()

	-- Heartbeat: tell all peers the owner's zone is live (a host-owner draws its own zone, so skip self).
	if session and LuaNetworking and _G.CSR_MP and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.AURA_PULSE then
		pcall(function()
			LuaNetworking:SendToPeers(CSR_MP.ITEM_MSG.AURA_PULSE, tostring(owner_pid))
		end)
	end
	if owner_pid ~= local_peer_id() then
		mark_remote_aura(owner_pid)
	end

	-- Host's own player (only if the host isn't the owner — owner already self-healed).
	if owner_pid ~= local_peer_id() then
		local pu = managers.player and managers.player:player_unit()
		if pu and in_radius(pu, center) then
			heal_local_player(pct)
		end
	end

	-- Remote human peers in radius (skip the owner; they self-healed locally).
	if session and session.peers then
		for _, peer in pairs(session:peers()) do
			local u = peer:unit()
			if peer:id() ~= owner_pid and alive(u) and in_radius(u, center) then
				send_aura_heal(peer:id(), pct)
			end
		end
	end

	-- AI bots / converted jokers / player turrets in radius (host-simulated allies).
	local groupai = managers.groupai and managers.groupai:state()
	if not groupai then
		return
	end
	for _, record in pairs(groupai:all_criminals() or {}) do
		if record.ai and alive(record.unit) and in_radius(record.unit, center) then
			heal_npc(record.unit:character_damage(), pct)
		end
	end
	for _, unit in pairs(groupai._converted_police or {}) do
		if alive(unit) and in_radius(unit, center) then
			heal_npc(unit:character_damage(), pct)
		end
	end
	for _, unit in pairs(groupai:turrets() or {}) do
		if alive(unit) and unit:base() and unit:base()._owner_id and in_radius(unit, center) then
			heal_npc(unit:character_damage(), pct)
		end
	end
end

-- One heal pulse, fired on the owner's machine each HEAL_TICK while the zone is armed.
local function do_heal_tick()
	local mgr = csr_mgr()
	if not mgr then
		return
	end
	local count = mgr:owned("aloe_leaf")
	if count <= 0 then
		return
	end
	local pu = managers.player and managers.player:player_unit()
	if not (alive(pu) and pu:movement()) then
		return
	end
	local pct = heal_pct_for(count)
	local pos = pu:movement():m_pos()

	-- 1. Owner self-heals locally (own health is authoritative on this machine).
	heal_local_player(pct)
	-- 2. Heal every other ally in radius via the host authority (also fans the zone heartbeat).
	if is_host() then
		host_heal_others(pos, pct, local_peer_id())
	elseif LuaNetworking and _G.CSR_MP and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.AURA_REQ then
		pcall(function()
			LuaNetworking:SendToPeer(1, CSR_MP.ITEM_MSG.AURA_REQ, tostring(pct))
		end)
	end
end

-- =====================================================
-- MP handlers (registered once, both roles; bodies gate on role)
-- =====================================================

local mp_registered = false
local function ensure_mp_handler()
	if mp_registered then
		return
	end
	if
		not (
			_G.CSR_MP
			and CSR_MP.register_handler
			and CSR_MP.ITEM_MSG
			and CSR_MP.ITEM_MSG.AURA_HEAL
			and CSR_MP.ITEM_MSG.AURA_REQ
			and CSR_MP.ITEM_MSG.AURA_PULSE
		)
	then
		return
	end
	mp_registered = true

	-- host -> all: zone heartbeat for an owner (skip our own — we draw it locally).
	CSR_MP.register_handler(CSR_MP.ITEM_MSG.AURA_PULSE, function(sender, data, sender_num, is_from_host)
		if not is_from_host or not csr_mgr() then
			return
		end
		local pid = tonumber(data)
		if not pid or pid == local_peer_id() then
			return
		end
		mark_remote_aura(pid)
	end)

	-- host -> a remote ally in radius: heal your own player by pct.
	CSR_MP.register_handler(CSR_MP.ITEM_MSG.AURA_HEAL, function(sender, data, sender_num, is_from_host)
		if not is_from_host or not csr_mgr() then
			return
		end
		heal_local_player(tonumber(data) or HEAL_BASE)
	end)

	-- client owner -> host: run the aura around the owner's husk position (host authority).
	CSR_MP.register_handler(CSR_MP.ITEM_MSG.AURA_REQ, function(sender, data, sender_num, is_from_host)
		if not (is_host() and csr_mgr()) then
			return
		end
		local session = managers.network and managers.network:session()
		local peer = session and session.peer and session:peer(sender_num)
		local u = peer and peer:unit()
		if not (alive(u) and u:movement()) then
			return
		end
		pcall(host_heal_others, u:movement():m_pos(), tonumber(data) or HEAL_BASE, sender_num)
	end)
end

-- =====================================================
-- One-time global hooks (standstill tick, zone draw, per-heist reset)
-- =====================================================

local function reset_state()
	still_t = 0
	last_pos = nil
	next_heal_t = 0
	aura_active = false
	aura_start_t = 0
	remote_auras = {}
end

-- Owner-local standstill detector + heal-tick scheduler. Any movement resets the timer and disarms.
local function tick(t, dt)
	ensure_mp_handler()
	local mgr = csr_mgr()
	if not mgr then
		still_t, last_pos, aura_active = 0, nil, false
		return
	end
	local pu = managers.player and managers.player:player_unit()
	if not (alive(pu) and pu:movement()) then
		still_t, last_pos, aura_active = 0, nil, false
		return
	end
	if (mgr:owned("aloe_leaf") or 0) <= 0 then
		still_t, last_pos, aura_active = 0, nil, false
		return
	end

	local pos = pu:movement():m_pos()
	if last_pos and mvector3.distance(pos, last_pos) > STILL_EPS then
		still_t = 0 -- moved at all -> disarm immediately
		aura_active = false
	else
		still_t = still_t + (dt or 0)
	end
	last_pos = mvector3.copy(pos)

	if still_t < STILL_THRESHOLD then
		aura_active = false -- not armed yet
		return
	end
	if not aura_active then
		aura_active = true -- just bloomed -> start the grow animation
		aura_start_t = gtime()
		if _G.CSR and _G.CSR.play_sound then
			_G.CSR.play_sound("aloe_leaf_activate", { volume = 0.5 }) -- owner volume
		end
	end
	if t >= next_heal_t then
		next_heal_t = t + HEAL_TICK
		pcall(do_heal_tick)
	end
end

local function install_global_hooks()
	if _G._CSR_ALOE_LEAF_GLOBAL_HOOKED then
		return
	end
	_G._CSR_ALOE_LEAF_GLOBAL_HOOKED = true

	Hooks:Add("GameSetupUpdate", "CSR_AloeLeaf_Tick", function(t, dt)
		pcall(tick, t, dt)
	end)

	-- Zone draw: owner's zone at its live feet, plus every remote owner's at their husk pos (heartbeat-fed).
	Hooks:Add("GameSetupUpdate", "CSR_AloeLeaf_AuraDraw", function(t, dt)
		local now = gtime()
		if aura_active then
			local pu = managers.player and managers.player:player_unit()
			if alive(pu) and pu:movement() then
				draw_aura(pu:movement():m_pos(), now - aura_start_t)
			end
		end
		for pid, a in pairs(remote_auras) do
			if now - (a.last_seen or 0) > HEARTBEAT_TIMEOUT then
				remote_auras[pid] = nil
			else
				local u = peer_player_unit(pid)
				if alive(u) and u:movement() then
					draw_aura(u:movement():m_pos(), now - (a.start_t or now))
				end
			end
		end
	end)

	-- Per-heist reset (fires on all peers at load).
	Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_AloeLeaf_Reset", function()
		pcall(reset_state)
	end)
end

-- =====================================================
-- Registration
-- =====================================================

_G.CSR.register_item({
	type = "aloe_leaf",
	rarity = "common",
	name = "csr_logbook_aloe_leaf_name",
	desc = "csr_item_aloe_leaf_desc",
	full_desc = "csr_logbook_aloe_leaf_effect",
	notes = "csr_logbook_aloe_leaf_notes",
	icon = "csr_aloe_leaf",
	icon_scale = 1.1,

	-- $still_s / $aura_radius / $heal_pct / $per_stack_pct / $cap_pct fill csr_logbook_aloe_leaf_effect.
	loc_macros = {
		still_s = string.format("%g", STILL_THRESHOLD),
		aura_radius = string.format("%gm", AURA_RADIUS / 100),
		heal_pct = string.format("%g", HEAL_BASE * 100),
		per_stack_pct = string.format("%g", HEAL_PER_STACK * 100),
		cap_pct = string.format("%g", HEAL_CAP * 100),
	},

	hooks = {
		["lib/managers/playermanager"] = function()
			-- PlayerManager always loads, so installing the global hooks from here is safe.
			install_global_hooks()
		end,
	},
})
