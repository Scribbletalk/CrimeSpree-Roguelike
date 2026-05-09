-- Crime Spree Roguelike -- Late-Join Catchup
-- When a new peer joins, simulate a "shopping spree" using the delta of host's
-- tokens-earned since the joiner's last received budget. Items granted to the
-- joiner via MSG.CATCHUP_GRANT RPC (joiner applies locally via CSR_AddItem).
-- Leftover (< 10) is included in the same RPC and credited to joiner's wallet.
--
-- Payload format: "leftover|prefix1,prefix2,prefix3"
-- Empty grants:   "0|"   (leftover=0, no prefixes)
-- id_prefixes never contain commas, so comma is a safe delimiter.

CSR_LateJoinCatchup = CSR_LateJoinCatchup or {}

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR JOIN] " .. tostring(msg))
	end
end

local function csr_chat(msg)
	if managers and managers.chat and ChatManager and ChatManager.GAME then
		managers.chat:_receive_message(1, "[CSR]", tostring(msg), Color(0.4, 0.85, 1))
	end
end

local function peer_name(peer_id)
	local session = managers and managers.network and managers.network:session()
	local peer = session and session.peer and session:peer(peer_id)
	if peer and peer.name then
		return peer:name()
	end
	return "Peer " .. tostring(peer_id)
end

-- Resolve a stable identifier for the joiner. user_id (Steam ID) survives
-- disconnect/reconnect; peer_id can be reassigned. Used as the key in
-- _G.CSR_HostCatchupSnapshots so a player can't farm items by rejoining.
local function joiner_key(peer_id)
	local session = managers and managers.network and managers.network:session()
	local peer = session and session.peer and session:peer(peer_id)
	if peer and peer.user_id then
		local uid = peer:user_id()
		if uid and uid ~= "" then
			return uid
		end
	end
	-- Fallback if Steam ID isn't available (shouldn't happen in normal play).
	return "peer_" .. tostring(peer_id)
end

local MAX_OVERPRICED_RETRIES = 5
local CHEAPEST_PRICE = 10

-- Build an item-grant list for a given budget by simulating shop purchases.
-- Returns: { granted_id_prefixes = { ... }, leftover = N }
function CSR_LateJoinCatchup.simulate(budget)
	if budget <= 0 then
		return { granted_id_prefixes = {}, leftover = 0 }
	end
	local result = { granted_id_prefixes = {}, leftover = budget }
	if not CSR_ShopManager or not CSR_ShopManager.build_pool then
		CSR_log("simulate: CSR_ShopManager missing -- abort")
		return result
	end

	local pool = CSR_ShopManager.build_pool()
	if #pool == 0 then
		return result
	end

	local retries = 0
	while result.leftover >= CHEAPEST_PRICE do
		local entry = CSR_ShopManager.pick_one(pool)
		if not entry then
			break
		end
		local price = CSR_TokensManager.price_for_rarity(entry.rarity)
		if price == math.huge then
			-- Unpriced rarity in pool -- skip (defensive against future Wildcards).
			retries = retries + 1
			if retries >= MAX_OVERPRICED_RETRIES then
				break
			end
		elseif result.leftover >= price then
			if entry.id_prefix then
				table.insert(result.granted_id_prefixes, entry.id_prefix)
				result.leftover = result.leftover - price
				retries = 0
			else
				retries = retries + 1
				if retries >= MAX_OVERPRICED_RETRIES then
					break
				end
			end
		else
			-- Rolled item too expensive for remaining budget; retry with another roll.
			retries = retries + 1
			if retries >= MAX_OVERPRICED_RETRIES then
				break
			end
		end
	end

	local exit_reason = (retries >= MAX_OVERPRICED_RETRIES) and "retry_cap"
		or (result.leftover < CHEAPEST_PRICE) and "below_cheapest"
		or "pool_empty_or_other"
	CSR_log(
		"simulate: budget="
			.. budget
			.. " granted="
			.. #result.granted_id_prefixes
			.. " leftover="
			.. result.leftover
			.. " exit="
			.. exit_reason
	)
	return result
end

