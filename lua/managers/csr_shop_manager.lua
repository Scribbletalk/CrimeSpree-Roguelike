-- Crime Spree Roguelike -- Gage Services Shop
-- Per-peer lineup state, weighted draw, reroll, purchase.
-- Lineup state stored on _G.CSR_PlayerItems[peer_id]:
--   shop_lineup       -- array of { type, rarity, sold }
--   shop_reroll_count -- integer (current heist's reroll count)
--
-- Add-item API: CSR_AddItem(id_prefix, level)  [player_items_store.lua:188]
--   id_prefix is the registry entry's .id_prefix field (e.g. "player_health_boost_")
--   level defaults to current spree_level when nil
--   Local-only; shop is local-only per design, so this is correct.

CSR_ShopManager = CSR_ShopManager or {}

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR SHOP] " .. tostring(msg))
	end
end

local LINEUP_SIZE = 3
local MAX_DUP_RETRIES = 50

-- Gage dialogue line counts. Must match the localization key counts in
-- localization.lua (csr_gage_line_<category>_<n>). Picker is 1..N inclusive.
local GAGE_GREETING_COUNT = 12
local GAGE_REROLL_COUNT = 6
local GAGE_PURCHASE_COUNT = 5

-- Build a weighted pool of all non-Contraband, non-Wildcard items from CSR_ITEM_REGISTRY.
-- Returns: { { entry = registry_entry, weight = w }, ... }
function CSR_ShopManager.build_pool()
	local pool = {}
	if not _G.CSR_ITEM_REGISTRY then
		return pool
	end
	for _, entry in ipairs(_G.CSR_ITEM_REGISTRY) do
		if entry.rarity ~= "contraband" and entry.rarity ~= "wildcard" then
			-- Wildcard intentionally excluded until Wildcards exist and are priced.
			-- Once added, remove the wildcard guard (or add a price entry in
			-- CSR_TokensManager.PRICE) and the picker will include them automatically.
			table.insert(pool, { entry = entry, weight = entry.weight or 0.5 })
		end
	end
	return pool
end

