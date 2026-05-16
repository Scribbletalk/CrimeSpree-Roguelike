-- Per-player item storage for Crime Spree Roguelike
-- Central module: all item reads/writes go through here

if not RequiredScript then
	return
end

-- Initialize the global store (survives file reloads)
_G.CSR_PlayerItems = _G.CSR_PlayerItems or {}

-- Per-peer count of wildcards stripped by the carry-1 cleanup in CSR_AddItem.
-- modifiers_to_select compensates with this so each replacement still counts as
-- one milestone pick (otherwise #items is unchanged across a swap and the popup
-- never advances). Seed reset clears it via seed_manager.lua.
_G.CSR_WildcardReplacements = _G.CSR_WildcardReplacements or {}

-- === STACKS CACHE ===
-- Counting stacks by prefix walks the items list every call. Combat hooks
-- (damage_bullet / damage_melee) can hit this hundreds of times per second.
-- Because EVERY mutation of CSR_PlayerItems goes through this module, we can
-- safely memoize counts and invalidate with a version bump on each write.
_G.CSR_StacksVersion = _G.CSR_StacksVersion or 0
_G.CSR_StacksCache = _G.CSR_StacksCache or { version = 0, data = {} }

local function invalidate_stacks()
	_G.CSR_StacksVersion = (_G.CSR_StacksVersion or 0) + 1
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR Store] " .. tostring(msg))
	end
end

-- Public alias so external code can force-invalidate if it ever mutates the
-- store through a back door (none exist today, but leaving the hook is cheap).
_G.CSR_InvalidateStacks = invalidate_stacks

local function cached_count(peer_id, id_prefix)
	local cache = _G.CSR_StacksCache
	if cache.version ~= _G.CSR_StacksVersion then
		cache.version = _G.CSR_StacksVersion
		cache.data = {}
	end
	local key = peer_id .. "|" .. id_prefix
	local cached = cache.data[key]
	if cached ~= nil then
		return cached
	end

	local data = _G.CSR_PlayerItems[peer_id]
	local count = 0
	if data and data.items then
		for _, item in ipairs(data.items) do
			if item.id and string.find(item.id, id_prefix, 1, true) == 1 then
				count = count + 1
			end
		end
	end
	cache.data[key] = count
	return count
end

-- === ACTIVE MODIFIER CACHE ===
-- Several hot paths (CopDamage:die for Shocking Surprise, CivilianDamage:die
-- for Civilian Alarm) scan the full active_modifiers() list every call just
-- to answer "is modifier X active?". Modifiers only grow during a spree, so
-- we cache answers per-prefix and invalidate when list length changes.
_G.CSR_ModifierPrefixCache = _G.CSR_ModifierPrefixCache or { len = -1, flags = {} }

function CSR_HasModifierPrefix(prefix)
	if not managers.crime_spree or not managers.crime_spree.active_modifiers then
		return false
	end
	local mods = managers.crime_spree:active_modifiers()
	if not mods then
		return false
	end

	local cache = _G.CSR_ModifierPrefixCache
	local cur_len = #mods
	if cache.len ~= cur_len then
		cache.len = cur_len
		cache.flags = {}
	end

	local cached = cache.flags[prefix]
	if cached ~= nil then
		return cached
	end

	local found = false
	for _, mod in ipairs(mods) do
		if mod and mod.id and string.find(mod.id, prefix, 1, true) == 1 then
			found = true
			break
		end
	end
	cache.flags[prefix] = found
	return found
end

-- Called when a spree ends / starts to force a rebuild on next lookup
function CSR_InvalidateModifierCache()
	_G.CSR_ModifierPrefixCache = { len = -1, flags = {} }
end

-- === QUERY API ===

