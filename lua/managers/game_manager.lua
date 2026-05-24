-- CSRGameManager — single source of truth for Crime Spree Roguelike state.
--
-- Replaces every _G.CSR_* global and the four legacy persistence surfaces
-- (crime_spree_roguelike.json, csr_mp_sessions.json, crime_spree_seed.txt,
-- and our slice of Global.crime_spree) with one hierarchical singleton:
--   managers.csr._meta      (carries across runs and mod updates)
--   managers.csr._state     (active run, resets between runs)
--   managers.csr._registry  (static authored content, read-only after init)
--
-- Items: identity is `type` only and ownership is a plain count per type
-- (_state.peer_items[peer_id].counts[type] = n). The legacy id-list / prefix
-- model was a vanilla-CS UI holdover, removed 2026-05-19; get_or_create_peer_entry
-- folds an old { items = {...} } save forward. Items (CSR's own included)
-- register through the public API — see extension_api.lua /
-- csr_builtin_items.lua / projects/.../csr_mod_extension_api_design.md.

CSRGameManager = CSRGameManager or class()
CSRGameManager.VERSION = "U1-alpha"

local SAVE_FILE = "csr_save.json"
local LEGACY_SETTINGS_FILE = "crime_spree_roguelike.json"
local LEGACY_MP_SESSIONS_FILE = "csr_mp_sessions.json"

local function log_csr(msg)
	log("[CSR] " .. tostring(msg))
end

local function default_meta()
	return {
		version = CSRGameManager.VERSION,
		stats = {},
		unlocks = {},
		settings = {},
	}
end

local function default_state()
	return {
		is_active = false,
		rank = 0,
		-- Count of heists completed in the CURRENT run. Tracked independently
		-- of rank on purpose: rank gain per heist is a tunable constant
		-- (rank_per_heist) and may also come from other sources later, so this
		-- must NOT be derived from rank. Old saves lacking this key inherit the
		-- 0 default here (init() seeds _state from default_state() before
		-- load() overlays only the keys present on disk -> automatic migration).
		missions_completed = 0,
		-- A FAILED run is not ended: it stays active but locked. The lobby
		-- blocks Start/Reroll/select until the player pays the Continue cost
		-- (clear_failed) or gives up (End Spree -> end_run). Persisted so the
		-- failed state survives the return-to-lobby. Old saves lacking this
		-- key inherit false here (same auto-migration as missions_completed).
		failed = false,
		-- The active run's difficulty, an internal id string (e.g. "overkill_145").
		-- nil until a run starts: start_run seeds it from the remembered preference
		-- via _default_difficulty(), and difficulty() handles the nil case. The
		-- player picks it on the contract screen (set_difficulty).
		difficulty = nil,
		seed = nil,
		mission_set = {}, -- array of mission ids currently offered in the lobby
		current_mission = nil, -- id of the mission the player picked to play next
		peer_items = {},
		milestones = {},
		spawners = { copiers = {}, scrappers = {} },
		mp_session = {},
	}
end

local function default_registry()
	-- items_list starts EMPTY. Every item -- CSR's own included -- registers
	-- through the public API (CSR.register_item), dogfooded; see
	-- csr_builtin_items.lua and projects/.../csr_mod_extension_api_design.md.
	-- Identity is `type` only: no id_prefix, no per-stack ids, no by_prefix
	-- (vanilla-CS holdover removed 2026-05-19). Ownership is a count per type
	-- (see the Items section below).
	return {
		items = {},
		by_type = {}, -- [type] = entry (identity lookup)
		by_kind = {}, -- [effect.kind] = { entry, ... } (effect-dispatch index; effect items only)
		callback_items = {}, -- { entry, ... } items with on_apply/on_remove/on_tick (escape hatch)
		-- Modifiers (CS difficulty mods), registry-driven like items. Each modifier
		-- file (lua/modifiers/<id>.lua) calls _G.CSR.register_modifier; the replay
		-- on init refills these. loud = flat list, stealth_families = tiered list.
		modifiers = {
			loud = {}, -- { entry, ... } { id, loc, icon, class, data }
			stealth_families = {}, -- { entry, ... } { id, icon, tiers = { {loc=...}, ... } }
			by_id = {}, -- [id] = entry (dedupe across both buckets)
		},
		constants = {
			-- Kept for back-compat/reference; the live Dog Tags value now
			-- travels in its effect descriptor (per_stack) via register_item.
			dog_tags_hp_bonus = 0.10,
			rank_per_heist = 1, -- rebalance: every completed heist grants exactly 1 rank
			-- Continental-coin cost to clear a FAILED run and continue:
			-- continue_cost_base + continue_cost_per_mission * missions_completed
			-- (user-locked 2026-05-18: 10 + 10*missions -> 1 mission=20, 5=60).
			continue_cost_base = 10,
			continue_cost_per_mission = 10,
		},
	}
end

function CSRGameManager:init()
	self._meta = default_meta()
	self._state = default_state()
	self._registry = default_registry()
	self._callbacks = {
		on_mission_started = {},
		on_mission_completed = {},
		on_item_added = {},
		on_item_removed = {},
	}
	self:_migrate_legacy_save()
	self:load()
	-- Cache the debug-logging flag (the mod's first setting) into a plain boolean
	-- for cheap hot-path gating; kept in sync by set_setting.
	self._debug = (self._meta.settings and self._meta.settings.debug_mode) == true
	-- Replay every registration (addon + csr_builtin_items.lua) into this fresh
	-- _registry. init() runs multiple times per session and rebuilds _registry
	-- empty each time, so this REPLAYS (idempotent via by_type), never drains.
	if _G.CSR and _G.CSR._apply_registrations then
		_G.CSR._apply_registrations(self)
	end
	-- Same replay for modifiers (lua/modifiers/<id>.lua passports). Persistent
	-- list, replayed into the fresh _registry.modifiers every init (idempotent
	-- via by_id), never drained -- exactly like the item registrations above.
	if _G.CSR and _G.CSR._apply_modifier_registrations then
		_G.CSR._apply_modifier_registrations(self)
	end
	-- After live addons have registered, prune any owned counts whose addon is
	-- gone. For selection-window items (only current source) this lowers
	-- total_item_count -- the lobby reminder auto-reappears (host_rank >
	-- owned) and the player can reselect a different item. Shop-sourced items
	-- (when the shop ports) will branch here for a token refund instead;
	-- source-tracking lands with the shop port.
	self:_drop_orphan_items()
	-- Callback escape-hatch wiring: reconcile applied-state on every ownership /
	-- run transition, and once now so items already owned in a loaded run
	-- (save-reload) get on_apply. Listeners go into the fresh _callbacks table
	-- (rebuilt each init), so a re-init never stacks duplicate listeners.
	self._applied_callbacks = {}
	local function reconcile_cb()
		self:reconcile_callback_items()
	end
	self:on_mission_started(reconcile_cb)
	self:on_mission_completed(reconcile_cb)
	self:on_item_added(reconcile_cb)
	self:on_item_removed(reconcile_cb)
	self:reconcile_callback_items()
	self:_setup_temporary_job()
	-- Re-populate the buyable mission Assets for the loading CSR level. Vanilla CS
	-- does this in CrimeSpreeManager:_setup right after _setup_temporary_job (gated
	-- on its CS being active); CSR replaced that flow, so the Assets tab stayed
	-- empty -- MissionAssetsManager:init() ran before our narrative chain was set,
	-- so its own _setup_mission_assets early-returned on a nil level and never
	-- re-ran. Host/SP only (the asset list is host-authoritative and synced to
	-- clients via the host); is_run_active() leaves non-CSR sessions untouched.
	-- Clear first: _setup_mission_assets APPENDS (the reset lives in _setup), so a
	-- re-init would otherwise duplicate every asset.
	if self:is_run_active() and managers.assets and managers.assets._setup_mission_assets then
		if managers.assets._global then
			managers.assets._global.assets = {}
		end
		managers.assets:_setup_mission_assets()
	end
	log_csr("CSRGameManager initialised; version=" .. tostring(self._meta.version))
end

-- Re-establish the temporary "crime_spree" narrative chain from the level the
-- game is actually loading. Mirrors vanilla CrimeSpreeManager:_setup_temporary_job
-- (crimespreemanager.lua:1184), which vanilla calls from CrimeSpreeManager:_setup
-- on EVERY manager construction -- including the game-side one -- so the chain
-- survives the menu->game state transition. CSR previously set the chain ONLY
-- in select_mission (menu-side); by the briefing screen (game-side)
-- tweak_data.narrative.jobs.crime_spree.chain was back to its {} default, so
-- JobManager:current_stage_data() returned {} (job_chain[1] == nil), then
-- current_level_id()/current_level_data() returned nil, and every
-- narrative-derived briefing surface nil-crashed on heist launch
-- (HUDMissionBriefing num_stages; MissionBriefingGui DescriptionItem
-- level_data -- crash_report_2026_05_18_11_51).
--
-- Sourced from Global.game_settings.level_id (set by select_mission and
-- persisted by the engine across the state transition -- it IS the level being
-- loaded), NOT _state.current_mission: select_mission deliberately does not
-- persist current_mission (see its body comment), so the freshly-loaded
-- game-side _state never has it. Gated like vanilla's `if not current_mission`
-- guard: if no crime_spree mission matches the loading level, leave the chain
-- untouched -- a safe no-op for non-CSR sessions and for the menu-side
-- construction (where level_id is absent or stale).
function CSRGameManager:_setup_temporary_job()
	-- NOT gated on self:is_active(): a CSR client never started the run, so its
	-- _state.is_active is false (the MP host->client carve-out is a later
	-- refactor slice), yet the client loads the same crime_spree level and its
	-- briefing surfaces need the chain just as much as the host's. Gating on
	-- is_active() would re-crash the client (feedback_check_host_and_client).
	-- The level-match below is the real CSR-context gate: the chain is written
	-- only when the loading level IS a registered crime_spree mission level.
	-- A normal heist on a level a CS mission happens to reuse would also match,
	-- but that write is provably inert -- nothing reads
	-- tweak_data.narrative.jobs.crime_spree.chain unless the active job is
	-- "crime_spree", and a real vanilla Crime Spree re-sets it itself before
	-- reading -- so normal play / vanilla CS / Skirmish stay behaviourally
	-- untouched (feedback_csr_only_no_vanilla_leak: no-op verified, not just
	-- gated).
	local gs = Global and Global.game_settings
	local level_id = gs and gs.level_id
	if not level_id then
		return
	end
	local narrative = tweak_data and tweak_data.narrative
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if not narrative or not narrative.jobs or not narrative.jobs.crime_spree or type(cs_missions) ~= "table" then
		return
	end
	local want_mission = gs.mission or "none"
	local fallback_level = nil
	for _, tier in ipairs(cs_missions) do
		for _, m in ipairs(tier) do
			if m.level and m.level.level_id == level_id then
				-- Exact match (level + mission variant) wins immediately; a
				-- level-only match is kept as a fallback in case the variant
				-- string drifted. Either way chain[1] is a valid narrative
				-- stage with a real .level_id, which is all the briefing/job
				-- surfaces need.
				if (m.mission or "none") == want_mission then
					narrative.jobs.crime_spree.chain = { m.level }
					log_csr("_setup_temporary_job: chain set from level_id=" .. tostring(level_id))
					return
				end
				fallback_level = fallback_level or m.level
			end
		end
	end
	if fallback_level then
		narrative.jobs.crime_spree.chain = { fallback_level }
		log_csr("_setup_temporary_job: chain set (level-only) from level_id=" .. tostring(level_id))
	end
end

-- =====================================================
-- Run-state queries
-- =====================================================

function CSRGameManager:is_run_active()
	-- Alpha pilot stub: always active so item hooks never bail. Real run
	-- gating lands when we port the mission-state machinery in beta.
	return true
end

function CSRGameManager:is_active()
	-- Honest accessor for `_state.is_active` (the field flipped by start_run /
	-- end_run). Use this when a hook genuinely needs to know "is a CSR run
	-- currently in flight" -- e.g. mission lifecycle, save migrations, MP
	-- session bring-up. Items keep using is_run_active() per the stub above.
	return self._state.is_active == true
end

function CSRGameManager:rank()
	return self._state.rank or 0
end

function CSRGameManager:missions_completed()
	return self._state.missions_completed or 0
end

function CSRGameManager:_default_difficulty()
	-- The difficulty used before a run has chosen one: the player's remembered
	-- preference (set on the contract screen, persisted in _meta so it survives
	-- runs and restarts), then the static CS base difficulty, then a hard
	-- fallback. Internal difficulty id string (a tweak_data.difficulties entry),
	-- e.g. "overkill_145".
	local cs_td = tweak_data and tweak_data.crime_spree
	local remembered = self._meta.settings and self._meta.settings.last_difficulty
	return remembered or (cs_td and cs_td.base_difficulty) or "overkill_145"
end

function CSRGameManager:difficulty()
	-- The difficulty the active run plays at, chosen by the player on the
	-- contract screen (set_difficulty). Falls back to the remembered preference /
	-- CS base when no run has set one. Returns an internal difficulty id string
	-- (a tweak_data.difficulties entry) -- the shape Global.game_settings.difficulty
	-- and tweak_data.difficulty_name_ids expect.
	return self._state.difficulty or self:_default_difficulty()
end

function CSRGameManager:set_difficulty(diff)
	-- Set the active run's difficulty AND remember it as the default for the next
	-- contract open. `diff` is an internal difficulty id string (a
	-- tweak_data.difficulties entry, e.g. "overkill_145"). Unknown ids are
	-- rejected so we never write garbage into Global.game_settings.difficulty.
	if type(diff) ~= "string" then
		return false
	end
	local diffs = tweak_data and tweak_data.difficulties
	if type(diffs) == "table" and not table.contains(diffs, diff) then
		log_csr("set_difficulty: unknown difficulty '" .. tostring(diff) .. "' — ignored")
		return false
	end
	self._state.difficulty = diff
	self._meta.settings = self._meta.settings or {}
	self._meta.settings.last_difficulty = diff
	self:save()
	log_csr("set_difficulty: " .. diff)
	return true
end

function CSRGameManager:seed()
	return self._state.seed
end

function CSRGameManager:host_rank()
	local mp = self._state.mp_session
	if mp and mp.host_rank then
		return mp.host_rank
	end
	return self._state.rank or 0
end

-- =====================================================
-- Peer ID
-- =====================================================

function CSRGameManager:local_peer_id()
	local nm = managers and managers.network
	if nm and nm.session then
		local session = nm:session()
		if session and session.local_peer then
			local peer = session:local_peer()
			if peer and peer.id then
				return peer:id()
			end
		end
	end
	return 1
end

-- =====================================================
-- Items
-- =====================================================

-- Ownership model: identity is `type` only, ownership is a plain count per
-- type — _state.peer_items[peer_id].counts[type] = n. No per-stack ids, no
-- prefix (the vanilla-CS id-list model was a UI holdover; removed 2026-05-19).
local function get_or_create_peer_entry(state, peer_id)
	local entry = state.peer_items[peer_id]
	if not entry then
		entry = { counts = {} }
		state.peer_items[peer_id] = entry
	end
	-- In-place migration of a legacy { items = { {id,type}, ... } } entry
	-- (pre-2026-05-19 model) into { counts = { [type] = n } }, so an alpha
	-- save written by the old shape is folded forward, not silently dropped.
	if entry.items and not entry.counts then
		local counts = {}
		for _, it in ipairs(entry.items) do
			if it.type then
				counts[it.type] = (counts[it.type] or 0) + 1
			end
		end
		entry.counts = counts
		entry.items = nil
	end
	entry.counts = entry.counts or {}
	return entry
end

-- Read-only { [type] = n } map of everything the peer owns ({} if nothing).
function CSRGameManager:player_items(peer_id)
	local entry = self._state.peer_items[peer_id]
	return (entry and entry.counts) or {}
end

-- Owned stacks of ONE item type.
function CSRGameManager:item_count(peer_id, item_type)
	local entry = self._state.peer_items[peer_id]
	local counts = entry and entry.counts
	return (counts and counts[item_type]) or 0
end

-- Total stacks across ALL types. One rank == one pick, so the lobby
-- "unselected items" reminder subtracts this from host rank.
function CSRGameManager:total_item_count(peer_id)
	local entry = self._state.peer_items[peer_id]
	local counts = entry and entry.counts
	if not counts then
		return 0
	end
	local total = 0
	for _, n in pairs(counts) do
		total = total + n
	end
	return total
end

function CSRGameManager:has_item(peer_id, item_type)
	return self:item_count(peer_id, item_type) > 0
end

-- Convenience for item hook code (CSR's own + addons): owned stacks of an item
-- by the LOCAL player, so a hook doesn't repeat the local_peer_id() plumbing.
function CSRGameManager:owned(item_type)
	return self:item_count(self:local_peer_id(), item_type)
end

-- Mutable per-peer state record (counts + subsystem-owned fields). Lazy-created.
-- The shop (lua/managers/shop.lua) stashes its token wallet + lineup here so they
-- ride the manager's own save() and the start_run/end_run inventory wipe. Callers
-- that mutate the returned table must call :save() to persist.
function CSRGameManager:peer_entry(peer_id)
	return get_or_create_peer_entry(self._state, peer_id or self:local_peer_id())
end

function CSRGameManager:add_item(peer_id, item_type)
	if not self._registry.by_type[item_type] then
		log_csr("add_item: unknown type '" .. tostring(item_type) .. "' — ignored")
		return false
	end
	local entry = get_or_create_peer_entry(self._state, peer_id)
	entry.counts[item_type] = (entry.counts[item_type] or 0) + 1
	for _, fn in ipairs(self._callbacks.on_item_added) do
		fn(peer_id, item_type, entry.counts[item_type])
	end
	self:save()
	log_csr("add_item: peer=" .. tostring(peer_id) .. " type=" .. item_type .. " count=" .. entry.counts[item_type])
	return true
end

function CSRGameManager:remove_item(peer_id, item_type)
	local entry = self._state.peer_items[peer_id]
	local counts = entry and entry.counts
	if not counts or not counts[item_type] or counts[item_type] <= 0 then
		return false
	end
	counts[item_type] = counts[item_type] - 1
	if counts[item_type] <= 0 then
		counts[item_type] = nil
	end
	for _, fn in ipairs(self._callbacks.on_item_removed) do
		fn(peer_id, item_type, counts[item_type] or 0)
	end
	self:save()
	log_csr("remove_item: peer=" .. tostring(peer_id) .. " type=" .. item_type)
	return true
end

-- ===================================================== Registration
--
-- The public surface (CSR.register_item, extension_api.lua) routes here.
-- CSR's own items use the SAME path (csr_builtin_items.lua) -- dogfooded.
local KNOWN_RARITIES = {
	common = true,
	uncommon = true,
	rare = true,
	contraband = true,
	wildcard = true,
}
-- Slice 1 declarative vocabulary. Grows one entry at a time as each item that
-- needs a new kind is ported (never speculatively).
--   stat_mul          -- max_health / max_stamina / damage / melee_damage /
--                        interaction_speed: linear per_stack added to a vanilla
--                        return-value multiplier
--   stat_hyperbolic   -- movement_speed (Escape Plan) / dodge (Falcogini Keys):
--                        diminishing-returns curve cap*(1-1/(1+(k_num/k_den)*n))
--   regen_max_hp_pct  -- Worn Band-Aid: hyperbolic % of max HP every N seconds
--   heal_on_kill      -- Pink Slip: heal local player when they kill an enemy
--   weapon_speed_streak -- Overkill Rush: kill-streak buff to fire rate + reload
--   instakill_on_hit  -- Bonnie's Lucky Chip: chance to instakill on a bullet hit
--   drill_timer_on_kill -- Wolf's Toolbox: kills cut active drill/saw timers
--   first_hit_damage  -- Piece of Rebar: bonus damage on the first hit per enemy
--   emergency_heal    -- The Edge: cooldown-gated heal + brief invuln when HP drops
--                        below a threshold (or on a lethal hit)
--   guardian_revive   -- Plush Shark: on the last down before custody, cancel it
--                        (heal + restore one down + armor) and grant invuln
local KNOWN_EFFECT_KINDS = {
	stat_mul = true,
	stat_hyperbolic = true,
	regen_max_hp_pct = true,
	heal_on_kill = true,
	weapon_speed_streak = true,
	instakill_on_hit = true,
	drill_timer_on_kill = true,
	first_hit_damage = true,
	emergency_heal = true,
	guardian_revive = true,
}

function CSRGameManager:register_item(def)
	if type(def) ~= "table" then
		log_csr("register_item: definition not a table — skipped")
		return false
	end
	local t = def.type
	if type(t) ~= "string" or t == "" then
		log_csr("register_item: missing/invalid 'type' — skipped")
		return false
	end
	if self._registry.by_type[t] then
		log_csr("register_item: duplicate type '" .. t .. "' — skipped")
		return false
	end
	if not KNOWN_RARITIES[def.rarity] then
		log_csr("register_item: '" .. t .. "' unknown rarity '" .. tostring(def.rarity) .. "' — skipped")
		return false
	end
	-- effect is OPTIONAL. Three valid item shapes: (a) a declarative effect with a
	-- known kind, (b) callback escape-hatch (on_apply/on_remove/on_tick), or
	-- (c) passport-only -- behavior installed externally via def.hooks by the API
	-- shim (the per-item-file model). Only validate the kind when an effect is given.
	local effect = def.effect
	if effect ~= nil then
		if type(effect) ~= "table" or not KNOWN_EFFECT_KINDS[effect.kind] then
			log_csr(
				"register_item: '" .. t .. "' bad effect kind '" .. tostring(effect and effect.kind) .. "' — skipped"
			)
			return false
		end
	end

	-- Optional human-readable addon name, used by future MP addon-mismatch
	-- warnings and tooltip surfaces ("From: <addon>"). Absent for CSR's own
	-- built-in items (they are core, not an addon). Tolerant of bad input:
	-- a non-string value is logged and dropped, not a hard rejection -- the
	-- item still registers, just without the attribution.
	local addon = def.addon
	if addon ~= nil and type(addon) ~= "string" then
		log_csr("register_item: '" .. t .. "' ignoring non-string 'addon' field (got " .. type(addon) .. ")")
		addon = nil
	end

	-- Optional per-item icon scale: a multiplier on the default icon size (1.0 =
	-- unchanged, 0.9 = slightly smaller, 1.1 = slightly larger). Scales ONLY the
	-- item glyph, never its rarity frame, on every surface that draws it. A
	-- non-number is logged and dropped (the item still registers); absence -> the
	-- 1.0 default is applied at the draw sites via item_icon_scale().
	local icon_scale = def.icon_scale
	if icon_scale ~= nil and type(icon_scale) ~= "number" then
		log_csr("register_item: '" .. t .. "' ignoring non-number 'icon_scale' field (got " .. type(icon_scale) .. ")")
		icon_scale = nil
	end

	local entry = {
		type = t,
		rarity = def.rarity,
		name = def.name,
		desc = def.desc,
		-- Logbook-tier text (optional): full_desc = detailed effect line, notes =
		-- flavor. Stored so the Logbook can read them from the registry instead of
		-- a hardcoded table (the per-item file now owns its own copy).
		full_desc = def.full_desc,
		notes = def.notes,
		icon = def.icon,
		icon_scale = icon_scale,
		effect = effect,
		on_apply = def.on_apply,
		on_remove = def.on_remove,
		on_tick = def.on_tick,
		addon = addon,
	}
	table.insert(self._registry.items, entry)
	self._registry.by_type[t] = entry
	-- Index by effect kind so the hot-path dispatchers iterate only the items of
	-- the kind they care about instead of scanning the whole registry every call.
	-- Callback-only items (no effect) are not effect-dispatched, so they are not
	-- indexed here. Rebuilt empty on each init() (default_registry) and refilled
	-- by the registration replay, in lockstep with by_type.
	if effect then
		local bucket = self._registry.by_kind[effect.kind]
		if not bucket then
			bucket = {}
			self._registry.by_kind[effect.kind] = bucket
		end
		bucket[#bucket + 1] = entry
	end
	-- Index callback-escape-hatch items (any of on_apply/on_remove/on_tick) for
	-- the lifecycle reconcile + throttled tick. An item may be BOTH effect- and
	-- callback-driven, so this is independent of the by_kind index above.
	if entry.on_apply or entry.on_remove or entry.on_tick then
		self._registry.callback_items[#self._registry.callback_items + 1] = entry
	end
	local from = addon and (" from '" .. addon .. "'") or ""
	log_csr("register_item: '" .. t .. "' (" .. def.rarity .. ")" .. from)
	return true
end

-- Read-only list of registered item definitions (UI / effect dispatcher
-- iterate this instead of hardcoded tables).
function CSRGameManager:registered_items()
	return self._registry.items
end

-- Per-item icon scale multiplier (1.0 = default size). Single source of truth
-- for every icon-drawing surface (selection window, Items panel grid, Logbook).
-- Returns 1 for an unregistered type or an item that did not set icon_scale.
function CSRGameManager:item_icon_scale(item_type)
	local entry = item_type and self._registry.by_type[item_type]
	return (entry and entry.icon_scale) or 1
end

-- =====================================================
-- Modifiers (Crime Spree difficulty mods)
--
-- THIS SLICE = UI + assignment only, NO combat effects yet.
--   Each earned rank applies 1 random LOUD + 1 random STEALTH modifier to the
--   run (user spec 2026-05-23). "Random" is deterministic from the run seed --
--   the pre-refactor model: same seed -> same modifiers (reproducible AND lets
--   every peer derive the same set once seed sync lands). Computed on the fly
--   from (seed, rank); nothing is persisted -- active_modifiers() is a pure
--   function of run state, the same way the lobby's unselected-items reminder
--   derives from rank - owned. Forking the vanilla ModifierX enemy-side effects
--   onto managers.csr is a SEPARATE later slice.
--
-- CATALOG: names/descriptions are the existing menu_cs_modifier_* localization
--   keys (loc/english.json) -- single source of truth, ported 1:1 from the
--   pre-refactor vanilla-CS modifier pool. Icons are vanilla CS atlas ids
--   (crime_spree_*, verified in HudIconsTweakData) plus two CSR custom ids
--   registered in tweakdata/hudicons.lua. The 4 vanilla "enable_<enemy>" unlock
--   mods are intentionally excluded (difficulty-normalisation helpers, not
--   roguelike escalation). Difficulty-gating of the loud pool (hiding e.g.
--   cloaker mods when the difficulty spawns none) is a follow-up.
-- Modifier catalog is REGISTRY-DRIVEN (mirrors the per-item-file model): each
-- modifier registers itself via _G.CSR.register_modifier from its own file in
-- lua/modifiers/. The manager stores them in _registry.modifiers (a `loud` list
-- and a `stealth_families` list); see register_modifier / modifier_catalog /
-- active_modifiers below. The csr_* helpers under this comment are the seeded
-- shuffle + stealth-progression used to derive the active set per rank.

-- Park-Miller minimal-standard LCG (pure -- no global math.random state) so the
-- shuffle is reproducible across peers/saves from the run seed alone.
local function csr_modifier_rng(seed)
	local state = (seed or 0) % 2147483647
	if state <= 0 then
		state = state + 2147483646
	end
	return function()
		state = (state * 16807) % 2147483647
		return state / 2147483647
	end
end

-- Deterministic Fisher-Yates shuffle of `pool` keyed by `seed`. Returns a NEW
-- array (the shared static catalog is never mutated).
local function csr_shuffled(pool, seed)
	local arr = {}
	for i = 1, #pool do
		arr[i] = pool[i]
	end
	local rnd = csr_modifier_rng(seed)
	for i = #arr, 2, -1 do
		local j = math.floor(rnd() * i) + 1
		arr[i], arr[j] = arr[j], arr[i]
	end
	return arr
end

-- Deterministic stealth pickup order: repeatedly choose a seeded-random family
-- that still has untaken tiers and take its next tier IN ORDER. Returns the full
-- sequence (length = total tiers across families); active_modifiers slices the
-- first `rank` of it. Each entry is normalised to the loud entry shape.
local function csr_stealth_sequence(families, seed)
	local rnd = csr_modifier_rng(seed)
	local taken = {}
	local total = 0
	for _, f in ipairs(families) do
		total = total + #f.tiers
	end
	local out = {}
	while #out < total do
		local avail = {}
		for fi, f in ipairs(families) do
			if (taken[fi] or 0) < #f.tiers then
				avail[#avail + 1] = fi
			end
		end
		local fi = avail[math.floor(rnd() * #avail) + 1]
		local f = families[fi]
		taken[fi] = (taken[fi] or 0) + 1
		local tier = f.tiers[taken[fi]]
		out[#out + 1] = {
			id = f.id .. "_" .. taken[fi],
			loc = tier.loc,
			icon = f.icon,
			class = f.class,
			data = tier.data,
		}
	end
	return out
end

-- A stable, id-sorted COPY of a modifier list so the seeded shuffle / stealth
-- sequence is independent of registration (file load) order.
local function csr_sorted_by_id(list)
	local arr = {}
	for i = 1, #list do
		arr[i] = list[i]
	end
	table.sort(arr, function(a, b)
		return (a.id or "") < (b.id or "")
	end)
	return arr
end

-- Register one modifier from its passport (lua/modifiers/<id>.lua via
-- _G.CSR.register_modifier). Parity with register_item: validated, deduped by
-- id, replayed into every fresh _registry on init. `category` buckets it:
--   "loud"    -> _registry.modifiers.loud            { id, loc, icon, class, data }
--   "stealth" -> _registry.modifiers.stealth_families { id, icon, tiers = {...} }
-- class/data are OPTIONAL: a loud modifier whose engine class isn't present is
-- still listed in the UI (apply_combat_modifiers nil-guards _G[class]).
function CSRGameManager:register_modifier(def)
	if type(def) ~= "table" then
		log_csr("register_modifier: definition not a table — skipped")
		return false
	end
	local id = def.id
	if type(id) ~= "string" or id == "" then
		log_csr("register_modifier: missing/invalid 'id' — skipped")
		return false
	end
	local mods = self._registry.modifiers
	if mods.by_id[id] then
		log_csr("register_modifier: duplicate id '" .. id .. "' — skipped")
		return false
	end
	if def.category == "loud" then
		local entry = {
			id = id,
			category = "loud",
			loc = def.loc,
			icon = def.icon,
			class = def.class,
			data = def.data or {},
		}
		mods.by_id[id] = entry
		mods.loud[#mods.loud + 1] = entry
	elseif def.category == "stealth" then
		local entry = {
			id = id,
			category = "stealth",
			icon = def.icon,
			class = def.class,
			tiers = def.tiers or {},
		}
		mods.by_id[id] = entry
		mods.stealth_families[#mods.stealth_families + 1] = entry
	else
		log_csr("register_modifier: '" .. id .. "' unknown category '" .. tostring(def.category) .. "' — skipped")
		return false
	end
	log_csr("register_modifier: '" .. id .. "' (" .. tostring(def.category) .. ")")
	return true
end

-- Read-only modifier registry { loud = {...}, stealth_families = {...}, by_id }.
function CSRGameManager:modifier_catalog()
	return self._registry.modifiers
end

-- The LOUD or STEALTH modifiers active for the current run, derived purely from
-- (host rank, run seed). `category` == "loud" (default) or "stealth". Each entry
-- is { id, loc, icon, [class, data] }; the UI splits the loc text into name/desc.
-- Cumulative: rank R returns the first R of the seeded sequence (rank R+1 is a
-- superset), capped at the pool size. Empty before rank 1. host_rank() (not
-- rank()) is the entitlement so a client shows the host's active set. The pool
-- is id-sorted first so the shuffle is stable regardless of file load order.
function CSRGameManager:active_modifiers(category)
	local rank = self:host_rank() or 0
	if rank <= 0 then
		return {}
	end
	local seed = self:seed() or 0
	local mods = self._registry.modifiers
	local seq
	if category == "stealth" then
		-- +1 salt so loud and stealth orders are independent of one another.
		seq = csr_stealth_sequence(csr_sorted_by_id(mods.stealth_families), seed * 2 + 1)
	else
		seq = csr_shuffled(csr_sorted_by_id(mods.loud), seed * 2)
	end
	local n = math.min(rank, #seq)
	local out = {}
	for i = 1, n do
		out[i] = seq[i]
	end
	return out
end

-- Apply the active modifiers (LOUD + STEALTH) as real engine effects, mirroring
-- vanilla CrimeSpreeManager:_setup_modifiers. Host/SP ONLY (Network:is_server):
-- CS modifiers drive server-side enemy spawning / stats / AI / stealth gates, so
-- the host applying them makes the whole session harder; clients need no local
-- copy (and the run seed isn't synced yet, so a client-derived set could
-- diverge). Called once per heist from the IngameWaitingForPlayersState hook
-- (combat_modifiers.lua). civilian_guilt / shocking_surprise carry CSR-custom
-- class names not present in the engine -- the _G[class] guard skips them (they
-- still appear in the UI). NOTE: ModifierLessConcealment is read per-player, so
-- under host-only apply only the host's detection rises until the MP sync slice.
function CSRGameManager:apply_combat_modifiers()
	if not Network:is_server() then
		return
	end
	if not managers or not managers.modifiers then
		return
	end
	-- managers.modifiers is rebuilt per game-state setup, so our category starts
	-- empty each heist; clear it anyway for idempotency (the hook could re-fire).
	if managers.modifiers._modifiers then
		managers.modifiers._modifiers.csr = nil
	end

	-- ModifierLessPagers:init destructively rebuilds tweak_data.player.alarm_pager
	-- from its CURRENT value and never reverts (BaseModifier:destroy is a no-op),
	-- so re-applying it each heist would compound. Snapshot the pristine arrays
	-- once (a _G global so it survives manager re-creation) and restore from it
	-- before every apply -- the pager modifier then always recomputes from a clean
	-- baseline, and pagers reset correctly on a run with no pager modifier active.
	local ap = tweak_data and tweak_data.player and tweak_data.player.alarm_pager
	if ap and type(ap.bluff_success_chance) == "table" then
		_G.CSR_PagerBaseline = _G.CSR_PagerBaseline
			or { bluff = clone(ap.bluff_success_chance), skill = clone(ap.bluff_success_chance_w_skill) }
		ap.bluff_success_chance = clone(_G.CSR_PagerBaseline.bluff)
		if _G.CSR_PagerBaseline.skill then
			ap.bluff_success_chance_w_skill = clone(_G.CSR_PagerBaseline.skill)
		end
	end

	-- Aggregate active loud + stealth modifiers by engine class (vanilla stacking).
	local to_activate = {}
	for _, category in ipairs({ "loud", "stealth" }) do
		for _, entry in ipairs(self:active_modifiers(category)) do
			if entry.class and entry.data then
				local agg = to_activate[entry.class] or {}
				for key, value_data in pairs(entry.data) do
					local value = value_data[1]
					local method = value_data[2]
					if method == "none" then
						agg[key] = value
					elseif method == "add" then
						agg[key] = (agg[key] or 0) + value
					elseif method == "sub" then
						agg[key] = (agg[key] or 0) - value
					elseif method == "min" then
						agg[key] = math.min(agg[key] or math.huge, value)
					elseif method == "max" then
						agg[key] = math.max(agg[key] or -math.huge, value)
					end
				end
				to_activate[entry.class] = agg
			end
		end
	end

	local applied = 0
	for class, data in pairs(to_activate) do
		local mod_class = _G[class]
		if mod_class then
			managers.modifiers:add_modifier(mod_class:new(data), "csr")
			applied = applied + 1
		else
			log_csr("apply_combat_modifiers: class '" .. tostring(class) .. "' not loaded -- effect skipped")
		end
	end
	log_csr("apply_combat_modifiers: applied " .. applied .. " modifier(s)")
end

-- =====================================================
-- Effect dispatch helpers
--
-- The "scan owned items of an effect kind and fold their effect" logic used to
-- be copy-pasted into every dispatcher file under lua/items/ -- a SuperBLT chunk
-- that is hooked on N targets loads N times and file-locals are not shared, so
-- each file (and each load) had its own identical copy. These three methods are
-- the single home for that logic; dispatchers now delegate here. All three are
-- LOCAL-PLAYER-scoped (local_peer_id) and gated on is_run_active(), so they
-- return a neutral value (0 / empty) outside a run -- the dispatcher call sites
-- only need a `managers.csr` nil-guard.
-- =====================================================

local EMPTY_ITEM_LIST = {}

-- Read-only list of registered entries whose effect.kind == kind (empty list if
-- none). Backed by the by_kind index, so this is an O(1) lookup; callers loop
-- the (short) returned list. Bespoke dispatchers (kill / streak / chip) use this
-- and apply their own per-item math.
function CSRGameManager:items_of_kind(kind)
	return self._registry.by_kind[kind] or EMPTY_ITEM_LIST
end

-- Summed additive bonus for one stat across every owned stat_mul item targeting
-- it: sum(per_stack * stacks). The additive convention for max_health /
-- max_stamina / damage / melee_damage / interaction_speed. 0 outside a run.
function CSRGameManager:sum_stat_mul(stat)
	if not self:is_run_active() then
		return 0
	end
	local items = self._registry.by_kind.stat_mul
	if not items then
		return 0
	end
	local pid = self:local_peer_id()
	local total = 0
	for i = 1, #items do
		local e = items[i].effect
		if e.stat == stat then
			local stacks = self:item_count(pid, items[i].type)
			if stacks > 0 then
				total = total + (e.per_stack or 0) * stacks
			end
		end
	end
	if self._debug then
		self:_debug_stat("stat_mul", stat, total)
	end
	return total
end

-- Combined diminishing-returns bonus for one stat across every owned
-- stat_hyperbolic item targeting it. Each item contributes
--   b = cap * (1 - 1 / (1 + (k_num/k_den) * stacks))
-- and items combine as a probabilistic union 1 - prod(1 - b) (stays < 1, reduces
-- to b for the single-item case). Used for movement_speed / dodge. 0 outside a run.
function CSRGameManager:combine_stat_hyperbolic(stat)
	if not self:is_run_active() then
		return 0
	end
	local items = self._registry.by_kind.stat_hyperbolic
	if not items then
		return 0
	end
	local pid = self:local_peer_id()
	local remain = 1
	for i = 1, #items do
		local e = items[i].effect
		if e.stat == stat then
			local stacks = self:item_count(pid, items[i].type)
			if stacks > 0 then
				local k = (e.k_num or 1) / (e.k_den or 1)
				local b = (e.cap or 1) * (1 - 1 / (1 + k * stacks))
				remain = remain * (1 - b)
			end
		end
	end
	local combined = 1 - remain
	if self._debug then
		self:_debug_stat("hyperbolic", stat, combined)
	end
	return combined
end

-- =====================================================
-- Callback escape-hatch dispatch (on_apply / on_remove / on_tick)
--
-- For mechanics that don't fit a declarative effect kind, register_item accepts
-- on_apply/on_remove/on_tick. An item is "applied" while a run is active AND the
-- local player owns >= 1. reconcile_callback_items() (wired to every ownership /
-- run transition, plus once at init for save-reload) fires on_apply when an item
-- ENTERS that state and on_remove when it LEAVES, with exactly-once semantics via
-- _applied_callbacks. tick_callback_items(dt) drives on_tick for applied items on
-- a throttle (the driver lives in csr_item_effects_callbacks.lua; never per-frame).
-- Every callback is pcall-isolated: a buggy addon callback is logged, never
-- crashes CSR. ctx = { mgr, peer_id, item_type, count, is_run_active }.
-- =====================================================

function CSRGameManager:_callback_ctx(entry, count)
	return {
		mgr = self,
		peer_id = self:local_peer_id(),
		item_type = entry.type,
		count = count,
		is_run_active = self:is_run_active(),
	}
end

local function safe_invoke(fn, ctx, dt, type_id, which)
	local ok, err = pcall(fn, ctx, dt)
	if not ok then
		log_csr(which .. " error for '" .. tostring(type_id) .. "': " .. tostring(err))
	end
end

function CSRGameManager:reconcile_callback_items()
	self._applied_callbacks = self._applied_callbacks or {}
	local list = self._registry.callback_items
	if #list == 0 then
		return
	end
	local pid = self:local_peer_id()
	local run_active = self:is_run_active()
	for i = 1, #list do
		local entry = list[i]
		local count = self:item_count(pid, entry.type)
		local should = run_active and count > 0
		local applied = self._applied_callbacks[entry.type]
		if should and not applied then
			self._applied_callbacks[entry.type] = true
			self:debug_log("callback on_apply '" .. tostring(entry.type) .. "' (count=" .. tostring(count) .. ")")
			if entry.on_apply then
				safe_invoke(entry.on_apply, self:_callback_ctx(entry, count), nil, entry.type, "on_apply")
			end
		elseif applied and not should then
			self._applied_callbacks[entry.type] = nil
			self:debug_log("callback on_remove '" .. tostring(entry.type) .. "'")
			if entry.on_remove then
				safe_invoke(entry.on_remove, self:_callback_ctx(entry, count), nil, entry.type, "on_remove")
			end
		end
	end
end

function CSRGameManager:tick_callback_items(dt)
	if not self:is_run_active() then
		return
	end
	local applied = self._applied_callbacks
	if not applied then
		return
	end
	local list = self._registry.callback_items
	local pid = self:local_peer_id()
	for i = 1, #list do
		local entry = list[i]
		if entry.on_tick and applied[entry.type] then
			local count = self:item_count(pid, entry.type)
			safe_invoke(entry.on_tick, self:_callback_ctx(entry, count), dt, entry.type, "on_tick")
		end
	end
end

-- Remove owned counts whose `type` is no longer in the registry (addon
-- uninstalled / disabled / renamed type). For now -- selection-window-only
-- world -- the strategy is "drop", because dropping naturally re-arms the
-- lobby reminder (host_rank > total_item_count) and the player gets a fresh
-- pick window. Shop-sourced items, when the shop ports, need a different
-- branch (refund tokens instead of just dropping); source-tracking +
-- per-source branching lands with the shop port.
function CSRGameManager:_drop_orphan_items()
	local dropped = 0
	for _, entry in pairs(self._state.peer_items) do
		if entry.counts then
			for type_id, n in pairs(entry.counts) do
				if not self._registry.by_type[type_id] then
					entry.counts[type_id] = nil
					dropped = dropped + n
				end
			end
		end
	end
	if dropped > 0 then
		log_csr(
			"_drop_orphan_items: dropped "
				.. dropped
				.. " stack(s) of unregistered item(s); lobby reminder will re-arm so the player can reselect"
		)
		self:save()
	end
end

-- Selection-window roll: weighted rarity, no contraband, ≤1 wildcard per window.
-- Locked design (project_csr_rebalance_design.md):
--   common 60 / uncommon 24 / rare 4 / wildcard 12   (sum 100)
--   contraband is EXPLICITLY 0 here -- contraband items still exist and can
--   enter inventory via other paths (shop/scrapper, when those port), but the
--   roguelike selection pool never offers one.
local RARITY_WEIGHTS = {
	common = 60,
	uncommon = 24,
	rare = 4,
	wildcard = 12,
}
local MAX_WILDCARDS_PER_WINDOW = 1
-- Hard size of one "pick offer". The UI renders one card per type stored in
-- the offer (so this also caps how many cards the window shows per pick).
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
	-- Float-tail fallback: r > cum by epsilon, take the last key seen.
	local last
	for k in pairs(weights) do
		last = k
	end
	return last
end

-- peer_id is currently unused (kept in the signature for the "owns 0 wildcards"
-- per-peer filter the design calls for once wildcards land as registered items).
-- count clamps to >=1; the UI calls with CARDS_PER_WINDOW = 3.
--
-- Each roll: rarity drawn by weight, then a uniform pick inside that rarity's
-- bucket. **No duplicates within a window** -- picked items are popped out of
-- their bucket for the rest of this call, so if you draw common, the next
-- roll's commons bucket is shorter by one. If a bucket empties, that rarity
-- drops out of the live weights (the remaining N-1 rolls re-distribute across
-- the rarities that still have items). If EVERY bucket empties before count
-- is reached -- registry has fewer than count items in the non-contraband
-- selection-pool -- the loop short-circuits and the result has whatever the
-- registry can provide (UI shows however many cards came back).
--
-- Mutation safety: we shallow-copy each rarity's array into `buckets` before
-- popping, so the registry's own items[] list is never touched -- only this
-- call's local copy shrinks.
function CSRGameManager:roll_item_pool(peer_id, count)
	count = math.max(1, tonumber(count) or 3)

	local buckets = {}
	for _, item in ipairs(self._registry.items) do
		local r = item.rarity
		if r and r ~= "contraband" then
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
		-- Rebuild the live weights table every roll: a bucket may have just
		-- emptied (so its rarity drops out), or wildcards may now be capped.
		-- 3 rebuilds per click is well within tolerable allocation cost.
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
--
-- The "owed picks" lifecycle: every rank earned grants one pick. To honour
-- "what the first open of the window shows must stay forever", each owed pick
-- is materialised as a STORED OFFER -- a frozen list of 3 item types --
-- BEFORE the window first reads it. Re-opening the window for the same pick
-- peeks the same offer; BACK never spends it; only a successful selection
-- (add_item-from-window) pops it.
--
-- Storage: _state.peer_items[peer_id].pending_offers = array of arrays of
-- type strings. JSON-safe and travels with the existing save/load path.
-- Persists across save/load and across game restarts -- a player who closes
-- the game mid-pick sees the same cards next session.
-- =====================================================

-- Lock in offers so the peer has AT LEAST `n` stored picks pre-rolled.
-- Idempotent: if there are already >= n offers, this is a no-op. Never trims
-- excess -- those stay until earned ranks catch up. Each new offer uses the
-- live roll_item_pool with current weights + dedupe.
function CSRGameManager:ensure_offers(peer_id, n)
	n = math.max(0, tonumber(n) or 0)
	local entry = get_or_create_peer_entry(self._state, peer_id)
	entry.pending_offers = entry.pending_offers or {}
	local needed = n - #entry.pending_offers
	if needed <= 0 then
		return
	end
	local dirty = false
	for _ = 1, needed do
		local rolled = self:roll_item_pool(peer_id, CARDS_PER_OFFER)
		if #rolled == 0 then
			-- Registry too thin to roll anything. Stop early; UI surfaces a
			-- "NO ITEMS" placeholder via peek_offer returning nil.
			break
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
end

function CSRGameManager:pending_offer_count(peer_id)
	local entry = self._state.peer_items[peer_id]
	return (entry and entry.pending_offers and #entry.pending_offers) or 0
end

-- Read-only look at the first stored offer, resolved to live registry defs.
-- Types whose addon vanished are filtered out (so the player never sees a
-- card backed by nothing). Returns nil when no offer is stored. Does NOT pop.
function CSRGameManager:peek_offer(peer_id)
	local entry = self._state.peer_items[peer_id]
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
	return defs
end

-- Pop the first stored offer. Called from the selection-window's finalize
-- right after add_item, so the picked offer is consumed (the OTHER cards in
-- that offer -- the ones the player didn't pick -- are discarded with it).
function CSRGameManager:pop_offer(peer_id)
	local entry = self._state.peer_items[peer_id]
	local offers = entry and entry.pending_offers
	if not offers or #offers == 0 then
		return nil
	end
	local popped = table.remove(offers, 1)
	self:save()
	return popped
end

-- =====================================================
-- Mission set & selection
--
-- Replaces vanilla CrimeSpreeManager's mission-set machinery
-- (generate_new_mission_set / get_random_missions / select_mission /
-- _setup_mission_lists / get_mission / current_mission).
--
-- The mission POOL is pure static config read straight from
-- tweak_data.crime_spree.missions (3 tier buckets). Only the *chosen* set and
-- the current pick are run state, stored as ids in _state so the save stays
-- JSON-serialisable (tweak_data entries hold engine refs that must not be
-- serialised). The launch path (narrative chain, JobManager temp job,
-- Global.game_settings) is Diesel/tweak_data surface and is mirrored 1:1 from
-- vanilla per REFACTOR_PLAN non-goals (we do not replace the engine surface).
-- =====================================================

-- Build the 3 tier lists from tweak_data, applying the same DLC visibility
-- filter vanilla's _setup_mission_lists uses. Cached after the first successful
-- build: the pool is static config and DLC ownership does not change
-- mid-session (vanilla likewise builds these once in _setup_mission_lists). The
-- cache keeps the reroll spin animation -- which queries random missions
-- per-frame -- free of the ~50-entry rebuild it would otherwise incur each call.
function CSRGameManager:_mission_lists()
	if self._mission_lists_cache then
		return self._mission_lists_cache
	end
	local lists = {}
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return lists -- tweak_data not ready yet; do not poison the cache
	end
	for index, mission_list in ipairs(cs_missions) do
		lists[index] = {}
		for _, mission in ipairs(mission_list) do
			local lvl = mission.level
			local dlc = lvl and lvl.dlc
			local dlc_unlocked = not dlc or (managers.dlc and managers.dlc:is_dlc_unlocked(dlc))
			local should_hide = dlc and managers.dlc and managers.dlc:should_hide_unavailable(dlc) or false
			if dlc_unlocked or not should_hide then
				table.insert(lists[index], mission)
			end
		end
	end
	self._mission_lists_cache = lists
	return lists
end

function CSRGameManager:get_mission(mission_id)
	mission_id = mission_id or self:current_mission()
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return nil
	end
	for _, tbl in pairs(cs_missions) do
		for _, data in pairs(tbl) do
			if data.id == mission_id then
				return data
			end
		end
	end
	return nil
end

-- Rank granted for COMPLETING a mission, by its length category -- the clock
-- icon on the lobby card (user balance spec 2026-05-23): short -> 1, medium ->
-- 2, long -> 3. Category is read from the mission's vanilla `add` value with the
-- SAME thresholds vanilla CrimeSpreeMissionButton:_get_mission_category uses
-- (add <= 5 short, <= 7 medium, else long), so the rank always matches the clock
-- the player saw. Defaults to the current mission; falls back to rank_per_heist
-- when the mission (or its `add`) can't be resolved.
function CSRGameManager:rank_for_mission(mission_id)
	local m = self:get_mission(mission_id)
	local add = m and m.add
	if type(add) ~= "number" then
		return self:constant("rank_per_heist") or 1
	end
	if add <= 5 then
		return 1
	elseif add <= 7 then
		return 2
	end
	return 3
end

-- Rank gain for the heist that was just PLAYED, for the end screen. current_mission()
-- is cleared by generate_mission_set in the mission-end hook before the result tab is
-- built, so it can't be read there. Resolve the played mission from
-- Global.game_settings.level_id (+ mission variant) instead -- the level actually
-- loaded, which BOTH host and client have -- using the SAME match _setup_temporary_job
-- uses, so the displayed gain matches the clock the player saw on the card. Falls back
-- to rank_per_heist when the level isn't a registered CS mission.
function CSRGameManager:rank_for_current_level()
	local gs = Global and Global.game_settings
	local level_id = gs and gs.level_id
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if not level_id or type(cs_missions) ~= "table" then
		return self:constant("rank_per_heist") or 1
	end
	local want_mission = gs.mission or "none"
	local fallback_id = nil
	for _, tier in ipairs(cs_missions) do
		for _, m in ipairs(tier) do
			if m.level and m.level.level_id == level_id then
				if (m.mission or "none") == want_mission then
					return self:rank_for_mission(m.id)
				end
				fallback_id = fallback_id or m.id
			end
		end
	end
	if fallback_id then
		return self:rank_for_mission(fallback_id)
	end
	return self:constant("rank_per_heist") or 1
end

function CSRGameManager:get_random_missions()
	local lists = self:_mission_lists()
	local set = {}
	for i = 1, 3 do
		local list = lists[i]
		if list and #list > 0 then
			set[i] = list[math.random(1, #list)]
		end
	end
	return set
end

-- Single random mission (used by the card spin-animation flavor text).
-- Mirrors vanilla get_random_mission = table.random(get_random_missions()).
function CSRGameManager:get_random_mission()
	local set = self:get_random_missions()
	local pool = {}
	for i = 1, 3 do
		if set[i] then
			pool[#pool + 1] = set[i]
		end
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

-- Roll a fresh set of mission ids and clear the current pick. Ids are stored
-- DENSELY (no nil holes): a missing tier is skipped, not left as a gap, so
-- #_state.mission_set is meaningful and table.concat can't error on a hole.
function CSRGameManager:generate_mission_set()
	local missions = self:get_random_missions()
	local ids = {}
	for i = 1, 3 do
		local m = missions[i]
		if m and m.id then
			ids[#ids + 1] = m.id
		end
	end
	self._state.mission_set = ids
	self._state.current_mission = nil
	log_csr("generate_mission_set: " .. table.concat(ids, ", "))
	self:save()
	return ids
end

function CSRGameManager:reroll_mission_set()
	-- Free reroll for the alpha mission-select slice (no continental-coin cost;
	-- vanilla's escalating-cost reroll economy is intentionally dropped here).
	return self:generate_mission_set()
end

-- Guarantee a non-empty set exists before the lobby renders. Covers old saves
-- (csr_save.json written before mission_set existed) and any path where
-- start_run() early-returned on an already-active loaded state, leaving the set
-- empty -> the missions panel built empty cards and crashed (see
-- crash_report_2026_05_16_19_45). Idempotent: a populated set is left as-is, so
-- reopening the contract does NOT reroll the player's missions.
function CSRGameManager:ensure_mission_set()
	local set = self._state.mission_set
	if type(set) ~= "table" or #set == 0 then
		self:generate_mission_set()
	end
end

-- Resolve the stored ids back to full tweak_data mission tables for the UI.
-- Unresolvable slots return nil (NOT {}), so the panel can skip them rather
-- than build a card with nil .add/.level.
function CSRGameManager:mission_set()
	local out = {}
	for i = 1, 3 do
		local id = (self._state.mission_set or {})[i]
		out[i] = id and self:get_mission(id) or nil
	end
	return out
end

function CSRGameManager:current_mission()
	return self._state.current_mission
end

function CSRGameManager:select_mission(mission_id)
	if mission_id == false then
		self._state.current_mission = nil
		self:save()
		return
	end
	local mission_data = self:get_mission(mission_id)
	if not mission_data then
		log_csr("select_mission: unknown mission id '" .. tostring(mission_id) .. "' — ignored")
		return
	end
	self._state.current_mission = mission_data.id

	-- Engine / tweak_data wiring — mirrors vanilla CrimeSpreeManager:select_mission
	-- (_setup_temporary_job + activate_temporary_job + _setup_global_from_mission_id).
	-- The heist loads at the run's chosen difficulty (self:difficulty()), picked
	-- by the player on the contract screen (set_difficulty) — no longer forced to
	-- the static CS base difficulty.
	local narrative_job = tweak_data
		and tweak_data.narrative
		and tweak_data.narrative.jobs
		and tweak_data.narrative.jobs.crime_spree
	if narrative_job and mission_data.level then
		narrative_job.chain = { mission_data.level }
	end
	if managers.job and mission_data.level then
		managers.job:activate_temporary_job("crime_spree", mission_data.level.level_id)
	end
	if Global and Global.game_settings and mission_data.level then
		Global.game_settings.difficulty = self:difficulty()
		Global.game_settings.one_down = false
		Global.game_settings.level_id = mission_data.level.level_id
		Global.game_settings.mission = mission_data.mission or "none"
	end
	if Network:is_server() and MenuCallbackHandler and MenuCallbackHandler.update_matchmake_attributes then
		MenuCallbackHandler:update_matchmake_attributes()
	end

	log_csr(
		"select_mission: "
			.. tostring(mission_data.id)
			.. " (level="
			.. tostring(mission_data.level and mission_data.level.level_id)
			.. ")"
	)
	-- Persist the selection. The in-game manager is a FRESH instance (init runs
	-- on GameSetup and loads from disk), so an unsaved current_mission reads back
	-- nil in-game -- and end-of-heist rank scaling (rank_for_mission, called from
	-- mission_lifecycle) needs the played mission's id to know its length. A
	-- per-card-click save is cheap here (csr_save.json is tiny; this is a menu
	-- click, not a hot path).
	self:save()
end

-- =====================================================
-- Run lifecycle (alpha stubs)
-- =====================================================

function CSRGameManager:start_run()
	-- Accepting a contract is an explicit "begin a NEW run" intent, so this
	-- ALWAYS resets run progress -- it never continues a leftover run. This is
	-- deliberate: a rank carried over from an old/stale save (a pre-rebalance
	-- csr_save.json, or one where start_run previously early-returned on a
	-- loaded is_active=true) would wreck the new flat-1-rank balance. Per
	-- REFACTOR_PLAN §5.2 alpha resets current run progress; a stats-preserving
	-- legacy migrator (§5.3) is still future work in _migrate_legacy_save.
	-- There is no "continue run" flow in alpha, and start_run is only called
	-- from the contract-accept callbacks (user-initiated, once), so an
	-- unconditional reset is safe and correct here.
	if self._state.is_active then
		log_csr(
			"start_run: discarding a leftover active run (rank=" .. tostring(self._state.rank) .. ") and starting fresh"
		)
	end
	self._state.is_active = true
	self._state.failed = false
	self._state.rank = 0
	self._state.missions_completed = 0
	-- Seed the run's difficulty from the player's remembered preference (the
	-- contract screen's set_difficulty wrote it to _meta before Accept). Falls
	-- back to the CS base difficulty for a first-ever run.
	self._state.difficulty = self:_default_difficulty()
	self._state.seed = math.random(1, 2 ^ 30)
	-- Fresh run = fresh inventory. Wipes every peer's counts + pending offer
	-- queues; the per-peer entries (with their counts/pending_offers fields)
	-- are recreated lazily by get_or_create_peer_entry / ensure_offers the
	-- next time those paths fire. Without this the Items panel renders stacks
	-- carried over from a prior run (user-reported 2026-05-20).
	self._state.peer_items = {}
	self:generate_mission_set()
	log_csr(
		"start_run: new run begun (difficulty="
			.. tostring(self._state.difficulty)
			.. ", seed="
			.. tostring(self._state.seed)
			.. ")"
	)
	for _, fn in ipairs(self._callbacks.on_mission_started) do
		fn()
	end
	self:save()
	return true
end

function CSRGameManager:end_run()
	if not self._state.is_active then
		return false
	end
	self._state.is_active = false
	self._state.failed = false
	-- Mirror the wipe start_run does: a finished run leaves no inventory
	-- residue behind. Without this, any UI that reads player_items() while
	-- is_run_active() is the stubbed-true value (see line ~193) keeps
	-- rendering the prior run's stacks until the player accepts a new
	-- contract. Stats-preserving migration is future work; for alpha,
	-- post-run inventory IS the next-run starting state, so drop it now.
	self._state.peer_items = {}
	log_csr("end_run: run ended at rank=" .. tostring(self._state.rank))
	for _, fn in ipairs(self._callbacks.on_mission_completed) do
		fn()
	end
	self:save()
	return true
end

function CSRGameManager:progress_rank(amount)
	amount = tonumber(amount) or 0
	if amount <= 0 then
		return false
	end
	if not self._state.is_active then
		log_csr("progress_rank: no active run; ignored")
		return false
	end
	self._state.rank = (self._state.rank or 0) + amount
	log_csr("progress_rank: +" .. tostring(amount) .. " (now " .. tostring(self._state.rank) .. ")")
	self:save()
	return true
end

-- One completed heist == +1 to the run's mission counter. Kept separate from
-- progress_rank because rank and "missions completed" are distinct concepts
-- (rank amount per heist is tunable / may gain other sources). Called from the
-- mission-lifecycle hook on a successful end only; mission-end is a rare,
-- once-per-heist event so the extra save() here is not a hot-path concern.
function CSRGameManager:record_mission_completed()
	if not self._state.is_active then
		log_csr("record_mission_completed: no active run; ignored")
		return false
	end
	self._state.missions_completed = (self._state.missions_completed or 0) + 1
	log_csr("record_mission_completed: now " .. tostring(self._state.missions_completed))
	self:save()
	return true
end

-- =====================================================
-- Registries & settings
-- =====================================================

-- =====================================================
-- Failed-run state + continue cost (Slice B)
-- =====================================================

function CSRGameManager:has_failed()
	return self._state.failed == true
end

-- Flag the active run as failed (lost a heist). Does NOT end the run — the run
-- stays active but locked; the lobby gates Start/Reroll/select on has_failed()
-- until clear_failed (paid Continue) or end_run (End Spree). No-op if no run.
function CSRGameManager:mark_failed()
	if not self._state.is_active then
		log_csr("mark_failed: no active run; ignored")
		return false
	end
	self._state.failed = true
	log_csr("mark_failed: run is now FAILED at rank=" .. tostring(self._state.rank))
	self:save()
	return true
end

-- Clear the failed flag so a failed run can continue (called after the player
-- pays the Continue cost). No-op if the run was not failed.
function CSRGameManager:clear_failed()
	if not self._state.failed then
		return false
	end
	self._state.failed = false
	log_csr("clear_failed: failed state cleared (run continues)")
	self:save()
	return true
end

-- Continental-coin cost to clear a failed run and continue. Scales with the
-- run's completed-mission count. Both terms are tunable constants (no
-- hardcoded balance, CLAUDE.md). User-locked 2026-05-18: 10 + 10*missions.
function CSRGameManager:get_continue_cost()
	local base = self:constant("continue_cost_base") or 0
	local per = self:constant("continue_cost_per_mission") or 0
	return base + per * (self._state.missions_completed or 0)
end

function CSRGameManager:constant(name)
	return self._registry.constants and self._registry.constants[name]
end

function CSRGameManager:setting(key)
	return self._meta.settings[key]
end

function CSRGameManager:set_setting(key, value)
	self._meta.settings[key] = value
	if key == "debug_mode" then
		self._debug = value == true
	end
	self:save()
end

-- =====================================================
-- Debug logging (gated on the "debug_mode" setting — the mod's first setting)
--
-- All CSR diagnostic logging routes through here so a single toggle silences it.
-- debug_enabled() is a cached boolean read (cheap enough for hot paths).
-- debug_log() is for discrete / bounded events. _debug_stat() is for continuous
-- per-shot / per-frame stat bonuses: it logs ONLY when the value changes, so the
-- log never floods (and allocates nothing while a value is stable / debug off).
-- =====================================================

function CSRGameManager:debug_enabled()
	return self._debug == true
end

function CSRGameManager:debug_log(msg)
	if self._debug then
		log("[CSR][dbg] " .. tostring(msg))
	end
end

function CSRGameManager:_debug_stat(group, stat, value)
	if not self._debug then
		return
	end
	local cache = self._dbg_stat
	if not cache then
		cache = {}
		self._dbg_stat = cache
	end
	local g = cache[group]
	if not g then
		g = {}
		cache[group] = g
	end
	if g[stat] ~= value then
		g[stat] = value
		log(string.format("[CSR][dbg] %s '%s' bonus -> %.4f", group, stat, value))
	end
end

-- Debug helper (mod-options "Debug Tools"): grant the peer one of every
-- registered item type, bypassing the selection window. add_item already
-- persists + fires on_item_added (so callback items reconcile). Local-player by
-- default; in MP each peer grants its own (item ownership is per-peer).
function CSRGameManager:grant_all_items(peer_id)
	peer_id = peer_id or self:local_peer_id()
	local granted = 0
	for _, item in ipairs(self._registry.items) do
		if self:add_item(peer_id, item.type) then
			granted = granted + 1
		end
	end
	log_csr("grant_all_items: granted " .. granted .. " item type(s) to peer " .. tostring(peer_id))
	return granted
end

-- =====================================================
-- Event registration
-- =====================================================

-- Registers `fn` into `list` and returns an unsubscribe function. UI components
-- with finite lifetime (CSRMissionsMenuComponent, MissionBriefingGui surfaces)
-- MUST hold the returned token and invoke it on teardown -- otherwise their
-- closures keep firing against destroyed panels, and a player who opens the
-- lobby N times stacks N copies of the same refresh handler. The unsub closure
-- captures both `list` and the exact `fn` reference and removes the first
-- match (`==`), which is safe because table.insert never duplicates the same
-- function in one list under normal use. Idempotent: a second call on an
-- already-removed token is a no-op.
local function register_callback(list, fn)
	if type(fn) ~= "function" then
		return function() end
	end
	table.insert(list, fn)
	return function()
		for i = 1, #list do
			if list[i] == fn then
				table.remove(list, i)
				return
			end
		end
	end
end

function CSRGameManager:on_mission_started(fn)
	return register_callback(self._callbacks.on_mission_started, fn)
end

function CSRGameManager:on_mission_completed(fn)
	return register_callback(self._callbacks.on_mission_completed, fn)
end

function CSRGameManager:on_item_added(fn)
	return register_callback(self._callbacks.on_item_added, fn)
end

function CSRGameManager:on_item_removed(fn)
	return register_callback(self._callbacks.on_item_removed, fn)
end

-- =====================================================
-- Save / load
-- =====================================================

local function save_path(name)
	return SavePath .. name
end

function CSRGameManager:save()
	local path = save_path(SAVE_FILE)
	local payload = {
		version = self._meta.version,
		meta = self._meta,
		state = self._state,
	}
	local encoded_ok, encoded = pcall(json.encode, payload)
	if not encoded_ok then
		log_csr("ERROR save: json.encode failed -> " .. tostring(encoded))
		return false
	end
	local f = io.open(path, "w")
	if not f then
		log_csr("ERROR save: could not open for write -> " .. path)
		return false
	end
	f:write(encoded)
	f:close()
	log_csr("save ok -> " .. path)
	return true
end

function CSRGameManager:load()
	local path = save_path(SAVE_FILE)
	local f = io.open(path, "r")
	if not f then
		log_csr("load: no save file at " .. path .. " (fresh install)")
		return false
	end
	local raw = f:read("*all")
	f:close()
	local decoded_ok, decoded = pcall(json.decode, raw)
	if not decoded_ok or type(decoded) ~= "table" then
		log_csr("ERROR load: json.decode failed -> " .. tostring(decoded))
		return false
	end
	if type(decoded.meta) == "table" then
		for k, v in pairs(decoded.meta) do
			self._meta[k] = v
		end
	end
	if type(decoded.state) == "table" then
		for k, v in pairs(decoded.state) do
			self._state[k] = v
		end
	end
	log_csr("load ok <- " .. path .. " (saved_version=" .. tostring(decoded.version) .. ")")
	return true
end

-- Read one persisted setting WITHOUT a live instance. The Mod Options menu is
-- populated during MenuManager:init, which runs BEFORE the Setup:init_managers
-- PostHook that creates managers.csr -- so the instance is nil at populate time
-- and a toggle/slider reading managers.csr would always fall back to its
-- default (e.g. Debug Logging showing OFF every launch even when saved ON).
-- This static reader lets the menu show the saved value. Read-only; nil on any
-- error. The live instance stays the source of truth once it exists.
function CSRGameManager.peek_setting(key)
	local f = io.open(save_path(SAVE_FILE), "r")
	if not f then
		return nil
	end
	local raw = f:read("*all")
	f:close()
	local ok, decoded = pcall(json.decode, raw)
	if not ok or type(decoded) ~= "table" then
		return nil
	end
	local settings = decoded.meta and decoded.meta.settings
	return settings and settings[key]
end

-- =====================================================
-- Legacy-save migrator (stub — logs only)
-- =====================================================

local function legacy_file_probe(path)
	local f = io.open(path, "r")
	if not f then
		return false, 0
	end
	local content = f:read("*all")
	f:close()
	return true, content and #content or 0
end

function CSRGameManager:_migrate_legacy_save()
	local legacy_settings = SavePath .. LEGACY_SETTINGS_FILE
	local legacy_mp = SavePath .. LEGACY_MP_SESSIONS_FILE

	local exists, size = legacy_file_probe(legacy_settings)
	if exists then
		log_csr("migrator: found legacy settings (" .. size .. " bytes) at " .. legacy_settings)
	else
		log_csr("migrator: no legacy settings at " .. legacy_settings)
	end

	exists, size = legacy_file_probe(legacy_mp)
	if exists then
		log_csr("migrator: found legacy MP-sessions (" .. size .. " bytes) at " .. legacy_mp)
	else
		log_csr("migrator: no legacy MP-sessions at " .. legacy_mp)
	end

	log_csr("migrator: stub run complete; legacy files untouched")
end

-- =====================================================
-- Attach to managers table
--
-- PostHook on Setup:init_managers. Both MenuSetup and GameSetup inherit from
-- Setup and call Setup.init_managers(self, managers), so this single hook
-- covers main menu AND in-game setups (verified in lib/setups/menusetup.lua
-- and lib/setups/gamesetup.lua).
-- =====================================================

Hooks:PostHook(Setup, "init_managers", "CSR_AttachGameManager", function(self, managers)
	if managers.csr then
		return
	end
	managers.csr = CSRGameManager:new()
end)
