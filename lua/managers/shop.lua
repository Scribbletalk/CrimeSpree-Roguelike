-- Gage Services shop: token wallet, per-heist earning, 3-card lineup + contraband slot, purchase, escalating reroll.

if not RequiredScript then
	return
end

if _G.CSR_Shop then
	return
end

CSR_Shop = {}

-- Wildcard never sold. Contraband is slot 4 (always offered, not in weighted 3-card pool).
CSR_Shop.PRICE = {
	common = 10,
	uncommon = 20,
	rare = 40,
	contraband = 30,
}

-- Weights for the 3 standard slots only.
local POOL_WEIGHTS = {
	common = 60,
	uncommon = 24,
	rare = 4,
}

local LINEUP_SIZE = 3
local MAX_DUP_RETRIES = 50

local function mgr()
	return managers and managers.csr
end

function CSR_Shop.local_peer_id()
	local m = mgr()
	return (m and m:local_peer_id()) or 1
end

function CSR_Shop.item_def(item_type)
	local m = mgr()
	if not m or not m.registered_items then
		return nil
	end
	for _, e in ipairs(m:registered_items()) do
		if e.type == item_type then
			return e
		end
	end
	return nil
end

-- ===== Token wallet (per-peer, run-scoped) =====

function CSR_Shop.tokens(peer_id)
	local m = mgr()
	if not m or not m.peer_entry then
		return 0
	end
	return m:peer_entry(peer_id or CSR_Shop.local_peer_id()).tokens or 0
end

function CSR_Shop.set_tokens(peer_id, value)
	local m = mgr()
	if not m or not m.peer_entry then
		return
	end
	m:peer_entry(peer_id or CSR_Shop.local_peer_id()).tokens = math.max(0, math.floor(value))
	m:save()
end

function CSR_Shop.credit(peer_id, amount)
	if (amount or 0) <= 0 then
		return
	end
	peer_id = peer_id or CSR_Shop.local_peer_id()
	-- Monotonic; never reduced — drives late-join wallet seed in mp_session.lua.
	local m = mgr()
	if m and m.peer_entry then
		local entry = m:peer_entry(peer_id)
		entry.tokens_earned = (entry.tokens_earned or 0) + amount
	end
	CSR_Shop.set_tokens(peer_id, CSR_Shop.tokens(peer_id) + amount)
end

function CSR_Shop.gross_earned(peer_id)
	local m = mgr()
	if not m or not m.peer_entry then
		return 0
	end
	return m:peer_entry(peer_id or CSR_Shop.local_peer_id()).tokens_earned or 0
end

function CSR_Shop.debit(peer_id, amount)
	if (amount or 0) <= 0 then
		return false
	end
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local cur = CSR_Shop.tokens(peer_id)
	if cur < amount then
		return false
	end
	CSR_Shop.set_tokens(peer_id, cur - amount)
	return true
end

-- ===== Token earning (per-heist) =====

CSR_Shop.TOKENS_PER_RANK = 5

function CSR_Shop.award_completion_tokens(peer_id, completion_ranks)
	completion_ranks = tonumber(completion_ranks) or 0
	if completion_ranks <= 0 then
		return 0
	end
	local tokens = completion_ranks * CSR_Shop.TOKENS_PER_RANK
	CSR_Shop.credit(peer_id, tokens)
	return tokens
end

-- Remainder carries forward across heists so loot accumulates fractionally.
function CSR_Shop.accrue_loot_tokens(peer_id, loot_cash)
	loot_cash = tonumber(loot_cash) or 0
	local m = mgr()
	if loot_cash <= 0 or not m or not m.peer_entry or not m.reward_per_rank_cash then
		return 0
	end
	local per_token = m:reward_per_rank_cash() / CSR_Shop.TOKENS_PER_RANK
	if per_token <= 0 then
		return 0
	end
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local entry = m:peer_entry(peer_id)
	local acc = (entry.loot_token_cash or 0) + loot_cash
	local tokens = math.floor(acc / per_token)
	entry.loot_token_cash = acc - tokens * per_token
	if tokens > 0 then
		CSR_Shop.credit(peer_id, tokens)
	else
		m:save() -- persist the carried remainder
	end
	return tokens
