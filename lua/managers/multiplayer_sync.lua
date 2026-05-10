local key = ModPath .. "\t" .. RequiredScript
if _G[key] then
	return
else
	_G[key] = true
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR MP] " .. tostring(msg))
	end
end

-- Message IDs (per-player protocol v2)
local MSG = {
	HANDSHAKE = "CSR_Handshake",
	HANDSHAKE_OK = "CSR_HandshakeOK",
	PLAYER_ITEMS = "CSR_PlayerItems2", -- peer sends own items to all
	REQUEST_ALL = "CSR_RequestAll", -- client asks host for all players' items
	ALL_PLAYERS = "CSR_AllPlayers", -- host sends all players' items (chunked)
	RANK_UP = "CSR_RankUp",
	FORCED_MODS = "CSR_ForcedMods",
	TIMER_START = "CSR_TimerStart",
	TOKEN_AWARD = "CSR_TokenAward", -- host -> all peers: per-heist tokens granted
	TOKEN_STATE = "CSR_TokenState", -- host -> joining peer: full token state on handshake
	CATCHUP_GRANT = "CSR_CatchupGrant", -- host -> joining peer: catchup item list + leftover wallet
	ASSAULT_END = "CSR_AssaultEnd", -- host -> all peers: assault ended (Crooked Badge revive trigger)
	LOCKES_HEAL = "CSR_LockesHeal", -- any peer -> all peers: 30s Locke's Beret pulse, payload = sender's stacks
	OATH_HEAL = "CSR_OathHeal", -- host -> client: Hippocratic Oath aura tick, client heals self locally
}

-- Max bytes per network payload (conservative; SuperBLT limit is ~237)
local MAX_PAYLOAD = 200

_G.CSR_MP = _G.CSR_MP or {}
CSR_MP.MSG = MSG
CSR_MP.is_mp_session = false
CSR_MP._synced_peers = CSR_MP._synced_peers or {}
CSR_MP._items_buf = CSR_MP._items_buf or {}

----------------------------------------------
-- RECOVER MP STATE FROM SESSION FILE AFTER LUA RELOAD
----------------------------------------------
-- Lua reloads during heist->end screen transitions wipe all globals.
-- seed_manager.lua (loaded earlier) stashes recovered values in globals.
if Network and Network:is_client() then
	if _G.CSR_MP_SessionTotalDrops and not _G.CSR_MP_TotalDrops then
		_G.CSR_MP_TotalDrops = _G.CSR_MP_SessionTotalDrops
		CSR_log("Recovered CSR_MP_TotalDrops=" .. tostring(_G.CSR_MP_SessionTotalDrops) .. " from session file")
		CSR_MP.is_mp_session = true
	end
	if _G.CSR_MP_SessionRunSeed then
		_G.CSR_MP_RunSeed = _G.CSR_MP_SessionRunSeed
		CSR_log("Recovered CSR_MP_RunSeed=" .. tostring(_G.CSR_MP_SessionRunSeed) .. " from session file")
	end
end

----------------------------------------------
-- UTILITY (unchanged)
----------------------------------------------

function CSR_MP.is_multiplayer()
	if managers.network and managers.network:session() then
		return true
	end
	-- Fallback: session may be temporarily nil during loading transitions
	return CSR_MP.is_mp_session == true
end

function CSR_MP.is_host()
	return not CSR_MP.is_multiplayer() or Network:is_server()
end

function CSR_MP.is_client()
	return CSR_MP.is_multiplayer() and Network:is_client()
end

function CSR_MP.local_peer_id()
	local session = managers.network and managers.network:session()
	local peer = session and session:local_peer()
	if peer then
		CSR_MP._cached_peer_id = peer:id()
		return peer:id()
	end
	-- Fallback: use cached ID during loading transitions
	return CSR_MP._cached_peer_id or 0
end

-- Send a chat message (local, visible only to this client)
function CSR_MP.chat_message(text)
	if managers.chat then
		managers.chat:_receive_message(1, "[CSR]", text, Color(0.2, 0.8, 1))
	end
end

----------------------------------------------
-- HELPERS
----------------------------------------------

-- Refresh a UI page instance (items tab, printer tab) with alive check.
-- Clears the global if the panel is dead (stale reference after component recreation).
local function refresh_ui_instance(global_name, method_name)
	local inst = _G[global_name]
	if not inst or type(inst[method_name]) ~= "function" then
		return
	end
	if type(inst.panel) == "function" then
		local ok, p = pcall(inst.panel, inst)
		if ok and p and alive(p) then
			pcall(function()
				inst[method_name](inst)
			end)
		else
			_G[global_name] = nil
		end
	end
end

-- Sanitize player name for use in delimited payloads (replace ~ delimiter)
local function sanitize_name(name)
	return name and string.gsub(name, "~", "-") or "Player"
end

-- Split an encoded items string into chunks that fit within MAX_PAYLOAD.
-- header: "PEER~NAME~" prefix.  Returns a list of payload strings ready to send.
local function build_chunked_payloads(header, encoded)
	local available = MAX_PAYLOAD - #header - 10 -- room for "IDX/TOTAL~"

	if encoded == "" then
		return { header .. "1/1~" }
	end

	local chunks = {}
	local current = ""
	for item_str in string.gmatch(encoded, "[^|]+") do
		local test = current == "" and item_str or (current .. "|" .. item_str)
		if #test > available then
			if current ~= "" then
				table.insert(chunks, current)
			end
			current = item_str
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

-- Calculate total item drops a player should have at the current rank
-- Only counts milestone drops (rank / 20). Bonus drops are host-only
-- and handled separately by the host's modifiers_to_select logic.
function CSR_MP._get_total_drops()
	local rank = managers.crime_spree and managers.crime_spree:spree_level() or 0
	return math.floor(rank / 20)
end

----------------------------------------------
-- SENDING
----------------------------------------------

-- Any peer broadcasts their own items to all other peers
function CSR_MP.broadcast_own_items()
	if not CSR_MP.is_multiplayer() then
		return
	end

	local peer_id = CSR_MP.local_peer_id()
	local encoded = CSR_EncodeItems(peer_id)
	local data = _G.CSR_PlayerItems[peer_id]
	local name = sanitize_name(data and data.name)

	local header = tostring(peer_id) .. "~" .. name .. "~"
	local payloads = build_chunked_payloads(header, encoded)

	for _, payload in ipairs(payloads) do
		LuaNetworking:SendToPeers(MSG.PLAYER_ITEMS, payload)
	end
end

-- Host sends all players' items to a specific peer (on late join)
function CSR_MP.send_all_players(target_peer_id)
	if not CSR_MP.is_host() then
		return
	end

	for peer_id, data in pairs(_G.CSR_PlayerItems) do
		local encoded = CSR_EncodeItems(peer_id)
		local name = sanitize_name(data.name or ("Player " .. peer_id))
		local header = tostring(peer_id) .. "~" .. name .. "~"
		local payloads = build_chunked_payloads(header, encoded)

		for _, payload in ipairs(payloads) do
			LuaNetworking:SendToPeer(target_peer_id, MSG.ALL_PLAYERS, payload)
		end
	end

	-- Terminator so client knows all players have been sent
	LuaNetworking:SendToPeer(target_peer_id, MSG.ALL_PLAYERS, "DONE")
end

