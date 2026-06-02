-- CSRGameManager item inventory, peer counts & remote-peer mirror (Tier 1 split from game_manager.lua).
if not CSRGameManager then
	return
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

-- =====================================================
-- Items
-- =====================================================

local function get_or_create_peer_entry(state, peer_id)
	local entry = state.peer_items[peer_id]
	if not entry then
		entry = { counts = {} }
		state.peer_items[peer_id] = entry
	end
	-- Migrate legacy { items = [...] } save shape to { counts = { [type]=n } }.
	if entry.items and not entry.counts then
		local counts = {}
		for _, it in ipairs(entry.items) do
			if it.type then
				counts[it.type] = (counts[it.type] or 0) + 1
			end
		end
		entry.counts = counts
		entry.items = nil
	end
	entry.counts = entry.counts or {}
	-- Tracks first-acquire order for the Items panel sort; self-heals from counts when absent.
	entry.order = entry.order or {}
	return entry
end

-- pcall-guarded os.time(); returning 0 on error makes TTL pruning never fire (safe default).
function CSRGameManager:_now()
	local ok, t = pcall(os.time)
	return (ok and type(t) == "number") and t or 0
end

-- True when acting as a client in an announced CSR run (host_seed known).
function CSRGameManager:_is_guesting()
	local mp = self._state.mp_session
	local net = _G.CSR_MP
	if not (net and net.is_client and net.is_client()) then
		return false
	end
	return mp ~= nil and mp.host_seed ~= nil
end

-- Key for the active guest session store ("h<seed>"); nil when not guesting.
function CSRGameManager:_guest_session_key()
	local mp = self._state.mp_session
	local seed = mp and mp.host_seed
	if seed == nil then
		return nil
	end
	return "h" .. tostring(seed)
end

-- Per-host guest session entry (same shape as peer_items entry). Lazily created when create=true.
-- Lives in _meta so it survives the guest's own run transitions; pruned only by age.
function CSRGameManager:_guest_session_entry(create)
	local key = self:_guest_session_key()
	if not key then
		return nil
	end
	self._meta.mp_sessions = self._meta.mp_sessions or {}
	local sess = self._meta.mp_sessions[key]
	if not sess then
		if not create then
			return nil
		end
		sess = { entry = { counts = {}, order = {} }, last_seen = self:_now() }
		self._meta.mp_sessions[key] = sess
	elseif create then
		sess.last_seen = self:_now()
	end
	sess.entry = sess.entry or { counts = {}, order = {} }
	sess.entry.counts = sess.entry.counts or {}
	sess.entry.order = sess.entry.order or {}
	return sess.entry
end

-- Own-side inventory entry: guest session store while guesting, else _state.peer_items.
-- create=true lazily allocates; false returns nil for unknown peers.
function CSRGameManager:_own_entry(peer_id, create)
	if peer_id == self:local_peer_id() and self:_is_guesting() then
		return self:_guest_session_entry(create)
	end
	if create then
		return get_or_create_peer_entry(self._state, peer_id)
	end
	return self._state.peer_items[peer_id]
end

-- Counts table for any peer: remote synced items win over own-side. Returns nil when no record.
function CSRGameManager:_peer_counts(peer_id)
	local remote = self._remote_peer_items and self._remote_peer_items[peer_id]
	if remote then
		return remote.counts
	end
	local entry = self:_own_entry(peer_id, false)
	return entry and entry.counts
end

-- Read-only { [type] = n } map of everything the peer owns ({} if nothing).
function CSRGameManager:player_items(peer_id)
	return self:_peer_counts(peer_id) or {}
end

-- Raw acquisition-order array for a peer (remote synced wins over own-side; may be stale/missing).
function CSRGameManager:_peer_order(peer_id)
	local remote = self._remote_peer_items and self._remote_peer_items[peer_id]
	if remote then
		return remote.order
	end
	local entry = self:_own_entry(peer_id, false)
	return entry and entry.order
end

