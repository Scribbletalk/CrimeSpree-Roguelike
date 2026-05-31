# Gage Contraband Purchase Lines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the player buys a contraband item in the Black Market, Gage's dialogue strip shows either a generic purchase line (50%) or a contraband-item-specific line (50%).

**Architecture:** Extend `CSR_Shop.pick_purchase_line()` to accept `item_type` + `rarity`; read slot data before `CSR_Shop.buy()` in `_on_buy()`; add 5 loc keys to `english.json`.

**Tech Stack:** Lua (PAYDAY 2 / Diesel), JSON localization

---

### Task 1: Extend `pick_purchase_line()` in shop.lua

**Files:**
- Modify: `lua/managers/shop.lua:622-624`

- [ ] **Step 1: Replace the function**

File: `lua/managers/shop.lua`

Old (line 622–624):
```lua
function CSR_Shop.pick_purchase_line()
	return "csr_gage_line_purchase_" .. tostring(math.random(1, PURCHASE_COUNT))
end
```

New:
```lua
function CSR_Shop.pick_purchase_line(item_type, rarity)
	if rarity == "contraband" and item_type and math.random(2) == 1 then
		return "csr_gage_line_purchase_" .. item_type
	end
	return "csr_gage_line_purchase_" .. tostring(math.random(1, PURCHASE_COUNT))
end
```

---

### Task 2: Pass slot data from `_on_buy()` in black_market_shop_page.lua

**Files:**
- Modify: `lua/menu/black_market/black_market_shop_page.lua:693-710`

- [ ] **Step 1: Replace `_on_buy()`**

File: `lua/menu/black_market/black_market_shop_page.lua`

Old (lines 693–710):
```lua
function CrimeSpreeBlackMarketShopPage:_on_buy(slot_index)
	local ok = CSR_Shop.buy(CSR_Shop.local_peer_id(), slot_index)
	if not ok then
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("menu_error")
		end
		self:_flash_token_denied()
		return
	end

	if managers.menu_component and managers.menu_component.post_event then
		managers.menu_component:post_event("item_sell")
	end

	-- The bought slot stays SOLD until the next mission restocks the lineup; no free restock here.
	self:_set_dialogue_line(CSR_Shop.pick_purchase_line(), true)
	self:refresh()
end
```

New:
```lua
function CrimeSpreeBlackMarketShopPage:_on_buy(slot_index)
	local peer_id = CSR_Shop.local_peer_id()
	local lineup = CSR_Shop.get_lineup(peer_id)
	local slot = lineup and lineup[slot_index]
	local ok = CSR_Shop.buy(peer_id, slot_index)
	if not ok then
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("menu_error")
		end
		self:_flash_token_denied()
		return
	end

	if managers.menu_component and managers.menu_component.post_event then
		managers.menu_component:post_event("item_sell")
	end

	-- The bought slot stays SOLD until the next mission restocks the lineup; no free restock here.
	self:_set_dialogue_line(CSR_Shop.pick_purchase_line(slot and slot.type, slot and slot.rarity), true)
	self:refresh()
end
```

---

### Task 3: Add contraband loc keys to english.json

**Files:**
- Modify: `loc/english.json` (after line 82, after `csr_gage_line_purchase_5`)

- [ ] **Step 1: Insert 5 keys after `"csr_gage_line_purchase_5"`**

File: `loc/english.json`

After line:
```json
"csr_gage_line_purchase_5": "Another satisfied customer.",
```

Add (user fills in the `"..."` values before committing):
```json
"csr_gage_line_purchase_crooked_badge": "...",
"csr_gage_line_purchase_dead_mans_trigger": "...",
"csr_gage_line_purchase_dozer_guide": "...",
"csr_gage_line_purchase_equalizer": "...",
"csr_gage_line_purchase_glass_pistol": "...",
```

- [ ] **Step 2: User provides phrase text** — wait for user to fill in the 5 values above before proceeding.

---

### Task 4: Manual test + commit

- [ ] **Step 1: Launch game, start a Crime Spree run, open Black Market**

Verify:
- Non-contraband purchase → dialogue strip shows one of 5 generic lines
- Contraband purchase → dialogue strip shows either a generic line OR the item-specific line (roughly 50/50 over several buys)
- No Lua errors in `mods/logs/`

- [ ] **Step 2: Commit**

Stage files:
- `lua/managers/shop.lua`
- `lua/menu/black_market/black_market_shop_page.lua`
- `loc/english.json`

Commit message: `feat: add Gage contraband-specific purchase lines`
