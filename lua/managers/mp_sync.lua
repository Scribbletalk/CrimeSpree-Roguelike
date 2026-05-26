-- Crime Spree Roguelike - Multiplayer sync backbone (the wire layer).
--
-- Ports the pre-refactor `CSR_MP` networking core to the U1 tree. Owns the
-- transport details ONLY: message ids, chunking, peer-role helpers, the item
-- codec, and the single NetworkReceivedData router. All persistent state lives
-- on managers.csr; this layer never stores run/peer data of its own.
--
-- SuperBLT transport note: LuaNetworking rides messages over chat
-- (ChatManagerOnReceiveMessageByPeer), so each payload is capped near ~237
-- bytes -- hence MAX_PAYLOAD + the chunked item protocol below.
--
-- Per-milestone handlers register via CSR_MP.register_handler(id, fn); the
-- router dispatches by id. The combat items (bonnie_chip, wolfs_toolbox,
-- shocking_surprise) register their receivers here too (M4) -- there is now a
-- single NetworkReceivedData hook in the whole mod.

-- Load-once guard: hooked on lib/entry, which can re-enter. Registering the
-- router twice is harmless (same Hooks id overwrites), but the guard keeps the
-- module idempotent and matches the reference.
local key = ModPath .. "\t" .. tostring(RequiredScript or "csr_mp_sync")
if _G[key] then
	return
else
	_G[key] = true
end

_G.CSR_MP = _G.CSR_MP or {}
local CSR_MP = _G.CSR_MP

-- Message ids (per-player protocol). The full set is declared up front so it
-- doesn't churn each milestone; handlers are wired in as milestones land.
CSR_MP.MSG = {
	HANDSHAKE = "CSR_Handshake", -- client -> host: {version} on join
	HANDSHAKE_OK = "CSR_HandshakeOK", -- host -> client: {version, host_rank, host_difficulty, run_seed}
	PLAYER_ITEMS = "CSR_PlayerItems", -- any peer -> all: own item counts (chunked)
	REQUEST_ALL = "CSR_RequestAll", -- client -> host: send me everyone's items
	ALL_PLAYERS = "CSR_AllPlayers", -- host -> joining client: every peer's items (chunked, "DONE" terminator)
	RANK_UP = "CSR_RankUp", -- host -> all: host rank advanced
	COPIER_SPAWN = "CSR_CopierSpawn", -- host -> all: spawn a printer (key~pos~rot~offer_type)
	SCRAPPER_SPAWN = "CSR_ScrapperSpawn", -- host -> all: spawn a scrapper (key~pos~rot)
	REQUEST_PROPS = "CSR_RequestProps", -- client -> host: replay every spawned prop (late-join)
	LOBBY_PING = "CSR_LobbyPing", -- client -> host: are you a CSR lobby? (join-time routing)
	LOBBY_CSR = "CSR_LobbyIsCSR", -- host -> client: yes -> reroute to crime_spree_lobby
	MISSION_SET = "CSR_MissionSet", -- host -> all: the lobby mission-card ids (comma-joined)
}

