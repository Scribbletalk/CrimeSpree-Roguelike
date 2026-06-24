-- CSR native-RPC transport (csr_net_sc / csr_net_cs). Reserved for in-heist sync (phase 2).
-- Native RPCs silently drop in the pre-heist lobby; all lobby sync uses the chat tunnel instead.
-- See mp_sync.lua / mp_session.lua, and csr_native_network_messages_restoration.md.

-- Load-once guard. Literal token (not RequiredScript) to avoid key collision across lib/entry hooks.
-- See pd2_requiredscript_shared_hookid_dedup_collision.md.
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

-- Host sends _sc; client sends _cs. check= on each message enforces direction at engine level.
local function dir_msg()
	return (CSR_MP.is_host and CSR_MP.is_host()) and CSR_MP.NET_SC or CSR_MP.NET_CS
end

-- Broadcast to all connected peers (host -> all clients, or client -> host).
function CSR_MP.send_to_peers(msg_id, payload)
	local session = net_session()
	if not session then
		return
	end
	local ok, err = pcall(session.send_to_peers, session, dir_msg(), tostring(msg_id), tostring(payload or ""))
	if not ok then
		log("[CSR] send_to_peers failed (id=" .. tostring(msg_id) .. "): " .. tostring(err))
	end
end

-- Send to one peer by id.
function CSR_MP.send_to_peer(pid, msg_id, payload)
	local session = net_session()
	if not session or not session.peer then
		return
	end
	local peer = session:peer(pid)
	if not peer then
		return
	end
	local ok, err = pcall(session.send_to_peer, session, peer, dir_msg(), tostring(msg_id), tostring(payload or ""))
	if not ok then
		log("[CSR] send_to_peer failed (pid=" .. tostring(pid) .. " id=" .. tostring(msg_id) .. "): " .. tostring(err))
	end
end

-- Single dispatch for both native handlers. Same (sender, data, sender_num, is_from_host) contract
-- as the chat router so handlers are transport-agnostic.
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
		local ok, err = pcall(handler, sender_num, payload, sender_num, is_from_host)
		if not ok then
			log("[CSR] native handler error (id=" .. tostring(msg_id) .. "): " .. tostring(err))
		end
	end
end
