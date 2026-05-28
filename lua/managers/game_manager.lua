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

-- Guest session-store TTL: a per-host guest inventory is pruned this many days
-- after it was last touched. Items-only expiry per the locked MP reward model
-- (~7 days); the cash earnings bucket B lives in _meta with NO expiry. os.time()
-- is available in the PD2 Lua sandbox (used throughout the pre-refactor tree).
local MP_SESSION_TTL_DAYS = 7

local function log_csr(msg)
	log("[CSR] " .. tostring(msg))
end

local function default_meta()
	return {
		version = CSRGameManager.VERSION,
		stats = {},
		unlocks = {},
		settings = {},
		-- Per-host GUEST session stores, keyed by the host's run seed ("h<seed>").
		-- While guesting, the local player's inventory/tokens/offers live here, NOT in
		-- the paused solo run's _state.peer_items. In _meta so they survive the
		-- player's own start_run/end_run wipe; pruned by age (MP_SESSION_TTL_DAYS),
		-- never by run transitions. See _own_entry / _guest_session_entry below and
		-- project_csr_mp_reward_model (item inventory = per-host cache, items-only TTL).
		mp_sessions = {},
		-- Guest EARNINGS bucket B (project_csr_mp_reward_model): rewards banked while
		-- playing in a host's lobby (own run paused). ONE global accumulator across all
		-- hosts, real banked money, NO TTL -- lives until claimed at the guest's own End
		-- Spree (paid as A + B). In _meta so it survives start_run/end_run; NOT per-host
		-- (unlike mp_sessions inventory). Old saves lacking it inherit these zeros.
		mp_earnings = { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 },
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
		-- Run-scoped accumulator (cash) toward the next LOOT rank. Looted cash on a
		-- completed heist feeds it, and every full reward_per_rank_cash() grants +1
		-- rank (accrue_loot_rank); the remainder carries across heists and is reset
		-- with the rest of _state by start_run. Distinct from the shop's loot->token
		-- remainder (peer_entry.loot_token_cash): loot grants BOTH tokens and rank
		-- progress, measured against the same per-rank payout but banked separately.
		loot_rank_cash = 0,
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
	-- Remote peers' synced item counts (MP visibility): { [peer_id] = { counts, name } }.
	-- RUNTIME ONLY -- never written into _state, so other players' inventories never
	-- leak into our csr_save.json. Filled by the MP item sync (mp_sync.lua) and read
	-- back through player_items() for the per-peer items panel.
	self._remote_peer_items = {}
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
	-- gone. For rank-pick items this lowers rank_item_count so the lobby reminder
	-- auto-reappears (host_rank > rank_item_count) and the player can reselect.
	-- A dropped SHOP-sourced orphan can wrongly re-arm a pick (the shop tally is
	-- not decremented) -- known deferred edge; a token refund + source-aware drop
	-- is still TODO.
	self:_drop_orphan_items()
	-- Expire stale guest session stores (items-only TTL). Sessions persist across the
	-- guest's own runs (in _meta), so age is the only thing that clears them.
	self:_prune_expired_sessions()
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

-- =====================================================
-- End-of-run rewards (projection + award source of truth)
-- =====================================================

-- Per-rank cash payout multiplier by CSR difficulty index (1=normal .. 7=death
-- sentence). Mirrors vanilla difficulty_multiplier_payout (moneytweakdata.lua).
-- Module-level so projected_rewards (End Spree payout) and reward_per_rank_cash
-- (loot->rank / loot->token thresholds) share one source of truth for the numbers.
local REWARD_PAYOUT_MULT = { 1, 2, 5, 10, 11, 13, 14 }

-- CSR difficulty index 1=normal .. 7=death_sentence for the reward multiplier
-- tables. tweak_data.difficulties leads with "easy" (index 1), so the CSR index is
-- difficulty_to_index - 1. Clamped so an unexpected id can't index out of range.
function CSRGameManager:reward_difficulty_index()
	local di = (tweak_data and tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(self:difficulty()))
		or 2
	return math.max(1, math.min(7, di - 1))
end

-- The projected run-completion reward for the CURRENT rank + difficulty, keyed for
-- vanilla CrimeSpreeManager:award_rewards (experience / cash / continental_coins /
-- loot_drop). Single source of truth: the Rewards panel renders it, and End Spree
-- awards it. Uses the OWN run rank/difficulty (self:rank()), NOT host_rank(): this
-- is reward bucket A in the locked MP model -- a guest's own-run payout is its own
-- rank/difficulty, while the host-difficulty guest earnings (bucket B) accrue
-- separately (next pass, project_csr_mp_reward_model). On host/SP rank()==host_rank().
-- Formulas locked in
-- project_csr_reward_system_design:
--   cash  = 200k × payout_mult[diff] × rank   (flat from rank; no skill/loot/crew)
--   xp    = 12k × (1 + xp_mult[diff]) × rank × skill_mult × infamy_mult
--   coins = rank * 2, loot cards = rank
-- REWARD_PAYOUT_MULT (module-level) mirrors vanilla difficulty_multiplier_payout
-- (moneytweakdata.lua); XP_MULT is 1 + vanilla experience difficulty_multiplier
-- (tweakdata.lua), normal=0.
-- The reward components for `rank` ranks at CSR difficulty index `idx`. Shared by
-- projected_rewards (own run, bucket A) and accrue_mp_earnings (guest run, bucket B,
-- at the HOST difficulty index). Linear in rank, so summing per-heist accruals is
-- mathematically identical to one projection at the final rank.
function CSRGameManager:_rewards_for(rank, idx)
	rank = tonumber(rank) or 0
	local XP_MULT = { 0, 2, 5, 10, 11.5, 13, 14 }

	local cash = 200000 * (REWARD_PAYOUT_MULT[idx] or 1) * rank
	local xp = 12000 * (1 + (XP_MULT[idx] or 0)) * rank
	-- Each accessor returns 1 + bonus already; pcall-isolated (a menu projection
	-- must never error). Skill mult touches managers.network only when in a session.
	local skill_mult, infamy_mult = 1, 1
	pcall(function()
		skill_mult = (managers.player and managers.player:get_skill_exp_multiplier()) or 1
	end)
	pcall(function()
		infamy_mult = (managers.player and managers.player:get_infamy_exp_multiplier()) or 1
	end)
	xp = xp * skill_mult * infamy_mult

	return {
		cash = math.round(cash),
		experience = math.round(xp),
		continental_coins = rank * 2,
		loot_drop = rank,
	}
end

function CSRGameManager:projected_rewards()
	-- Bucket A: own run rank + own difficulty (NOT host_rank/host difficulty -- a
	-- guest's own-run payout is its own paused progress; the host-difficulty guest
	-- earnings are bucket B, summed in separately at End Spree).
	return self:_rewards_for(self:rank(), self:reward_difficulty_index())
end

-- CSR difficulty index for the HOST's synced difficulty (bucket B accrual). Falls
-- back to the own-run index when no host difficulty is synced (not guesting / not yet
-- pushed). Same 1..7 clamp as reward_difficulty_index.
function CSRGameManager:host_reward_difficulty_index()
	local hd = self:mp_host_difficulty()
	if type(hd) ~= "string" then
		return self:reward_difficulty_index()
	end
	local di = (tweak_data and tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(hd)) or 2
	return math.max(1, math.min(7, di - 1))
end

-- =====================================================
-- Guest earnings bucket B (project_csr_mp_reward_model)
-- =====================================================

-- Bank a completed GUEST heist's reward into _meta.mp_earnings. `rank_gained` =
-- the heist's rank value (length-based, same as a host/solo heist); valued at the
-- HOST difficulty per the model. Called ONLY from the guest fork in
-- mission_lifecycle.lua (own run is paused there). Returns the accrued delta for
-- logging; persists immediately (real banked money, never lost on a later crash).
function CSRGameManager:accrue_mp_earnings(rank_gained)
	rank_gained = tonumber(rank_gained) or 0
	if rank_gained <= 0 then
		return nil
	end
	local r = self:_rewards_for(rank_gained, self:host_reward_difficulty_index())
	local b = self._meta.mp_earnings or { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 }
	b.cash = (b.cash or 0) + r.cash
	b.experience = (b.experience or 0) + r.experience
	b.continental_coins = (b.continental_coins or 0) + r.continental_coins
	b.loot_drop = (b.loot_drop or 0) + r.loot_drop
	self._meta.mp_earnings = b
	self:save()
	log_csr(
		"accrue_mp_earnings: +"
			.. tostring(r.cash)
			.. " cash / +"
			.. tostring(r.experience)
			.. " xp (bucket B now "
			.. tostring(b.cash)
			.. " cash)"
	)
	return r
end

-- A guest's looted cash -> bucket B rank rewards (the MP analogue of the own-run
-- accrue_loot_rank): every full per-rank of loot banks one rank's worth into bucket B,
-- the remainder carried on the guest SESSION entry (per-host, in _meta, so it survives
-- across the host's heists). reward_per_rank_cash() returns the HOST per-rank while
-- guesting (and this only runs while guesting), so a guest's SHARED loot banks the same
-- rank value the host gets as literal ranks (accrue_loot_rank). Returns ranks banked.
function CSRGameManager:accrue_guest_loot_rank(loot_cash)
	loot_cash = tonumber(loot_cash) or 0
	if loot_cash <= 0 then
		return 0
	end
	local per_rank = self:reward_per_rank_cash()
	if per_rank <= 0 then
		return 0
	end
	local entry = self:_guest_session_entry(true)
	if not entry then
		return 0
	end
	local acc = (entry.loot_rank_cash or 0) + loot_cash
	local ranks = math.floor(acc / per_rank)
	entry.loot_rank_cash = acc - ranks * per_rank
	if ranks > 0 then
		self:accrue_mp_earnings(ranks) -- accrue_mp_earnings saves
	else
		self:save() -- persist the carried remainder
	end
	return ranks
end

-- Read-only copy of bucket B (zeros when empty -- always a full table for callers).
function CSRGameManager:mp_earnings()
	local b = self._meta.mp_earnings or {}
	return {
		cash = b.cash or 0,
		experience = b.experience or 0,
		continental_coins = b.continental_coins or 0,
		loot_drop = b.loot_drop or 0,
	}
end

-- True when bucket B holds anything claimable -- used to widen the End Spree rank-0
-- gate so a pure-client (own rank 0) who banked guest earnings still cashes out.
function CSRGameManager:has_mp_earnings()
	local b = self._meta.mp_earnings
	if not b then
		return false
	end
	return (b.cash or 0) > 0 or (b.experience or 0) > 0 or (b.continental_coins or 0) > 0 or (b.loot_drop or 0) > 0
end

-- Zero bucket B after it has been paid out (End Spree A + B). Persists.
function CSRGameManager:reset_mp_earnings()
	self._meta.mp_earnings = { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 }
	self:save()
end

-- Public guesting check (delegates to _is_guesting): true while the local player is a
-- client in a host's announced CSR run. Reward + lifecycle code outside game_manager
-- forks on this to pause the own run and bank into bucket B instead.
function CSRGameManager:is_guesting()
	return self:_is_guesting()
end

-- Cash value of one rank at the difficulty the player is CURRENTLY earning at -- the
-- per-rank yardstick looted cash is measured against (a full reward_per_rank_cash() of
-- loot earns +1 rank via accrue_loot_rank, reward_per_rank_cash()/TOKENS_PER_RANK earns
-- one Gage Token in the shop). Own run difficulty normally; while GUESTING it returns
-- the HOST difficulty, so a guest's SHARED loot yields the SAME tokens + end-screen
-- conversion as the host (PD2 loot is shared, so the per-rank economy a guest measures
-- it against must be the host's, not its own paused run's). Bucket A (projected_rewards)
-- reads _rewards_for directly, NOT this, so it is unaffected and stays own-difficulty.
function CSRGameManager:reward_per_rank_cash()
	local idx = self:_is_guesting() and self:host_reward_difficulty_index() or self:reward_difficulty_index()
	return 200000 * (REWARD_PAYOUT_MULT[idx] or 1)
end

-- Feed a completed heist's looted cash into the run's loot->rank accumulator. Every
-- full reward_per_rank_cash() of accumulated loot grants +1 rank; the cash
-- remainder carries forward (loot_rank_cash) so nothing is lost across heists.
-- No token side effect -- loot tokens are credited separately and continuously by
-- the shop (CSR_Shop.accrue_loot_tokens). Run-scoped: reset by start_run. Returns
-- the number of ranks granted this call.
function CSRGameManager:accrue_loot_rank(loot_cash)
	loot_cash = tonumber(loot_cash) or 0
	if loot_cash <= 0 or not self._state.is_active then
		return 0
	end
	local per_rank = self:reward_per_rank_cash()
	if per_rank <= 0 then
		return 0
	end
	local acc = (self._state.loot_rank_cash or 0) + loot_cash
	local ranks = math.floor(acc / per_rank)
	self._state.loot_rank_cash = acc - ranks * per_rank
	if ranks > 0 then
		self:progress_rank(ranks) -- progress_rank saves
	else
		self:save() -- persist the carried remainder
	end
	return ranks
end

function CSRGameManager:seed()
	return self._state.seed
end

function CSRGameManager:host_rank()
	-- The run rank that COMBAT scaling reads: enemy HP/dmg, per-rank player
	-- passives (rank_passives.lua), and the item-selection quota. For a guest it
	-- follows the HOST's synced rank; for a host/SP it's the own run rank.
	--
	-- Gated on is_client() (plus a debug-sim override) so a stale persisted
	-- mp_session.host_rank can never leak into solo/host play: synced host rank
	-- applies ONLY while actually guesting. Reward bucket A intentionally does NOT
	-- read this -- see projected_rewards (own rank/difficulty), per the locked MP
	-- reward model (project_csr_mp_reward_model).
	local mp = self._state.mp_session
	if mp and mp.host_rank then
		local mpnet = _G.CSR_MP
		local guesting = mpnet and mpnet.is_client and mpnet.is_client()
		if guesting then
			return mp.host_rank
		end
	end
	return self._state.rank or 0
end

-- Client-side: store the host's synced run rank + difficulty + run seed (from the
-- MP host-state push in mp_session.lua). host_rank() returns host_rank while
-- guesting; host_difficulty is banked for the (next-pass) guest reward bucket; and
-- host_seed keys the per-host guest session store (_guest_session_key / _own_entry)
-- so the guest's inventory/tokens live separate from the paused solo run. Host/SP
-- never call this.
function CSRGameManager:set_mp_host_state(host_rank, host_difficulty, host_seed, host_missions)
	self._state.mp_session = self._state.mp_session or {}
	local mp = self._state.mp_session
	if type(host_rank) == "number" then
		mp.host_rank = host_rank
	end
	if type(host_difficulty) == "string" then
		mp.host_difficulty = host_difficulty
	end
	if type(host_seed) == "number" then
		mp.host_seed = host_seed
	end
	if type(host_missions) == "number" then
		mp.host_missions = host_missions
	end
