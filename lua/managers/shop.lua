-- Gage Services shop (logic layer). Token wallet + per-heist earning + 3-card
-- standard lineup + 4th contraband slot + purchase + escalating reroll + Gage
-- dialogue. Per-peer state lives on managers.csr:peer_entry, persists with the run.

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
	-- Monotonic gross-earned accumulator — credit() is the single choke point both
	-- earn paths funnel through. Never reduced (debit/reroll refund go through set_tokens).
	-- Drives the late-joining guest's wallet seed in mp_session.lua.
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
-- Two independent streams: completion ranks + looted cash. Driven from
-- mission_lifecycle.lua's success path.

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

-- Per-token threshold = reward_per_rank / TOKENS_PER_RANK. Remainder carries on
-- peer entry so loot accumulates across heists.
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

-- Sellable registered items (common/uncommon/rare; never scrap).
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

-- Lazily rolls on first read. Old saves missing the contraband slot get one appended.
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

-- Contraband slot is NOT required for the free-restock trigger — buying the 3 standard
-- cards triggers it whether the player bought contraband or not.
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

-- Returns true / (true, "sold_out") on success; false + reason ("no_slot" / "sold" /
-- "no_price" / "cant_afford" / "add_failed") otherwise. Local-only by design.
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
	-- Tally shop_item_count BEFORE add_item so the on_item_added callback reads a
	-- consistent rank_item_count (shop purchases don't consume rank picks).
	-- Rolled back if add_item rejects the type so a bad entry never inflates.
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
	-- Free restock after the 3rd non-contraband card. UI defers the re-roll so the
	-- player sees the lineup for a beat first; shop page self-heals on open.
	if CSR_Shop.lineup_sold_out(peer_id) then
		csr_log("[CSR] shop: lineup sold out -> free restock pending")
		return true, "sold_out"
	end
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

function CSR_Shop.reroll(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m or not m.peer_entry then
		return false
	end
	local cost = CSR_Shop.reroll_cost(peer_id)
	if not CSR_Shop.debit(peer_id, cost) then
		return false
	end
	local prev = CSR_Shop.get_reroll_count(peer_id)
	if not CSR_Shop.roll_lineup(peer_id) then
		-- Refund: set_tokens (not credit) so refund doesn't inflate gross.
		CSR_Shop.set_tokens(peer_id, CSR_Shop.tokens(peer_id) + cost)
		return false
	end
	-- roll_lineup reset reroll_count to 0; restore+increment so next costs prev+2.
	m:peer_entry(peer_id).shop.reroll_count = prev + 1
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

-- ===== Gage dialogue =====
-- Loc-key counts must match the csr_gage_line_<category>_<n> entries in english.json.
local GREETING_COUNT = 12
local REROLL_COUNT = 6
local PURCHASE_COUNT = 5
local SOLDOUT_COUNT = 2

-- Greeting persists across menu open/close (next to wallet/lineup); picked lazily.
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

-- Action lines are ephemeral.
function CSR_Shop.pick_reroll_line()
	return "csr_gage_line_reroll_" .. tostring(math.random(1, REROLL_COUNT))
end

function CSR_Shop.pick_purchase_line()
	return "csr_gage_line_purchase_" .. tostring(math.random(1, PURCHASE_COUNT))
end

function CSR_Shop.pick_soldout_line()
	return "csr_gage_line_soldout_" .. tostring(math.random(1, SOLDOUT_COUNT))
end

csr_log("[CSR] shop.lua loaded")
