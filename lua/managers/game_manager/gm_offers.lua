-- CSRGameManager item-pool roll + pending offers (Tier 1 split from game_manager.lua).
if not CSRGameManager then
	return
end

-- Selection-window roll weights: contraband is 0 (never offered; still reachable via shop/scrapper).
local RARITY_WEIGHTS = {
	common = 60,
	uncommon = 24,
	rare = 4,
	wildcard = 12,
}
local MAX_WILDCARDS_PER_WINDOW = 1
local CARDS_PER_OFFER = 3

local function csr_weighted_pick(weights)
	local total = 0
	for _, w in pairs(weights) do
		total = total + w
	end
	if total <= 0 then
		return nil
	end
	local r = math.random() * total
	local cum = 0
	for rarity, w in pairs(weights) do
		cum = cum + w
		if r <= cum then
			return rarity
		end
	end
	-- Float epsilon: r > cum; take the last key seen.
	local last
	for k in pairs(weights) do
		last = k
	end
	return last
end

-- Roll count distinct items from the weighted pool. No duplicates within a window.
-- Shallow-copies buckets so the registry is never mutated.
function CSRGameManager:roll_item_pool(peer_id, count)
	count = math.max(1, tonumber(count) or 3)

	local buckets = {}
	for _, item in ipairs(self._registry.items) do
		local r = item.rarity
		if r and r ~= "contraband" and not item.is_scrap then
			buckets[r] = buckets[r] or {}
			table.insert(buckets[r], item)
		end
	end
	if next(buckets) == nil then
		return {}
	end

	local result = {}
	local wildcards_drawn = 0
	for _ = 1, count do
		local weights = {}
		for rarity, w in pairs(RARITY_WEIGHTS) do
			if w > 0 and buckets[rarity] and #buckets[rarity] > 0 then
				if rarity ~= "wildcard" or wildcards_drawn < MAX_WILDCARDS_PER_WINDOW then
					weights[rarity] = w
				end
			end
		end
		if next(weights) == nil then
			break -- no eligible items left across any rarity
		end
		local rarity = csr_weighted_pick(weights)
		if not rarity then
			break
		end
		local bucket = buckets[rarity]
		local item = table.remove(bucket, math.random(1, #bucket))
		result[#result + 1] = item
		if rarity == "wildcard" then
			wildcards_drawn = wildcards_drawn + 1
		end
	end

	return result
end

-- =====================================================
-- Pending offers (per-peer locked picks)
-- Each rank materialises a stored offer (frozen 3-card list) before the window opens.
-- Re-opening shows the same cards; only a confirmed pick pops it.
-- =====================================================

-- Ensure the peer has at least n pre-rolled stored offers. Idempotent (no-op if already >= n).
function CSRGameManager:ensure_offers(peer_id, n)
	n = math.max(0, tonumber(n) or 0)
	local entry = self:_own_entry(peer_id, true)
	entry.pending_offers = entry.pending_offers or {}
	local needed = n - #entry.pending_offers
	if needed <= 0 then
		return
	end
	local dirty = false
	for _ = 1, needed do
		local rolled = self:roll_item_pool(peer_id, CARDS_PER_OFFER)
		if #rolled == 0 then
			break -- registry too thin; UI shows "NO ITEMS" via peek_offer returning nil
		end
		local types = {}
		for _, def in ipairs(rolled) do
			types[#types + 1] = def.type
		end
		entry.pending_offers[#entry.pending_offers + 1] = types
		dirty = true
	end
	if dirty then
		self:save()
	end
	csr_log(
		"[CSR][mptest][offers] ensure_offers pid=" .. tostring(peer_id) .. " now=" .. tostring(#entry.pending_offers)
	)
end

function CSRGameManager:pending_offer_count(peer_id)
	local entry = self:_own_entry(peer_id, false)
	return (entry and entry.pending_offers and #entry.pending_offers) or 0
end

-- Read the first stored offer (resolved to live defs; filtered if addon vanished). Does NOT pop.
function CSRGameManager:peek_offer(peer_id)
	local entry = self:_own_entry(peer_id, false)
	local offers = entry and entry.pending_offers
	if not offers or #offers == 0 then
		return nil
	end
	local types = offers[1]
	local defs = {}
	for _, t in ipairs(types) do
		local def = self._registry.by_type[t]
		if def then
			defs[#defs + 1] = def
		end
	end
	csr_log("[CSR][mptest][offers] peek_offer pid=" .. tostring(peer_id) .. " cards=" .. tostring(#defs))
	return defs
end

-- Pop the first stored offer (called after add_item; discards all unchosen cards with it).
function CSRGameManager:pop_offer(peer_id)
	local entry = self:_own_entry(peer_id, false)
	local offers = entry and entry.pending_offers
	if not offers or #offers == 0 then
		return nil
	end
	local popped = table.remove(offers, 1)
	self:save()
	return popped
end
