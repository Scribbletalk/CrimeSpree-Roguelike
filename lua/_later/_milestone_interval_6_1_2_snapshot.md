# Milestone Interval 20 → 10 — parked from 6.1.2 WIP

**Parked:** 2026-05-08
**Reason:** User reverted; will come back to it. The whole 6.1.2 milestone-interval tune is banked here verbatim so a future re-apply is a paste-back, not a re-derivation.

This is a multi-file inline patch (not a movable `.lua` feature), so it lives as a markdown snapshot rather than as code under `lua/_later/`. The mod loader ignores `.md` files; nothing here is wired into mod.txt.

---

## Goal of the original change

Items + vanilla loud modifiers drop every **10** rank instead of every **20**. Max start-level button on the briefing halves accordingly. The previous attempt (changing only the tweakdata value) had no effect because 5 hardcoded consumers used the literal `20`. The 6.1.2 patch hoists every consumer to read from `tweak_data.crime_spree.modifier_levels.loud` so future tunes are a one-line change.

Per `feedback_grep_literal_for_hardcoded_consumers.md` — that grep heuristic was born here.

---

## Re-apply checklist

1. Restore the 5 patches below verbatim.
2. MP-test both host and client per `feedback_check_host_and_client.md` — the multiplayer_sync edits are the highest-risk surface.
3. Heads-up in changelog: high-rank existing CS saves will see a "catch-up burst" of item rolls when the rank passes the new interval the first time after update — self-corrects after one popup cycle.
4. Don't forget the difficulty-button regen in `difficulty_select.lua` — easy to miss because it's a UI-only file.

---

## Patch 1 — `lua/tweakdata/crimespree.lua`

### 1a. Comment block + constants (around line 286–293)

**Pre-revert (apply this on re-enable):**
```lua
	-- === FORCED MODIFIERS ===
	-- HP/Damage: every level (+0.4% HP, +0.3% DMG, additive)
	-- Loud (vanilla): every 10 levels (10, 20, 30, ...)
	-- Stealth: every 10 levels (10, 20, 30, ...)
	-- BOTH can occur on the same level (loud + stealth) - handled in code!
	-- Reduced from 20 → 10 on 2026-05-07 (user direction). Must stay in sync
	-- with self.modifier_levels.loud / .forced at the bottom of this file.
	local STEALTH_INTERVAL = 10 -- Interval between stealth modifiers
	local STEALTH_START = 10 -- First stealth modifier at level 10 (same as loud)
	local LOUD_INTERVAL = 10 -- Loud every 10 levels
```

### 1b. `modifier_levels` (around line 1018–1021)

**Pre-revert (apply this on re-enable):**
```lua
	self.modifier_levels = self.modifier_levels or {}
	self.modifier_levels.loud = 10 -- Player items (chosen). Must match LOUD_INTERVAL above.
	self.modifier_levels.stealth = 9999 -- Unused
	self.modifier_levels.forced = 10 -- Stealth+Loud combined (both every 10 levels)
```

---

## Patch 2 — `lua/managers/crimespree_filter.lua`

### Around line 363–365 (inside `modifiers_to_select` PostHook body)

**Pre-revert (apply this on re-enable):**
```lua
			local _ml = tweak_data.crime_spree and tweak_data.crime_spree.modifier_levels
			local _interval = (_ml and _ml.loud) or 10
			local expected = math.floor(level / _interval)
```

---

## Patch 3 — `lua/managers/multiplayer_sync.lua`

### 3a. `_get_total_drops` (around line 161–166)

**Pre-revert (apply this on re-enable):**
```lua
-- Calculate total item drops a player should have at the current rank
-- Only counts milestone drops (rank / modifier_levels.loud). Bonus drops are
-- host-only and handled separately by the host's modifiers_to_select logic.
-- Reads interval from tweak_data so the value tracks any future change to
-- modifier_levels.loud automatically.
function CSR_MP._get_total_drops()
	local rank = managers.crime_spree and managers.crime_spree:spree_level() or 0
	local ml = tweak_data.crime_spree and tweak_data.crime_spree.modifier_levels
	local interval = (ml and ml.loud) or 10
	return math.floor(rank / interval)
end
```

### 3b. `broadcast_rank_up` (around line 231–234)

**Pre-revert (apply this on re-enable):**
```lua
	-- Only milestone drops (rank / modifier_levels.loud). Bonus drops are host-only.
	local ml = tweak_data.crime_spree and tweak_data.crime_spree.modifier_levels
	local interval = (ml and ml.loud) or 10
	local total_drops = math.floor(new_rank / interval)
```

### 3c. `apply_rank_up` else branch (around line 753–758)

**Pre-revert (apply this on re-enable):**
```lua
	if total_drops then
		_G.CSR_MP_TotalDrops = total_drops
	else
		local ml = tweak_data.crime_spree and tweak_data.crime_spree.modifier_levels
		local interval = (ml and ml.loud) or 10
		_G.CSR_MP_TotalDrops = math.floor(new_rank / interval)
	end
```

---

## Patch 4 — `lua/menu/difficulty_select.lua`

### Around line 239–250 (starting-level button generation)

**Pre-revert (apply this on re-enable):**
```lua
		-- === NEW STARTING LEVEL BUTTON SYSTEM ===
		-- Generate starting levels at every milestone interval (modifier_levels.loud)
		-- based on total loud modifier count. Each modifier occupies one
		-- LOUD_INTERVAL, so max start level = count × interval.
		-- Reads from tweak_data so the value tracks future changes automatically.
		local _ml = tweak_data.crime_spree and tweak_data.crime_spree.modifier_levels
		local LOUD_INTERVAL_UI = (_ml and _ml.loud) or 10
		local total_loud = _G.CSR_TotalLoudModifiers or 22
		local all_start_levels = {}
		for i = 1, total_loud do
			table.insert(all_start_levels, i * LOUD_INTERVAL_UI)
		end
```

---

## Player-facing changelog draft (re-use when shipping)

- Items now drop and modifiers now appear every 10 ranks (was every 20). Maximum starting level on the difficulty briefing is 220.

---

## Out of scope here

- **csr_heavies kill-switch** — separate change in same release, NOT parked. Stays disabled in the active code.
- **the_edge sound replacement** — separate change, NOT parked. Stays in active code.
- **`CSR_TotalLoudModifiers or 22` fallback** — kept active even after revert. The 22 reflects the post-csr_heavies-kill-switch count and is correct as-is.