-- Item types in acquisition order; self-heals against live counts (handles legacy saves and remote peers without order).
function CSRGameManager:player_items_order(peer_id)
	local counts = self:_peer_counts(peer_id) or {}
	local stored = self:_peer_order(peer_id)
	local result, seen = {}, {}
	if type(stored) == "table" then
		for _, item_type in ipairs(stored) do
			if (counts[item_type] or 0) > 0 and not seen[item_type] then
				result[#result + 1] = item_type
				seen[item_type] = true
			end
		end
	end
	local missing = {}
	for item_type, n in pairs(counts) do
		if type(n) == "number" and n > 0 and not seen[item_type] then
			missing[#missing + 1] = item_type
		end
	end
	table.sort(missing)
	for _, item_type in ipairs(missing) do
		result[#result + 1] = item_type
	end
	return result
end

-- Scrap floats to the front of display lists, ordered rare > uncommon > common.
local CSR_SCRAP_DISPLAY_RANK = { rare = 1, uncommon = 2, common = 3 }

-- Display order: scrap first (rare->uncommon->common), then everything else in acquisition order.
-- Used by the items sidebar / owned strip / ESC items panel. Wraps player_items_order without
-- mutating it, so the network/canonical order (mp_sync) and the scrapper list stay untouched.
-- table.sort is unstable in LuaJIT, so non-scrap entries carry their original index as a tiebreaker.
function CSRGameManager:display_items_order(peer_id)
	local order = self:player_items_order(peer_id)
	local by_type = self._registry.by_type
	local decorated = {}
	for i, item_type in ipairs(order) do
		local def = by_type[item_type]
		local scrap_rank = nil
		if def and def.is_scrap then
			scrap_rank = CSR_SCRAP_DISPLAY_RANK[def.rarity] or 99
		end
		decorated[i] = { item_type = item_type, idx = i, scrap_rank = scrap_rank }
	end
	table.sort(decorated, function(a, b)
		if a.scrap_rank and b.scrap_rank then
			if a.scrap_rank ~= b.scrap_rank then
				return a.scrap_rank < b.scrap_rank
			end
			return a.idx < b.idx
		elseif a.scrap_rank then
			return true
		elseif b.scrap_rank then
			return false
		end
		return a.idx < b.idx
	end)
	local result = {}
	for i, d in ipairs(decorated) do
		result[i] = d.item_type
	end
	return result
end

-- Owned stacks of ONE item type.
function CSRGameManager:item_count(peer_id, item_type)
	local counts = self:_peer_counts(peer_id)
	return (counts and counts[item_type]) or 0
end

-- Total stacks across all types (used by the lobby "unselected items" reminder).
function CSRGameManager:total_item_count(peer_id)
	local counts = self:_peer_counts(peer_id)
	if not counts then
		return 0
	end
	local total = 0
	for _, n in pairs(counts) do
		total = total + n
	end
	return total
end

function CSRGameManager:has_item(peer_id, item_type)
	return self:item_count(peer_id, item_type) > 0
end

-- Items obtained outside rank picks (shop purchases). These don't count toward the rank quota.
-- Scrapper/copier is net-zero on total_item_count, so rank_item_count stays correct through transforms.
function CSRGameManager:shop_item_count(peer_id)
	local entry = self:_own_entry(peer_id or self:local_peer_id(), false)
	return (entry and entry.shop_item_count) or 0
end

-- Stacks from rank picks = total minus shop purchases (what the lobby reminder compares against host rank).
function CSRGameManager:rank_item_count(peer_id)
	peer_id = peer_id or self:local_peer_id()
	-- net_zero_picks compensates for rank picks that consumed an offer without growing the count
	-- (carry-1 wildcard swap or re-pick); see note_net_zero_rank_pick.
	local entry = self:_own_entry(peer_id, false)
	local adjust = (entry and entry.net_zero_picks) or 0
	return math.max(0, self:total_item_count(peer_id) - self:shop_item_count(peer_id) + adjust)
end

-- Record a confirmed rank pick that did NOT grow total_item_count (carry-1 wildcard swap or
-- re-picking the held wildcard). Without this the owed-pick quota (host_rank - rank_item_count)
-- never advances for such a pick, so the selection window re-opens for a free extra pick.
-- Called only from the selection finalize path, so shop/copier/scrapper transforms never inflate it.
function CSRGameManager:note_net_zero_rank_pick(peer_id)
	local entry = self:_own_entry(peer_id, true)
	if not entry then
		return
	end
	entry.net_zero_picks = (entry.net_zero_picks or 0) + 1
	self:save()
end

-- =====================================================
-- Remote peers' synced inventories (runtime-only, never saved)
-- =====================================================

-- Store a remote peer's synced counts + name. Does not fire callbacks or save (display-only).
function CSRGameManager:set_remote_peer_items(peer_id, counts, name, order)
	if not peer_id then
		return
	end
	self._remote_peer_items = self._remote_peer_items or {}
	self._remote_peer_items[peer_id] = { counts = counts or {}, name = name, order = order }
end

function CSRGameManager:remove_remote_peer(peer_id)
	if self._remote_peer_items then
		self._remote_peer_items[peer_id] = nil
	end
end

function CSRGameManager:clear_remote_peers()
	self._remote_peer_items = {}
end

function CSRGameManager:remote_peer_name(peer_id)
	local r = self._remote_peer_items and self._remote_peer_items[peer_id]
	return r and r.name
end

-- Peer ids we hold synced inventories for (includes the SP debug fake peer).
function CSRGameManager:remote_peer_ids()
	local ids = {}
	if self._remote_peer_items then
		for pid in pairs(self._remote_peer_items) do
			ids[#ids + 1] = pid
		end
	end
	return ids
end

-- Convenience: owned stacks for the local player (saves hooks from calling local_peer_id() explicitly).
function CSRGameManager:owned(item_type)
	return self:item_count(self:local_peer_id(), item_type)
end

-- Mutable per-peer state record (counts + shop wallet/lineup). Lazy-created.
-- Returns the guest session entry while guesting so tokens/offers never touch the paused run.
function CSRGameManager:peer_entry(peer_id)
	return self:_own_entry(peer_id or self:local_peer_id(), true)
end

-- Registered definition for a type (nil if unknown).
function CSRGameManager:item_def(item_type)
	return self._registry.by_type[item_type]
end

-- The peer's currently-held wildcard type, or nil. Wildcards are carry-1 and never stack.
function CSRGameManager:held_wildcard(peer_id)
	local counts = self:_peer_counts(peer_id)
	if not counts then
		return nil
	end
	local by_type = self._registry.by_type
	for item_type, n in pairs(counts) do
		if type(n) == "number" and n > 0 then
			local def = by_type[item_type]
			if def and def.rarity == "wildcard" then
				return item_type
			end
		end
	end
	return nil
end

function CSRGameManager:add_item(peer_id, item_type)
	local def = self._registry.by_type[item_type]
	if not def then
		log("[CSR] add_item: unknown type '" .. tostring(item_type) .. "' — ignored")
		return false
	end
	-- Wildcards are carry-1: one wildcard (any type) at a time, never stacks. A new pick replaces the old.
	if def.rarity == "wildcard" then
		local held = self:held_wildcard(peer_id)
		if held == item_type then
			return true
		end
		if held then
			self:remove_item(peer_id, held)
		end
	end
	local entry = self:_own_entry(peer_id, true)
	local was = entry.counts[item_type] or 0
	entry.counts[item_type] = was + 1
	-- First copy: append to acquisition order. Duplicates only bump the count.
	if was == 0 then
		entry.order = entry.order or {}
		entry.order[#entry.order + 1] = item_type
	end
	for _, fn in ipairs(self._callbacks.on_item_added) do
		fn(peer_id, item_type, entry.counts[item_type])
	end
	self:save()
	log_csr("add_item: peer=" .. tostring(peer_id) .. " type=" .. item_type .. " count=" .. entry.counts[item_type])
	return true
end

function CSRGameManager:remove_item(peer_id, item_type)
	local entry = self:_own_entry(peer_id, false)
	local counts = entry and entry.counts
	if not counts or not counts[item_type] or counts[item_type] <= 0 then
		return false
	end
	counts[item_type] = counts[item_type] - 1
	if counts[item_type] <= 0 then
		counts[item_type] = nil
		-- Last copy gone: remove from order so a future re-acquire counts as new.
		if entry.order then
			for i = #entry.order, 1, -1 do
				if entry.order[i] == item_type then
					table.remove(entry.order, i)
					break
				end
			end
		end
	end
	for _, fn in ipairs(self._callbacks.on_item_removed) do
		fn(peer_id, item_type, counts[item_type] or 0)
	end
	self:save()
	log_csr("remove_item: peer=" .. tostring(peer_id) .. " type=" .. item_type)
	return true
end
