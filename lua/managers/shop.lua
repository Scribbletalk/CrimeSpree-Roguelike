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
-- MVP scope: token wallet + per-heist EARNING + 3-card lineup + purchase. Reroll,
-- Gage dialogue, and MP wallet sync are deferred to later slices.

if not RequiredScript then
	return
end

if _G.CSR_Shop then
	return
end

CSR_Shop = {}

-- Price by rarity, in Gage Tokens. Wildcard is never sold (no price). Contraband
-- occupies slot 4 (always offered, not part of the weighted 3-card pool).
CSR_Shop.PRICE = {
	common = 10,
	uncommon = 20,
	rare = 40,
	contraband = 30,
}

-- Lineup roll weights for the 3 standard slots (common/uncommon/rare only).
-- Wildcard and contraband are absent: wildcard is never sold; contraband has its
-- own dedicated 4th slot (always offered, picked from build_contraband_pool).
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
	-- Bump the gross-earned accumulator (run-scoped, monotonic): credit() is the
	-- single choke point both earn paths (completion + loot) funnel through. Never
	-- reduced -- debit() and the reroll refund use set_tokens directly -- so it
	-- tracks total tokens EARNED this run. That gross figure is what a host pushes
	-- to seed a late-joining guest's wallet (project_csr_late_join_grant_model).
	local m = mgr()
	if m and m.peer_entry then
		local entry = m:peer_entry(peer_id)
		entry.tokens_earned = (entry.tokens_earned or 0) + amount
	end
	CSR_Shop.set_tokens(peer_id, CSR_Shop.tokens(peer_id) + amount) -- set_tokens saves
end

-- Gross tokens EARNED this run (monotonic; never reduced by spend/refund). The
-- host-state push (mp_session.lua) carries this so a late-joining guest's wallet
-- can be seeded to it exactly (project_csr_late_join_grant_model).
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
-- A completed heist credits tokens via two independent paths, mirroring the run's
-- two reward streams (see project_csr_token_earning):
--   * completion ranks -> TOKENS_PER_RANK per rank the heist itself granted.
--   * looted cash       -> 1 token per (reward_per_rank / TOKENS_PER_RANK) of loot,
--                          with the cash remainder carried on the peer entry.
-- The loot->token path is deliberately separate from the manager's loot->rank
-- accrual (managers.csr:accrue_loot_rank): looted cash grants BOTH a token stream
-- and rank progress, not one converted from the other. Orchestrated from the
-- mission-lifecycle success hook; both are run-scoped (wallet + remainder reset on
-- start_run). MP wallet sync deferred (project_csr_mp_reward_model).

CSR_Shop.TOKENS_PER_RANK = 5

-- Tokens for the ranks the heist COMPLETION itself granted (1/2/3 by mission
-- length). Returns the number credited.
function CSR_Shop.award_completion_tokens(peer_id, completion_ranks)
	completion_ranks = tonumber(completion_ranks) or 0
	if completion_ranks <= 0 then
		return 0
	end
	local tokens = completion_ranks * CSR_Shop.TOKENS_PER_RANK
	CSR_Shop.credit(peer_id, tokens)
	return tokens
end

-- Feed looted cash into the peer's loot->token accumulator. Threshold per token is
-- the run's per-rank payout / TOKENS_PER_RANK (e.g. 200k on overkill). The cash
-- remainder carries on the peer entry (loot_token_cash) so nothing is lost across
-- heists. Returns the number of tokens credited this call.
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
		CSR_Shop.credit(peer_id, tokens) -- credit -> set_tokens -> save
	else
		m:save() -- persist the carried remainder
	end
	return tokens
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
		-- Scrap (printer fodder) is never sold -- it only enters inventory via the
		-- in-world scrapper, and the printer consumes it.
		if POOL_WEIGHTS[entry.rarity] and not entry.is_scrap then
			pool[#pool + 1] = entry
		end
	end
	return pool
end

-- All contraband items eligible for the 4th shop slot.
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

-- Roll a fresh lineup and store it on the per-peer entry as
-- { shop = { lineup = { { type, rarity, sold }, ... } } } + save.
-- Slots 1-3: weighted common/uncommon/rare pick (distinct types).
-- Slot 4:    one contraband item (uniform random from build_contraband_pool).
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
	-- Slot 4: contraband. Uniform random pick (no weights — all are equally rare).
	local cb_pool = CSR_Shop.build_contraband_pool()
	csr_log("[CSR] shop: roll_lineup contraband pool size = " .. tostring(#cb_pool))
	if #cb_pool > 0 then
		local cb = cb_pool[math.random(#cb_pool)]
		lineup[#lineup + 1] = { type = cb.type, rarity = cb.rarity, sold = false }
		csr_log("[CSR] shop: roll_lineup contraband slot = " .. tostring(cb.type))
	end
	-- reroll_count resets to 0 on a fresh lineup; reroll() restores+increments it.
	m:peer_entry(peer_id).shop = { lineup = lineup, reroll_count = 0 }
	m:save()
	return lineup
end

-- Current lineup, rolled lazily on first read (a player opening the shop before
-- any heist still sees cards).
-- Migration: if the saved lineup has exactly LINEUP_SIZE slots (pre-contraband-slot
-- save), append a contraband card without re-rolling the existing 3 slots.
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
		-- Old save: contraband slot missing. Append one without disturbing the 3 existing cards.
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

-- True when every non-contraband slot in the current lineup has been sold.
-- The contraband card (slot 4) is NOT required -- buying the 3 standard cards
-- triggers the free restock regardless of whether the player bought contraband.
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
	-- Tally this as a SHOP purchase BEFORE add_item, so add_item's on_item_added
	-- callback (the lobby/briefing reminder) reads a consistent rank-item count:
	-- a purchase adds an item but does NOT consume a rank pick (the manager's
	-- rank_item_count = total minus shop_item_count). Stored on the same per-peer
	-- entry as the wallet/lineup; rolled back if the (registry-validated) add
	-- somehow fails so a bad type never inflates the count.
	local entry = m:peer_entry(peer_id)
	entry.shop_item_count = (entry.shop_item_count or 0) + 1
	-- add_item validates the type against the registry and persists; only charge
	-- once it sticks, so a bad type never costs tokens.
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
	-- Buying the 3rd non-contraband card flags a FREE restock (return "sold_out");
	-- contraband does not count toward this threshold. The actual re-roll is deferred
	-- to the UI so it can show the lineup for a short beat first. The shop page also
	-- self-heals on open if the deferred roll was missed. roll_lineup (no debit) keeps
	-- this free. Local-only.
	if CSR_Shop.lineup_sold_out(peer_id) then
		csr_log("[CSR] shop: lineup sold out -> free restock pending")
		return true, "sold_out"
	end
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
		-- Refund on roll failure -- set_tokens (NOT credit) so the refund does not
		-- inflate the gross-earned accumulator (a refund is not an earn).
		CSR_Shop.set_tokens(peer_id, CSR_Shop.tokens(peer_id) + cost)
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
-- english.json (greeting 12, reroll 6, purchase 5, soldout 2). Picker is 1..N.
local GREETING_COUNT = 12
local REROLL_COUNT = 6
local PURCHASE_COUNT = 5
local SOLDOUT_COUNT = 2

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

-- Said when a purchase empties the whole lineup (the free restock case).
function CSR_Shop.pick_soldout_line()
	return "csr_gage_line_soldout_" .. tostring(math.random(1, SOLDOUT_COUNT))
end

csr_log("[CSR] shop.lua loaded (Gage Services logic)")