-- Triggered from multiplayer_sync.lua when the late-join 30s auto-fill timer fires
-- on the host. Reads (and updates) the joiner's catchup_received_budget snapshot.
-- Sends MSG.CATCHUP_GRANT to the joiner; also updates the snapshot so a re-join
-- doesn't double-grant.
-- send_target: the exact value to pass to LuaNetworking:SendToPeer. Threaded through
-- from the late-join code path so it matches whatever HandshakeOK/TokenState used
-- (string or number, depending on SuperBLT). Round-tripping via tonumber/tostring
-- has been observed to drop the message even though the NetworkHelper logs the send.
function CSR_LateJoinCatchup.run_for_peer(joiner_peer_id, send_target)
	send_target = send_target or joiner_peer_id
	if not (Network and Network:is_server()) then
		log("[CSR JOIN] run_for_peer: not server, peer=" .. tostring(joiner_peer_id) .. " -- bailing")
		return
	end
	local current_earned = CSR_TokensManager.get_host_earned()

	-- Backfill host_earned for hosts whose CSR_HostTokensEarned was never seeded
	-- (pre-6.0.0 seed files have no line 12, so it loads as 0; same for hosts
	-- who haven't completed a mission this Lua session). Without this, the
	-- delta below is always 0 for high-rank pre-shop hosts and joiners get
	-- nothing — the catchup is silently a no-op despite a rank-47 spree.
	-- Formula matches run_for_starting_level so a "ranked-up to N" host and a
	-- "started at N" host produce the same joiner experience.
	local rank = managers.crime_spree and managers.crime_spree.spree_level and managers.crime_spree:spree_level() or 0
	local rank_baseline = math.floor((rank + 1) / 2)
	if current_earned < rank_baseline then
		log(
			"[CSR JOIN] run_for_peer: host_earned="
				.. tostring(current_earned)
				.. " < rank_baseline="
				.. tostring(rank_baseline)
				.. " (rank="
				.. tostring(rank)
				.. ") -- seeding so future joiners get items"
		)
		CSR_TokensManager.set_host_earned(rank_baseline)
		current_earned = rank_baseline
	end

	_G.CSR_PlayerItems = _G.CSR_PlayerItems or {}
	if not _G.CSR_PlayerItems[joiner_peer_id] then
		log("[CSR JOIN] run_for_peer: pdata missing for peer=" .. tostring(joiner_peer_id) .. " -- auto-creating")
		_G.CSR_PlayerItems[joiner_peer_id] = {
			items = {},
			name = "Player " .. tostring(joiner_peer_id),
			rank = 0,
			difficulty = _G.CSR_CurrentDifficulty or "overkill",
			tokens = 0,
		}
	end

	-- Host-side watermark keyed by Steam user_id so reconnects don't double-grant.
	-- Lives outside CSR_PlayerItems (which gets cleared on peer disconnect).
	_G.CSR_HostCatchupSnapshots = _G.CSR_HostCatchupSnapshots or {}

	-- Lazy-restore from the session JSON the first time we run for the current
	-- seed -- handles the case where the host restarted the game mid-run. Higher
	-- of (in-memory, persisted) wins so a crash doesn't roll back the watermark.
	if _G.CSR_CurrentSeed and _G.CSR_HostCatchupSnapshotsLoadedSeed ~= _G.CSR_CurrentSeed then
		if CSR_LookupSession then
			local session = CSR_LookupSession(_G.CSR_CurrentSeed)
			if session and session.host_catchup_snapshots then
				for k, v in pairs(session.host_catchup_snapshots) do
					local cur = _G.CSR_HostCatchupSnapshots[k] or 0
					if (tonumber(v) or 0) > cur then
						_G.CSR_HostCatchupSnapshots[k] = tonumber(v) or 0
					end
				end
				log(
					"[CSR JOIN] run_for_peer: restored host_catchup_snapshots from session for seed="
						.. tostring(_G.CSR_CurrentSeed)
				)
			end
		end
		_G.CSR_HostCatchupSnapshotsLoadedSeed = _G.CSR_CurrentSeed
	end

	local key = joiner_key(joiner_peer_id)
	local prev_snapshot = _G.CSR_HostCatchupSnapshots[key] or 0
	local delta = current_earned - prev_snapshot
	log(
		"[CSR JOIN] run_for_peer: peer="
			.. tostring(joiner_peer_id)
			.. " key="
			.. tostring(key)
			.. " current_earned="
			.. tostring(current_earned)
			.. " prev_snapshot="
			.. tostring(prev_snapshot)
			.. " delta="
			.. tostring(delta)
	)
	if delta <= 0 then
		log(
			"[CSR JOIN] run_for_peer: peer="
				.. joiner_peer_id
				.. " delta="
				.. delta
				.. " no catchup needed (already received "
				.. prev_snapshot
				.. " of "
				.. current_earned
				.. ")"
		)
		return
	end

	local result = CSR_LateJoinCatchup.simulate(delta)

	-- Advance the watermark immediately. Even if the RPC is dropped, the next
	-- rejoin sees delta=0 and won't double-grant. Stored by user_id so the
	-- watermark survives the peer disconnect that wipes CSR_PlayerItems[peer_id].
	_G.CSR_HostCatchupSnapshots[key] = current_earned
	CSR_log(
		"run_for_peer: snapshot advanced for key="
			.. tostring(key)
			.. " (peer="
			.. joiner_peer_id
			.. ") to "
			.. current_earned
	)

	-- Persist immediately so a host crash/quit before the next save doesn't
	-- lose this watermark and let the joiner farm again on next launch.
	if CSR_SaveSession and _G.CSR_CurrentSeed then
		local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, _G.CSR_MP_TotalDrops)
	end

	-- Build payload: "leftover|prefix1,prefix2,prefix3"
	-- Empty grants are still sent so the joiner can credit leftover wallet (if any).
	local prefix_str = table.concat(result.granted_id_prefixes, ",")
	local payload = tostring(result.leftover) .. "|" .. prefix_str

	if LuaNetworking and CSR_MP and CSR_MP.MSG and CSR_MP.MSG.CATCHUP_GRANT then
		LuaNetworking:SendToPeer(send_target, CSR_MP.MSG.CATCHUP_GRANT, payload)
		log(
			"[CSR JOIN] run_for_peer: sent CATCHUP_GRANT to send_target="
				.. tostring(send_target)
				.. " (type="
				.. type(send_target)
				.. ") peer="
				.. joiner_peer_id
				.. " grants="
				.. #result.granted_id_prefixes
				.. " leftover="
				.. result.leftover
				.. " payload="
				.. payload
		)
	else
		log("[CSR JOIN] run_for_peer: WARN networking unavailable, peer=" .. joiner_peer_id .. " did not receive grant")
	end
