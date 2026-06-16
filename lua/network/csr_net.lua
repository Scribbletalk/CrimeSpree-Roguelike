-- CSR native-RPC transport (csr_net_sc / csr_net_cs, registered by csr_network_tweak.xml).
-- RESERVED FOR IN-HEIST sync (phase 2). Native session RPCs do NOT deliver in the pre-heist
-- lobby: send returns ok=true for ANY message name — even an unregistered one — yet nothing is
-- received (confirmed via probe + zero RECV on both unit and connection receivers). So all
-- lobby-phase sync (host-state / handshake / mission-set) rides the SuperBLT chat tunnel instead
-- (see mp_sync.lua / mp_session.lua). Restoration likewise never sends a native message in the
-- lobby — every native send there gates on any_ingame. See csr_native_network_messages_restoration.md.

-- Unique literal token: RequiredScript is the shared hook path ("lib/entry"), so a key built
-- from it collides with every other lib/entry hook (mp_sync ran first, starving this file).
local key = ModPath .. "\tcsr_net"
if _G[key] then
	return
else
	_G[key] = true
end

_G.CSR_MP = _G.CSR_MP or {}
local CSR_MP = _G.CSR_MP
CSR_MP._handlers = CSR_MP._handlers or {}

-- Native message ids (must match csr_network_tweak.xml).
CSR_MP.NET_SC = "csr_net_sc" -- server -> client
CSR_MP.NET_CS = "csr_net_cs" -- client -> server

local function net_session()
	return managers and managers.network and managers.network:session()
end

local function log_mp(msg)
	if CSR_MP.log then
		CSR_MP.log(msg)
	end
end

-- Host owns the server->client message; everyone else owns client->server. The check= guard on
-- each message means the engine only accepts _sc from the host and _cs from a client.
local function dir_msg()
	return (CSR_MP.is_host and CSR_MP.is_host()) and CSR_MP.NET_SC or CSR_MP.NET_CS
end

-- Broadcast to every connected peer (host -> all clients, or client -> host).
function CSR_MP.send_to_peers(msg_id, payload)
	local session = net_session()
	if not session then
		return
	end
	csr_log("[CSR][mptest][native] send_to_peers id=" .. tostring(msg_id))
	pcall(session.send_to_peers, session, dir_msg(), tostring(msg_id), tostring(payload or ""))
end

-- Send to one peer by id (host -> a client, or client -> host, whose id is 1).
function CSR_MP.send_to_peer(pid, msg_id, payload)
	local session = net_session()
	if not session or not session.peer then
		return
	end
	local peer = session:peer(pid)
	if not peer then
		return
	end
	csr_log("[CSR][mptest][native] send_to_peer pid=" .. tostring(pid) .. " id=" .. tostring(msg_id))
	pcall(session.send_to_peer, session, peer, dir_msg(), tostring(msg_id), tostring(payload or ""))
end

-- Single dispatch point for both native handlers. Mirrors the chat router's
-- (sender, data, sender_num, is_from_host) handler contract so handlers are transport-agnostic.
function CSR_MP.dispatch_native(msg_id, payload, sender_num, is_from_host)
	if type(msg_id) ~= "string" then
		return
	end
	log_mp(
		"native recv id="
			.. msg_id
			.. " from="
			.. tostring(sender_num)
			.. " len="
			.. tostring(payload and #payload or 0)
	)
	local handler = CSR_MP._handlers[msg_id]
	if handler then
		handler(sender_num, payload, sender_num, is_from_host)
	end
end
