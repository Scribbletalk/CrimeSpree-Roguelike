# Gage Contraband Purchase Lines

**Date:** 2026-05-31
**Status:** Approved

## Summary

When buying a contraband item in the Black Market, the existing Gage dialogue strip shows either a generic purchase line (existing pool of 5) or a contraband-item-specific line, chosen 50/50.

## Architecture

No new systems. Extends the existing `pick_purchase_line()` / `_set_dialogue_line()` pipeline.

### Files Changed

| File | Change |
|------|--------|
| `lua/managers/shop.lua` | `pick_purchase_line(item_type, rarity)` — add optional args; 50/50 branch for contraband |
| `lua/menu/black_market/black_market_shop_page.lua` | `_on_buy()` — read slot before buy, pass item_type+rarity |
| `loc/english.json` | 5 new keys, one per contraband item |

### Logic

```
pick_purchase_line(item_type, rarity):
  if rarity == "contraband" AND item_type != nil AND math.random(2) == 1:
    return "csr_gage_line_purchase_" .. item_type
  else:
    return "csr_gage_line_purchase_" .. math.random(1, 5)  -- existing pool
```

### Slot Read Order

Slot data (`type`, `rarity`) is read from `CSR_Shop.get_lineup()[slot_index]` **before** `CSR_Shop.buy()` is called, so the slot is guaranteed non-nil and unmodified.

## Localization Keys (5)

```
csr_gage_line_purchase_crooked_badge
csr_gage_line_purchase_dead_mans_trigger
csr_gage_line_purchase_dozer_guide
csr_gage_line_purchase_equalizer
csr_gage_line_purchase_glass_pistol
```

Text provided by user during implementation.

## Out of Scope

- Audio/VO
- Weighted probability (staying 50/50)
- MP sync (dialogue strip is local-only, consistent with existing lines)
