-- CSRGameManager item callbacks + orphan/expired-session maintenance (Tier 1 split from game_manager.lua).
if not CSRGameManager then
	return
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

-- Per-host guest inventory is pruned after this many days (items only; bucket B cash has no TTL).
local MP_SESSION_TTL_DAYS = 7

-- =====================================================
-- Callback escape-hatch (on_apply / on_remove / on_tick)
-- Fires with exactly-once semantics; all callbacks are pcall-isolated.
-- =====================================================

function CSRGameManager:_callback_ctx(entry, count)
	return {
		mgr = self,
		peer_id = self:local_peer_id(),
		item_type = entry.type,
		count = count,
		is_run_active = self:is_run_active(),
	}
end

local function safe_invoke(fn, ctx, dt, type_id, which)
	local ok, err = pcall(fn, ctx, dt)
	if not ok then
		log("[CSR] " .. which .. " error for '" .. tostring(type_id) .. "': " .. tostring(err))
	end
end

function CSRGameManager:reconcile_callback_items()
	self._applied_callbacks = self._applied_callbacks or {}
	local list = self._registry.callback_items
	if #list == 0 then
		return
	end
	local pid = self:local_peer_id()
	local run_active = self:in_csr_heist()
	for i = 1, #list do
		local entry = list[i]
		local count = self:item_count(pid, entry.type)
		local should = run_active and count > 0
		local applied = self._applied_callbacks[entry.type]
		if should and not applied then
			self._applied_callbacks[entry.type] = true
			self:debug_log("callback on_apply '" .. tostring(entry.type) .. "' (count=" .. tostring(count) .. ")")
			if entry.on_apply then
				safe_invoke(entry.on_apply, self:_callback_ctx(entry, count), nil, entry.type, "on_apply")
			end
		elseif applied and not should then
			self._applied_callbacks[entry.type] = nil
			self:debug_log("callback on_remove '" .. tostring(entry.type) .. "'")
			if entry.on_remove then
				safe_invoke(entry.on_remove, self:_callback_ctx(entry, count), nil, entry.type, "on_remove")
			end
		end
	end
end

function CSRGameManager:tick_callback_items(dt)
	if not self:in_csr_heist() then
		return
	end
	local applied = self._applied_callbacks
	if not applied then
		return
	end
	local list = self._registry.callback_items
	local pid = self:local_peer_id()
	for i = 1, #list do
		local entry = list[i]
		if entry.on_tick and applied[entry.type] then
			local count = self:item_count(pid, entry.type)
			safe_invoke(entry.on_tick, self:_callback_ctx(entry, count), dt, entry.type, "on_tick")
		end
	end
end

-- Drop owned counts for item types no longer in the registry (addon removed/renamed).
-- Dropping a rank-pick orphan re-arms the lobby pick reminder.
function CSRGameManager:_drop_orphan_items()
	local dropped = 0
	local function sweep(counts)
		if not counts then
			return
		end
		for type_id, n in pairs(counts) do
			if not self._registry.by_type[type_id] then
				counts[type_id] = nil
				dropped = dropped + n
			end
		end
	end
	for _, entry in pairs(self._state.peer_items) do
		sweep(entry.counts)
	end
	if type(self._meta.mp_sessions) == "table" then
		for _, sess in pairs(self._meta.mp_sessions) do
			if type(sess) == "table" and sess.entry then
				sweep(sess.entry.counts)
			end
		end
	end
	if dropped > 0 then
		log_csr(
			"_drop_orphan_items: dropped "
				.. dropped
				.. " stack(s) of unregistered item(s); lobby reminder will re-arm so the player can reselect"
		)
		self:save()
	end
end

-- Prune guest session stores older than MP_SESSION_TTL_DAYS (items-only TTL; bucket B cash is untouched).
function CSRGameManager:_prune_expired_sessions()
	local sessions = self._meta.mp_sessions
	if type(sessions) ~= "table" then
		return
	end
	local now = self:_now()
	local cutoff = MP_SESSION_TTL_DAYS * 86400
	local removed = 0
	for key, sess in pairs(sessions) do
		local last = (type(sess) == "table" and tonumber(sess.last_seen)) or 0
		if now - last > cutoff then
			sessions[key] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		log_csr("_prune_expired_sessions: removed " .. removed .. " stale guest session(s)")
		self:save()
	end
end
