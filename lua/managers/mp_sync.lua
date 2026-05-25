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
-- router dispatches by id. Existing items (bonnie_chip, wolfs_toolbox,
-- shocking_surprise) keep their own NetworkReceivedData hooks for now -- they
-- work; consolidating them onto this router is a later cleanup.

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

-- Encode a peer's owned counts as "type:count|type:count|...". Pre-refactor
-- carried per-stack ids + levels; the U1 store is a plain count map, so this is
-- simpler. Zero/absent counts are skipped.
function CSR_MP.encode_items(peer_id)
	local mgr = managers and managers.csr
	local counts = (mgr and mgr.player_items and mgr:player_items(peer_id)) or {}
	local parts = {}
	for item_type, n in pairs(counts) do
		if type(n) == "number" and n > 0 then
			parts[#parts + 1] = item_type .. ":" .. tostring(n)
		end
	end
	return table.concat(parts, "|")
end

-- Parse "type:count|..." back into a { [type] = count } map. Unknown/malformed
-- entries are skipped (the consumer still validates types against the registry).
function CSR_MP.decode_items(encoded)
	local counts = {}
	for pair in string.gmatch(encoded or "", "[^|]+") do
		local item_type, n = string.match(pair, "^([^:]+):(%d+)$")
		if item_type then
			counts[item_type] = tonumber(n)
		end
	end
	return counts
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

mp_log("mp_sync backbone loaded")
