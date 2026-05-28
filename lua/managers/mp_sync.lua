-- CSR MP wire layer. Message ids, chunked codec, single NetworkReceivedData router,
-- peer-role helpers, item-counts sync, prop sync, lobby-join routing, mission-set sync.
-- All persistent state lives on managers.csr; this layer never stores run/peer data.
-- See csr_mp_architecture.md for the full protocol.
--
-- SuperBLT transport: LuaNetworking rides chat, ~237-byte payload cap → MAX_PAYLOAD
-- + chunking. Multiple item RPCs (bonnie_chip / wolfs_toolbox / shocking_surprise)
-- register handlers here too — one router for the whole mod.

-- Load-once guard (lib/entry can re-enter).
local key = ModPath .. "\t" .. tostring(RequiredScript or "csr_mp_sync")
if _G[key] then
	return
else
	_G[key] = true
end

_G.CSR_MP = _G.CSR_MP or {}
local CSR_MP = _G.CSR_MP

CSR_MP.MSG = {
	HANDSHAKE = "CSR_Handshake", -- client -> host: pull request
	HANDSHAKE_OK = "CSR_HandshakeOK", -- host -> client: full host state (json)
	PLAYER_ITEMS = "CSR_PlayerItems", -- any peer -> all: own item counts (chunked)
	REQUEST_ALL = "CSR_RequestAll", -- client -> host: send me everyone's items
	ALL_PLAYERS = "CSR_AllPlayers", -- host -> joining client: full roster ("DONE" terminator)
	RANK_UP = "CSR_RankUp", -- host -> all: host rank advanced
	COPIER_SPAWN = "CSR_CopierSpawn", -- host -> all: spawn printer (key~pos~rot~offer)
	SCRAPPER_SPAWN = "CSR_ScrapperSpawn", -- host -> all: spawn scrapper (key~pos~rot)
	REQUEST_PROPS = "CSR_RequestProps", -- client -> host: replay every prop (late-join)
	LOBBY_PING = "CSR_LobbyPing", -- client -> host: is this a CSR lobby?
	LOBBY_CSR = "CSR_LobbyIsCSR", -- host -> client: yes; reroute
	MISSION_SET = "CSR_MissionSet", -- host -> all: lobby mission card ids (comma-joined)
}

-- Combat-item RPC ids — handlers registered from each item file via register_handler.
CSR_MP.ITEM_MSG = {
	CHIP_KILL = "CSR_ChipKill",
	WOLF_KILL = "CSR_WolfKill",
	SHOCK = "CSR_ShockingSurprise",
}

local MAX_PAYLOAD = 200

-- =====================================================
-- Debug log
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

function CSR_MP.is_multiplayer()
	return (managers and managers.network and managers.network:session()) and true or false
end

-- Host or solo (server-authoritative work gates on this).
function CSR_MP.is_host()
	return not CSR_MP.is_multiplayer() or Network:is_server()
end

function CSR_MP.is_client()
	return CSR_MP.is_multiplayer() and Network:is_client()
end

function CSR_MP.local_peer_id()
	local mgr = managers and managers.csr
	if mgr and mgr.local_peer_id then
		return mgr:local_peer_id()
	end
	return 1
end

function CSR_MP.chat_message(text)
	if managers and managers.chat then
		managers.chat:_receive_message(1, "[CSR]", tostring(text), Color(1, 0.2, 0.8, 1))
	end
end

-- =====================================================
-- Chunking
-- =====================================================

-- Split a "|"-delimited body into chunks that fit MAX_PAYLOAD after header + "IDX/TOTAL~".
-- Empty body still yields one "1/1~" chunk so the receiver learns the peer has zero items.
function CSR_MP.build_chunked_payloads(header, encoded)
	local available = MAX_PAYLOAD - #header - 10

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
-- Item codec — "type:count|type:count|..." in acquisition order
-- =====================================================

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

-- Handler signature: fn(sender, data, sender_num, is_from_host).
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

-- Repaint whichever CSR items surface is currently up (lobby or briefing).
function CSR_MP.refresh_items_panel()
	local mcm = managers and managers.menu_component
	local comp = mcm and mcm._crime_spree_missions
	if comp and comp.refresh_for_rank_change then
		comp:refresh_for_rank_change()
	end
	-- Briefing items panel lives on _mission_briefing_gui, not _crime_spree_missions.
	local brief = mcm and mcm._mission_briefing_gui
	if brief and brief._populate_items_panel then
		brief:_populate_items_panel()
	end
end

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

function CSR_MP.request_all_items()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.REQUEST_ALL, tostring(CSR_MP.local_peer_id()))
	mp_log("request_all_items")
end

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