-- Combat-item RPCs route through the SAME router (they pass the "CSR_" id filter
-- below). The codec/payloads are owned by each item file; only the ids live here
-- for a single source of truth. Handlers register from the item files via
-- register_handler (they close over item-local helpers we don't see here).
CSR_MP.ITEM_MSG = {
	CHIP_KILL = "CSR_ChipKill", -- bonnie_chip: proc-kill position (play sound at peers)
	WOLF_KILL = "CSR_WolfKill", -- wolfs_toolbox: client kill -> host drill-timer reduction
	SHOCK = "CSR_ShockingSurprise", -- shocking_surprise: host -> in-range peer slows locally
}

-- Conservative per-payload byte budget (SuperBLT's chat transport caps ~237).
local MAX_PAYLOAD = 200

-- =====================================================
-- Debug log (routes through managers.csr's debug gate)
-- =====================================================
local function mp_log(msg)
	local mgr = managers and managers.csr
	if mgr and mgr.debug_enabled and mgr:debug_enabled() and mgr.debug_log then
		mgr:debug_log("[MP] " .. tostring(msg))
	end
end
CSR_MP.log = mp_log

-- =====================================================
-- Peer-role helpers
-- =====================================================

-- True when in any networked session. managers.network:session() is the
-- canonical check; SP and host-without-clients both report false here, which
-- is exactly what is_host() wants below.
function CSR_MP.is_multiplayer()
	return (managers and managers.network and managers.network:session()) and true or false
end

-- Host OR solo. Server-authoritative work gates on this so SP runs the same
-- path as the host.
function CSR_MP.is_host()
	return not CSR_MP.is_multiplayer() or Network:is_server()
end

-- A guest in someone else's lobby (never true in SP or as host).
function CSR_MP.is_client()
	return CSR_MP.is_multiplayer() and Network:is_client()
end

-- Local peer id (delegates to the manager's own resolver; 1 when standalone).
function CSR_MP.local_peer_id()
	local mgr = managers and managers.csr
	if mgr and mgr.local_peer_id then
		return mgr:local_peer_id()
	end
	return 1
end

-- Local convenience chat line (visible only to this client).
function CSR_MP.chat_message(text)
	if managers and managers.chat then
		managers.chat:_receive_message(1, "[CSR]", tostring(text), Color(1, 0.2, 0.8, 1))
	end
end

-- =====================================================
-- Chunking (protocol-agnostic; ported 1-to-1 from the reference)
-- =====================================================

-- Split an encoded payload body into chunks that each fit MAX_PAYLOAD after the
-- header + "IDX/TOTAL~" framing. `header` is the per-message prefix (e.g.
-- "PEER~NAME~"); `encoded` is "|"-delimited entries. Returns a list of ready
-- payload strings. An empty body still yields one "1/1~" chunk so the receiver
-- learns the peer has zero items.
function CSR_MP.build_chunked_payloads(header, encoded)
	local available = MAX_PAYLOAD - #header - 10 -- room for "IDX/TOTAL~"

	if encoded == "" then
		return { header .. "1/1~" }
	end

	local chunks = {}
	local current = ""
	for entry in string.gmatch(encoded, "[^|]+") do
		local test = current == "" and entry or (current .. "|" .. entry)
		if #test > available then
			if current ~= "" then
				table.insert(chunks, current)
			end
			current = entry
		else
			current = test
		end
	end
	if current ~= "" then
		table.insert(chunks, current)
	end

	local payloads = {}
	for i, chunk in ipairs(chunks) do
		table.insert(payloads, header .. tostring(i) .. "/" .. tostring(#chunks) .. "~" .. chunk)
	end
	return payloads
end

-- =====================================================
-- Item codec (U1 shape: { [type] = count })
-- =====================================================

-- Encode a peer's owned counts as "type:count|type:count|...". The "|"-sequence
-- is emitted in ACQUISITION ORDER (player_items_order), so the order survives the
-- wire for free and the receiver can render the remote peer's items in the same
-- order the owner sees them. Falls back to a plain count scan if the ordered
-- getter is unavailable. Zero/absent counts are skipped.
function CSR_MP.encode_items(peer_id)
	local mgr = managers and managers.csr
	local counts = (mgr and mgr.player_items and mgr:player_items(peer_id)) or {}
	local order = mgr and mgr.player_items_order and mgr:player_items_order(peer_id)
	local parts = {}
	if type(order) == "table" then
		for _, item_type in ipairs(order) do
			local n = counts[item_type]
			if type(n) == "number" and n > 0 then
				parts[#parts + 1] = item_type .. ":" .. tostring(n)
			end
		end
	else
		for item_type, n in pairs(counts) do
			if type(n) == "number" and n > 0 then
				parts[#parts + 1] = item_type .. ":" .. tostring(n)
			end
		end
	end
	return table.concat(parts, "|")
end

-- Parse "type:count|..." back into a { [type] = count } map PLUS the order array
-- (the sequence as parsed = the sender's acquisition order). Unknown/malformed
-- entries are skipped (the consumer still validates types against the registry).
-- Two returns; legacy callers reading only the first still work.
function CSR_MP.decode_items(encoded)
	local counts = {}
	local order = {}
	for pair in string.gmatch(encoded or "", "[^|]+") do
		local item_type, n = string.match(pair, "^([^:]+):(%d+)$")
		if item_type then
			counts[item_type] = tonumber(n)
			order[#order + 1] = item_type
		end
	end
	return counts, order
end

-- =====================================================
-- Handler registry + single NetworkReceivedData router
-- =====================================================

CSR_MP._handlers = CSR_MP._handlers or {}

-- Register a handler for one message id. fn(sender, data, sender_num, is_from_host).
-- Last registration wins (idempotent re-register on reload).
function CSR_MP.register_handler(id, fn)
	CSR_MP._handlers[id] = fn
end

Hooks:Add("NetworkReceivedData", "CSR_MP_Router", function(sender, id, data)
	if type(id) ~= "string" or id:sub(1, 4) ~= "CSR_" then
		return
	end
	local sender_num = tonumber(sender)
	local is_from_host = (sender_num == 1)
	mp_log("recv sender=" .. tostring(sender) .. " id=" .. id .. " len=" .. tostring(data and #data or 0))
	local handler = CSR_MP._handlers[id]
	if handler then
		handler(sender, data, sender_num, is_from_host)
	end
end)

-- =====================================================
-- M2: per-peer item visibility sync
-- =====================================================
--
-- Each peer broadcasts its own item counts; the host relays them so everyone
-- converges (a client's SendToPeers only reaches the host -- PD2's chat transport
-- gives a client GetPeers() == { host }). Received counts land in
-- managers.csr:set_remote_peer_items (runtime, never saved); the items panel reads
-- them back through player_items(). Own items are NEVER stored as remote -- we are
-- authoritative for ourselves (_state) and a stored echo would shadow it.

CSR_MP._items_buf = CSR_MP._items_buf or {} -- chunk reassembly, keyed "items_<pid>"

local function sanitize_name(name)
	return (name and tostring(name):gsub("~", "-")) or "Player"
end

local function local_peer_name()
	local nm = managers and managers.network
	local session = nm and nm.session and nm:session()
	local peer = session and session.local_peer and session:local_peer()
	return (peer and peer.name and peer:name()) or "Player"
end

-- Repaint whichever CSR items surface is currently up after a sync. No-op when
-- neither is built (e.g. outside the CSR lobby/briefing).
function CSR_MP.refresh_items_panel()
	local mcm = managers and managers.menu_component
	-- Lobby missions component.
	local comp = mcm and mcm._crime_spree_missions
	if comp and comp.refresh_for_rank_change then
		comp:refresh_for_rank_change()
	end
	-- Briefing component: the guest's items panel lives here (borrowed
	-- _populate_items_panel), NOT on _crime_spree_missions. _populate_items_panel
	-- self-guards on an unbuilt panel, so this is a safe no-op off the briefing.
	local brief = mcm and mcm._mission_briefing_gui
	if brief and brief._populate_items_panel then
		brief:_populate_items_panel()
	end
end

-- Any peer -> all: broadcast own item counts (chunked "pid~name~idx/total~items").
function CSR_MP.broadcast_own_items()
	if not CSR_MP.is_multiplayer() then
		return
	end
	local pid = CSR_MP.local_peer_id()
	local encoded = CSR_MP.encode_items(pid)
	local header = tostring(pid) .. "~" .. sanitize_name(local_peer_name()) .. "~"
	for _, payload in ipairs(CSR_MP.build_chunked_payloads(header, encoded)) do
		LuaNetworking:SendToPeers(CSR_MP.MSG.PLAYER_ITEMS, payload)
	end
	mp_log("broadcast_own_items pid=" .. tostring(pid) .. " '" .. encoded .. "'")
end

-- Client -> host: ask for every peer's items (on lobby open / join).
function CSR_MP.request_all_items()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.REQUEST_ALL, tostring(CSR_MP.local_peer_id()))
	mp_log("request_all_items")
end

-- Host -> one peer: every peer's items, then a "DONE" terminator. encode_items is
-- remote-aware (managers.csr:player_items), so it serialises remotes too.
function CSR_MP.send_all_players(target_pid)
	if not CSR_MP.is_host() or not target_pid then
		return
	end
	local mgr = managers and managers.csr
	if not mgr then
		return
	end
	local pids = { CSR_MP.local_peer_id() }
	if mgr.remote_peer_ids then
		for _, pid in ipairs(mgr:remote_peer_ids()) do
			pids[#pids + 1] = pid
		end
	end
	for _, pid in ipairs(pids) do
		local is_local = pid == CSR_MP.local_peer_id()
		local name =
			sanitize_name(is_local and local_peer_name() or (mgr.remote_peer_name and mgr:remote_peer_name(pid)))
		local header = tostring(pid) .. "~" .. name .. "~"
		for _, payload in ipairs(CSR_MP.build_chunked_payloads(header, CSR_MP.encode_items(pid))) do
			LuaNetworking:SendToPeer(target_pid, CSR_MP.MSG.ALL_PLAYERS, payload)
		end
	end
	LuaNetworking:SendToPeer(target_pid, CSR_MP.MSG.ALL_PLAYERS, "DONE")
	mp_log("send_all_players -> " .. tostring(target_pid) .. " (" .. #pids .. " peers)")
end

-- Reassemble a chunked items payload and apply it to the remote-peer store. The
-- REMOVED payload (peer disconnect) is auth-gated: only the host or the peer
-- removing itself may erase a record, so a forged "<victim>~~1/1~REMOVED" from a
-- malicious client is rejected.
local function handle_items_payload(sender, data, sender_num, is_from_host)
	local peer_str, name, idx_total, items_encoded = string.match(data, "^(%d+)~([^~]*)~(%d+/%d+)~(.*)$")
	if not peer_str then
		mp_log("handle_items_payload: parse fail '" .. tostring(data) .. "'")
		return
	end
	local peer_id = tonumber(peer_str)

	-- Never store/remove our OWN items via the remote path -- _state is authoritative.
	if peer_id == CSR_MP.local_peer_id() then
		return
	end

	local idx, total = string.match(idx_total, "(%d+)/(%d+)")
	idx, total = tonumber(idx), tonumber(total)
	local mgr = managers and managers.csr

	if items_encoded == "REMOVED" then
		sender_num = sender_num or tonumber(sender)
		if is_from_host == nil then
			is_from_host = (sender_num == 1)
		end
		local self_remove = sender_num and peer_id and (sender_num == peer_id)
		if not (is_from_host or self_remove) then
			mp_log("REJECT forged REMOVED for " .. tostring(peer_id) .. " from " .. tostring(sender_num))
			return
		end
		if mgr and mgr.remove_remote_peer then
			mgr:remove_remote_peer(peer_id)
		end
		CSR_MP._items_buf["items_" .. tostring(peer_id)] = nil
		CSR_MP.refresh_items_panel()
		return
	end

	local key = "items_" .. tostring(peer_id)
	local buf = CSR_MP._items_buf[key]
	if not buf then
		buf = { name = name, total = total, chunks = {} }
		CSR_MP._items_buf[key] = buf
	end
	if idx == 1 then
		buf.name = name
		buf.total = total
	end
	buf.chunks[idx] = items_encoded

	local filled = 0
	for i = 1, (buf.total or 0) do
		if buf.chunks[i] then
			filled = filled + 1
		end
	end
	if filled < (buf.total or 0) then
		return
	end

	local parts = {}
	for i = 1, buf.total do
		if buf.chunks[i] and buf.chunks[i] ~= "" then
			parts[#parts + 1] = buf.chunks[i]
		end
	end
	CSR_MP._items_buf[key] = nil

	local counts, order = CSR_MP.decode_items(table.concat(parts, "|"))
	if mgr and mgr.set_remote_peer_items then
		mgr:set_remote_peer_items(peer_id, counts, buf.name, order)
	end
	mp_log("applied items: peer " .. tostring(peer_id) .. " (" .. tostring(buf.name) .. ")")
	CSR_MP.refresh_items_panel()
end

-- Any peer's items. Host relays to the OTHER peers (clients can't reach each
-- other directly), refusing to relay a forged REMOVED.
CSR_MP.register_handler(CSR_MP.MSG.PLAYER_ITEMS, function(sender, data, sender_num, is_from_host)
	handle_items_payload(sender, data, sender_num, is_from_host)
	if not CSR_MP.is_host() then
		return
	end
	local relay_ok = true
	if string.find(data, "~REMOVED", 1, true) then
		local victim = tonumber(string.match(data, "^(%d+)~"))
		relay_ok = (sender_num == 1) or (victim ~= nil and sender_num == victim)
	end
	if not relay_ok then
		return
	end
	local session = managers.network and managers.network:session()
	if session and session.peers then
		for _, peer in pairs(session:peers() or {}) do
			local pid = peer and peer:id()
			if pid and pid ~= sender_num and pid ~= 1 then
				LuaNetworking:SendToPeer(pid, CSR_MP.MSG.PLAYER_ITEMS, data)
			end
		end
	end
end)

-- Host's full roster to a joining client (DONE = end of stream).
CSR_MP.register_handler(CSR_MP.MSG.ALL_PLAYERS, function(sender, data, sender_num, is_from_host)
	if not (CSR_MP.is_client() and is_from_host) then
		return
	end
	if data == "DONE" then
		mp_log("ALL_PLAYERS DONE")
		return
	end
	handle_items_payload(sender, data, sender_num, is_from_host)
end)

-- Client asked the host for everyone's items.
CSR_MP.register_handler(CSR_MP.MSG.REQUEST_ALL, function(sender, data, sender_num, is_from_host)
	if not CSR_MP.is_host() then
		return
	end
	CSR_MP.send_all_players(sender_num or tonumber(sender))
end)

-- Peer-removed cleanup. BaseNetworkSession is not loaded at lib/entry, so defer
-- the PostHook registration until it exists (checked each MenuUpdate, then the
-- deferral removes itself). Once installed the hook fires in menu AND in game.
local function register_peer_removed_hook()
	if CSR_MP._peer_removed_hooked then
		return
	end
	if not (BaseNetworkSession and BaseNetworkSession._on_peer_removed) then
		return
	end
	CSR_MP._peer_removed_hooked = true
	Hooks:PostHook(BaseNetworkSession, "_on_peer_removed", "CSR_MP_OnPeerRemoved", function(self, peer, peer_id, reason)
		if not peer_id then
			return
		end
		local mgr = managers and managers.csr
		if mgr and mgr.remove_remote_peer then
			mgr:remove_remote_peer(peer_id)
		end
		CSR_MP._items_buf["items_" .. tostring(peer_id)] = nil
		-- Host: tell the remaining peers to drop this one too.
		if CSR_MP.is_host() then
			LuaNetworking:SendToPeers(CSR_MP.MSG.PLAYER_ITEMS, tostring(peer_id) .. "~~1/1~REMOVED")
		end
		CSR_MP.refresh_items_panel()
		mp_log("peer removed: " .. tostring(peer_id))
	end)

	-- Host -> a peer that just entered OUR lobby: tell it this is a CSR lobby (so it
	-- reroutes to crime_spree_lobby) and push host rank/difficulty/seed so its lobby
	-- shows the HOST's values + is_guesting() turns true. HOST-DRIVEN, so it fires no
	-- matter HOW the guest arrived -- join-straight-into-lobby AND return-to-lobby
	-- between heists -- unlike the client-side on_enter_lobby ping, which a guest
	-- joining mid-heist (JOINED_GAME path) never triggers. _crime_spree_missions is
	-- the no-leak "we're in the CSR lobby" signal (absent in a vanilla lobby).
	Hooks:PostHook(BaseNetworkSession, "on_peer_entered_lobby", "CSR_MP_OnPeerEnteredLobby", function(self, peer)
		if not CSR_MP.is_host() then
			return
		end
		local mcm = managers and managers.menu_component
		if not (mcm and mcm._crime_spree_missions) then
			return
		end
		local pid = peer and peer.id and peer:id()
		if not pid then
			return
		end
		LuaNetworking:SendToPeer(pid, CSR_MP.MSG.LOBBY_CSR, "")
		if CSR_MP.broadcast_host_state then
			CSR_MP.broadcast_host_state()
		end
		mp_log("peer entered lobby -> pushed CSR + host state to " .. tostring(pid))
	end)
	mp_log("peer-removed hook registered")
end

Hooks:Add("MenuUpdate", "CSR_MP_DeferPeerRemoved", function()
	register_peer_removed_hook()
	if CSR_MP._peer_removed_hooked then
		Hooks:Remove("CSR_MP_DeferPeerRemoved")
	end
end)

-- =====================================================
-- M3: in-world prop spawn sync (printer / scrapper)
-- =====================================================
--
-- The host spawns props with World:spawn_unit, which is LOCAL (it does not
-- replicate), so each prop is mirrored to clients: the host broadcasts the
-- spawn, and every client spawns its OWN local copy at the synced pos/rot/offer
-- and registers it in its own globals. The interaction then runs locally against
-- that peer's own (guest-session) inventory -- a personal-roguelike exchange, no
-- host authority needed for the swap itself.
--
-- _prop_log is HOST-only: an ordered list of { msg_id, payload } replayed
-- verbatim to a late-joining client, so this layer stays agnostic of the
-- copier-vs-scrapper payload format (the spawner files own encode/decode +
-- the COPIER_SPAWN / SCRAPPER_SPAWN handlers + dedup).

CSR_MP._prop_log = CSR_MP._prop_log or {}

-- Host: broadcast a prop spawn to all peers AND log it for late-join replay.
-- Self-gates to host-in-a-session, so a client calling its own spawn path (which
-- ends in the SAME _spawn helper) never echoes. Logged even with zero clients
-- connected so a peer joining later still receives the full set.
function CSR_MP.broadcast_prop(msg_id, payload)
	if not (CSR_MP.is_multiplayer() and CSR_MP.is_host()) then
		return
	end
	CSR_MP._prop_log[#CSR_MP._prop_log + 1] = { msg_id = msg_id, payload = payload }
	LuaNetworking:SendToPeers(msg_id, payload)
	mp_log("broadcast_prop " .. tostring(msg_id) .. " '" .. tostring(payload) .. "'")
end

-- Client: ask the host to replay every prop spawned this heist (late-join catch-up).
function CSR_MP.request_props()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.REQUEST_PROPS, "")
	mp_log("request_props")
end

-- Host: a client asked for the prop set -> replay the log to that peer only.
-- Dedup on the client side (host unit key in the payload) means a peer that
-- already got the real-time broadcast safely ignores the replayed duplicate.
CSR_MP.register_handler(CSR_MP.MSG.REQUEST_PROPS, function(sender, data, sender_num, is_from_host)
	if not CSR_MP.is_host() then
		return
	end
	local target = sender_num or tonumber(sender)
	if not target then
		return
	end
	for _, rec in ipairs(CSR_MP._prop_log) do
		LuaNetworking:SendToPeer(target, rec.msg_id, rec.payload)
	end
	mp_log("replay props -> " .. tostring(target) .. " (" .. #CSR_MP._prop_log .. ")")
end)

-- Per-heist reset: host clears its log at load; client requests the host's set.
-- BaseNetworkSessionOnLoadComplete fires on every heist load for host AND client.
-- The host clears BEFORE its auto-spawn (which only fires later once nav is
-- ready), so the log only ever holds the current heist's props.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_MP_PropSyncReset", function()
	if CSR_MP.is_host() then
		CSR_MP._prop_log = {}
	end
	if CSR_MP.is_client() then
		CSR_MP.request_props()
	end
end)

-- =====================================================
-- Lobby join routing: client -> crime_spree_lobby
-- =====================================================
--
-- A CSR run does NOT enable the vanilla Crime Spree gamemode, so vanilla's
-- on_enter_lobby (which routes by gamemode) never sends a JOINING CLIENT to the
-- crime_spree_lobby node -- the client lands in the plain "lobby" node with no
-- CSR UI (the lobby component is built only on crime_spree_lobby). The host
-- reroutes itself via Global.CSR_RETURN_TO_LOBBY; the client has no such trigger.
-- Fix: on lobby entry the client pings the host; if the host is actually sitting
-- in a CSR lobby it replies, and the client reroutes. Chat transport is already
-- live in the lobby (item sync uses it), so no menu-attribute plumbing is needed.
-- (The briefing screen is unaffected -- briefing_sidebar.lua hooks MissionBriefingGui
-- directly, bypassing node routing, which is why the client's briefing already works.)

-- Client -> host: ask whether this is a CSR lobby. Called from on_enter_lobby
-- (lobby_routing.lua); self-gates so the host/SP calling it is a no-op.
function CSR_MP.lobby_ping_host()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.LOBBY_PING, "")
	mp_log("lobby_ping_host")
end

-- Client -> host: PULL the current host-state (rank/difficulty/seed/tokens). Used
-- on heist at_enter so the guest re-acquires host-state reliably via request-reply
-- instead of relying on the host's timed push landing in the load window. The host
-- replies HANDSHAKE_OK (mp_session.lua handler). A non-CSR host has no router and
-- ignores it, so the guest's host-state correctly stays cleared there (no leak).
function CSR_MP.request_host_state()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.HANDSHAKE, "")
	mp_log("request_host_state")
end

-- Host -> all: the lobby mission-card ids (comma-joined) so guests show the SAME 3
-- missions. Sent on every host-state broadcast (lobby join / HANDSHAKE reply) and
-- on host reroll (generate_mission_set). Self-gates to the host. Ids are short
-- alphanumeric keys, so a single unchunked message stays well under the transport cap.
function CSR_MP.broadcast_mission_set()
	if not (CSR_MP.is_host() and CSR_MP.is_multiplayer()) then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.mission_set_ids) then
		return
	end
	local joined = table.concat(mgr:mission_set_ids(), ",")
	LuaNetworking:SendToPeers(CSR_MP.MSG.MISSION_SET, joined)
	mp_log("broadcast_mission_set: " .. joined)
end

-- Client: store the host's mission-card ids and repaint the lobby cards in place
-- (CSRMissionsMenuComponent:update_mission -> btn:update_mission, the direct setter,
-- no reroll spin). is_from_host blocks forgery. No-op off the CSR lobby (no component).
CSR_MP.register_handler(CSR_MP.MSG.MISSION_SET, function(sender, data, sender_num, is_from_host)
	if not (CSR_MP.is_client() and is_from_host) then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.set_mp_host_mission_set) then
		return
	end
	local ids = {}
	for id in tostring(data):gmatch("[^,]+") do
		ids[#ids + 1] = id
	end
	mgr:set_mp_host_mission_set(ids)
	local comp = managers.menu_component and managers.menu_component._crime_spree_missions
	if comp and comp.update_mission then
		comp:update_mission()
	end
	mp_log("applied host mission set: " .. tostring(data))
end)

-- Host: a joining client asked -> reply ONLY if we're actually in the CSR lobby.
-- _crime_spree_missions exists solely on the crime_spree_lobby node, so it's a
-- no-leak signal (a vanilla lobby never has it, regardless of a stale is_active).
CSR_MP.register_handler(CSR_MP.MSG.LOBBY_PING, function(sender, data, sender_num, is_from_host)
	if not CSR_MP.is_host() then
		return
	end
	local mcm = managers and managers.menu_component
	if not (mcm and mcm._crime_spree_missions) then
		return
	end
	local target = sender_num or tonumber(sender)
	if target then
		LuaNetworking:SendToPeer(target, CSR_MP.MSG.LOBBY_CSR, "")
		mp_log("lobby ping -> CSR, reply to " .. tostring(target))
		-- Also push host rank/difficulty/seed NOW so the joining guest's lobby shows
		-- the HOST's rank + item quota (not its own) and is_guesting() turns true in
		-- the lobby. Without this the host only announces at heist start, leaving the
		-- guest lobby on its own rank. broadcast_host_state is assigned by mp_session.lua.
		if CSR_MP.broadcast_host_state then
			CSR_MP.broadcast_host_state()
		end
	end
end)

-- Client: the host confirmed a CSR lobby -> reroute to the crime_spree_lobby node
-- so the CSR lobby UI (sidebar + panels) builds. The actual select_node lives in
-- lobby_routing.lua (which owns node routing).
CSR_MP.register_handler(CSR_MP.MSG.LOBBY_CSR, function(sender, data, sender_num, is_from_host)
	if not (CSR_MP.is_client() and is_from_host) then
		return
	end
	if _G.CSR_reroute_client_to_csr_lobby then
		_G.CSR_reroute_client_to_csr_lobby()
	end
end)

mp_log("mp_sync backbone loaded")