-- Single weighted pick from a pool. Returns the registry entry.
function CSR_ShopManager.pick_one(pool)
	if not pool or #pool == 0 then
		return nil
	end
	local total = 0
	for _, p in ipairs(pool) do
		total = total + p.weight
	end
	if total <= 0 then
		return pool[1].entry
	end
	local r = math.random() * total
	local acc = 0
	for _, p in ipairs(pool) do
		acc = acc + p.weight
		if r <= acc then
			return p.entry
		end
	end
	return pool[#pool].entry
end

-- Roll a fresh 3-slot lineup for a peer. Slots are distinct by item type.
-- Stores { { type=, rarity=, sold=false }, ... } in CSR_PlayerItems[peer_id].shop_lineup.
function CSR_ShopManager.roll_lineup(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local pool = CSR_ShopManager.build_pool()
	local lineup = {}
	local seen = {}

	for _ = 1, LINEUP_SIZE do
		local entry, retries = nil, 0
		repeat
			entry = CSR_ShopManager.pick_one(pool)
			retries = retries + 1
		until (entry and not seen[entry.type]) or retries >= MAX_DUP_RETRIES
		if entry then
			seen[entry.type] = true
			table.insert(lineup, { type = entry.type, rarity = entry.rarity, sold = false })
		end
	end

	if #lineup < LINEUP_SIZE then
		CSR_log("WARN roll_lineup: only " .. #lineup .. " distinct slots available (wanted " .. LINEUP_SIZE .. ")")
	end

	-- Stash on the per-peer record (slot exists in player_items_store.lua;
	-- reusing rather than creating a parallel namespace).
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		CSR_log("WARN roll_lineup: no record for peer " .. tostring(peer_id) .. " -- ignoring")
		return nil
	end
	pdata.shop_lineup = lineup
	pdata.shop_reroll_count = 0

	CSR_log("rolled lineup for peer=" .. tostring(peer_id) .. " count=" .. #lineup)
	return lineup
end

function CSR_ShopManager.get_lineup(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		return nil
	end
	-- Lazy first-roll: if no lineup has been rolled yet (e.g., player opens the
	-- shop before completing any heist), seed one now so the menu has cards to
	-- show. Subsequent rolls happen on heist completion or via reroll.
	if not pdata.shop_lineup or #pdata.shop_lineup == 0 then
		CSR_ShopManager.roll_lineup(peer_id)
	end
	return pdata.shop_lineup
end

function CSR_ShopManager.get_reroll_count(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	return (pdata and pdata.shop_reroll_count) or 0
end

function CSR_ShopManager.reroll_cost(peer_id)
	return CSR_ShopManager.get_reroll_count(peer_id) + 1
end

-- Reroll the lineup. Returns true on success, false if the peer can't afford it.
function CSR_ShopManager.reroll(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local cost = CSR_ShopManager.reroll_cost(peer_id)
	if not CSR_TokensManager.debit(peer_id, cost) then
		return false
	end
	local prev_count = CSR_ShopManager.get_reroll_count(peer_id)
	if not CSR_ShopManager.roll_lineup(peer_id) then
		CSR_TokensManager.credit(peer_id, cost)
		CSR_log("WARN reroll: roll_lineup failed, refunding " .. cost)
		return false
	end
	-- roll_lineup() resets shop_reroll_count to 0; restore and increment so the
	-- next reroll costs prev_count+2 (escalating within the current heist).
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if pdata then
		pdata.shop_reroll_count = prev_count + 1
	end
	CSR_log("reroll peer=" .. tostring(peer_id) .. " cost=" .. cost .. " new_count=" .. (prev_count + 1))
	return true
end

-- Purchase slot N of the current lineup. Returns true on success, false otherwise.
-- CSR_AddItem(id_prefix, level) is local-only, matching the local-only shop design.
function CSR_ShopManager.purchase(peer_id, slot_index)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local lineup = CSR_ShopManager.get_lineup(peer_id)
	if not lineup or not lineup[slot_index] then
		return false
	end
	local slot = lineup[slot_index]
	if slot.sold then
		return false
	end
	local price = CSR_TokensManager.price_for_rarity(slot.rarity)
	if not price or price == math.huge then
		CSR_log("purchase: no price defined for rarity=" .. tostring(slot.rarity))
		return false
	end
	if not CSR_TokensManager.debit(peer_id, price) then
		return false
	end

	-- Look up registry entry by type to get id_prefix for CSR_AddItem.
	local registry_entry = _G.CSR_ITEM_BY_TYPE and _G.CSR_ITEM_BY_TYPE[slot.type]
	if not registry_entry then
		CSR_TokensManager.credit(peer_id, price)
		CSR_log("purchase: registry entry not found for type=" .. tostring(slot.type))
		return false
	end

	if not registry_entry.id_prefix then
		CSR_TokensManager.credit(peer_id, price)
		CSR_log("purchase: missing id_prefix for type=" .. tostring(slot.type))
		return false
	end

	CSR_AddItem(registry_entry.id_prefix) -- local-player only by design; peer_id unused here

	-- Track shop purchases so crimespree_filter.lua:modifiers_to_select can
	-- subtract them from the milestone quota — without this, the engine sees
	-- the shop item as a "selected milestone" and (a) suppresses the next
	-- legitimate select-item button and (b) makes the "select item" button
	-- show up unpressable when counts go out of sync.
	_G.CSR_ShopItemsBought = _G.CSR_ShopItemsBought or {}
	_G.CSR_ShopItemsBought[peer_id] = (_G.CSR_ShopItemsBought[peer_id] or 0) + 1

	-- Mark sold BEFORE persisting so the save captures the new state. If we
	-- saved first, the third buy in a session would write [true,true,false]
	-- and the just-bought slot would re-appear as buyable after a rejoin.
	slot.sold = true

	-- Persist so the item survives transitions back to the lobby. Shop adds
	-- bypass vanilla's select_modifier path, so the autosave PostHook on
	-- select_modifier never fires — we have to drive the save ourselves.
	if managers and managers.crime_spree and managers.crime_spree.is_active and managers.crime_spree:is_active() then
		local cs_global = managers.crime_spree._global
		local seed = _G.CSR_CurrentSeed
		local difficulty = (cs_global and cs_global.selected_difficulty) or _G.CSR_CurrentDifficulty or "normal"
		if seed and CSR_SaveSeed then
			CSR_SaveSeed(seed, difficulty, cs_global and cs_global.modifiers)
		end
		-- MP client: seed save is host-only, so mirror to session file too.
		if _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and CSR_SaveSession then
			local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
			local td = _G.CSR_MP_TotalDrops or 0
			local rs = _G.CSR_MP_RunSeed
			if rs then
				CSR_SaveSession(rs, nil, items, td)
			end
			if seed and tostring(seed) ~= tostring(rs) then
				CSR_SaveSession(seed, nil, items, td)
			end
		end
	end

	-- Broadcast our updated item list so other peers' Items tabs reflect the
	-- purchase. CSR_AddItem only mutates the local pdata; without this the
	-- host's bought item never propagates to clients (and vice versa).
	if _G.CSR_MP and CSR_MP.is_multiplayer and CSR_MP.is_multiplayer() and CSR_MP.broadcast_own_items then
		CSR_MP.broadcast_own_items()
	end

	CSR_log(
		"purchase peer="
			.. tostring(peer_id)
			.. " slot="
			.. slot_index
			.. " type="
			.. slot.type
			.. " price="
			.. price
			.. " shop_total="
			.. tostring(_G.CSR_ShopItemsBought[peer_id])
	)
	return true
end

-- Called after a heist completes for the local peer.
-- Hooked from the heist-end handler in Task 5.
function CSR_ShopManager.on_heist_complete()
	local peer_id = CSR_TokensManager.local_peer_id()
	CSR_ShopManager.roll_lineup(peer_id)
	CSR_ShopManager.reset_greeting(peer_id)
end

-- === GAGE DIALOGUE ===

-- Returns the greeting line key for this peer. Picks lazily on first read so
-- a player who never completed a heist still gets a line, then keeps it stable
-- across menu open/close until the next heist completion clears it.
function CSR_ShopManager.get_or_pick_greeting(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		return "csr_gage_line_greeting_1"
	end
	if not pdata.gage_greeting_idx then
		pdata.gage_greeting_idx = math.random(1, GAGE_GREETING_COUNT)
	end
	return "csr_gage_line_greeting_" .. tostring(pdata.gage_greeting_idx)
end

-- Clear the cached greeting so the next get_or_pick_greeting picks a fresh one.
function CSR_ShopManager.reset_greeting(peer_id)
	peer_id = peer_id or CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if pdata then
		pdata.gage_greeting_idx = nil
	end
end

-- Action lines are ephemeral — picked on the spot, no persistence needed.
function CSR_ShopManager.pick_reroll_line()
	return "csr_gage_line_reroll_" .. tostring(math.random(1, GAGE_REROLL_COUNT))
end

function CSR_ShopManager.pick_purchase_line()
	return "csr_gage_line_purchase_" .. tostring(math.random(1, GAGE_PURCHASE_COUNT))
end

-- === PERSISTENCE ===

-- Serialize the local player's shop state to a plain-text string for the seed file.
-- Format: "reroll_count~type1:rarity1:sold1|type2:rarity2:sold2|..."
-- Seed file uses this (line 10). Returns "" when there is no lineup.
function CSR_ShopSerialize()
	local peer_id = CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		return ""
	end
	local reroll = pdata.shop_reroll_count or 0
	local lineup = pdata.shop_lineup
	if not lineup or #lineup == 0 then
		return tostring(reroll) .. "~"
	end
	local parts = {}
	for _, slot in ipairs(lineup) do
		local sold_str = slot.sold and "1" or "0"
		table.insert(parts, tostring(slot.type) .. ":" .. tostring(slot.rarity) .. ":" .. sold_str)
	end
	return tostring(reroll) .. "~" .. table.concat(parts, "|")
end

-- Deserialize shop state from the plain-text seed file string (line 10).
function CSR_ShopDeserialize(str)
	if not str or str == "" then
		return
	end
	local peer_id = CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		CSR_log("ShopDeserialize: no pdata for local peer -- ignored")
		return
	end
	local reroll_str, slots_str = string.match(str, "^(%d+)~(.*)$")
	if not reroll_str then
		CSR_log("ShopDeserialize: malformed string '" .. str .. "'")
		return
	end
	pdata.shop_reroll_count = tonumber(reroll_str) or 0
	local lineup = {}
	if slots_str and slots_str ~= "" then
		for slot_str in string.gmatch(slots_str, "[^|]+") do
			local item_type, rarity, sold_str = string.match(slot_str, "^([^:]+):([^:]+):([01])$")
			if item_type and rarity and sold_str then
				table.insert(lineup, { type = item_type, rarity = rarity, sold = sold_str == "1" })
			else
				CSR_log("ShopDeserialize: skipping malformed slot '" .. tostring(slot_str) .. "'")
			end
		end
	end
	pdata.shop_lineup = lineup
	CSR_log("ShopDeserialize: restored reroll=" .. pdata.shop_reroll_count .. " slots=" .. #lineup)
end

-- Serialize shop state to a Lua table for JSON (session file field my_shop).
-- Returns a table (json.encode-ready) or nil when there is no lineup.
function CSR_ShopSerializeForJson()
	local peer_id = CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		return nil
	end
	if not pdata.shop_lineup then
		return nil
	end
	local slots = {}
	for _, slot in ipairs(pdata.shop_lineup) do
		table.insert(slots, { type = slot.type, rarity = slot.rarity, sold = slot.sold })
	end
	return {
		reroll_count = pdata.shop_reroll_count or 0,
		lineup = slots,
		gage_greeting_idx = pdata.gage_greeting_idx,
	}
end

-- Deserialize shop state from the JSON table produced by CSR_ShopSerializeForJson.
-- Called during MP session restore in multiplayer_sync.lua.
function CSR_ShopDeserializeFromJson(tbl)
	if not tbl or type(tbl) ~= "table" then
		return
	end
	local peer_id = CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata then
		CSR_log("ShopDeserializeFromJson: no pdata for local peer -- ignored")
		return
	end
	pdata.shop_reroll_count = tonumber(tbl.reroll_count) or 0
	local lineup = {}
	for _, slot in ipairs(tbl.lineup or {}) do
		if slot.type and slot.rarity then
			-- Save migration: registry types were renamed to match player-facing
			-- names so def.type can never print as a generic noun. Without this
			-- remap old saves load with a type CSR_ITEM_BY_TYPE no longer
			-- indexes, and the slot renders blank in the shop.
			local TYPE_REMAP = {
				health = "dog_tags",
				damage = "evidence_rounds",
				car_keys = "falcogini_keys",
			}
			local slot_type = TYPE_REMAP[slot.type] or slot.type
			table.insert(lineup, { type = slot_type, rarity = slot.rarity, sold = slot.sold == true })
		end
	end
	pdata.shop_lineup = lineup
	pdata.gage_greeting_idx = tonumber(tbl.gage_greeting_idx) or nil
	CSR_log("ShopDeserializeFromJson: restored reroll=" .. pdata.shop_reroll_count .. " slots=" .. #lineup)
end

-- Reset shop state for the local player (called on CS reset / new run).
function CSR_ShopReset()
	local peer_id = CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if pdata then
		pdata.shop_lineup = nil
		pdata.shop_reroll_count = 0
		pdata.gage_greeting_idx = nil
	end
	CSR_log("ShopReset: cleared for peer=" .. tostring(peer_id))
end

CSR_log("loaded")