end

-- Apply a CATCHUP_GRANT received from host (called from the multiplayer_sync
-- router when MSG.CATCHUP_GRANT arrives). Parses payload, credits leftover,
-- adds each granted item locally via CSR_AddItem.
-- Caller (router) is responsible for verifying the sender is the host before
-- calling this function; apply_grant itself does not gate by sender authority.
function CSR_LateJoinCatchup.apply_grant(payload)
	log("[CSR JOIN] apply_grant: received payload=" .. tostring(payload))
	local leftover_str, prefix_str = string.match(payload, "^(%-?%d+)|(.*)$")
	if not leftover_str then
		log("[CSR JOIN] apply_grant: malformed payload: " .. tostring(payload))
		return
	end
	local leftover = tonumber(leftover_str) or 0

	-- Resolve the local peer_id we're about to write to. If the session isn't fully
	-- ready, CSR_LocalPeerId() falls back to 1 (host's slot) — log loudly so we can
	-- tell when that's happening.
	local local_pid = (CSR_LocalPeerId and CSR_LocalPeerId()) or 1
	local mp_pid = (_G.CSR_MP and CSR_MP.local_peer_id and CSR_MP.local_peer_id()) or "?"
	log(
		"[CSR JOIN] apply_grant: resolved local_pid="
			.. tostring(local_pid)
			.. " (CSR_MP.local_peer_id="
			.. tostring(mp_pid)
			.. ")"
	)

	-- Snapshot pdata BEFORE mutations.
	_G.CSR_PlayerItems = _G.CSR_PlayerItems or {}
	local pdata = _G.CSR_PlayerItems[local_pid]
	local items_before = pdata and pdata.items and #pdata.items or 0
	local tokens_before = pdata and pdata.tokens or 0
	log(
		"[CSR JOIN] apply_grant: BEFORE peer="
			.. tostring(local_pid)
			.. " items="
			.. tostring(items_before)
			.. " tokens="
			.. tostring(tokens_before)
	)

	if leftover > 0 then
		CSR_TokensManager.credit(local_pid, leftover)
	end

	local count = 0
	if prefix_str and #prefix_str > 0 then
		if not CSR_AddItem then
			log("[CSR JOIN] apply_grant: WARN CSR_AddItem nil -- items not applied")
		else
			for prefix in string.gmatch(prefix_str, "([^,]+)") do
				CSR_AddItem(prefix)
				count = count + 1
			end
		end
	end

	-- Track catchup items in the per-peer counter so they are EXCLUDED from the
	-- milestone selection-popup quota (same exemption pattern as shop purchases
	-- and bonus drops -- see crimespree_filter.lua modifiers_to_select).
	if count > 0 then
		_G.CSR_CatchupItemsReceived = _G.CSR_CatchupItemsReceived or {}
		_G.CSR_CatchupItemsReceived[local_pid] = (_G.CSR_CatchupItemsReceived[local_pid] or 0) + count
		log(
			"[CSR JOIN] apply_grant: CSR_CatchupItemsReceived["
				.. tostring(local_pid)
				.. "]="
				.. tostring(_G.CSR_CatchupItemsReceived[local_pid])
		)
	end

	-- Snapshot pdata AFTER mutations.
	pdata = _G.CSR_PlayerItems[local_pid]
	local items_after = pdata and pdata.items and #pdata.items or 0
	local tokens_after = pdata and pdata.tokens or 0
	log(
		"[CSR JOIN] apply_grant: AFTER peer="
			.. tostring(local_pid)
			.. " items="
			.. tostring(items_after)
			.. " tokens="
			.. tostring(tokens_after)
			.. " (added "
			.. count
			.. " items, +"
			.. leftover
			.. " tokens)"
	)

	-- Persist immediately so a Lua reload (heist start) doesn't lose the grant.
	if CSR_SaveSession and _G.CSR_CurrentSeed then
		local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, _G.CSR_MP_TotalDrops)
		log("[CSR JOIN] apply_grant: persisted session for seed=" .. tostring(_G.CSR_CurrentSeed))
	end

	-- Refresh Items tab + Printer tab so the new items show up immediately.
	local function refresh_ui(global_name, method)
		local inst = _G[global_name]
		if inst and type(inst[method]) == "function" then
			pcall(function()
				inst[method](inst)
			end)
		end
	end
	refresh_ui("CSR_ItemsPageInstance", "_setup_items")
	refresh_ui("CSR_PrinterPageInstance", "_setup_printer")

	-- Broadcast our new items to the rest of the lobby so other peers see them.
	if _G.CSR_MP and CSR_MP.broadcast_own_items then
		CSR_MP.broadcast_own_items()
	end

	if count > 0 or leftover > 0 then
		csr_chat("Catch-up received: " .. count .. " items, +" .. leftover .. " tokens")
	else
		csr_chat("Catch-up received: nothing (host had no earned tokens)")
	end
