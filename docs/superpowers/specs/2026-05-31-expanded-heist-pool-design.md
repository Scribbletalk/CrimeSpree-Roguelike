# Expanded vanilla heist pool for CSR — Design

Date: 2026-05-31
Status: approved approach, pending spec review

## Goal

CSR mission cards can roll the vanilla heists currently absent from Crime Spree
(~31 extra heists), each with correct card art, correct rank-reward (`add`
value), and correct card slot (stealth / short-loud / long-loud). Behavior
mirrors the reference mod "More Heists In Crime Spree" (MHiCS), restricted to
**normal heists only** (no Holdout / wave-defense levels for now).

### Success criteria (verify in-game)
1. Open the CSR lobby missions panel and reroll: new heists appear with proper
   atlas card art (not a generic placeholder).
2. The card slot matches heist type — slot 1 stealth-capable, slot 2 short loud,
   slot 3 long loud.
3. Completing an extra heist grants rank matching its length (`add` ≤5 → +1,
   ≤7 → +2, else +3), same thresholds CSR already uses.
4. MP: host and guest see the same heist on each card (ids resolve on guest via
   existing `get_mission`).
5. No Holdout heist (`chill_combat`) ever appears.

## Background — how the pieces work

- **CSR pool source.** `CSRGameManager:get_random_missions()`
  (`lua/managers/game_manager.lua:1708`) reads `tweak_data.crime_spree.missions`,
  a 3-bucket table (1 = stealth-capable, 2 = short loud, 3 = long loud), and
  picks one mission per bucket → 3 cards. CSR never mutates that table; it uses
  vanilla's as-is. Therefore expanding the pool = appending entries to that
  table at init. No change to selection, reroll, or MP code.
- **Vanilla structure.** `CrimeSpreeTweakData:init_missions(self, tweak_data)`
  builds `self.missions = { {…}, {…}, {…} }`; each entry is
  `{ stage_id, id, icon = "csm_<x>", add, level = tweak_data.narrative.stages.<x> }`.
- **MHiCS extras.** `base.lua:117-153` lists ~33 heists not in vanilla CS, with
  a `value` (= `add`) and optional `ghost`. `add_mission` / `repair_ghost_param`
  assign each to buckets from the level's ghost flags.
- **Card icon render.** `missions_menu.lua:1117` calls
  `tweak_data.hud_icons:get_icon_data(mission.icon)` — the standard HUD-icon
  lookup. Atlas-registered `csm_*` entries (texture + texture_rect) render
  exactly like vanilla cards.

## Decisions (confirmed with user)

| Decision | Choice |
|----------|--------|
| Icons | Port MHiCS's `mission_atlas.texture` 1:1 into CSR |
| Toggle | Always on — no settings field, no MP mismatch logic |
| Bucketing | Faithful port of MHiCS ghost/add bucket assignment |
| Holdout heists | Excluded for now (normal heists only) |

## Excluded from the port (MHiCS machinery CSR does not need)

- **DLC lock + network sync.** Narrative *stages* carry no `.dlc` (it lives on
  jobs); both vanilla CS and CSR filter on `mission.level.dlc`, which is inert.
  CS plays DLC heists without ownership (permissive model). MHiCS's
  `is_dlc_locked` exists only for its custom-heist auto-discovery, which we are
  not porting.
- **Custom-heist auto-discovery, dummy mission, mission history, reroll-fit
  algorithm.** CSR already owns reroll + MP sync.

Net: ~800 MHiCS lines → ~120 lines of CSR code + one texture asset.

## Heist list (31 normal extras)

From MHiCS `base.lua:117-153`, verbatim `value`, **minus**:
- `four_stores` — MHiCS itself disables it (1-ECM cheese).
- `chill_combat` — Holdout / wave-defense (`wave_count` + `group_ai_state="safehouse"`).

Included (stage_id = value): `vit=13, family=6, kenaz=13, jewelry_store=4,
ukrainian_job=5, gallery=4, welcome_to_the_jungle_1_d=4, dah=8, nightclub=5,
election_day_1=1 (ghost=1), mallcrasher=4, shoutout_raid=8, election_day_3=6,
watchdogs_2_d=6, crojob2_d=14, bph=13, nmh=13 (ghost=0), des=14, peta_1=14,
peta_2=14, mex=14, mex_cooking=7, fex=10, chas=5, sand=9, chca=8, pent=9,
ranc=8, trai=12, corp=7, deep=12`.

All 31 stage_ids verified present in `tweak_data.narrative.stages`.

## Implementation

### 1. `lua/tweakdata/extra_heists.lua` (NEW)
Hooked on `lib/tweak_data/crimespreetweakdata`.
`Hooks:PostHook(CrimeSpreeTweakData, "init_missions", "CSR_ExtraHeists", function(self, tweak_data) … end)`:
- Local `EXTRA` table = the 31 entries above.
- Port `repair_ghost_param(tweak_data, level_id, params)` — reads
  `tweak_data.levels[level_id].ghost_required / ghost_required_visual /
  ghost_bonus` → ghost 1 / 1 / 2, else 0.
- Port `add_mission`-equivalent bucket assignment: ghost>0 → bucket 1;
  ghost≠1 & add≤10 → bucket 2; ghost≠1 & add≥9 → bucket 3.
- For each extra: skip if `tweak_data.narrative.stages[id]` is nil (defensive);
  build `{ stage_id=id, id=id, icon="csm_"..id, add=value,
  level=tweak_data.narrative.stages[id] }`; insert into `self.missions[bucket]`
  for each assigned bucket.

### 2. `lua/tweakdata/hudicons.lua` (EDIT existing)
- Register atlas:
  `DB:create_entry(Idstring("texture"),
   Idstring("guis/textures/pd2/crime_spree/csr_mission_atlas"),
   mod_path .. "assets/gui/missions/mission_atlas.texture")`.
- In the wrapped `HudIconsTweakData:init`, add `self.csm_<id>` entries for the
  31 heists (280×140 atlas rects, re-pathed to `csr_mission_atlas`), mirroring
  MHiCS `hudiconstweakdata.lua`. Aliases kept:
  `csm_welcome_to_the_jungle_1_d = self.csm_bigoil_1`,
  `csm_election_day_1 = self.csm_election_1`,
  `csm_ukrainian_job = self.csm_jewelry_store`. `dah` uses existing vanilla
  `csm_dah`. Do **not** register `csm_chill_combat` / `csm_four_stores`.

### 3. Asset
Copy MHiCS `mission_atlas.texture` →
`assets/gui/missions/mission_atlas.texture`.

### 4. `mod.txt`
Add one hook:
`{ "hook_id": "lib/tweak_data/crimespreetweakdata", "script_path": "lua/tweakdata/extra_heists.lua" }`.

## Multiplayer

Zero new sync. `tweak_data.crime_spree.missions` is deterministic and identical
on every client running CSR, so the host's broadcast mission ids resolve on
guests via existing `get_mission`. Caveat: a guest on an older CSR build without
this change resolves nil for an extra heist → that card is skipped. Acceptable —
this is core CSR, shipped to everyone at once.

## Risks / test focus

1. Atlas rect alignment — confirm each card shows the right art.
2. A couple of extras are one-day `_d` variants or `peta_*`; confirm they load
   and complete under CSR's standard gamemode + manual package load
   (`lua/core/heist_packages.lua`).
3. Confirm rank reward on completion matches the `add` thresholds.

## Out of scope (future)

- Holdout heists (`chill_combat`, and any future wave-defense levels).
- A settings toggle to disable the expanded pool.
- Custom / modded heist discovery.