-- Reassemble chunks + apply. REMOVED rejected unless from host or from the victim.
local function handle_items_payload(sender, data, sender_num, is_from_host)
	local peer_str, name, idx_total, items_encoded = string.match(data, "^(%d+)~([^~]*)~(%d+/%d+)~(.*)$")
	if not peer_str then
		mp_log("handle_items_payload: parse fail '" .. tostring(data) .. "'")
		return
	end
	local peer_id = tonumber(peer_str)

	-- Never store/remove our OWN items via remote path; _state is authoritative.
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

-- Host relays to OTHER peers (clients can't reach each other). Forged REMOVED filtered.
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

CSR_MP.register_handler(CSR_MP.MSG.REQUEST_ALL, function(sender, data, sender_num, is_from_host)
	if not CSR_MP.is_host() then
		return
	end
	CSR_MP.send_all_players(sender_num or tonumber(sender))
end)

-- BaseNetworkSession is unloaded at lib/entry; defer the PostHook registration.
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
		if CSR_MP.is_host() then
			LuaNetworking:SendToPeers(CSR_MP.MSG.PLAYER_ITEMS, tostring(peer_id) .. "~~1/1~REMOVED")
		end
		CSR_MP.refresh_items_panel()
		mp_log("peer removed: " .. tostring(peer_id))
	end)

	-- Host -> new peer: this is a CSR lobby + push host state. Fires for all entry
	-- paths (join-straight-into-lobby AND return-to-lobby between heists), unlike the
	-- client-side on_enter_lobby ping which a mid-heist joiner never triggers.
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
-- World:spawn_unit is LOCAL — host broadcasts, each client spawns its own copy
-- and registers it locally. _prop_log is host-only for late-join replay.

CSR_MP._prop_log = CSR_MP._prop_log or {}

-- Host: broadcast + log for late-join replay. Self-gates to host; logged even with
-- zero clients so a later joiner gets the full set.
function CSR_MP.broadcast_prop(msg_id, payload)
	if not (CSR_MP.is_multiplayer() and CSR_MP.is_host()) then
		return
	end
	CSR_MP._prop_log[#CSR_MP._prop_log + 1] = { msg_id = msg_id, payload = payload }
	LuaNetworking:SendToPeers(msg_id, payload)
	mp_log("broadcast_prop " .. tostring(msg_id) .. " '" .. tostring(payload) .. "'")
end

function CSR_MP.request_props()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.REQUEST_PROPS, "")
	mp_log("request_props")
end

-- Replay; client dedups on host unit key.
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

-- Per-heist reset: host clears log; client requests host's set.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_MP_PropSyncReset", function()
	if CSR_MP.is_host() then
		CSR_MP._prop_log = {}
	end
	if CSR_MP.is_client() then
		CSR_MP.request_props()
	end
end)

-- =====================================================
-- Lobby-join routing + host-state pull + mission-set sync
-- =====================================================
-- Vanilla on_enter_lobby routes by gamemode; CSR never enables CS gamemode, so a
-- joining client lands in the empty "lobby" node with no CSR UI. Client pings host
-- on lobby entry; host replies LOBBY_CSR if in CSR lobby.

function CSR_MP.lobby_ping_host()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.LOBBY_PING, "")
	mp_log("lobby_ping_host")
end

-- Client PULL of current host-state — makes in-heist re-acquire reliable instead of
-- depending on the host's timed push landing in the load window.
function CSR_MP.request_host_state()
	if not CSR_MP.is_client() then
		return
	end
	LuaNetworking:SendToPeer(1, CSR_MP.MSG.HANDSHAKE, "")
	mp_log("request_host_state")
end

-- Host -> all: lobby mission ids (comma-joined; short, no chunking needed).
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

-- Client: in-place repaint of mission cards (no reroll spin). is_from_host blocks forgery.
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

-- Host: reply only if actually in the CSR lobby. _crime_spree_missions is the
-- no-leak signal (absent in a vanilla lobby).
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
		-- Also push host state NOW so the guest's lobby shows host rank + is_guesting() turns true.
		if CSR_MP.broadcast_host_state then
			CSR_MP.broadcast_host_state()
		end
	end
end)

-- Client: host confirmed CSR -> reroute. The actual select_node lives in lobby_routing.lua.
CSR_MP.register_handler(CSR_MP.MSG.LOBBY_CSR, function(sender, data, sender_num, is_from_host)
	if not (CSR_MP.is_client() and is_from_host) then
		return
	end
	if _G.CSR_reroute_client_to_csr_lobby then
		_G.CSR_reroute_client_to_csr_lobby()
	end
end)

mp_log("mp_sync backbone loaded")
