-- Crime Spree Roguelike — Gage Services shop (logic layer).
--
-- U1 port of the pre-refactor csr_shop_manager.lua + csr_tokens_manager.lua. The
-- old globals those leaned on (CSR_PlayerItems, CSR_ITEM_REGISTRY, CSR_AddItem,
-- CSR_SaveSeed/Session, CSR_MP) are GONE in U1; this rebuilds the same behaviour
-- on CSRGameManager primitives:
--   * per-peer state  -> managers.csr:peer_entry(pid)  (.tokens, .shop), persisted
--                        by the manager's save() and wiped on start_run/end_run
--   * item registry   -> managers.csr:registered_items()
--   * grant an item   -> managers.csr:add_item(pid, type)  (saves + fires callbacks)
--
-- MVP scope: token wallet + 3-card lineup + purchase. Reroll, Gage dialogue,
-- token EARNING and MP wallet sync are deferred to later slices.

if not RequiredScript then
	return
end

if _G.CSR_Shop then
	return
end

CSR_Shop = {}

-- Price by rarity, in Gage Tokens. Wildcard + contraband are not sold (no price)
-- and are excluded from the lineup pool.
CSR_Shop.PRICE = {
	common = 10,
	uncommon = 20,
	rare = 40,
}

-- Lineup roll weights by rarity (sellable tiers only). Mirrors CSRGameManager's
-- RARITY_WEIGHTS for common/uncommon/rare; the rarities absent here (wildcard,
-- contraband) never enter the shop pool.
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

-- Registered item def for a type ({} registry is small; a linear scan is cheap
-- and keeps the def lookup in the shop domain rather than widening the manager).
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

-- ===== Token wallet =====
-- Stored on the per-peer manager entry so it persists with the run and resets
-- (with the inventory) on start_run/end_run.

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
	CSR_Shop.set_tokens(peer_id, CSR_Shop.tokens(peer_id) + amount)
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

function CSR_Shop.price_for_rarity(rarity)
	return CSR_Shop.PRICE[rarity] or math.huge
end

-- ===== Lineup =====

-- All sellable registered items (common/uncommon/rare). Returns registry entries.
function CSR_Shop.build_pool()
	local pool = {}
	local m = mgr()
	if not m or not m.registered_items then
		return pool
	end
	for _, entry in ipairs(m:registered_items()) do
		if POOL_WEIGHTS[entry.rarity] then
			pool[#pool + 1] = entry
		end
	end
	return pool
end

-- One weighted pick (by rarity) from a pool of registry entries.
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

-- Roll a fresh 3-slot lineup (distinct item types) and store it on the per-peer
-- entry as { shop = { lineup = { { type, rarity, sold }, ... } } } + save.
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
	-- reroll_count resets to 0 on a fresh lineup; reroll() restores+increments it.
	m:peer_entry(peer_id).shop = { lineup = lineup, reroll_count = 0 }
	m:save()
	return lineup
end

-- Current lineup, rolled lazily on first read (a player opening the shop before
-- any heist still sees cards).
function CSR_Shop.get_lineup(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	if not m or not m.peer_entry then
		return {}
	end
	local entry = m:peer_entry(peer_id)
	if not entry.shop or not entry.shop.lineup or #entry.shop.lineup == 0 then
		CSR_Shop.roll_lineup(peer_id)
		entry = m:peer_entry(peer_id)
	end
	return entry.shop.lineup
end

-- Buy slot N of the current lineup. Returns true on success; false + a reason
-- string ("no_slot" / "sold" / "no_price" / "cant_afford" / "add_failed") otherwise.
-- Local-only by design (mirrors the old shop): add_item mutates the local peer's
-- inventory and the wallet is per-peer; MP wallet sync is a later slice.
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
	-- add_item validates the type against the registry and persists; only charge
	-- once it sticks, so a bad type never costs tokens.
	if not m:add_item(peer_id, slot.type) then
		return false, "add_failed"
	end
	CSR_Shop.debit(peer_id, price)
	slot.sold = true
	m:save()
	log(
		"[CSR] shop: bought slot " .. tostring(slot_index) .. " (" .. tostring(slot.type) .. ") for " .. tostring(price)
	)
	return true
end

-- ===== Reroll =====
-- Cost escalates within the run: reroll_count starts at 0 (set by roll_lineup),
-- so the first reroll costs 1, the next 2, etc.

function CSR_Shop.get_reroll_count(peer_id)
	peer_id = peer_id or CSR_Shop.local_peer_id()
	local m = mgr()
	local shop = m and m.peer_entry and m:peer_entry(peer_id).shop
	return (shop and shop.reroll_count) or 0
end

function CSR_Shop.reroll_cost(peer_id)
	return CSR_Shop.get_reroll_count(peer_id) + 1
end

-- Reroll the lineup. Returns true on success, false if the peer can't afford it.
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
		CSR_Shop.credit(peer_id, cost) -- refund on roll failure
		return false
	end
	-- roll_lineup reset reroll_count to 0; restore + increment so the next reroll
	-- costs prev+2 (escalating within the current run).
	m:peer_entry(peer_id).shop.reroll_count = prev + 1
	m:save()
	return true
end

-- ===== Owned-stack count (for the card's "x N owned" badge) =====
function CSR_Shop.owned_count(peer_id, item_type)
	local m = mgr()
	if not m or not m.item_count then
		return 0
	end
	return m:item_count(peer_id or CSR_Shop.local_peer_id(), item_type)
end

-- ===== Gage dialogue =====
-- Loc-key counts must match the csr_gage_line_<category>_<n> entries in
-- english.json (greeting 12, reroll 6, purchase 5). Picker is 1..N inclusive.
local GREETING_COUNT = 12
local REROLL_COUNT = 6
local PURCHASE_COUNT = 5

-- Greeting persists across menu open/close (stored on the per-peer entry, next
-- to the wallet/lineup) so re-opening the shop keeps the same line. Picked lazily.
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

-- Action lines are ephemeral — picked on the spot, no persistence needed.
function CSR_Shop.pick_reroll_line()
	return "csr_gage_line_reroll_" .. tostring(math.random(1, REROLL_COUNT))
end

function CSR_Shop.pick_purchase_line()
	return "csr_gage_line_purchase_" .. tostring(math.random(1, PURCHASE_COUNT))
end

log("[CSR] shop.lua loaded (Gage Services logic)")