end

function CSR_Shop.price_for_rarity(rarity)
	return CSR_Shop.PRICE[rarity] or math.huge
end

-- ===== Lineup =====

-- Sellable pool: common/uncommon/rare only, no scrap.
function CSR_Shop.build_pool()
	local pool = {}
	local m = mgr()
	if not m or not m.registered_items then
		return pool
	end
	for _, entry in ipairs(m:registered_items()) do
		if POOL_WEIGHTS[entry.rarity] and not entry.is_scrap then
			pool[#pool + 1] = entry
		end
	end
	return pool
end

function CSR_Shop.build_contraband_pool()
	local pool = {}
	local m = mgr()
	if not m or not m.registered_items then
		return pool
	end
	for _, entry in ipairs(m:registered_items()) do
		if entry.rarity == "contraband" and not entry.is_scrap then
			pool[#pool + 1] = entry
		end
	end
	return pool
end

local function pick_one(pool)
	if not pool or #pool == 0 then
		return nil
	end
	local total = 0
	for _, e in ipairs(pool) do
		total = total + (POOL_WEIGHTS[e.rarity] or 0)
	end
	if total <= 0 then
		return pool[1]
	end
	local r = math.random() * total
	local acc = 0
	for _, e in ipairs(pool) do
		acc = acc + (POOL_WEIGHTS[e.rarity] or 0)
		if r <= acc then
			return e
		end
	end
	return pool[#pool]
end

-- Slots 1-3: weighted distinct picks. Slot 4: uniform-random contraband.
function CSR_Shop.roll_lineup(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m or not m.peer_entry then
		return nil
	end
	local pool = CSR_Shop.build_pool()
	local lineup = {}
	local seen = {}
	for _ = 1, LINEUP_SIZE do
		local entry, retries = nil, 0
		repeat
			entry = pick_one(pool)
			retries = retries + 1
		until (entry and not seen[entry.type]) or retries >= MAX_DUP_RETRIES
		if entry and not seen[entry.type] then
			seen[entry.type] = true
			lineup[#lineup + 1] = { type = entry.type, rarity = entry.rarity, sold = false }
		end
	end
	local cb_pool = CSR_Shop.build_contraband_pool()
	csr_log("[CSR] shop: roll_lineup contraband pool size = " .. tostring(#cb_pool))
	if #cb_pool > 0 then
		local cb = cb_pool[math.random(#cb_pool)]
		lineup[#lineup + 1] = { type = cb.type, rarity = cb.rarity, sold = false }
		csr_log("[CSR] shop: roll_lineup contraband slot = " .. tostring(cb.type))
	end
	m:peer_entry(peer_id).shop = { lineup = lineup, reroll_count = 0 }
	m:save()
	return lineup
end

-- Rolls on first read; appends missing contraband slot to pre-contraband saves.
function CSR_Shop.get_lineup(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m or not m.peer_entry then
		return {}
	end
	local entry = m:peer_entry(peer_id)
	if not entry.shop or not entry.shop.lineup or #entry.shop.lineup == 0 then
		csr_log("[CSR] shop: get_lineup rolling fresh lineup for peer " .. tostring(peer_id))
		CSR_Shop.roll_lineup(peer_id)
		entry = m:peer_entry(peer_id)
	elseif #entry.shop.lineup == LINEUP_SIZE then
		-- Pre-contraband save: append one without disturbing the 3 existing cards.
		csr_log("[CSR] shop: migrating lineup to add contraband slot (peer " .. tostring(peer_id) .. ")")
		local cb_pool = CSR_Shop.build_contraband_pool()
		csr_log("[CSR] shop: contraband pool size = " .. tostring(#cb_pool))
		if #cb_pool > 0 then
			local cb = cb_pool[math.random(#cb_pool)]
			entry.shop.lineup[#entry.shop.lineup + 1] = { type = cb.type, rarity = cb.rarity, sold = false }
			m:save()
		end
	end
	csr_log("[CSR] shop: get_lineup returning " .. tostring(#entry.shop.lineup) .. " slots")
	return entry.shop.lineup
end

-- Sold-out = all 3 standard slots bought; contraband slot doesn't count.
function CSR_Shop.lineup_sold_out(peer_id)
	local lineup = CSR_Shop.get_lineup(peer_id)
	if not lineup or #lineup == 0 then
		return false
	end
	local any = false
	for _, slot in ipairs(lineup) do
		if slot.rarity ~= "contraband" then
			any = true
			if not slot.sold then
				return false
			end
		end
	end
	return any
end

-- Returns true on success, or false + reason string on failure.
-- A bought slot stays SOLD until the next mission completes (lineup restocks in mission_lifecycle).
function CSR_Shop.buy(peer_id, slot_index)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m then
		return false, "no_manager"
	end
	local lineup = CSR_Shop.get_lineup(peer_id)
	local slot = lineup and lineup[slot_index]
	if not slot then
		return false, "no_slot"
	end
	if slot.sold then
		return false, "sold"
	end
	local price = CSR_Shop.price_for_rarity(slot.rarity)
	if not price or price == math.huge then
		return false, "no_price"
	end
	if CSR_Shop.tokens(peer_id) < price then
		return false, "cant_afford"
	end
	-- Increment before add_item so the callback sees a consistent rank_item_count; roll back on failure.
	local entry = m:peer_entry(peer_id)
	entry.shop_item_count = (entry.shop_item_count or 0) + 1
	if not m:add_item(peer_id, slot.type) then
		entry.shop_item_count = entry.shop_item_count - 1
		return false, "add_failed"
	end
	CSR_Shop.debit(peer_id, price)
	slot.sold = true
	m:save()
	csr_log(
		"[CSR] shop: bought slot " .. tostring(slot_index) .. " (" .. tostring(slot.type) .. ") for " .. tostring(price)
	)
	return true
end

-- ===== Reroll (escalating cost within the run) =====

function CSR_Shop.get_reroll_count(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	local shop = m and m.peer_entry and m:peer_entry(peer_id).shop
	return (shop and shop.reroll_count) or 0
end

function CSR_Shop.reroll_cost(peer_id)
	return CSR_Shop.get_reroll_count(peer_id) + 1
end

-- Rerolls UNSOLD slots IN PLACE (standard + contraband); sold slots stay sold and untouched.
-- Reroll stays usable as long as ANY slot is unsold (e.g. the contraband slot after the 3 standard
-- cards are bought). Returns false without charging when every slot is sold.
function CSR_Shop.reroll(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m or not m.peer_entry then
		return false
	end
	local lineup = CSR_Shop.get_lineup(peer_id)
	local any_unsold = false
	for _, slot in ipairs(lineup) do
		if not slot.sold then
			any_unsold = true
			break
		end
	end
	if not any_unsold then
		return false
	end
	local cost = CSR_Shop.reroll_cost(peer_id)
	if not CSR_Shop.debit(peer_id, cost) then
		return false
	end
	-- Keep the 3 standard cards distinct: seed dedup with the SOLD standard types we're preserving.
	local seen = {}
	for _, slot in ipairs(lineup) do
		if slot.rarity ~= "contraband" and slot.sold then
			seen[slot.type] = true
		end
	end
	local std_pool = CSR_Shop.build_pool()
	local cb_pool = CSR_Shop.build_contraband_pool()
	for _, slot in ipairs(lineup) do
		if not slot.sold then
			if slot.rarity == "contraband" then
				if #cb_pool > 0 then
					local cb = cb_pool[math.random(#cb_pool)]
					slot.type, slot.rarity = cb.type, cb.rarity
				end
			else
				local entry, retries = nil, 0
				repeat
					entry = pick_one(std_pool)
					retries = retries + 1
				until (entry and not seen[entry.type]) or retries >= MAX_DUP_RETRIES
				if entry then
					slot.type, slot.rarity = entry.type, entry.rarity
					seen[entry.type] = true
				end
			end
		end
	end
	m:peer_entry(peer_id).shop.reroll_count = CSR_Shop.get_reroll_count(peer_id) + 1
	m:save()
	return true
end

function CSR_Shop.owned_count(peer_id, item_type)
	local m = mgr()
	if not m or not m.item_count then
		return 0
	end
	return m:item_count(peer_id or CSR_Shop.local_peer_id(), item_type)
end

-- ===== Late-join auto-grant (guest catch-up) =====

-- A fair player buys at most 3 items per completed mission, so cap shop-sourced items at 3 * missions.
local LATE_JOIN_ITEM_CAP_PER_MISSION = 3

-- Auto-grant gives at most 1 wildcard total (add_item doesn't enforce the carry-1 rule). Only the
-- rank source can roll it — the shop never sells wildcards. Weight mirrors the selection window.
local LATE_JOIN_MAX_WILDCARDS = 1
local RANK_WILDCARD_WEIGHT = 12

-- Weighted rarity for one token-converted item, affordability-aware: rolls the shop's weighted
-- distribution (pick_one); if that rarity costs more than budget, falls back to the most expensive
-- AFFORDABLE rarity present in the pool. Returns a rarity string or nil.
local function roll_affordable_rarity(pool, budget)
	local item = pick_one(pool)
	if not item then
		return nil
	end
	if (CSR_Shop.PRICE[item.rarity] or math.huge) <= budget then
		return item.rarity
	end
	local best, best_price = nil, -1
	for _, e in ipairs(pool) do
		local p = CSR_Shop.PRICE[e.rarity] or math.huge
		if p <= budget and p > best_price then
			best, best_price = e.rarity, p
		end
	end
	return best
end

local function random_item_of_rarity(pool, rarity)
	local matches = {}
	for _, e in ipairs(pool) do
		if e.rarity == rarity then
			matches[#matches + 1] = e
		end
	end
	if #matches == 0 then
		return nil
	end
	return matches[math.random(1, #matches)]
end

-- Weighted rarity pick from a {rarity = weight} table (mirrors the selection window's roller).
local function weighted_rarity(weights)
	local total = 0
	for _, w in pairs(weights) do
		total = total + w
	end
	if total <= 0 then
		return nil
	end
	local roll = math.random() * total
	local acc = 0
	for rarity, w in pairs(weights) do
		acc = acc + w
		if roll <= acc then
			return rarity
		end
	end
	local last
	for r in pairs(weights) do
		last = r
	end
	return last
end

-- Wildcard-rarity sellable items (registry), used only by the rank source's capped wildcard draw.
local function build_wildcard_pool()
	local pool = {}
	local m = mgr()
	if not m or not m.registered_items then
		return pool
	end
	for _, entry in ipairs(m:registered_items()) do
		if entry.rarity == "wildcard" and not entry.is_scrap then
			pool[#pool + 1] = entry
		end
	end
	return pool
end

-- Wildcard-rarity stacks the peer already holds, so the grant never pushes them past carry-1.
local function wildcard_held(m, peer_id)
	if not m.registered_items or not m.item_count then
		return 0
	end
	local n = 0
	for _, entry in ipairs(m:registered_items()) do
		if entry.rarity == "wildcard" then
			n = n + (m:item_count(peer_id, entry.type) or 0)
		end
	end
	return n
end

-- Guest late-join catch-up.
--   A) RANK items: auto-grant the owed picks (host_rank - rank_item_count); self-corrects on re-grant.
--      Weighted like the selection window and may roll AT MOST 1 wildcard total (honouring carry-1);
--      everything else comes from the standard common/uncommon/rare pool.
--   B) SHOP items: convert the host's NEW gross tokens (gross - prev_gross) at shop prices, capped
--      cumulatively at 3 * host_missions shop items. Standard pool only — the shop never sells wildcards.
-- Returns leftover tokens (of the delta budget) for the caller to add to the wallet.
function CSR_Shop.auto_grant_late_join(peer_id, host_rank, gross, host_missions, prev_gross)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	host_rank = math.max(0, tonumber(host_rank) or 0)
	gross = math.max(0, tonumber(gross) or 0)
	host_missions = math.max(0, tonumber(host_missions) or 0)
	prev_gross = math.max(0, tonumber(prev_gross) or 0)
	local budget = math.max(0, gross - prev_gross)

	local m = mgr()
	if not m or not m.add_item then
		return budget
	end
	local pool = CSR_Shop.build_pool()
	if #pool == 0 then
		return budget
	end

	-- Source A: rank items (do NOT bump shop_item_count, so they count as rank picks).
	-- Weighted by POOL_WEIGHTS (+ wildcard) with a grant-wide wildcard cap that honours carry-1.
	local owned_rank = (m.rank_item_count and m:rank_item_count(peer_id)) or 0
	local wc_budget = math.max(0, LATE_JOIN_MAX_WILDCARDS - wildcard_held(m, peer_id))
	local wc_pool = build_wildcard_pool()
	local base_weights = {}
	for _, e in ipairs(pool) do
		base_weights[e.rarity] = POOL_WEIGHTS[e.rarity]
	end
	local wildcards_granted = 0
	for _ = 1, host_rank - owned_rank do
		local weights = base_weights
		if wc_budget > 0 and #wc_pool > 0 then
			weights = {}
			for r, w in pairs(base_weights) do
				weights[r] = w
			end
			weights.wildcard = RANK_WILDCARD_WEIGHT
		end
		local rarity = weighted_rarity(weights)
		local item
		if rarity == "wildcard" then
			item = wc_pool[math.random(#wc_pool)]
			wc_budget = wc_budget - 1
			wildcards_granted = wildcards_granted + 1
		elseif rarity then
			item = random_item_of_rarity(pool, rarity)
		end
		if not item then
			break
		end
		m:add_item(peer_id, item.type)
	end

	-- Source B: token -> shop items (delta budget, cumulative cap).
	local owned_shop = (m.shop_item_count and m:shop_item_count(peer_id)) or 0
	local cap = math.max(0, LATE_JOIN_ITEM_CAP_PER_MISSION * host_missions - owned_shop)
	local cheapest = CSR_Shop.PRICE.common or 10
	local granted = 0
	while budget >= cheapest and granted < cap do
		local rarity = roll_affordable_rarity(pool, budget)
		if not rarity then
			break
		end
		local item = random_item_of_rarity(pool, rarity)
		if not item then
			break
		end
		if not m:add_item(peer_id, item.type) then
			break
		end
		local entry = m:peer_entry(peer_id)
		entry.shop_item_count = (entry.shop_item_count or 0) + 1
		budget = budget - (CSR_Shop.PRICE[rarity] or cheapest)
		granted = granted + 1
	end

	csr_log(
		"[CSR] shop: late-join grant rank_owed="
			.. tostring(host_rank - owned_rank)
			.. " wildcards="
			.. tostring(wildcards_granted)
			.. " shop_items="
			.. tostring(granted)
			.. " leftover="
			.. tostring(budget)
	)
	return budget
end

-- ===== Gage dialogue =====
-- Counts must match csr_gage_line_<category>_<n> keys in english.json.
local GREETING_COUNT = 12
local REROLL_COUNT = 6
local PURCHASE_COUNT = 5

-- Greeting is picked once per run and persists across menu opens.
function CSR_Shop.get_or_pick_greeting(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m or not m.peer_entry then
		return "csr_gage_line_greeting_1"
	end
	local entry = m:peer_entry(peer_id)
	if not entry.gage_greeting then
		entry.gage_greeting = math.random(1, GREETING_COUNT)
		m:save()
	end
	return "csr_gage_line_greeting_" .. tostring(entry.gage_greeting)
end

function CSR_Shop.reset_greeting(peer_id)
	local m = mgr()
	if m and m.peer_entry then
		m:peer_entry(peer_id or CSR_Shop.local_peer_id()).gage_greeting = nil
	end
end

-- Action lines are ephemeral (re-picked each time).
function CSR_Shop.pick_reroll_line()
	return "csr_gage_line_reroll_" .. tostring(math.random(1, REROLL_COUNT))
end

function CSR_Shop.pick_purchase_line(item_type, rarity)
	if rarity == "contraband" and item_type then
		if math.random(2) == 1 then
			return "csr_gage_line_purchase_" .. item_type
		end
		return "csr_gage_line_purchase_contraband"
	end
	return "csr_gage_line_purchase_" .. tostring(math.random(1, PURCHASE_COUNT))
end

csr_log("[CSR] shop.lua loaded")