-- Host broadcasts forced mods notification to all clients
function CSR_MP.broadcast_forced_mods(mods_to_add)
	if not CSR_MP.is_host() or not CSR_MP.is_multiplayer() then
		return
	end
	local parts = {}
	for _, mod in ipairs(mods_to_add) do
		table.insert(parts, tostring(mod.id) .. ":" .. tostring(mod.level or 0))
	end
	local payload = table.concat(parts, "|")
	CSR_log("Broadcasting forced mods (" .. #mods_to_add .. " mods): " .. payload)
	LuaNetworking:SendToPeers(MSG.FORCED_MODS, payload)
end

-- Host broadcasts rank update to all clients (includes total_drops for item tracking)
function CSR_MP.broadcast_rank_up(new_rank)
	if not CSR_MP.is_host() or not CSR_MP.is_multiplayer() then
		return
	end
	-- Only milestone drops (rank / 20). Bonus drops are host-only.
	local total_drops = math.floor(new_rank / 20)
	CSR_log("Broadcasting rank up: " .. tostring(new_rank) .. " total_drops=" .. tostring(total_drops))
	LuaNetworking:SendToPeers(MSG.RANK_UP, tostring(new_rank) .. "|" .. tostring(total_drops))
end

-- Client sends handshake to host on connect
function CSR_MP.send_handshake()
	if not CSR_MP.is_client() then
		return
	end
	local payload = json.encode({
		version = _G.CSR_MOD_VERSION or "unknown",
	})
	CSR_log("Sending handshake to host (peer 1), version=" .. tostring(_G.CSR_MOD_VERSION))
	LuaNetworking:SendToPeer(1, MSG.HANDSHAKE, payload)
end

----------------------------------------------
-- MESSAGE HANDLERS
----------------------------------------------

-- Handle incoming player items (from PLAYER_ITEMS or ALL_PLAYERS messages).
-- Parse: "PEER~NAME~IDX/TOTAL~items..."
-- sender_num + is_from_host are forwarded from the dispatch site so we can
-- authenticate REMOVED payloads — they must come from the host (legitimate
-- _on_peer_removed path) or the peer self-removing. Without this, any peer
-- could craft "<victim_id>~~1/1~REMOVED" and wipe another peer's record on
-- every receiver, including being relayed by the host to the rest of the lobby.
function CSR_MP._handle_player_items(sender, data, sender_num, is_from_host)
	local peer_str, name, idx_total, items_encoded = string.match(data, "^(%d+)~([^~]*)~(%d+/%d+)~(.*)$")
	if not peer_str then
		CSR_log("_handle_player_items: failed to parse data: '" .. tostring(data) .. "'")
		return
	end

	local peer_id = tonumber(peer_str)
	local idx, total = string.match(idx_total, "(%d+)/(%d+)")
	idx = tonumber(idx)
	total = tonumber(total)

	-- Handle REMOVED payload (peer disconnected) — auth-gated.
	if items_encoded == "REMOVED" then
		sender_num = sender_num or tonumber(sender)
		if is_from_host == nil then
			is_from_host = (sender_num == 1)
		end
		local is_self_remove = sender_num and peer_id and (sender_num == peer_id)
		if not (is_from_host or is_self_remove) then
			CSR_log(
				"_handle_player_items: REJECTED REMOVED for peer "
					.. tostring(peer_id)
					.. " from non-authoritative sender "
					.. tostring(sender_num)
			)
			return
		end
		CSR_log("_handle_player_items: peer " .. tostring(peer_id) .. " removed (auth ok)")
		if CSR_RemovePeer then
			CSR_RemovePeer(peer_id)
		end
		-- Refresh UI tabs
		refresh_ui_instance("CSR_ItemsPageInstance", "_setup_items")
		refresh_ui_instance("CSR_PrinterPageInstance", "_setup_printer")
		return
	end

	-- Buffer chunks (init on any chunk index to handle out-of-order delivery)
	local key = "items_" .. tostring(peer_id)
	if not CSR_MP._items_buf[key] then
		CSR_MP._items_buf[key] = { name = name, chunks = {}, total = total }
	end
	local buf = CSR_MP._items_buf[key]
	-- Update name/total from chunk 1 (most authoritative)
	if idx == 1 then
		buf.name = name
		buf.total = total
	end

	buf.chunks[idx] = items_encoded

	-- Check if all chunks received (explicit count — # is unreliable on sparse tables)
	local filled = 0
	for i = 1, buf.total do
		if buf.chunks[i] then
			filled = filled + 1
		end
	end
	if filled < buf.total then
		return
	end

	-- Reassemble in order
	local parts = {}
	for i = 1, buf.total do
		if buf.chunks[i] and buf.chunks[i] ~= "" then
			table.insert(parts, buf.chunks[i])
		end
	end
	local full_encoded = table.concat(parts, "|")

	local items = CSR_DecodeItems(full_encoded)

	local existing = _G.CSR_PlayerItems[peer_id]
	CSR_SetPeerItems(
		peer_id,
		items,
		buf.name,
		existing and existing.rank or 0,
		existing and existing.difficulty or _G.CSR_CurrentDifficulty
	)

	CSR_MP._items_buf[key] = nil

	CSR_log(
		"_handle_player_items: peer " .. tostring(peer_id) .. " (" .. buf.name .. ") now has " .. #items .. " items"
	)

	-- Refresh UI tabs (items arrival may enable the printer Exchange button)
	refresh_ui_instance("CSR_ItemsPageInstance", "_setup_items")
	refresh_ui_instance("CSR_PrinterPageInstance", "_setup_printer")
end

-- Handle ALL_PLAYERS message (from host to late-joining client)
-- Same format as PLAYER_ITEMS but uses "DONE" terminator
function CSR_MP._handle_all_players(sender, data)
	if data == "DONE" then
		CSR_log("_handle_all_players: received DONE terminator — all players synced")
		return
	end

	-- For own items: only skip if we have items locally (authoritative).
	-- If local items were wiped (transition glitch), accept host's version as recovery.
	local peer_str = string.match(data, "^(%d+)~")
	if peer_str then
		local peer_id = tonumber(peer_str)
		local session = managers.network and managers.network:session()
		local local_peer = session and session:local_peer()
		local my_id = local_peer and local_peer:id()
		if peer_id == my_id then
			local my_items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
			if #my_items > 0 then
				CSR_log("_handle_all_players: skipping own items (local has " .. #my_items .. " items)")
				return
			end
			CSR_log("_handle_all_players: accepting own items from host (local was empty)")
		end
	end

	-- Reuse the same parsing logic
	CSR_MP._handle_player_items(sender, data)
end

-- Handle HANDSHAKE_OK from host (client only)
function CSR_MP._handle_handshake_ok(data)
	local ok, payload = pcall(json.decode, data)
	if not ok or not payload then
		CSR_log("_handle_handshake_ok: failed to decode payload")
		return
	end

	CSR_MP.is_mp_session = true
	_G.CSR_MP_HostRank = payload.rank
	_G.CSR_MP_HostDifficulty = payload.difficulty
	_G.CSR_CurrentDifficulty = payload.difficulty or "overkill"

	-- Auto-create minimal CS state for clients without their own CS run, now
	-- that HANDSHAKE_OK has confirmed the host is running CSR. Previously the
	-- in_progress() override did this speculatively for any client in any MP
	-- session, which leaked CSR state into vanilla heists. By moving it here,
	-- we only mutate state once we KNOW we're in a CSR session.
	-- TaheyaKinnie 2026-05-10.
	local cs_mgr = managers.crime_spree
	if cs_mgr and cs_mgr._global and not cs_mgr._global.in_progress then
		CSR_log("HANDSHAKE_OK: client has no own CS — auto-creating minimal state")
		cs_mgr._global.in_progress = true
		cs_mgr._global.spree_level = 0
		cs_mgr._global.reward_level = 0
		cs_mgr._global.modifiers = cs_mgr._global.modifiers or {}
		_G.CSR_MP_NeedsAutoCreate = true
	end

	-- Force client's engine difficulty to match host's CSR-mapped difficulty.
	-- Vanilla's load-level handshake sets Global.game_settings.difficulty on first
	-- join, but on REJOIN after a crash the client's prior cached value can survive
	-- and the engine sync doesn't always overwrite it. The host-only branch in
	-- _setup_global_from_mission_id never runs on clients, so without this explicit
	-- write the rejoining client keeps spawning enemies at the stale HP scale.
	-- Only Global.game_settings.difficulty drives enemy HP on the client; the
	-- selected_difficulty fields (CLAUDE.md Critical Rule 3) are inputs to the
	-- host-side resolver and intentionally NOT touched here — overwriting them
	-- would corrupt the client's own paused CS run's difficulty setting.
	-- BanditGrey 2026-05-04: client crashed at CS rank 635 on Death Wish, rejoined
	-- with enemy HP feeling like Overkill.
	local host_diff = payload.difficulty or "overkill"
	local engine_id = (_G.CSR_DifficultyMap and _G.CSR_DifficultyMap[host_diff]) or "normal"
	local prev_engine = Global.game_settings and Global.game_settings.difficulty or "?"
	if Global.game_settings then
		Global.game_settings.difficulty = engine_id
	end
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(
			"[CSR MP Diff] handshake_ok: host_diff="
				.. tostring(host_diff)
				.. " engine_id="
				.. tostring(engine_id)
				.. " prev_engine="
				.. tostring(prev_engine)
		)
	end

	local run_seed = payload.run_seed
	_G.CSR_MP_RunSeed = run_seed
	local total_drops = payload.total_drops or 0
	_G.CSR_MP_TotalDrops = total_drops
	local my_items_count = #(CSR_GetLocalItems and CSR_GetLocalItems() or {})

	CSR_log(
		"_handle_handshake_ok: rank="
			.. tostring(payload.rank)
			.. " difficulty="
			.. tostring(payload.difficulty)
			.. " run_seed="
			.. tostring(run_seed)
			.. " total_drops="
			.. tostring(total_drops)
			.. " my_items="
			.. tostring(my_items_count)
	)

	-- Auto-create CS for client if flagged by in_progress override
	if _G.CSR_MP_NeedsAutoCreate then
		_G.CSR_MP_NeedsAutoCreate = nil
		local host_diff = payload.difficulty or "overkill"
		CSR_log("_handle_handshake_ok: completing auto-creation — generating seed at difficulty=" .. host_diff)
		local cs = managers.crime_spree
		if cs and cs._global then
			cs._global.winning_streak = 0
		end

		-- Generate seed and write to the REAL seed file (not _mp.txt)
		local seed = os.time() + math.floor(math.random() * 1000000)
		local seed_file_path = SavePath .. "crime_spree_seed.txt"
		local f = io.open(seed_file_path, "w")
		if f then
			f:write(tostring(seed) .. "\n")
			f:write(tostring(host_diff) .. "\n")
			f:write(tostring(_G.CSR_MOD_VERSION or "alpha-2.0.0") .. "\n")
			f:write("0\n") -- Line 4: mission_selection_level
			f:write("\n") -- Line 5: forced modifiers
			f:write("\n") -- Line 6: player items
			f:write("0.01|0\n") -- Line 7: bonus chance|drop count
			-- Lines 8-13: written even on a fresh client auto-create so a
			-- subsequent CSR_LoadSeed sees explicit zeros instead of nil.
			-- Without these, a Lua reload before the session JSON catches up
			-- silently zeroes the client's tokens / shop_bought / catchup_budget.
			f:write("\n") -- Line 8: printer state (tier~offer_prefix; empty = none)
			f:write("0\n") -- Line 9: Gage Tokens balance
			f:write("\n") -- Line 10: Gage Shop state
			f:write("0\n") -- Line 11: local peer's Gage Shop purchase count
			f:write("0\n") -- Line 12: host cumulative tokens earned
			f:write("0\n") -- Line 13: local peer's catchup_received_budget
			f:close()
			CSR_log("_handle_handshake_ok: wrote seed file: seed=" .. seed .. " difficulty=" .. host_diff)
		end
		_G.CSR_CurrentSeed = seed
		_G.CSR_CurrentDifficulty = host_diff

		-- Regenerate forced modifiers pool for the new seed
		if _G.CSR_RegenerateForcedModifiers then
			CSR_RegenerateForcedModifiers(seed, host_diff)
		end

		-- Notify client
		local diff_display = host_diff:upper():gsub("_", " ")
		CSR_MP.chat_message(
			string.format(
				managers.localization:text("csr_mp_auto_created") or "Crime Spree created at %s difficulty!",
				diff_display
			)
		)

		_G.CSR_MP_AutoCreatedCS = true
		CSR_log("_handle_handshake_ok: auto-created CS done")
	end

	-- Check for reconnect (restore items from previous session with same seed).
	-- Only restore if session file has MORE items than we currently have
	-- (prevents overwriting items selected between duplicate handshakes).
	local session_matches_run = false
	if run_seed and CSR_LookupSession then
		local session = CSR_LookupSession(run_seed)
		if session and session.my_items then
			session_matches_run = true
			if #session.my_items > my_items_count then
				local prev_count = my_items_count
				local restored = session.my_items
				CSR_InitLocalPlayer(restored, payload.rank, nil, nil)
				my_items_count = #restored
				CSR_log(
					"_handle_handshake_ok: restored "
						.. my_items_count
						.. " items from session file (had "
						.. prev_count
						.. " before)"
				)
			end
			-- Restore Gage Tokens for this seed. CSR_InitLocalPlayer resets tokens
			-- to 0, so write them back directly on the struct here after init.
			if session.my_tokens and _G.CSR_PlayerItems then
				local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
				local data = _G.CSR_PlayerItems[local_peer]
				if data then
					data.tokens = session.my_tokens
					CSR_log("_handle_handshake_ok: restored " .. tostring(data.tokens) .. " Gage Tokens")
				end
			end

			-- Restore Gage Shop state for this seed (chests + last_purchased).
			if session.my_shop and CSR_ShopDeserializeFromJson then
				CSR_ShopDeserializeFromJson(session.my_shop)
				CSR_log("_handle_handshake_ok: restored Gage Shop state")
			end
		end
		-- Restore printer-use counters from the same session entry.
		-- CRITICAL: do NOT call send_threshold_message here. Session restore must be silent.
		if session and session.printer_uses then
			_G.CSR_PrinterUses = {}
			for pid_str, count in pairs(session.printer_uses) do
				local pid = tonumber(pid_str)
				if pid then
					_G.CSR_PrinterUses[pid] = count
				end
			end
			CSR_log("_handle_handshake_ok: restored printer uses from session file")
		end
		-- Restore this player's Gage Shop purchase counter so milestone
		-- accounting continues to exclude their prior shop buys after rejoin.
		if session and session.my_shop_bought and session.my_shop_bought > 0 then
			local pid = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			_G.CSR_ShopItemsBought = _G.CSR_ShopItemsBought or {}
			_G.CSR_ShopItemsBought[pid] = session.my_shop_bought
			CSR_log(
				"_handle_handshake_ok: restored shop_bought=" .. tostring(session.my_shop_bought) .. " for peer " .. pid
			)
		end
		-- Same restore for catchup grant counter so the milestone exclusion
		-- survives a Lua reload (the catchup itself only fires once per run).
		if session and session.my_catchup_received and session.my_catchup_received > 0 then
			local pid = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			_G.CSR_CatchupItemsReceived = _G.CSR_CatchupItemsReceived or {}
			_G.CSR_CatchupItemsReceived[pid] = session.my_catchup_received
			CSR_log(
				"_handle_handshake_ok: restored catchup_received="
					.. tostring(session.my_catchup_received)
					.. " for peer "
					.. pid
			)
		end
		-- Restore host cumulative tokens earned (needed by clients to compute their
		-- own late-join catchup delta after a game restart).
		if session and session.my_host_earned then
			if CSR_TokensManager then
				CSR_TokensManager.set_host_earned(session.my_host_earned)
				CSR_log(
					"_handle_handshake_ok: restored host_earned=" .. tostring(session.my_host_earned) .. " from session"
				)
			end
		end
		-- Restore local peer's catchup_received_budget so the host's snapshot
		-- is correct after a restart (prevents double-granting on rejoin).
		if session and session.my_catchup_budget then
			local pid = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[pid]
			if pdata then
				pdata.catchup_received_budget = session.my_catchup_budget
				CSR_log(
					"_handle_handshake_ok: restored catchup_budget="
						.. tostring(session.my_catchup_budget)
						.. " for peer "
						.. pid
				)
			end
		end
	end

	-- Guard: clear stale items from a different run.
	-- seed_manager may load items from a previous session (keyed by date, not seed)
	-- before the handshake arrives. If no session matches this run_seed, those items
	-- belong to a different run and must be cleared — regardless of count.
	if my_items_count > 0 and not session_matches_run then
		CSR_log(
			"_handle_handshake_ok: clearing "
				.. my_items_count
				.. " stale items (no session for seed "
				.. tostring(run_seed)
				.. ")"
		)
		CSR_InitLocalPlayer({}, payload.rank, nil, nil)
		my_items_count = 0
	end

	-- Item selection: lobby = let client pick, mid-heist = auto-fill
	local deficit = total_drops - my_items_count
	if deficit > 0 then
		local is_in_heist = Global.game_settings and Global.game_settings.is_playing
		if is_in_heist then
			-- Late join mid-heist: defer auto-fill so the host's CATCHUP_GRANT
			-- (sent on a 1s DelayedCall after HANDSHAKE) can land first. Without
			-- this delay the joiner would auto-fill `total_drops` items, then
			-- apply_grant would add catchup shop items on top — total exceeds
			-- the intended count. Recompute deficit at fire time using the
			-- post-grant item count.
			local local_pid = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			DelayedCalls:Add("CSR_AutoFillAfterCatchup", 2.5, function()
				local current_count = (CSR_GetLocalItems and #CSR_GetLocalItems()) or 0
				local recomputed_deficit = total_drops - current_count
				if recomputed_deficit > 0 then
					CSR_AutoFillItems(recomputed_deficit, run_seed, local_pid)
					CSR_MP.chat_message("You received " .. recomputed_deficit .. " items to catch up")
					CSR_log(
						"_handle_handshake_ok: auto-filled "
							.. recomputed_deficit
							.. " items (late join, post-catchup recompute)"
					)
				else
					CSR_log("_handle_handshake_ok: deficit closed by CATCHUP_GRANT, no auto-fill needed")
				end
			end)
		else
			-- In lobby: "Select Items" / "Auto-Fill" buttons appear via client_select_button.lua
			-- The update PostHook detects CSR_MP_HostRank being set and triggers a rebuild
			CSR_log("_handle_handshake_ok: " .. deficit .. " items to select (lobby)")
		end
	end

	-- Set vanilla peer spree level so server_spree_level() returns host's rank.
	-- Clamp to at least the client's own rank so the "Crime Spree Suspended"
	-- warning never appears (it triggers when server_spree_level < spree_level).
	if managers.crime_spree then
		local host_rank = payload.rank or 0
		local local_rank = managers.crime_spree:spree_level() or 0
		managers.crime_spree:set_peer_spree_level(1, math.max(host_rank, local_rank))
	end

	-- Version mismatch warning
	local host_version = payload.version or "unknown"
	local my_version = _G.CSR_MOD_VERSION or "unknown"
	if host_version ~= my_version then
		if managers.chat then
			managers.chat:_receive_message(
				1,
				"[CSR]",
				"Version mismatch! Host: " .. tostring(host_version) .. ", yours: " .. tostring(my_version),
				tweak_data.system_chat_color
			)
		end
	end

	-- Broadcast our items to all peers
	CSR_MP.broadcast_own_items()

	-- Request all other players' items from host
	LuaNetworking:SendToPeer(1, MSG.REQUEST_ALL, tostring(CSR_LocalPeerId()))

	-- Save session locally for reconnect support.
	-- Save under BOTH run_seed and CSR_CurrentSeed so reload recovery finds it.
	if CSR_SaveSession then
		local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		if run_seed then
			CSR_SaveSession(run_seed, nil, items, total_drops)
		end
		if _G.CSR_CurrentSeed and tostring(_G.CSR_CurrentSeed) ~= tostring(run_seed) then
			CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, total_drops)
		end
	end

	-- Refresh CS lobby header
	if managers.menu_component and managers.menu_component._crime_spree_details then
		pcall(function()
			managers.menu_component._crime_spree_details:perform_update()
		end)
	end

	CSR_MP.chat_message("Synced with host: rank " .. tostring(payload.rank))
end

-- Apply forced mods notification from host and show popup
function CSR_MP.apply_forced_mods(payload)
	CSR_log("apply_forced_mods: payload='" .. tostring(payload) .. "'")
	if not payload or payload == "" then
		return
	end
	local mods = {}
	for entry in payload:gmatch("[^|]+") do
		local mod_id, level_str = entry:match("^(.+):(%d+)$")
		if mod_id then
			table.insert(mods, { id = mod_id, level = tonumber(level_str) or 0 })
		end
	end
	if #mods == 0 then
		return
	end

	-- Add mods to server_modifiers so Modifiers tab shows them
	if managers.crime_spree then
		for _, mod in ipairs(mods) do
			if mod.id then
				pcall(function()
					managers.crime_spree:set_server_modifier(mod.id, mod.level or 0, false)
				end)
				if mod.level and mod.level > (_G.CSR_LastShownForcedLevel or 0) then
					_G.CSR_LastShownForcedLevel = mod.level
				end
			end
		end
	end

	-- Show popup notification (same as host sees)
	DelayedCalls:Add("CSR_ClientForcedModsPopup", 0.5, function()
		if _G.CSR_ShowForcedModsPopup then
			CSR_ShowForcedModsPopup(mods)
		end
	end)
end

-- Apply rank update from host
function CSR_MP.apply_rank_up(new_rank, total_drops)
	CSR_log("apply_rank_up: " .. tostring(new_rank) .. " (was " .. tostring(_G.CSR_MP_HostRank) .. ")")
	_G.CSR_MP_HostRank = new_rank

	-- Use host-provided total_drops (includes host's bonus drops which the client doesn't track).
	-- Fall back to rank-based-only calculation if total_drops not provided (old format compat).
	-- Do NOT add CSR_BonusDropCount here — that counter is host-only state. On a
	-- client carrying stale value from a prior run, it inflated the pending-item
	-- count and the end screen showed phantom drops.
	if total_drops then
		_G.CSR_MP_TotalDrops = total_drops
	else
		_G.CSR_MP_TotalDrops = math.floor(new_rank / 20)
	end
	CSR_log("apply_rank_up: total_drops now " .. tostring(_G.CSR_MP_TotalDrops))

	-- Refresh end screen component so _setup PostHook fires with updated pending count.
	-- Delayed to let the menu system finish any in-progress node transitions.
	DelayedCalls:Add("CSR_RefreshEndScreen", 0.3, function()
		if _G.CSR_RefreshEndScreenComponent then
			_G.CSR_RefreshEndScreenComponent()
		end
	end)

	-- Persist to session file so values survive Lua reload (heist->end screen transition).
	-- Save under BOTH run_seed (for reconnect) and CSR_CurrentSeed (for reload recovery).
	-- The client's local seed differs from the host's run_seed.
	if CSR_SaveSession then
		local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		local td = _G.CSR_MP_TotalDrops
		if _G.CSR_MP_RunSeed then
			CSR_SaveSession(_G.CSR_MP_RunSeed, nil, items, td)
		end
		if _G.CSR_CurrentSeed and tostring(_G.CSR_CurrentSeed) ~= tostring(_G.CSR_MP_RunSeed) then
			CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, td)
		end
	end

	-- Update vanilla peer_spree_levels[1] so server_spree_level() returns the host's actual rank
	if managers.crime_spree then
		managers.crime_spree:set_peer_spree_level(1, new_rank)
	end

	-- Refresh CS lobby header if it exists
	if managers.menu_component and managers.menu_component._crime_spree_details then
		pcall(function()
			managers.menu_component._crime_spree_details:perform_update()
		end)
	end
end

----------------------------------------------
-- MAIN MESSAGE ROUTER
----------------------------------------------

Hooks:Add("NetworkReceivedData", "CSR_MultiplayerSync", function(sender, id, data)
	-- Log all CSR messages
	if id and type(id) == "string" and id:sub(1, 4) == "CSR_" then
		CSR_log(
			"NetworkReceivedData: sender="
				.. tostring(sender)
				.. " id="
				.. tostring(id)
				.. " data_len="
				.. tostring(data and #data or 0)
		)
	end

	local sender_num = tonumber(sender)
	local is_from_host = (sender_num == 1)

	-- === HOST receives handshake from client ===
	if id == MSG.HANDSHAKE and CSR_MP.is_host() then
		CSR_log("Received HANDSHAKE from peer " .. tostring(sender))

		-- Mark peer as verified (cancel auto-kick timer in csr_matchmaking.lua).
		-- csr_matchmaking writes the table with a numeric key (peer:id()), so
		-- clear with sender_num — clearing with the raw `sender` string left the
		-- entry alive and the auto-kick fired on legitimately-handshaked CSR clients.
		if _G.CSR_PendingVerification then
			_G.CSR_PendingVerification[sender_num] = nil
		end

		local ok, payload = pcall(json.decode, data)
		local client_version = ok and payload and payload.version or "unknown"

		-- Warn if version mismatch
		local host_version = _G.CSR_MOD_VERSION or "unknown"
		if client_version ~= host_version then
			local session = managers.network and managers.network:session()
			local peer = session and session:peer(sender)
			local peer_name = peer and peer:name() or "Peer " .. tostring(sender)
			local warn_msg = peer_name
				.. " has CSR "
				.. tostring(client_version)
				.. " (host: "
				.. tostring(host_version)
				.. ")"
			if managers.chat then
				managers.chat:_receive_message(1, "[CSR]", warn_msg, tweak_data.system_chat_color)
			end
		end

		-- Send enriched HandshakeOK with rank, difficulty, seed, total drops
		CSR_log("Sending HANDSHAKE_OK to peer " .. tostring(sender))
		LuaNetworking:SendToPeer(
			sender,
			MSG.HANDSHAKE_OK,
			json.encode({
				version = _G.CSR_MOD_VERSION or "unknown",
				rank = managers.crime_spree and managers.crime_spree:spree_level() or 0,
				difficulty = _G.CSR_CurrentDifficulty or "overkill",
				run_seed = _G.CSR_CurrentSeed or 0,
				total_drops = CSR_MP._get_total_drops(),
			})
		)

		-- Send all players' items after short delay
		DelayedCalls:Add("CSR_AllPlayers_Peer" .. tostring(sender), 1, function()
			CSR_MP.send_all_players(sender)
			-- Also send printer state to late joiner
			if CSR_PrinterSendToPeer then
				CSR_PrinterSendToPeer(sender)
			end
			-- Also send all printer use counters to late joiner
			if CSR_PrinterSendUsesToPeer then
				CSR_PrinterSendUsesToPeer(sender)
			end
			-- Replay the current heist's auto-spawned copier so the late
			-- joiner sees the same machine in the same spot as everyone else.
			if _G.CSR_CopierSendToPeer then
				CSR_CopierSendToPeer(sender)
			end
			-- Same idea for the scrapper auto-spawn(s) — replay every scrapper
			-- the host has standing this heist so late-joiners see them too.
			if _G.CSR_ScrapperSendToPeer then
				CSR_ScrapperSendToPeer(sender)
			end
			-- Seed the joiner's token state before issuing the catchup grant
			-- so they have the canonical earned counter when the grant arrives.
			if Network and Network:is_server() and CSR_TokensManager then
				-- Ensure the joiner has a pdata record on host before run_for_peer
				-- (their PLAYER_ITEMS may not have arrived yet). Without this, the
				-- catchup early-returns with WARN and the joiner gets nothing.
				_G.CSR_PlayerItems = _G.CSR_PlayerItems or {}
				if not _G.CSR_PlayerItems[sender_num] then
					log("[CSR JOIN] late-join: creating placeholder pdata for joiner peer=" .. tostring(sender_num))
					_G.CSR_PlayerItems[sender_num] = {
						items = {},
						name = "Player " .. tostring(sender_num),
						rank = 0,
						difficulty = _G.CSR_CurrentDifficulty or "overkill",
						tokens = 0,
					}
				end
				local host_earned = CSR_TokensManager.get_host_earned()
				local joiner_wallet = CSR_TokensManager.get_wallet(sender_num)
				log(
					"[CSR JOIN] late-join token seed: peer="
						.. tostring(sender_num)
						.. " host_earned="
						.. tostring(host_earned)
						.. " joiner_wallet="
						.. tostring(joiner_wallet)
				)
				local token_payload = tostring(joiner_wallet) .. "|" .. tostring(host_earned)
				if LuaNetworking and CSR_MP and CSR_MP.MSG and CSR_MP.MSG.TOKEN_STATE then
					LuaNetworking:SendToPeer(sender, CSR_MP.MSG.TOKEN_STATE, token_payload)
					log("[CSR JOIN] late-join: sent TOKEN_STATE to peer=" .. tostring(sender))
				end
				if CSR_LateJoinCatchup and CSR_LateJoinCatchup.run_for_peer then
					-- Pass the original `sender` value (same one TOKEN_STATE uses) so
					-- SuperBLT dispatches CATCHUP_GRANT identically — round-tripping
					-- through tonumber/tostring has been observed to drop the message.
					CSR_LateJoinCatchup.run_for_peer(sender_num, sender)
				else
					log("[CSR JOIN] late-join: WARN CSR_LateJoinCatchup.run_for_peer missing")
				end
			end
		end)
		return
	end

	-- === CLIENT receives handshake OK from host ===
	if id == MSG.HANDSHAKE_OK and CSR_MP.is_client() and is_from_host then
		CSR_log("Received HANDSHAKE_OK from host")
		CSR_MP._handle_handshake_ok(data)
		return
	end

	-- === Any peer receives another peer's items ===
	if id == MSG.PLAYER_ITEMS then
		CSR_log("Received PLAYER_ITEMS from peer " .. tostring(sender))

		-- Auth-pre-check: if this is a REMOVED payload, only relay/handle when
		-- the sender is the host or is removing themselves. Without the gate,
		-- a malicious client can erase another peer's items on every receiver
		-- (including via the host relay below).
		local relay_ok = true
		local is_removed = string.find(data, "~REMOVED", 1, true) ~= nil
		if is_removed then
			local victim_str = string.match(data, "^(%d+)~")
			local victim_id = tonumber(victim_str)
			local is_self_remove = victim_id and (sender_num == victim_id)
			if not (is_from_host or is_self_remove) then
				CSR_log(
					"PLAYER_ITEMS: REJECTED forged REMOVED for victim "
						.. tostring(victim_id)
						.. " from peer "
						.. tostring(sender_num)
				)
				return
			end
		end

		CSR_MP._handle_player_items(sender, data, sender_num, is_from_host)

		-- Host relays to all other peers so everyone stays in sync.
		if CSR_MP.is_host() and relay_ok then
			local session = managers.network and managers.network:session()
			if session then
				for _, peer in pairs(session:peers() or {}) do
					local pid = peer and peer:id()
					if pid and pid ~= sender_num and pid ~= 1 then
						LuaNetworking:SendToPeer(pid, MSG.PLAYER_ITEMS, data)
					end
				end
			end
		end
		return
	end

	-- === Client asks host for all players' items (late join) ===
	if id == MSG.REQUEST_ALL and CSR_MP.is_host() then
		CSR_log("Received REQUEST_ALL from peer " .. tostring(sender))
		CSR_MP.send_all_players(sender_num or sender)
		return
	end

	-- === Client receives all players' items from host ===
	if id == MSG.ALL_PLAYERS and CSR_MP.is_client() and is_from_host then
		CSR_MP._handle_all_players(sender, data)
		return
	end

	-- === Client receives forced mods from host ===
	if id == MSG.FORCED_MODS and CSR_MP.is_client() and is_from_host then
		CSR_log("FORCED_MODS from host: " .. tostring(data))
		CSR_MP.apply_forced_mods(data)
		return
	end

	-- === Client receives rank update from host ===
	if id == MSG.RANK_UP and CSR_MP.is_client() and is_from_host then
		-- Format: "rank|total_drops" (new) or just "rank" (old compat)
		local rank_str, drops_str = data:match("^([^|]+)|?(.*)$")
		local new_rank = tonumber(rank_str)
		local total_drops = drops_str and drops_str ~= "" and tonumber(drops_str) or nil
		if new_rank then
			CSR_log("RANK_UP from host: rank=" .. tostring(new_rank) .. " total_drops=" .. tostring(total_drops))
			CSR_MP.apply_rank_up(new_rank, total_drops)
		end
		return
	end

	-- === Printer state (host -> clients) ===
	if id == "CSR_Printer" and CSR_MP.is_client() and is_from_host then
		CSR_log("Received CSR_Printer from host: " .. tostring(data))
		if CSR_PrinterHandleState then
			CSR_PrinterHandleState(data)
		end
		return
	end

	-- === Printer use counter (any peer -> all others) ===
	if id == "CSR_PrinterUses" then
		CSR_log("Received CSR_PrinterUses from peer " .. tostring(sender) .. ": " .. tostring(data))
		if CSR_PrinterHandleUses then
			CSR_PrinterHandleUses(data)
		end
		return
	end

	-- === Copier auto-spawn (host -> clients) ===
	-- Payload: "x|y|z|yaw|id_prefix|tier". Handler is registered in
	-- lua/core/copier_spawner.lua. The handler queues payloads if the client
	-- isn't heist-ready yet — see CSR_PendingClientCopiers.
	if id == "CSR_CopierSpawn" and CSR_MP.is_client() and is_from_host then
		CSR_log("Received CSR_CopierSpawn from host: " .. tostring(data))
		if _G.CSR_HandleCopierSpawn then
			CSR_HandleCopierSpawn(data)
		end
		return
	end

	-- === Scrapper auto-spawn (host -> clients) ===
	-- Payload: "x|y|z|yaw|key". Handler is registered in scrapper_spawner.lua.
	-- Same dispatch shape as CSR_CopierSpawn above.
	if id == "CSR_ScrapperSpawn" and CSR_MP.is_client() and is_from_host then
		if _G.CSR_HandleScrapperSpawn then
			CSR_HandleScrapperSpawn(data)
		end
		return
	end

	-- === Client receives per-heist token award from host ===
	if id == MSG.TOKEN_AWARD and CSR_MP.is_client() and is_from_host then
		local award_str, earned_str = string.match(data, "^(%-?%d+)|(%-?%d+)$")
		if not award_str or not earned_str then
			CSR_log("TOKEN_AWARD malformed: " .. tostring(data))
			return
		end
		local award = tonumber(award_str) or 0
		local earned = tonumber(earned_str) or 0
		if award > 0 and CSR_TokensManager then
			CSR_TokensManager.credit(CSR_TokensManager.local_peer_id(), award)
		end
		if CSR_TokensManager then
			CSR_TokensManager.set_host_earned(earned)
		end
		-- Persist client-side token state immediately so a quit before the next modifier-pick
		-- doesn't lose this heist's host_earned tally on the client.
		if CSR_SaveSession then
			local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
			local td = _G.CSR_MP_TotalDrops
			if _G.CSR_MP_RunSeed then
				CSR_SaveSession(_G.CSR_MP_RunSeed, nil, items, td)
			end
			if _G.CSR_CurrentSeed and tostring(_G.CSR_CurrentSeed) ~= tostring(_G.CSR_MP_RunSeed) then
				CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, td)
			end
		end
		CSR_log("TOKEN_AWARD applied: +" .. award .. " host_earned=" .. earned)
		return
	end

	-- === Client receives late-join catchup grant from host ===
	if id == MSG.CATCHUP_GRANT and CSR_MP.is_client() and is_from_host then
		if CSR_LateJoinCatchup and CSR_LateJoinCatchup.apply_grant then
			CSR_LateJoinCatchup.apply_grant(data)
		end
		return
	end

	-- === Client receives authoritative token state from host (late-join seed) ===
	if id == MSG.TOKEN_STATE and CSR_MP.is_client() and is_from_host then
		local wallet_str, earned_str = string.match(data, "^(%-?%d+)|(%-?%d+)$")
		if wallet_str and earned_str then
			local wallet = tonumber(wallet_str) or 0
			local earned = tonumber(earned_str) or 0
			if CSR_TokensManager then
				-- host_earned is host-authoritative (per-heist contributions tally),
				-- so always accept it.
				CSR_TokensManager.set_host_earned(earned)
				-- Wallet is NOT host-authoritative for rejoiners: the host just
				-- holds a placeholder pdata for a freshly-connected client and
				-- doesn't know our true wallet. Only seed wallet from host when
				-- the local wallet is empty (fresh join with no session restore);
				-- otherwise the value already restored from csr_mp_sessions.json
				-- is correct and must not be stomped.
				local local_pid = CSR_TokensManager.local_peer_id()
				local local_wallet = CSR_TokensManager.get_wallet and CSR_TokensManager.get_wallet(local_pid) or 0
				if local_wallet <= 0 then
					CSR_TokensManager.set_wallet(local_pid, wallet)
					CSR_log("TOKEN_STATE applied: wallet=" .. wallet .. " host_earned=" .. earned)
				else
					CSR_log(
						"TOKEN_STATE: kept local wallet="
							.. local_wallet
							.. " (host sent "
							.. wallet
							.. "), host_earned="
							.. earned
					)
				end
			end
		else
			CSR_log("TOKEN_STATE malformed: " .. tostring(data))
		end
		return
	end

	-- === Client receives assault-end notification (Crooked Badge revive trigger) ===
	-- The vanilla GroupAIStateBesiege:_begin_regroup_task only runs on the host,
	-- so without this RPC clients with Crooked Badge would never get their
	-- post-assault revive roll. Host broadcasts this message and each client
	-- evaluates its own CSR_ActiveBuffs locally.
	if id == MSG.ASSAULT_END and CSR_MP.is_client() and is_from_host then
		if _G.CSR_CrookedBadge_OnAssaultEnd then
			_G.CSR_CrookedBadge_OnAssaultEnd()
		end
		return
	end

	-- === Locke's Beret 30s pulse from any peer ===
	-- Sender heals their own player locally; this packet tells every other peer to
	-- heal their own local player. The host additionally heals bots/jokers/turrets
	-- (handled inside CSR_LockesBeret_ApplyTeamHeal when Network:is_server() is true).
	if id == MSG.LOCKES_HEAL then
		local stacks = tonumber(data)
		log("[CSR][Beret] received LOCKES_HEAL from peer=" .. tostring(sender) .. " stacks=" .. tostring(stacks))
		if stacks and stacks > 0 and _G.CSR_LockesBeret_ApplyTeamHeal then
			_G.CSR_LockesBeret_ApplyTeamHeal(stacks)
		end
		return
	end

	-- Hippocratic Oath aura tick (host -> client). Heals local player by the
	-- per-tick percent and triggers the local pulse visual on the client's
	-- medic. Payload is empty; the heal amount lives in CSR_ItemConstants so
	-- client and host stay in sync if values are tweaked.
	if id == MSG.OATH_HEAL then
		local heal_pct = (_G.CSR_ItemConstants and _G.CSR_ItemConstants.hippocratic_heal_pct_per_tick) or 0.05
		local pu = managers.player and managers.player:player_unit()
		local hp_before, hp_after
		if alive(pu) then
			local cdmg = pu:character_damage()
			if cdmg and cdmg.restore_health then
				hp_before = cdmg.get_real_health and cdmg:get_real_health() or nil
				pcall(cdmg.restore_health, cdmg, heal_pct, false)
				hp_after = cdmg.get_real_health and cdmg:get_real_health() or nil
			end
		end
		-- Find own medic, fire pulse visual + voiceline (voiceline only if HP
		-- actually went up and the 30s throttle elapsed).
		local medic
		if _G.CSR_HippocraticOath_FindLocalMedic then
			medic = CSR_HippocraticOath_FindLocalMedic()
		end
		if medic then
			if _G.CSR_HippocraticOath_StartPulse then
				CSR_HippocraticOath_StartPulse(medic)
			end
			if _G.CSR_HippocraticOath_TryPlayVoice then
				CSR_HippocraticOath_TryPlayVoice(medic, hp_before, hp_after)
			end
		end
		return
	end

	-- === Debug messages from any peer (relay client state to host log) ===
	if id == "CSR_Debug" then
		CSR_log("DEBUG from peer " .. tostring(sender) .. ": " .. tostring(data))
		return
	end
end)

----------------------------------------------
-- BLOCK VANILLA SYNC FOR PLAYER ITEMS (client only)
----------------------------------------------

-- Vanilla syncs ALL modifiers via set_server_modifier, including our player_* items.
-- This triggers refresh_crime_spree_details_gui which destroys and recreates the UI,
-- breaking our custom tab buttons. Skip player_* items — we handle them ourselves.
local _orig_set_server_modifier = CrimeSpreeManager.set_server_modifier
function CrimeSpreeManager:set_server_modifier(modifier_id, modifier_level, announce)
	if CSR_MP.is_client() and modifier_id and string.find(modifier_id, "player_", 1, true) == 1 then
		CSR_log("Skipping vanilla set_server_modifier for player item: " .. tostring(modifier_id))
		return
	end
	return _orig_set_server_modifier(self, modifier_id, modifier_level, announce)
end

----------------------------------------------
-- AUTO-CREATE CS FOR CLIENTS WITHOUT ONE (lazy init via in_progress override)
----------------------------------------------

-- When a client joins a CSR-confirmed MP session without their own active CS,
-- minimal CS state is set up so vanilla UI checks of in_progress() see a sane
-- value. The auto-create now happens directly in _handle_handshake_ok (which
-- is the moment we KNOW the host is running CSR). This override is a defensive
-- passthrough for any later in_progress() callers — the real state mutation
-- has already been done by the time we get here.
--
-- Gate must require CSR_MP.is_mp_session, not just is_client(). is_mp_session
-- is set only in _handle_handshake_ok and the session-file recovery path —
-- both legitimate "we are in a CSR session" signals. The previous gate fired
-- for ANY client in ANY MP session, which leaked CSR state into vanilla
-- heists. TaheyaKinnie 2026-05-10.
local _orig_in_progress = CrimeSpreeManager.in_progress
function CrimeSpreeManager:in_progress()
	local result = _orig_in_progress(self)
	if result then
		return true
	end

	if not (_G.CSR_MP and CSR_MP.is_mp_session and Network:is_client()) then
		return false
	end

	if self._global and not self._global.in_progress then
		CSR_log("in_progress override: defensive auto-set after handshake confirm")
		self._global.in_progress = true
		self._global.spree_level = 0
		self._global.reward_level = 0
		self._global.modifiers = self._global.modifiers or {}
		_G.CSR_MP_NeedsAutoCreate = true
	end
	return true
end

----------------------------------------------
-- FUZZY get_modifier OVERRIDE (client: different seed -> different mod IDs)
----------------------------------------------

-- Loud modifier IDs include level suffix (e.g. "medic_bulldozer_25") which differs
-- between host and client seeds. Fuzzy match by base ID so Modifiers tab works.
-- NOTE: This captures crimespree_filter.lua's override (loaded earlier via mod.txt).
-- Call chain: this override -> crimespree_filter -> vanilla.
-- Load order in mod.txt MUST be preserved.
local _orig_get_modifier = CrimeSpreeManager.get_modifier
function CrimeSpreeManager:get_modifier(modifier_id)
	local result = _orig_get_modifier(self, modifier_id)
	if result then
		return result
	end

	-- Fuzzy match: strip level suffix and find any modifier with same base
	local base_id = modifier_id and modifier_id:match("^(.+)_%d+$")
	if base_id then
		for _, modifiers_table in pairs(tweak_data.crime_spree.modifiers) do
			for _, data in pairs(modifiers_table) do
				local data_base = data.id and data.id:match("^(.+)_%d+$")
				if data_base and data_base == base_id then
					return data
				end
			end
		end
	end
	return nil
end

----------------------------------------------
-- CLIENT "SELECT ITEM" + "AUTO-FILL" BUTTONS
-- (moved to lua/menu/client_endscreen_component.lua)
----------------------------------------------

----------------------------------------------
-- LIFECYCLE HOOKS
----------------------------------------------

-- Clean up when leaving any lobby
-- Suppress "Crime Spree Suspended" warning for clients whose rank exceeds the host's.
-- Vanilla sets peer_spree_levels[1] = host_rank in on_entered_lobby, which triggers the
-- warning immediately (server_spree_level() < spree_level()). Clamp it synchronously here
-- so the detail pages never see the wrong value.
Hooks:PostHook(CrimeSpreeManager, "on_entered_lobby", "CSR_MP_SuppressSuspendedWarning", function(self)
	-- Mirror vanilla's gate (lib/managers/crimespreemanager.lua:1415) so this
	-- PostHook only fires for CS-gamemode lobbies. Without this gate, joining
	-- ANY MP lobby (including plain vanilla heists) would set is_mp_session and
	-- schedule a handshake, and the in_progress() override below would then
	-- mutate CS state on the client. TaheyaKinnie 2026-05-10.
	if not self:is_active() then
		return
	end
	if not Network:is_client() then
		return
	end
	local local_rank = self:spree_level() or 0
	local server_rank = self:server_spree_level() or 0
	CSR_log("on_entered_lobby (client): local_rank=" .. local_rank .. " server_rank=" .. server_rank)
	if local_rank > server_rank then
		self:set_peer_spree_level(1, local_rank)
		CSR_log("on_entered_lobby: clamped peer_spree_levels[1] to " .. local_rank)
	end

	-- Schedule handshake to restore MP state after Lua reload (heist->lobby transition).
	-- Lua reloads wipe all globals (CSR_MP_HostRank, CSR_MP_TotalDrops, CSR_PlayerItems).
	-- Uses same key as on_finalize_modifiers / on_mission_started so they don't double-fire.
	CSR_MP.is_mp_session = true
	CSR_log("on_entered_lobby: scheduling handshake to restore MP state")
	DelayedCalls:Add("CSR_MP_Handshake", 0.5, function()
		CSR_MP.send_handshake()
	end)
end)

Hooks:PostHook(CrimeSpreeManager, "on_left_lobby", "CSR_MP_RestoreOnLeave", function(self)
	CSR_log("on_left_lobby: cleaning up MP state")

	-- Clear all remote peers' data (keep only local player)
	if CSR_ClearRemotePeers then
		CSR_ClearRemotePeers()
	end

	-- Reset MP globals
	_G.CSR_MP_HostRank = nil
	_G.CSR_MP_HostDifficulty = nil
	_G.CSR_MP_AutoCreatedCS = nil
	_G.CSR_MP_RunSeed = nil
	_G.CSR_MP_TotalDrops = nil
	CSR_MP.is_mp_session = false
	CSR_MP._items_buf = {}
	CSR_MP._synced_peers = {}

	-- Reset modifier count tracking
	_G.CSR_LastModifierCount = nil
	_G.CSR_ModifierCountInitialized = false
	_G.CSR_CachedModifierOffer = nil

	_G.CSR_LastShownForcedLevel = 0

	CSR_log("on_left_lobby: done, CSR_CurrentDifficulty=" .. tostring(_G.CSR_CurrentDifficulty))
end)

-- Any peer: broadcast own items when selecting a player item
-- Host also starts 30s timer for other players to pick
Hooks:PostHook(CrimeSpreeManager, "select_modifier", "CSR_MP_BroadcastOnSelect", function(self, modifier_id)
	if not CSR_MP.is_multiplayer() then
		return
	end
	if modifier_id and string.find(modifier_id, "player_", 1, true) == 1 then
		CSR_MP.broadcast_own_items()
		if CSR_MP.is_host() then
			-- Host-side: block "Start the heist" until clients have selected
			_G.CSR_HostSelectionDeadline = os.clock() + 30
		end
		-- Client: persist items to session file for reload recovery
		-- (crimespree_autosave.lua is blocked by is_active() which is false for auto-created CS)
		if CSR_MP.is_client and CSR_MP.is_client() and CSR_SaveSession then
			local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
			local td = _G.CSR_MP_TotalDrops or 0
			local rs = _G.CSR_MP_RunSeed
			if rs then
				CSR_SaveSession(rs, nil, items, td)
			end
			if _G.CSR_CurrentSeed and tostring(_G.CSR_CurrentSeed) ~= tostring(rs) then
				CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, td)
			end
			CSR_log(
				"BroadcastOnSelect: client saved session, items="
					.. tostring(#items)
					.. " td="
					.. tostring(td)
					.. " rs="
					.. tostring(rs)
			)
		end
	end
end)

-- Host: send all players' items after vanilla finishes syncing modifiers to a joining peer
Hooks:PostHook(CrimeSpreeManager, "on_peer_finished_loading", "CSR_MP_SyncOnPeerJoin", function(self, peer)
	local pid = peer and peer:id()
	CSR_log("on_peer_finished_loading: peer=" .. tostring(pid) .. " is_host=" .. tostring(CSR_MP.is_host()))
	if not CSR_MP.is_host() or not peer then
		return
	end
	if not pid or pid == 1 then
		return
	end
	CSR_log("Peer " .. tostring(pid) .. " finished loading — scheduling all players sync in 0.5s")
	DelayedCalls:Add("CSR_AllPlayers_Peer" .. tostring(pid), 0.5, function()
		CSR_MP.send_all_players(pid)
	end)
end)

-- Client: send handshake after receiving all vanilla modifiers from host
-- on_finalize_modifiers only fires for new peers joining in-progress sessions.
-- on_mission_started also schedules CSR_MP_Handshake (same key) as fallback for
-- existing lobby peers transitioning to heist. DelayedCalls:Add with same key
-- replaces the existing entry, so only one handshake fires.
Hooks:PostHook(CrimeSpreeManager, "on_finalize_modifiers", "CSR_MP_ClientHandshake", function(self)
	if not CSR_MP.is_client() then
		return
	end
	CSR_log("Vanilla modifiers finalized — scheduling handshake to host in 1s")
	CSR_MP._handshake_scheduled = true
	DelayedCalls:Add("CSR_MP_Handshake", 1, function()
		CSR_MP._handshake_scheduled = false
		CSR_MP.send_handshake()
	end)
end)

-- Host: sync when any player spawns in mission (catches edge cases for late joiners)
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_MP_SyncOnSpawn", function(self, id, unit)
	if not CSR_MP.is_host() or not CSR_MP.is_multiplayer() then
		return
	end
	local session = managers.network and managers.network:session()
	if not session then
		return
	end
	CSR_MP._synced_peers = CSR_MP._synced_peers or {}
	for _, peer in pairs(session:peers() or {}) do
		local pid = peer and peer:id()
		if pid and pid ~= 1 then
			if not CSR_MP._synced_peers[pid] then
				CSR_log("spawned_player: sending all players to unsynced peer " .. tostring(pid))
				CSR_MP._synced_peers[pid] = true
				CSR_MP.send_all_players(pid)
			end
		end
	end
end)

-- Handle peer disconnect — remove from store and refresh UI
-- BaseNetworkSession doesn't exist when this file loads (hooks on crimespreemanager).
-- Defer registration: MenuUpdate covers lobby, on_mission_started covers briefing.
local function CSR_register_peer_removed_hook()
	if CSR_MP._peer_hook_registered then
		return
	end
	if not BaseNetworkSession or not BaseNetworkSession._on_peer_removed then
		return
	end
	CSR_MP._peer_hook_registered = true

	Hooks:PostHook(BaseNetworkSession, "_on_peer_removed", "CSR_MP_OnPeerRemoved", function(self, peer, peer_id, reason)
		if not peer_id then
			return
		end
		CSR_log(
			"_on_peer_removed: peer="
				.. tostring(peer_id)
				.. " reason="
				.. tostring(reason)
				.. " has_data="
				.. tostring(_G.CSR_PlayerItems[peer_id] ~= nil)
		)

		if _G.CSR_PlayerItems[peer_id] then
			CSR_RemovePeer(peer_id)
			CSR_MP._items_buf["items_" .. tostring(peer_id)] = nil

			-- Host: notify remaining peers
			if CSR_MP.is_host() then
				LuaNetworking:SendToPeers(MSG.PLAYER_ITEMS, tostring(peer_id) .. "~~1/1~REMOVED")
			end

			-- Refresh UI tabs immediately
			refresh_ui_instance("CSR_ItemsPageInstance", "_setup_items")
			refresh_ui_instance("CSR_PrinterPageInstance", "_setup_printer")
		end
	end)
	CSR_log("_on_peer_removed hook registered successfully")
end

-- Reset synced peers at mission start
-- Client: also trigger handshake here for the lobby→heist transition.
-- on_finalize_modifiers only fires for NEW peers joining in-progress sessions.
-- Existing lobby peers that transition with the host never receive
-- sync_crime_spree_modifiers_finalize, so on_finalize_modifiers never fires for them.
Hooks:PostHook(CrimeSpreeManager, "on_mission_started", "CSR_MP_ResetSyncedPeers", function(self)
	CSR_log("on_mission_started: resetting synced peers")
	CSR_MP._synced_peers = {}
	-- Register peer-removed hook now (MenuUpdate doesn't fire in briefing)
	CSR_register_peer_removed_hook()

	-- Fallback for existing lobby peers (on_finalize_modifiers never fires for them).
	-- Skip if on_finalize_modifiers already scheduled a handshake.
	if CSR_MP.is_client() and not CSR_MP._handshake_scheduled then
		CSR_log("on_mission_started: client scheduling handshake (lobby->heist fallback)")
		DelayedCalls:Add("CSR_MP_Handshake", 2, function()
			CSR_MP.send_handshake()
		end)
	end
end)

Hooks:Add("MenuUpdate", "CSR_DeferPeerRemovedHook", function()
	if CSR_MP._peer_hook_registered then
		Hooks:Remove("CSR_DeferPeerRemovedHook")
		return
	end
	CSR_register_peer_removed_hook()
	if CSR_MP._peer_hook_registered then
		Hooks:Remove("CSR_DeferPeerRemovedHook")
	end
end)
