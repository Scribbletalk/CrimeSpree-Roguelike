-- CSRGameManager stat-dispatch helpers (Tier 1 split from game_manager.lua).
-- Effect dispatch helpers (local-player-scoped; return neutral outside a run).
if not CSRGameManager then
	return
end

local EMPTY_ITEM_LIST = {}

-- O(1) lookup of entries by effect.kind (empty list when none).
function CSRGameManager:items_of_kind(kind)
	return self._registry.by_kind[kind] or EMPTY_ITEM_LIST
end

-- Additive bonus for a stat across all owned stat_mul items: sum(per_stack * stacks). 0 outside a run.
function CSRGameManager:sum_stat_mul(stat)
	if not self:in_csr_heist() then
		return 0
	end
	local items = self._registry.by_kind.stat_mul
	if not items then
		return 0
	end
	local pid = self:local_peer_id()
	local total = 0
	for i = 1, #items do
		local e = items[i].effect
		if e.stat == stat then
			local stacks = self:item_count(pid, items[i].type)
			if stacks > 0 then
				total = total + (e.per_stack or 0) * stacks
			end
		end
	end
	if self._debug then
		self:_debug_stat("stat_mul", stat, total)
	end
	return total
end

-- Diminishing-returns bonus: each item b=cap*(1-1/(1+k*n)); combined as 1-prod(1-b). 0 outside a run.
function CSRGameManager:combine_stat_hyperbolic(stat)
	if not self:in_csr_heist() then
		return 0
	end
	local items = self._registry.by_kind.stat_hyperbolic
	if not items then
		return 0
	end
	local pid = self:local_peer_id()
	local remain = 1
	for i = 1, #items do
		local e = items[i].effect
		if e.stat == stat then
			local stacks = self:item_count(pid, items[i].type)
			if stacks > 0 then
				local k = (e.k_num or 1) / (e.k_den or 1)
				local b = (e.cap or 1) * (1 - 1 / (1 + k * stacks))
				remain = remain * (1 - b)
			end
		end
	end
	local combined = 1 - remain
	if self._debug then
		self:_debug_stat("hyperbolic", stat, combined)
	end
	return combined
end