-- Count how many items with the given id_prefix the local player has
-- Replaces all count_modifier_stacks() / count_stacks() calls across the codebase
function CSR_CountStacks(id_prefix)
	local peer_id = 1
	if _G.CSR_MP and CSR_MP.local_peer_id then
		peer_id = CSR_MP.local_peer_id()
		if peer_id == 0 then
			peer_id = 1
		end
	end
	return cached_count(peer_id, id_prefix)
end

-- Count stacks for a specific peer (used by UI to show other players' items)
function CSR_CountStacksForPeer(peer_id, id_prefix)
	return cached_count(peer_id, id_prefix)
end

-- Get local player's items list (returns the table reference)
function CSR_GetLocalItems()
	local peer_id = 1
	if _G.CSR_MP and CSR_MP.local_peer_id then
		peer_id = CSR_MP.local_peer_id()
		if peer_id == 0 then
			peer_id = 1
		end
	end

	local data = _G.CSR_PlayerItems[peer_id]
	if not data then
		_G.CSR_PlayerItems[peer_id] = { items = {}, name = "", rank = 0, difficulty = "overkill", tokens = 0 }
		data = _G.CSR_PlayerItems[peer_id]
	end
	return data.items
end

-- Get local player's peer_id (convenience)
function CSR_LocalPeerId()
	if _G.CSR_MP and CSR_MP.local_peer_id then
		local id = CSR_MP.local_peer_id()
		return id ~= 0 and id or 1
	end
	return 1
end

-- === QUERY API (rarity) ===

-- Get all items of a specific rarity that the local player currently owns.
-- Returns a list of { item_def = <registry entry>, id = <full item id>, level = <level> }
function CSR_GetOwnedItemsByRarity(rarity)
	local items = CSR_GetLocalItems()
	local registry_by_prefix = _G.CSR_ITEM_BY_PREFIX
	if not registry_by_prefix then
		return {}
	end

	local result = {}
	for _, item in ipairs(items) do
		if item.id then
			local prefix = item.id:gsub("_%d+$", "")
			local item_def = registry_by_prefix[prefix]
			if item_def and item_def.rarity == rarity then
				table.insert(result, { item_def = item_def, id = item.id, level = item.level or 0 })
			end
		end
	end
	return result
end

-- === MUTATION API ===

-- Find next available numeric ID for an item type
-- e.g. if player has player_health_boost_1 and _2, returns 3
function CSR_GetNextId(id_prefix)
	local items = CSR_GetLocalItems()
	local max_num = 0
	for _, item in ipairs(items) do
		if item.id and string.find(item.id, id_prefix, 1, true) == 1 then
			local num_str = string.sub(item.id, #id_prefix + 1)
			local num = tonumber(num_str)
			if num and num > max_num then
				max_num = num
			end
		end
	end
	return max_num + 1
end

-- Add an item to the local player's inventory
-- Returns the full item id (e.g. "player_health_boost_3")
function CSR_AddItem(id_prefix, level)
	local items = CSR_GetLocalItems()

	-- Carry-1 wildcard enforcement: when adding a wildcard, strip any
	-- existing wildcard from the inventory first. The popup UI flow shows a
	-- confirmation modal before reaching this point (wildcard_replace_prompt.lua),
	-- but the cleanup runs unconditionally so that non-popup paths
	-- (scrapper, MP late-join catchup, debug menu, sync recovery) can never
	-- leave the player holding two wildcards and producing a HUD/items-tab
	-- desync. CSR_ITEM_BY_PREFIX may not be ready on very-early-load paths,
	-- so guard the lookup.
	local registry = _G.CSR_ITEM_BY_PREFIX
	local new_def = registry and registry[id_prefix:sub(1, -2)]
	if new_def and new_def.rarity == "wildcard" then
		local peer_id = CSR_LocalPeerId()
		for i = #items, 1, -1 do
			local it = items[i]
			local it_prefix = it.id and it.id:match("^(.+_)%d+$")
			local it_key = it_prefix and it_prefix:sub(1, -2)
			local it_def = it_key and registry[it_key]
			if it_def and it_def.rarity == "wildcard" then
				table.remove(items, i)
				-- Compensate milestone math: removal would otherwise mask the
				-- fact that the player just made a selection (see
				-- modifiers_to_select in crimespree_filter.lua).
				_G.CSR_WildcardReplacements[peer_id] = (_G.CSR_WildcardReplacements[peer_id] or 0) + 1
			end
		end
	end

	local next_num = CSR_GetNextId(id_prefix)
	local new_id = id_prefix .. tostring(next_num)
	level = level or (managers.crime_spree and managers.crime_spree:spree_level() or 0)

	table.insert(items, { id = new_id, level = level })
	invalidate_stacks()

	-- Register Gage package contour materials when Half-a-Glass is first picked up
	if string.find(id_prefix, "half_a_glass", 1, true) and CSR_RegisterGageContourMaterials then
		CSR_RegisterGageContourMaterials()
	end

	-- Mark as seen in logbook
	if _G.CSR_Logbook and _G.CSR_ITEM_BY_PREFIX then
		local prefix_key = string.sub(id_prefix, 1, -2) -- remove trailing _
		local item_def = _G.CSR_ITEM_BY_PREFIX[prefix_key]
		if item_def then
			_G.CSR_Logbook:mark_seen(item_def.type)
		end
	end

	return new_id
end

-- Remove a specific item by full ID (e.g. "player_health_boost_2") from the local player
-- Returns the removed item table, or nil if not found
function CSR_RemoveItem(full_id)
	local items = CSR_GetLocalItems()
	for i, item in ipairs(items) do
		if item.id == full_id then
			local removed = table.remove(items, i)
			invalidate_stacks()
			return removed
		end
	end
	return nil
end

-- Initialize local player's entry in the store (called on CS start / seed load)
function CSR_InitLocalPlayer(items, rank, difficulty, name)
	CSR_log("CSR_InitLocalPlayer: items=" .. tostring(items and #items or "nil") .. " rank=" .. tostring(rank))
	local peer_id = CSR_LocalPeerId()
	_G.CSR_PlayerItems[peer_id] = {
		items = items or {},
		name = name
			or (managers.network and managers.network:session() and managers.network:session():local_peer() and managers.network
				:session()
				:local_peer()
				:name())
			or "Player",
		rank = rank or (managers.crime_spree and managers.crime_spree:spree_level() or 0),
		difficulty = difficulty or _G.CSR_CurrentDifficulty or "overkill",
		-- Tokens reset on init. Session-restore callers write .tokens directly
		-- on the struct AFTER calling this function (see multiplayer_sync.lua).
		tokens = 0,
	}
	invalidate_stacks()
end

-- Set a peer's data (called when receiving sync from other players)
function CSR_SetPeerItems(peer_id, items, name, rank, difficulty)
	-- Tokens are per-peer but not synced across the wire — each peer earns its
	-- own locally. Preserve any existing value for this peer across repeated
	-- sync messages so we don't stomp locally-tracked tokens on our own entry.
	local prev = _G.CSR_PlayerItems[peer_id]
	local prev_count = (prev and prev.items and #prev.items) or 0
	local new_count = (items and #items) or 0
	_G.CSR_PlayerItems[peer_id] = {
		items = items or {},
		name = name or ("Player " .. peer_id),
		rank = rank or 0,
		difficulty = difficulty or "overkill",
		tokens = prev and prev.tokens or 0,
	}
	-- Items arriving for the local peer via the network (ALL_PLAYERS recovery,
	-- PLAYER_ITEMS echo, etc.) were "given" to us, not chosen via the local
	-- selection popup — bump the catchup-exemption counter by the delta so they
	-- don't eat into the milestone quota in modifiers_to_select. Local picks
	-- use CSR_AddItem (mutates _G.CSR_PlayerItems directly) and bypass this path.
	local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
	if peer_id == local_peer and new_count > prev_count then
		local delta = new_count - prev_count
		_G.CSR_CatchupItemsReceived = _G.CSR_CatchupItemsReceived or {}
		_G.CSR_CatchupItemsReceived[peer_id] = (_G.CSR_CatchupItemsReceived[peer_id] or 0) + delta
		log(
			"[CSR] CSR_SetPeerItems: local peer "
				.. tostring(peer_id)
				.. " gained "
				.. tostring(delta)
				.. " items via network sync, catchup_received="
				.. tostring(_G.CSR_CatchupItemsReceived[peer_id])
		)
	end
	invalidate_stacks()
end

-- Remove a peer (on disconnect)
function CSR_RemovePeer(peer_id)
	CSR_log("CSR_RemovePeer: peer_id=" .. tostring(peer_id))
	_G.CSR_PlayerItems[peer_id] = nil
	invalidate_stacks()
end

-- Clear all peers except local (on leaving lobby)
function CSR_ClearRemotePeers()
	CSR_log("CSR_ClearRemotePeers called")
	local local_id = CSR_LocalPeerId()
	for peer_id, _ in pairs(_G.CSR_PlayerItems) do
		if peer_id ~= local_id then
			_G.CSR_PlayerItems[peer_id] = nil
		end
	end
	invalidate_stacks()
end

-- === SERIALIZATION (for network sync) ===

-- Encode a player's items as a string: "id1:lvl|id2:lvl|..."
function CSR_EncodeItems(peer_id)
	local data = _G.CSR_PlayerItems[peer_id]
	if not data or not data.items or #data.items == 0 then
		return ""
	end
	local parts = {}
	for _, item in ipairs(data.items) do
		table.insert(parts, item.id .. ":" .. tostring(item.level or 0))
	end
	return table.concat(parts, "|")
end

-- Decode an item string back into a table
function CSR_DecodeItems(encoded)
	local items = {}
	if not encoded or encoded == "" then
		return items
	end
	for item_str in string.gmatch(encoded, "[^|]+") do
		local id, level_str = string.match(item_str, "([^:]+):(%d+)")
		if id then
			table.insert(items, { id = id, level = tonumber(level_str) or 0 })
		end
	end
	return items
end

-- === SESSION FILE (csr_mp_sessions.json) ===

local SESSION_FILE = SavePath .. "csr_mp_sessions.json"
local SESSION_EXPIRY_DAYS = 14

-- Load all saved sessions, prune expired entries
function CSR_LoadSessions()
	local file = io.open(SESSION_FILE, "r")
	if not file then
		return {}
	end

	local content = file:read("*a")
	file:close()

	local ok, data = pcall(json.decode, content)
	if not ok or type(data) ~= "table" then
		return {}
	end

	-- Prune entries older than SESSION_EXPIRY_DAYS
	local now = os.time()
	local pruned = {}
	for seed_key, session in pairs(data) do
		if session.last_played then
			local y, m, d = string.match(session.last_played, "(%d+)-(%d+)-(%d+)")
			if y then
				local saved_time = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
				if (now - saved_time) < SESSION_EXPIRY_DAYS * 86400 then
					pruned[seed_key] = session
				end
			end
		end
	end

	return pruned
end

-- Save a session entry for a foreign run
function CSR_SaveSession(run_seed, host_name, my_items, total_drops, printer_uses)
	local sessions = CSR_LoadSessions()
	local key = tostring(run_seed)

	-- Serialize items
	local items_data = {}
	for _, item in ipairs(my_items or {}) do
		table.insert(items_data, { id = item.id, level = item.level or 0 })
	end

	-- Pull local player's token balance from the live store so callers don't
	-- have to plumb tokens through their signatures (CSR_SaveSession has many
	-- call sites). Falls back to 0 if the store is missing for any reason.
	local local_peer = CSR_LocalPeerId and CSR_LocalPeerId() or 1
	local local_data = _G.CSR_PlayerItems and _G.CSR_PlayerItems[local_peer]
	local local_tokens = (local_data and local_data.tokens) or 0

	-- Pull the Gage Shop state from the live global (optional — nil if shop
	-- hasn't been rolled yet this run). Same no-signature-change rationale as
	-- local_tokens above.
	local local_shop = (CSR_ShopSerializeForJson and CSR_ShopSerializeForJson()) or nil

	-- Per-peer shop purchase count so late-join rejoins don't lose the
	-- milestone-exclusion math (see crimespree_filter.lua modifiers_to_select).
	local local_shop_bought = 0
	if _G.CSR_ShopItemsBought then
		local_shop_bought = _G.CSR_ShopItemsBought[local_peer] or 0
	end

	-- Same milestone-exclusion accounting for catchup grants.
	local local_catchup_received = 0
	if _G.CSR_CatchupItemsReceived then
		local_catchup_received = _G.CSR_CatchupItemsReceived[local_peer] or 0
	end

	-- Host cumulative tokens earned. Persisted here for MP clients who don't
	-- have a seed file. Clients receive this via TOKEN_STATE/TOKEN_AWARD RPCs but
	-- the value would be lost across a game restart without the session record.
	local host_earned = _G.CSR_HostTokensEarned or 0

	-- Host-only: per-user-id catchup watermarks. Persisted so a host restart
	-- doesn't reset the rejoin-farm protection within the same CS run. Clients
	-- write nothing for this field (their map is empty).
	local host_catchup_snapshots = _G.CSR_HostCatchupSnapshots or {}

	-- Local peer's catchup_received_budget watermark. Stored so a rejoining host
	-- can restore the per-peer snapshot and avoid double-granting on restart.
	local local_catchup_budget = (local_data and local_data.catchup_received_budget) or 0

	sessions[key] = {
		seed = run_seed,
		host_name = host_name or "Unknown",
		my_items = items_data,
		my_tokens = local_tokens,
		my_shop = local_shop,
		my_shop_bought = local_shop_bought,
		my_catchup_received = local_catchup_received,
		my_host_earned = host_earned,
		my_catchup_budget = local_catchup_budget,
		host_catchup_snapshots = host_catchup_snapshots,
		total_drops = total_drops or 0,
		printer_uses = printer_uses or {},
		last_played = os.date("%Y-%m-%d"),
	}

	local file = io.open(SESSION_FILE, "w")
	if file then
		file:write(json.encode(sessions))
		file:close()
	end
end

-- Look up a session by run seed
function CSR_LookupSession(run_seed)
	local sessions = CSR_LoadSessions()
	return sessions[tostring(run_seed)]
end

-- === AUTO-FILL FOR LATE JOIN ===

-- Generate N random items (no Contraband) using deterministic RNG
function CSR_AutoFillItems(count, cs_seed, peer_id)
	if count <= 0 then
		return
	end

	local registry = _G.CSR_ITEM_REGISTRY
	if not registry then
		return
	end

	-- Build pool of non-contraband items
	local pool = {}
	for _, item_def in ipairs(registry) do
		if item_def.rarity ~= "contraband" then
			table.insert(pool, item_def)
		end
	end
	if #pool == 0 then
		return
	end

	-- Deterministic RNG seeded per player
	local player_seed = (cs_seed or 0) + (peer_id or 1) * 104729
	math.randomseed(player_seed)

	local items = CSR_GetLocalItems()
	local level = managers.crime_spree and managers.crime_spree:spree_level() or 0

	for i = 1, count do
		-- Re-seed each iteration for determinism
		math.randomseed(player_seed + #items * 1337 + i * 7919)
		local pick = pool[math.random(1, #pool)]
		CSR_AddItem(pick.id_prefix, level)
	end

	-- Restore non-deterministic RNG for other consumers (auto-fill corrupts global state)
	math.randomseed(os.time())
end