end

-- Host's completed-heist count while guesting (nil on host/SP -> caller uses own).
-- The lobby + briefing headers show this so a guest reads the HOST's run progress.
-- Gated on _is_guesting() for the same reason as mp_host_difficulty: clear_mp_host_state
-- runs only on the client path, so a stale host_missions would otherwise leak into the
-- header after the player leaves a host and starts hosting their own run.
function CSRGameManager:mp_host_missions_completed()
	if not self:_is_guesting() then
		return nil
	end
	local mp = self._state.mp_session
	return mp and mp.host_missions or nil
end

-- Drop synced host state (leaving a host's session / between heists). Clears
-- host_seed too: during the heist-load window (before the host re-pushes) the guest
-- falls back to its own _state -- the same fallback host_rank() uses -- and no
-- inventory mutation happens on the load screen.
function CSRGameManager:clear_mp_host_state()
	local mp = self._state.mp_session
	if not mp then
		return
	end
	mp.host_rank = nil
	mp.host_difficulty = nil
	mp.host_seed = nil
	mp.host_missions = nil
	-- Cleared too so the guest re-pulls the host's CURRENT set on the next lobby
	-- (the host rolls a fresh set after each heist); the MISSION_SET reply refills it.
	mp.host_mission_set = nil
end

-- Host difficulty synced while guesting (nil when not). For the next-pass guest
-- reward bucket; combat already follows host via host_rank().
--
-- Gated on _is_guesting() (mirrors how host_rank() self-gates on is_client): a
-- stale host_difficulty lingers in _state.mp_session after the player leaves a host
-- and starts hosting their OWN run, because clear_mp_host_state() runs only on the
-- client path (mp_session.lua at_enter). Without the gate the lobby/briefing showed
-- the previous host's difficulty (e.g. overkill) instead of the player's own pick.
function CSRGameManager:mp_host_difficulty()
	if not self:_is_guesting() then
		return nil
	end
	local mp = self._state.mp_session
	return mp and mp.host_difficulty or nil
end

-- Late-join token seed bookkeeping (project_csr_late_join_grant_model). The guest's
-- wallet is seeded to the host's GROSS earned tokens ONCE per host run; the guard
-- rides the guest SESSION record (in _meta), not a runtime global, so re-joining the
-- SAME host -- even after a game restart -- never re-seeds over what the guest has
-- spent/hoarded. A different host = a different session = re-seed. Both no-op outside
-- a keyed guest session (returns false / does nothing), so host/SP are unaffected.
function CSRGameManager:guest_tokens_seeded()
	local key = self:_guest_session_key()
	if not key then
		return false
	end
	local sess = self._meta.mp_sessions and self._meta.mp_sessions[key]
	return (sess and sess.tokens_seeded) == true
end

function CSRGameManager:mark_guest_tokens_seeded()
	local key = self:_guest_session_key()
	if not key then
		return
	end
	-- Ensure the session record exists (the wallet write that precedes this already
	-- created it, but guard anyway), then flag + persist.
	self:_guest_session_entry(true)
	local sess = self._meta.mp_sessions and self._meta.mp_sessions[key]
	if sess then
		sess.tokens_seeded = true
		self:save()
	end
end

-- Public mod version (for MP version/addon-mismatch reporting). Reads the meta
-- field the save header carries.
function CSRGameManager:mod_version()
	return (self._meta and self._meta.version) or "unknown"
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
	-- Acquisition order: item types in the sequence the player FIRST obtained them
	-- (add_item appends a NEW type, remove_item drops it at zero so a re-acquire is
	-- "new" again). Drives the Items panel sort. Absent on legacy/pre-order saves --
	-- player_items_order self-heals from counts, so a nil here is safe.
	entry.order = entry.order or {}
	return entry
end

-- Wall-clock unix time for the session-store TTL, pcall-guarded. os.time() is
-- available in the PD2 sandbox; on the off chance it errors, returning 0 makes
-- pruning never expire anything (now - last_seen < 0) rather than wrongly wipe.
function CSRGameManager:_now()
	local ok, t = pcall(os.time)
	return (ok and type(t) == "number") and t or 0
end

-- True while the local player is GUESTING in another host's CSR run: a real network
-- client AND the host has announced its run (host_seed known -- which is also what
-- host_rank() needs to scale). While guesting, the local player's inventory / tokens
-- / pending offers live in a per-host SESSION store (keyed by the host's run seed, in
-- _meta so it survives the player's own start_run/end_run wipe), NOT the paused solo
-- run's _state.peer_items.
function CSRGameManager:_is_guesting()
	local mp = self._state.mp_session
	local net = _G.CSR_MP
	if not (net and net.is_client and net.is_client()) then
		return false
	end
	return mp ~= nil and mp.host_seed ~= nil
end

-- Storage key for the active guest session: the host's run seed. nil when not
-- guesting / the host hasn't announced its seed yet (the redirect then stays off and
-- inventory falls back to _state -- the same fallback host_rank() uses).
function CSRGameManager:_guest_session_key()
	local mp = self._state.mp_session
	local seed = mp and mp.host_seed
	if seed == nil then
		return nil
	end
	return "h" .. tostring(seed)
end

-- The per-host guest session entry ({ counts, pending_offers, tokens, shop, ... } --
-- same shape as a _state.peer_items entry). Lazily created under create=true (which
-- also refreshes the TTL clock); read-only callers pass false and get nil when no
-- session exists yet. Lives in _meta.mp_sessions so it persists across the guest's
-- own runs and is pruned only by age (_prune_expired_sessions), not run transitions.
function CSRGameManager:_guest_session_entry(create)
	local key = self:_guest_session_key()
	if not key then
		return nil
	end
	self._meta.mp_sessions = self._meta.mp_sessions or {}
	local sess = self._meta.mp_sessions[key]
	if not sess then
		if not create then
			return nil
		end
		sess = { entry = { counts = {}, order = {} }, last_seen = self:_now() }
		self._meta.mp_sessions[key] = sess
	elseif create then
		sess.last_seen = self:_now()
	end
	sess.entry = sess.entry or { counts = {}, order = {} }
	sess.entry.counts = sess.entry.counts or {}
	sess.entry.order = sess.entry.order or {}
	return sess.entry
end

-- Resolve the OWN-side inventory entry for `peer_id`: the per-host guest session
-- store while the LOCAL player is guesting, else the _state.peer_items entry. `create`
-- lazily makes the entry (writers pass true; read-only callers pass false to get nil
-- when nothing exists, so a stray/unsynced peer id never pollutes _state). Remote
-- peers are display-only and are resolved by _peer_counts before reaching here.
function CSRGameManager:_own_entry(peer_id, create)
	if peer_id == self:local_peer_id() and self:_is_guesting() then
		return self:_guest_session_entry(create)
	end
	if create then
		return get_or_create_peer_entry(self._state, peer_id)
	end
	return self._state.peer_items[peer_id]
end

-- Counts table for ANY peer. A REMOTE peer's synced items (runtime, never saved)
-- win; otherwise the own-side entry (_own_entry: guest session store while guesting,
-- else _state). Remote peers are never written into _state.peer_items, and the local
-- peer is never put in _remote_peer_items, so the two never collide. Read-only (no
-- create), so enumerating peers never spawns spurious entries. Returns nil when the
-- peer has no record.
function CSRGameManager:_peer_counts(peer_id)
	local remote = self._remote_peer_items and self._remote_peer_items[peer_id]
	if remote then
		return remote.counts
	end
	local entry = self:_own_entry(peer_id, false)
	return entry and entry.counts
end

-- Read-only { [type] = n } map of everything the peer owns ({} if nothing).
function CSRGameManager:player_items(peer_id)
	return self:_peer_counts(peer_id) or {}
end

-- Stored acquisition-order array for a peer (the raw list; may be stale/missing).
-- A remote peer's synced order wins; otherwise the own-side entry's order.
function CSRGameManager:_peer_order(peer_id)
	local remote = self._remote_peer_items and self._remote_peer_items[peer_id]
	if remote then
		return remote.order
	end
	local entry = self:_own_entry(peer_id, false)
	return entry and entry.order
end

-- Owned item types in acquisition order (first-obtained first), self-healing: it
-- reconciles the stored order against the live counts so it is always correct even
-- for a legacy save (no order field) or a remote peer synced without one --
-- recognised types keep their recorded order, any owned-but-untracked type is
-- appended in a deterministic (type-sorted) fallback. Duplicates never reorder.
function CSRGameManager:player_items_order(peer_id)
	local counts = self:_peer_counts(peer_id) or {}
	local stored = self:_peer_order(peer_id)
	local result, seen = {}, {}
	if type(stored) == "table" then
		for _, item_type in ipairs(stored) do
			if (counts[item_type] or 0) > 0 and not seen[item_type] then
				result[#result + 1] = item_type
				seen[item_type] = true
			end
		end
	end
	local missing = {}
	for item_type, n in pairs(counts) do
		if type(n) == "number" and n > 0 and not seen[item_type] then
			missing[#missing + 1] = item_type
		end
	end
	table.sort(missing)
	for _, item_type in ipairs(missing) do
		result[#result + 1] = item_type
	end
	return result
end

-- Owned stacks of ONE item type.
function CSRGameManager:item_count(peer_id, item_type)
	local counts = self:_peer_counts(peer_id)
	return (counts and counts[item_type]) or 0
end

-- Total stacks across ALL types. One rank == one pick, so the lobby
-- "unselected items" reminder subtracts this from host rank.
function CSRGameManager:total_item_count(peer_id)
	local counts = self:_peer_counts(peer_id)
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

-- Items NOT earned through the rank-pick window (currently: Black Market
-- purchases) must NOT count toward the rank quota -- the player is entitled to
-- one pick PER RANK no matter how many extra items they bought/printed (user
-- spec 2026-05-26). A per-peer aggregate, bumped on purchase (shop.lua buy());
-- resets with the run (peer_items wiped on start_run).
--
-- It honours "a scrapped/printed item keeps its source" for free: both the
-- scrapper and the in-world copier are NET-ZERO on total_item_count (remove the
-- input stack, add the output stack), so rank_item_count is preserved through
-- any real<->scrap<->real chain -- no per-instance provenance needed. (Orphan-
-- drop of a purchased item is a known deferred edge; see _drop_orphan_items.)
function CSRGameManager:shop_item_count(peer_id)
	local entry = self:_own_entry(peer_id or self:local_peer_id(), false)
	return (entry and entry.shop_item_count) or 0
end

-- Owned stacks that DID come from rank picks = total minus purchases. This is
-- what the lobby/briefing reminder compares against host rank.
function CSRGameManager:rank_item_count(peer_id)
	peer_id = peer_id or self:local_peer_id()
	return math.max(0, self:total_item_count(peer_id) - self:shop_item_count(peer_id))
end

-- =====================================================
-- Remote peers' synced inventories (MP visibility; runtime-only, never saved)
-- =====================================================

-- Store a remote peer's synced item counts + display name. Does NOT fire the
-- on_item_added/removed callbacks (remote items apply on THEIR machine, not ours --
-- host-authoritative) and does NOT save (these never persist into our save).
-- `order` is the acquisition-order sequence as received over the wire (optional;
-- player_items_order self-heals from counts when absent, e.g. the SP debug peer).
function CSRGameManager:set_remote_peer_items(peer_id, counts, name, order)
	if not peer_id then
		return
	end
	self._remote_peer_items = self._remote_peer_items or {}
	self._remote_peer_items[peer_id] = { counts = counts or {}, name = name, order = order }
end

function CSRGameManager:remove_remote_peer(peer_id)
	if self._remote_peer_items then
		self._remote_peer_items[peer_id] = nil
	end
end

function CSRGameManager:clear_remote_peers()
	self._remote_peer_items = {}
end

function CSRGameManager:remote_peer_name(peer_id)
	local r = self._remote_peer_items and self._remote_peer_items[peer_id]
	return r and r.name
end

-- Peer ids we hold synced inventories for, so the items panel can enumerate them
-- even when the live session peer list lags (and the SP debug fake peer).
function CSRGameManager:remote_peer_ids()
	local ids = {}
	if self._remote_peer_items then
		for pid in pairs(self._remote_peer_items) do
			ids[#ids + 1] = pid
		end
	end
	return ids
end

-- Convenience for item hook code (CSR's own + addons): owned stacks of an item
-- by the LOCAL player, so a hook doesn't repeat the local_peer_id() plumbing.
function CSRGameManager:owned(item_type)
	return self:item_count(self:local_peer_id(), item_type)
end

-- Mutable per-peer state record (counts + subsystem-owned fields). Lazy-created.
-- The shop (lua/managers/shop.lua) stashes its token wallet + lineup here so they
-- ride the manager's own save() and the start_run/end_run inventory wipe. While the
-- local player is guesting this returns the per-host guest session entry instead, so
-- guest tokens/lineup/offers never touch the paused solo run (M5, _own_entry).
-- Callers that mutate the returned table must call :save() to persist.
function CSRGameManager:peer_entry(peer_id)
	return self:_own_entry(peer_id or self:local_peer_id(), true)
end

function CSRGameManager:add_item(peer_id, item_type)
	if not self._registry.by_type[item_type] then
		log_csr("add_item: unknown type '" .. tostring(item_type) .. "' — ignored")
		return false
	end
	local entry = self:_own_entry(peer_id, true)
	local was = entry.counts[item_type] or 0
	entry.counts[item_type] = was + 1
	-- First copy of this type -> record it at the end of the acquisition order.
	-- A duplicate (was > 0) only bumps the count and keeps its existing position.
	if was == 0 then
		entry.order = entry.order or {}
		entry.order[#entry.order + 1] = item_type
	end
	for _, fn in ipairs(self._callbacks.on_item_added) do
		fn(peer_id, item_type, entry.counts[item_type])
	end
	self:save()
	log_csr("add_item: peer=" .. tostring(peer_id) .. " type=" .. item_type .. " count=" .. entry.counts[item_type])
	return true
end

function CSRGameManager:remove_item(peer_id, item_type)
	local entry = self:_own_entry(peer_id, false)
	local counts = entry and entry.counts
	if not counts or not counts[item_type] or counts[item_type] <= 0 then
		return false
	end
	counts[item_type] = counts[item_type] - 1
	if counts[item_type] <= 0 then
		counts[item_type] = nil
		-- Last copy gone: drop it from the acquisition order so a future re-acquire
		-- counts as "new" and appends at the end (matches the count going 0 -> 1).
		if entry.order then
			for i = #entry.order, 1, -1 do
				if entry.order[i] == item_type then
					table.remove(entry.order, i)
					break
				end
			end
		end
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
		-- Printer fodder: scrap items (produced by the in-world scrapper, consumed
		-- by the printer) are stackable inventory like any item but are excluded
		-- from the selection-window roll (see roll_item_pool). nil unless true.
		is_scrap = def.is_scrap == true or nil,
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
-- still listed in the UI (apply_modifiers nil-guards _G[class]).
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
-- Per-rank enemy scaling (additive percent, no cap). Both +5%/rank (user balance
-- 2026-05-24): ports the pre-refactor +0.3% HP / +0.4% DMG scaled up for the new
-- ~1-item-per-rank cadence (was ~1 item per 20 ranks), rounded to a clean 5/5.
local ENEMY_HEALTH_PCT_PER_RANK = 5
local ENEMY_DAMAGE_PCT_PER_RANK = 5

function CSRGameManager:apply_modifiers()
	if not managers or not managers.modifiers then
		return
	end
	-- managers.modifiers is rebuilt per game-state setup, so our category starts
	-- empty each heist; clear it anyway for idempotency (the hook could re-fire).
	if managers.modifiers._modifiers then
		managers.modifiers._modifiers.csr = nil
	end

	-- CLIENT branch. Enemy DAMAGE-to-player is computed in EACH peer's OWN
	-- PlayerDamage (vanilla modify_value "PlayerDamage:TakeDamageBullet"), so the
	-- rank-based ModifierEnemyDamage MUST live on the client too -- without it a
	-- guest takes UNSCALED hits even though host_rank is synced (the documented
	-- "enemy damage is host-local" gap below). Enemy HP and every other
	-- host-authoritative effect stay host-only and reach the client via unit/spawn
	-- sync, so the client adds ONLY this one modifier, rank-based off the synced
	-- host_rank(). (Special-modifier enemy-damage additions remain an
	-- active-modifier sync gap.) Re-applied when host_rank arrives mid-load -- see
	-- mp_session.lua HANDSHAKE_OK handler.
	if not Network:is_server() then
		local rank = self:host_rank() or 0
		if rank > 0 and _G.ModifierEnemyDamage then
			managers.modifiers:add_modifier(
				_G.ModifierEnemyDamage:new({ damage = rank * ENEMY_DAMAGE_PCT_PER_RANK }),
				"csr"
			)
			self:debug_log(
				string.format(
					"client enemy-damage modifier: rank=%d -> +%d%% DMG",
					rank,
					rank * ENEMY_DAMAGE_PCT_PER_RANK
				)
			)
		end
		return
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

	-- Same trap for ModifierEnemyHealth (injected below): its :init multiplies
	-- tweak_data.character[*].HEALTH_INIT in place and never reverts, so re-applying
	-- each heist would compound. Snapshot the pristine HEALTH_INIT once, then restore
	-- from it before every apply -- the modifier then always multiplies from a clean
	-- baseline, and HP returns to vanilla on a rank-0 / no-scaling run. (Enemy DAMAGE
	-- needs no baseline: ModifierEnemyDamage scales via modify_value, no mutation.)
	local ctd = tweak_data and tweak_data.character
	if ctd and ctd.enemy_list then
		local snapshotted = false
		if not _G.CSR_EnemyHealthBaseline then
			local base = {}
			for _, name in ipairs(ctd:enemy_list()) do
				if ctd[name] and ctd[name].HEALTH_INIT then
					base[name] = ctd[name].HEALTH_INIT
				end
			end
			_G.CSR_EnemyHealthBaseline = base
			snapshotted = true
		end
		local restored = 0
		for name, hp in pairs(_G.CSR_EnemyHealthBaseline) do
			if ctd[name] then
				ctd[name].HEALTH_INIT = hp
				restored = restored + 1
			end
		end
		self:debug_log(
			string.format(
				"enemy HP baseline %s, restored pristine HEALTH_INIT for %d enemies (no compounding)",
				snapshotted and "snapshotted" or "reused",
				restored
			)
		)
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

	-- Per-rank enemy HP / damage scaling. NOT a registered passport (it is continuous
	-- in rank, not a per-rank unlock), so it is injected directly here. host_rank() is
	-- the entitlement (a client mirrors the host). Value is a PERCENT -- ModifierEnemy
	-- Health/Damage compute 1 + value/100. MP: enemy HP applies to everyone (host
	-- spawns units from the mutated tweak); enemy damage is host-local until the
	-- modifier-sync slice (same gap as ModifierLessConcealment).
	local rank = self:host_rank() or 0
	if rank > 0 then
		to_activate["ModifierEnemyHealth"] = { health = rank * ENEMY_HEALTH_PCT_PER_RANK }
		to_activate["ModifierEnemyDamage"] = { damage = rank * ENEMY_DAMAGE_PCT_PER_RANK }
		self:debug_log(
			string.format(
				"enemy scaling: rank=%d -> +%d%% HP, +%d%% DMG",
				rank,
				rank * ENEMY_HEALTH_PCT_PER_RANK,
				rank * ENEMY_DAMAGE_PCT_PER_RANK
			)
		)
	end

	local applied = 0
	for class, data in pairs(to_activate) do
		local mod_class = _G[class]
		if mod_class then
			managers.modifiers:add_modifier(mod_class:new(data), "csr")
			applied = applied + 1
		else
			log_csr("apply_modifiers: class '" .. tostring(class) .. "' not loaded -- effect skipped")
		end
	end
	log_csr("apply_modifiers: applied " .. applied .. " modifier(s)")
end

-- Current enemy HP / damage scaling percents (host_rank-based; 0 outside a run).
-- The Modifiers panel's "enemies buffed by X%" header reads this so the shown number
-- can't drift from what apply_modifiers actually applies. Returns two values (HP%,
-- DMG%) -- equal today (both rank * 5), kept separate so a future split needs no
-- caller change.
function CSRGameManager:enemy_scaling()
	local rank = self:host_rank() or 0
	return rank * ENEMY_HEALTH_PCT_PER_RANK, rank * ENEMY_DAMAGE_PCT_PER_RANK
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
-- uninstalled / disabled / renamed type). The strategy is "drop": dropping a
-- rank-pick orphan re-arms the lobby reminder (host_rank > rank_item_count) so
-- the player gets a fresh pick. Shop-sourced orphans aren't distinguished here
-- (the shop tally isn't decremented), a known deferred edge -- a token refund +
-- per-source branching is still TODO.
function CSRGameManager:_drop_orphan_items()
	local dropped = 0
	local function sweep(counts)
		if not counts then
			return
		end
		for type_id, n in pairs(counts) do
			if not self._registry.by_type[type_id] then
				counts[type_id] = nil
				dropped = dropped + n
			end
		end
	end
	-- Own run inventories...
	for _, entry in pairs(self._state.peer_items) do
		sweep(entry.counts)
	end
	-- ...and every cached guest session inventory (same orphan-drop invariant).
	if type(self._meta.mp_sessions) == "table" then
		for _, sess in pairs(self._meta.mp_sessions) do
			if type(sess) == "table" and sess.entry then
				sweep(sess.entry.counts)
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

-- Prune guest session stores not touched within MP_SESSION_TTL_DAYS (items-only
-- expiry per the locked MP reward model). Runs once at init after load; cheap
-- (a handful of sessions at most). The cash earnings bucket B lives elsewhere in
-- _meta with NO expiry and is never touched here.
function CSRGameManager:_prune_expired_sessions()
	local sessions = self._meta.mp_sessions
	if type(sessions) ~= "table" then
		return
	end
	local now = self:_now()
	local cutoff = MP_SESSION_TTL_DAYS * 86400
	local removed = 0
	for key, sess in pairs(sessions) do
		local last = (type(sess) == "table" and tonumber(sess.last_seen)) or 0
		if now - last > cutoff then
			sessions[key] = nil
			removed = removed + 1
		end
	end
	if removed > 0 then
		log_csr("_prune_expired_sessions: removed " .. removed .. " stale guest session(s)")
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
		-- Skip contraband (never in the roguelike pool) AND scrap (printer fodder,
		-- reaches inventory only via the scrapper -- never offered as a pick).
		if r and r ~= "contraband" and not item.is_scrap then
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
	local entry = self:_own_entry(peer_id, true)
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
	local entry = self:_own_entry(peer_id, false)
	return (entry and entry.pending_offers and #entry.pending_offers) or 0
end

-- Read-only look at the first stored offer, resolved to live registry defs.
-- Types whose addon vanished are filtered out (so the player never sees a
-- card backed by nothing). Returns nil when no offer is stored. Does NOT pop.
function CSRGameManager:peek_offer(peer_id)
	local entry = self:_own_entry(peer_id, false)
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
	local entry = self:_own_entry(peer_id, false)
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
	-- MP: push the new set to guests so their cards match the host's (reroll /
	-- first generate). Self-gates to the host inside broadcast_mission_set.
	if _G.CSR_MP and _G.CSR_MP.broadcast_mission_set then
		_G.CSR_MP.broadcast_mission_set()
	end
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
	-- A guest does NOT roll its own set -- it mirrors the HOST's (synced via the
	-- MISSION_SET wire message / set_mp_host_mission_set). Rolling here would show
	-- the guest a DIFFERENT 3 cards than the host. If the host's set hasn't arrived
	-- yet the cards build empty and the MISSION_SET handler repaints them when it
	-- lands (CSRMissionsMenuComponent:update_mission).
	if self:_is_guesting() then
		return
	end
	local set = self._state.mission_set
	if type(set) ~= "table" or #set == 0 then
		self:generate_mission_set()
	end
end

-- Resolve the stored ids back to full tweak_data mission tables for the UI.
-- Unresolvable slots return nil (NOT {}), so the panel can skip them rather
-- than build a card with nil .add/.level.
function CSRGameManager:mission_set()
	-- While guesting, mirror the HOST's set (its synced ids resolved against our own
	-- identical tweak_data.crime_spree.missions); fall back to the own set for
	-- host/SP or before the host's set has arrived.
	local ids = self._state.mission_set
	if self:_is_guesting() then
		local mp = self._state.mp_session
		if mp and type(mp.host_mission_set) == "table" then
			ids = mp.host_mission_set
		end
	end
	local out = {}
	for i = 1, 3 do
		local id = (ids or {})[i]
		out[i] = id and self:get_mission(id) or nil
	end
	return out
end

-- Host: the ordered id list to broadcast to guests (mp_sync.lua broadcast_mission_set).
function CSRGameManager:mission_set_ids()
	return self._state.mission_set or {}
end

-- Guest: store the host's synced set (ids). mission_set() reads it while guesting.
function CSRGameManager:set_mp_host_mission_set(ids)
	self._state.mp_session = self._state.mp_session or {}
	self._state.mp_session.host_mission_set = type(ids) == "table" and ids or nil
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
	-- MP: push the new selection to guests NOW so their Global.game_settings.level_id
	-- adopts the host's pick before Start (CSR's temp-job chain is built locally per
	-- peer, so the host's level must be synced explicitly or guests load their own).
	if _G.CSR_MP and _G.CSR_MP.broadcast_host_state then
		_G.CSR_MP.broadcast_host_state()
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
	-- Fresh run = fresh loot->rank progress (the per-peer loot->token remainder
	-- rides peer_items, wiped above).
	self._state.loot_rank_cash = 0
	-- Starting your OWN run clears any synced guest host-state residue (host_rank()
	-- is gated on is_client() anyway, but keep the field clean).
	self._state.mp_session = {}
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
	self._state.mp_session = {}
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

-- Debug helper (mod-options "Debug Tools"): force the lobby's mission set to a single
-- card for the vanilla heist whose level_id matches `level_id` (e.g. "red2" =
-- First World Bank), and pre-select it. Lets a tester jump straight to a specific heist
-- to reproduce a heist-specific crash without rerolling for it. Sets CSR state only --
-- the normal lobby/Start flow does the engine wiring when the contract is (re)opened
-- (the card auto-selects because current_mission matches). Requires an active run.
-- Returns true if a matching CS mission was found.
function CSRGameManager:debug_force_mission(level_id)
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		log_csr("debug_force_mission: CS missions not ready")
		return false
	end
	for _, tier in ipairs(cs_missions) do
		for _, m in ipairs(tier) do
			if m.id and m.level and m.level.level_id == level_id then
				self._state.mission_set = { m.id }
				self._state.current_mission = m.id
				self:save()
				log_csr("debug_force_mission: forced '" .. tostring(m.id) .. "' (level " .. tostring(level_id) .. ")")
				return true
			end
		end
	end
	log_csr("debug_force_mission: no CS mission for level '" .. tostring(level_id) .. "'")
	return false
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