end

-- Grant random items to the local player when a Crime Spree is started at a
-- non-zero rank. Mirrors the late-join catchup flow: budget is spent through
-- the shop simulator, items are applied locally via CSR_AddItem, leftover is
-- credited to the wallet, and items are marked catchup-received so they are
-- excluded from the milestone selection-popup quota.
--
-- Token-budget formula matches the host's per-mission token award:
--   floor((total_ranks + 1) / 2)
-- so a host who STARTS at rank N gets the same wallet a host who EARNED their
-- way to rank N would have, keeping the late-join math consistent.
function CSR_LateJoinCatchup.run_for_starting_level(starting_level)
	if not starting_level or starting_level <= 0 then
		return
	end
	-- Clients receive items via CATCHUP_GRANT from the host; never run the
	-- starting-level grant locally on a client.
	if _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() then
		return
	end

	local budget = math.floor((starting_level + 1) / 2)
	CSR_log("run_for_starting_level: starting_level=" .. starting_level .. " budget=" .. budget)

	-- Seed the host_earned counter so future late-joiners compute the correct
	-- delta against this initial budget (otherwise their first run_for_peer
	-- would re-grant the entire amount).
	if CSR_TokensManager and CSR_TokensManager.set_host_earned then
		CSR_TokensManager.set_host_earned(budget)
	else
		_G.CSR_HostTokensEarned = budget
	end

	local result = CSR_LateJoinCatchup.simulate(budget)

	local local_pid = (CSR_LocalPeerId and CSR_LocalPeerId()) or 1
	if result.leftover > 0 and CSR_TokensManager and CSR_TokensManager.credit then
		CSR_TokensManager.credit(local_pid, result.leftover)
	end

	local count = 0
	if CSR_AddItem then
		for _, prefix in ipairs(result.granted_id_prefixes) do
			CSR_AddItem(prefix)
			count = count + 1
		end
	end

	-- Count starting-rank items as PURCHASED (CSR_ShopItemsBought), not as
	-- late-join catchup. They behave like a Gage Shop spree paid for by the
	-- starting-coin cost: same milestone-quota exemption either way, but the
	-- bookkeeping bucket reflects their nature.
	if count > 0 then
		_G.CSR_ShopItemsBought = _G.CSR_ShopItemsBought or {}
		_G.CSR_ShopItemsBought[local_pid] = (_G.CSR_ShopItemsBought[local_pid] or 0) + count
	end

	-- Persist immediately so a Lua reload (heist start) doesn't lose the grant.
	if CSR_SaveSession and _G.CSR_CurrentSeed then
		local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, _G.CSR_MP_TotalDrops)
	end
	if CSR_SaveSeed and _G.CSR_CurrentSeed then
		local cs = managers and managers.crime_spree
		local difficulty = (cs and cs._global and cs._global.selected_difficulty)
			or _G.CSR_CurrentDifficulty
			or "normal"
		local modifiers = cs and cs._global and cs._global.modifiers or {}
		CSR_SaveSeed(_G.CSR_CurrentSeed, difficulty, modifiers)
	end

	-- Refresh Items tab so the new items show up immediately.
	local function refresh_ui(global_name, method)
		local inst = _G[global_name]
		if inst and type(inst[method]) == "function" then
			pcall(function()
				inst[method](inst)
			end)
		end
	end
	refresh_ui("CSR_ItemsPageInstance", "_setup_items")
	refresh_ui("CSR_PrinterPageInstance", "_setup_printer")

	-- Broadcast our new items to the rest of the lobby (no-op in SP).
	if _G.CSR_MP and CSR_MP.broadcast_own_items then
		CSR_MP.broadcast_own_items()
	end

	-- Modal dialog styled as a present from Gage. No item list — player
	-- discovers what's in the stash on their own. Reuses vanilla system_menu
	-- so it inherits PD2 styling and dismiss handling.
	if managers and managers.system_menu and managers.localization and (count > 0 or result.leftover > 0) then
		managers.system_menu:show({
			title = "A present from Gage",
			text = "Heard you're skipping the warm-up and jumping straight to rank "
				.. starting_level
				.. ".\n\nDon't sweat it, kid - I packed you a little something to get you on your feet. Compliments of the house. Take a look in your stash when you're ready... and don't ask where it came from.",
			button_list = { { text = managers.localization:text("dialog_ok") } },
		})
	end

	CSR_log(
		"run_for_starting_level: granted "
			.. count
			.. " items, +"
			.. result.leftover
			.. " tokens leftover (host_earned now "
			.. tostring(_G.CSR_HostTokensEarned)
			.. ")"
	)
end

CSR_log("loaded")
