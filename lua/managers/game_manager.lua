-- CSRGameManager — single source of truth for Crime Spree Roguelike state.
-- Hierarchical singleton: _meta (persists across runs), _state (active run), _registry (static content).

CSRGameManager = CSRGameManager or class()
CSRGameManager.VERSION = "U1-beta"

local SAVE_FILE = "csr_save.json"
local LEGACY_SETTINGS_FILE = "crime_spree_roguelike.json"
local LEGACY_MP_SESSIONS_FILE = "csr_mp_sessions.json"

-- False until init() loads settings; kept in sync by set_setting.
_G.CSR_DEBUG = _G.CSR_DEBUG or false

_G.csr_log = function(msg)
	if _G.CSR_DEBUG then
		log(msg)
	end
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

local function default_meta()
	return {
		version = CSRGameManager.VERSION,
		stats = {},
		unlocks = {},
		settings = {},
		-- Per-host guest inventories, keyed by "h<seed>". In _meta so they survive own start/end_run; pruned by age.
		mp_sessions = {},
		-- Bucket B: rewards earned while guesting. Accumulates across hosts; claimed at own End Spree as A+B.
		mp_earnings = { cash = 0, experience = 0, continental_coins = 0, loot_drop = 0 },
	}
end

local function default_state()
	return {
		is_active = false,
		rank = 0,
		-- Tracked separately from rank because rank may have multiple sources.
		missions_completed = 0,
		-- Per-spree BM purchase count; feeds the "Most Purchases" career peak. Resets each start_run.
		run_purchases = 0,
		-- A failed run stays active but locked until the player pays Continue or ends the run.
		failed = false,
		-- Loss penalty (host/SP). Heist outcome commits on start: in_heist is set at heist start,
		-- cleared at MissionEndState. After grace, an interruption (crash/quit) marks the run failed.
		in_heist = false,
		heist_grace_over = false,
		-- Monotonic; a fresh token invalidates a pending grace timer from a prior attempt.
		heist_token = 0,
		-- Internal difficulty id (e.g. "overkill_145"); nil until start_run seeds it.
		difficulty = nil,
		seed = nil,
		mission_set = {}, -- array of mission ids currently offered in the lobby
		current_mission = nil, -- id of the mission the player picked to play next
		peer_items = {},
		-- Accumulated looted cash toward the next loot-rank; remainder carries across heists.
		loot_rank_cash = 0,
		-- Banked continental coins (bucket A), escalated per heist by the streak multiplier.
		-- Replaces the flat rank*COINS_PER_RANK projection; see gm_rewards.lua:accrue_escalated_coins.
		coins_escalated = 0,
		milestones = {},
		spawners = { copiers = {}, scrappers = {} },
		mp_session = {},
	}
end

local function default_registry()
	return {
		items = {},
		by_type = {}, -- [type] = entry
		by_kind = {}, -- [effect.kind] = { entry, ... }
		callback_items = {}, -- items with on_apply/on_remove/on_tick
		modifiers = {
			loud = {},
			stealth_families = {},
			by_id = {},
		},
		constants = {
			dog_tags_hp_bonus = 0.10,
			rank_per_heist = 1,
			-- Continue cost = continue_cost_per_rank * current rank (a failed run keeps its rank).
			continue_cost_per_rank = 3,
			-- Interrupting a live heist (crash / alt-F4 / quit-to-menu) after this many seconds = a loss.
			heist_grace_seconds = 60,
		},
	}
end

function CSRGameManager:init()
	self._meta = default_meta()
	self._state = default_state()
	self._registry = default_registry()
	-- Remote peers' synced item counts for MP visibility: { [peer_id] = { counts, name } }.
	-- Runtime-only (filled by mp_sync.lua, read via player_items) -- never saved to csr_save.json.
	self._remote_peer_items = {}
	self._callbacks = {
		on_mission_started = {},
		on_mission_completed = {},
		on_item_added = {},
		on_item_removed = {},
	}
	self:_migrate_legacy_save()
	self:load()
	self._debug = (self._meta.settings and self._meta.settings.debug_mode) == true
	_G.CSR_DEBUG = self._debug
	-- Loss penalty: if a heist was in flight when the game last closed (crash/alt-F4/quit), commit
	-- the outcome now. Runs once per init, right after load() restored in_heist/heist_grace_over.
	self:_check_interrupted_heist()
	-- Replay registrations into the fresh _registry every init (idempotent, never drains).
	if _G.CSR and _G.CSR._apply_registrations then
		_G.CSR._apply_registrations(self)
	end
	if _G.CSR and _G.CSR._apply_modifier_registrations then
		_G.CSR._apply_modifier_registrations(self)
	end
	-- Tombstone frozen modifier-seq slots whose modifier is gone, so re-installing an add-on
	-- does not restore it to an in-progress spree. Runs after registrations replay (by_id current).
	self:_prune_modifier_seq()
	-- Drop owned items whose addon is no longer registered; re-arms the lobby pick reminder.
	self:_drop_orphan_items()
	self:_prune_expired_sessions()
	-- Wire reconcile to every ownership/run transition so on_apply fires on save-reload too.
	-- Fresh _callbacks table each init prevents stacking duplicate listeners.
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
	-- MissionAssetsManager:init() ran before our narrative chain was set, so the Assets tab stayed empty.
	-- Re-run _setup_mission_assets manually; clear first because it appends (would duplicate on re-init).
	if self:is_run_active() and managers.assets and managers.assets._setup_mission_assets then
		if managers.assets._global then
			managers.assets._global.assets = {}
		end
		managers.assets:_setup_mission_assets()
	end
	log_csr("CSRGameManager initialised; version=" .. tostring(self._meta.version))
end

-- Re-establish the crime_spree narrative chain from Global.game_settings.level_id each time managers init.
-- Without this the game-side manager has an empty chain (set by select_mission only on menu-side),
-- causing nil-crashes in HUDMissionBriefing / MissionBriefingGui on heist launch.
function CSRGameManager:_setup_temporary_job()
	-- Not gated on is_active() — a guest has is_active=false but still needs the chain for briefing surfaces.
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
				-- Exact match wins; keep a level-only fallback in case the variant string drifted.
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

-- MP guest only: the guest never runs select_mission, so its JobManager has no active job
-- (job_id nil) -> current_level_data() nil. EVERY briefing surface built from it is then empty,
-- incl. HUDMissionBriefing:reload which bails at `if not has_active_job() then return` BEFORE it
-- loads the contact assets_gui (the briefing bg video). Mirror the host's select_mission wiring:
-- set the narrative chain, then activate the temporary crime_spree job from game_settings.level_id
-- (vanilla network sync already set it for the heist load). Idempotent + guest-gated: the
-- has_active_job guard makes it a no-op for the host and for vanilla (non-CSR) heists where the
-- job is already active. Must run BEFORE the briefing builds (IngameWaitingForPlayersState:at_enter).
function CSRGameManager:ensure_guest_temp_job()
	if not (_G.CSR_MP and _G.CSR_MP.is_client and _G.CSR_MP.is_client()) then
		return
	end
	if not managers.job or managers.job:has_active_job() then
		return
	end
	local gs = Global and Global.game_settings
	local level_id = gs and gs.level_id
	if not level_id or not managers.job.activate_temporary_job then
		return
	end
	self:_setup_temporary_job()
	managers.job:activate_temporary_job("crime_spree", level_id)
	-- Assets were built off the (then empty) chain at MissionAssetsManager:init; rebuild now.
	if managers.assets and managers.assets._setup_mission_assets then
		if managers.assets._global then
			managers.assets._global.assets = {}
		end
		managers.assets:_setup_mission_assets()
	end
	log_csr("ensure_guest_temp_job: activated crime_spree temp job (level=" .. tostring(level_id) .. ")")
end

-- =====================================================
-- Run-state queries
-- =====================================================

function CSRGameManager:is_run_active()
	-- Alpha stub: always true so item hooks never bail.
	return true
end

function CSRGameManager:is_active()
	-- True only while a CSR run is actually in flight (flipped by start_run/end_run).
	return self._state.is_active == true
end

-- True only while the local player is actually INSIDE a CSR heist (temp crime_spree job loaded).
-- THIS is the gate for every gameplay stat/buff hook so nothing leaks into vanilla heists.
-- Works for guests too: they load the same crime_spree job, even though is_active() is false for them.
-- Note: real vanilla Crime Spree also uses job_id "crime_spree"; CSR runs the STANDARD gamemode, so a
-- truthy crime_spree:is_active() means we're in actual CS (not CSR) -> bail. (Mirrors csr_heist_active().)
function CSRGameManager:in_csr_heist()
	if not (managers and managers.job and managers.job.current_job_id) then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree.is_active and managers.crime_spree:is_active() then
		return false
	end
	return true
end

function CSRGameManager:rank()
	return self._state.rank or 0
end

function CSRGameManager:missions_completed()
	return self._state.missions_completed or 0
end

-- Career (cross-run) stat read. Values live in _meta.stats so they survive start_run().
-- Nil-safe -> default. Nothing writes here yet (the Logbook stats UI is scaffold-only;
-- the increment hooks are a later step). The UI reads through this so wiring the writes
-- later needs no UI change.
function CSRGameManager:career_stat(key, default)
	local v = self._meta.stats and self._meta.stats[key]
	return v or default or 0
end

-- Career stat writers (cross-run, _meta.stats). Each persists; called at most once per heist,
-- so the extra disk write is negligible. add_career_stat accumulates a running total;
-- record_career_max keeps an all-time peak.
function CSRGameManager:add_career_stat(key, amount)
	amount = tonumber(amount) or 0
	if amount == 0 then
		return
	end
	self._meta.stats = self._meta.stats or {}
	self._meta.stats[key] = (self._meta.stats[key] or 0) + amount
	self:save()
end

function CSRGameManager:record_career_max(key, value)
	value = tonumber(value) or 0
	self._meta.stats = self._meta.stats or {}
	if value > (self._meta.stats[key] or 0) then
		self._meta.stats[key] = value
		self:save()
	end
end

-- Per-wildcard career mission tally: counts heists completed while holding each wildcard, keyed by
-- item type in _meta.stats.wildcard_missions. Drives the Logbook "Favorite Wildcard" stat.
function CSRGameManager:record_wildcard_mission(wildcard_type)
	if not wildcard_type then
		return
	end
	self._meta.stats = self._meta.stats or {}
	local wm = self._meta.stats.wildcard_missions or {}
	wm[wildcard_type] = (wm[wildcard_type] or 0) + 1
	self._meta.stats.wildcard_missions = wm
	self:save()
end

-- Wildcard with the most completed heists, as (type, count); nil if none recorded. Ties broken by
-- type name for a stable pick.
function CSRGameManager:favorite_wildcard()
	local wm = self._meta.stats and self._meta.stats.wildcard_missions
	if not wm then
		return nil
	end
	local best_type, best_n
	for wtype, n in pairs(wm) do
		if not best_n or n > best_n or (n == best_n and wtype < best_type) then
			best_type, best_n = wtype, n
		end
	end
	return best_type, best_n
end

-- Per-heist combat tally (runtime only). Combat hooks (combat_stats.lua) increment it every hit
-- during a CSR heist; flush_heist_tally banks the totals into _meta.stats ONCE at heist end, so
-- we never touch disk per bullet. reset at heist start, flush at heist end (mission_lifecycle.lua).
function CSRGameManager:reset_heist_tally()
	self._heist_tally = { kills = 0, damage_dealt = 0, damage_taken = 0 }
end

function CSRGameManager:tally_combat(key, amount)
	local tally = self._heist_tally
	if not tally then
		return
	end
	tally[key] = (tally[key] or 0) + (tonumber(amount) or 0)
end

function CSRGameManager:flush_heist_tally()
	local tally = self._heist_tally
	if not tally then
		return
	end
	self._meta.stats = self._meta.stats or {}
	local s = self._meta.stats
	s.total_kills = (s.total_kills or 0) + (tally.kills or 0)
	s.total_damage_dealt = (s.total_damage_dealt or 0) + (tally.damage_dealt or 0)
	s.total_damage_taken = (s.total_damage_taken or 0) + (tally.damage_taken or 0)
	self:save()
	self._heist_tally = nil
end

function CSRGameManager:_default_difficulty()
	-- Remembered preference -> CS base difficulty -> hardcoded fallback.
	local cs_td = tweak_data and tweak_data.crime_spree
	local remembered = self._meta.settings and self._meta.settings.last_difficulty
	return remembered or (cs_td and cs_td.base_difficulty) or "overkill_145"
end

function CSRGameManager:difficulty()
	return self._state.difficulty or self:_default_difficulty()
end

function CSRGameManager:set_difficulty(diff)
	-- Also persists as the remembered preference for the next contract open. Rejects unknown ids.
	if type(diff) ~= "string" then
		return false
	end
	local diffs = tweak_data and tweak_data.difficulties
	if type(diffs) == "table" and not table.contains(diffs, diff) then
		log("[CSR] set_difficulty: unknown difficulty '" .. tostring(diff) .. "' — ignored")
		return false
	end
	self._state.difficulty = diff
	self._meta.settings = self._meta.settings or {}
	self._meta.settings.last_difficulty = diff
	self:save()
	log_csr("set_difficulty: " .. diff)
	return true
end

-- [Tier 1 split] end-of-run rewards + guest earnings + MP host-state mirror -> managers/game_manager/gm_rewards.lua

function CSRGameManager:mod_version()
	return (self._meta and self._meta.version) or "unknown"
end

-- =====================================================
-- Peer ID
-- =====================================================

function CSRGameManager:local_peer_id()
	-- Cached per session: the local peer id is stable for a session's lifetime, and
	-- this is queried per-hit by combat item hooks. Cache is cleared on session load
	-- (see CSR_ResetLocalPeerIdCache). Only a real resolved id is cached, never the
	-- fallback, so a pre-session call doesn't pin the cache to 1.
	if self._cached_local_peer_id then
		return self._cached_local_peer_id
	end
	local nm = managers and managers.network
	if nm and nm.session then
		local session = nm:session()
		if session and session.local_peer then
			local peer = session:local_peer()
			if peer and peer.id then
				local id = peer:id()
				self._cached_local_peer_id = id
				return id
			end
		end
	end
	return 1
end

-- [Tier 1 split] item inventory + peer counts + remote-peer mirror -> managers/game_manager/gm_inventory.lua

-- [Tier 1 split] item + modifier registration & enemy scaling -> managers/game_manager/gm_registry.lua

-- [Tier 1 split] stat helpers (items_of_kind / sum_stat_mul / combine_stat_hyperbolic) -> managers/game_manager/gm_stats.lua

-- [Tier 1 split] item callbacks (on_apply/remove/tick) + orphan/session maintenance -> managers/game_manager/gm_callbacks.lua

-- [Tier 1 split] item-pool roll + pending offers -> managers/game_manager/gm_offers.lua
-- [Tier 1 split] mission set & selection -> managers/game_manager/gm_missions.lua

-- =====================================================
-- Run lifecycle (alpha stubs)
-- =====================================================

function CSRGameManager:start_run()
	-- Always resets: no "continue" flow; a leftover rank from a stale save would break the flat-1-rank balance.
	if self._state.is_active then
		log_csr(
			"start_run: discarding a leftover active run (rank=" .. tostring(self._state.rank) .. ") and starting fresh"
		)
	end
	self._state.is_active = true
	self._state.failed = false
	-- No heist in flight yet; the loss-penalty flag arms on IngameWaitingForPlayersState.
	self._state.in_heist = false
	self._state.heist_grace_over = false
	self._state.rank = 0
	self._state.missions_completed = 0
	self._state.run_purchases = 0
	self._state.difficulty = self:_default_difficulty()
	self._state.seed = math.random(1, 2 ^ 30)
	-- Fresh spree re-rolls the modifier order with the current pool (picks up new add-ons).
	self._state.modifier_seq = nil
	-- New-modifier highlight: nothing flagged yet; seen-count 0 (not nil) so the first unlock flashes.
	self._state.modifier_hl_floor = nil
	self._state.modifier_hl_count = 0
	self._state.modifier_glow_pending = nil
	-- Wipe inventory so Items panel doesn't carry stacks from a prior run.
	self._state.peer_items = {}
	self._state.loot_rank_cash = 0
	self._state.coins_escalated = 0
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
	-- Wipe inventory so UI doesn't render stale stacks after the run ends.
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

-- Increments missions_completed (tracked separately from rank because rank-per-heist is tunable).
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

-- One BM purchase: bumps the per-spree count and folds it into the "Most Purchases" career peak.
-- record_career_max only writes when the new value beats the record, so calling per-buy is cheap.
function CSRGameManager:record_purchase()
	self._state.run_purchases = (self._state.run_purchases or 0) + 1
	self:record_career_max("most_purchases", self._state.run_purchases)
end

-- Peak non-scrap inventory size held during one run -> "Most Items Collected" career record.
-- Reads live holdings (no per-spree counter needed: record_career_max only grows the peak, and
-- removals/tier-ups can't lower an already-captured max). Excludes is_scrap so printer-spammed
-- scrap can't game the record. Called from add_item (the single collection chokepoint).
function CSRGameManager:record_items_peak(peer_id)
	local counts = self:player_items(peer_id)
	local by_type = self._registry.by_type
	local total = 0
	for item_type, n in pairs(counts) do
		if type(n) == "number" and n > 0 then
			local def = by_type[item_type]
			if not (def and def.is_scrap) then
				total = total + n
			end
		end
	end
	self:record_career_max("most_items", total)
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

-- Flag the run as failed (locked until Continue or End Spree). Does not end the run.
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

-- Clear the failed flag after the player pays the Continue cost.
function CSRGameManager:clear_failed()
	if not self._state.failed then
		return false
	end
	self._state.failed = false
	log_csr("clear_failed: failed state cleared (run continues)")
	self:save()
	return true
end

function CSRGameManager:get_continue_cost()
	-- Tied to the rank reached (a failed heist grants no rank, so this is the rank at failure).
	-- base 0 -> rank 0 costs nothing; 3x sits above the 2x/rank end-spree payout for a real sting.
	local per = self:constant("continue_cost_per_rank") or 0
	return per * (self._state.rank or 0)
end

-- =====================================================
-- Loss penalty: heist commit-on-start flag (host/SP)
-- =====================================================

-- Arm the in-flight flag on heist start. Returns a fresh token; a later token invalidates any
-- grace timer still pending from a previous attempt (restart / fast finish).
function CSRGameManager:begin_heist()
	self._state.in_heist = true
	self._state.heist_grace_over = false
	self._state.heist_token = (self._state.heist_token or 0) + 1
	self:save()
	return self._state.heist_token
end

-- Flip grace_over only if this is still the same heist that armed the timer (token match).
function CSRGameManager:mark_heist_grace_over(token)
	if not self._state.in_heist or self._state.heist_token ~= token then
		return false
	end
	self._state.heist_grace_over = true
	log_csr("mark_heist_grace_over: grace elapsed; interruption now counts as a loss")
	self:save()
	return true
end

-- Heist resolved cleanly (win or wipe) -> clear the flag and bump the token so the pending
-- grace timer no-ops.
function CSRGameManager:clear_in_heist()
	self._state.in_heist = false
	self._state.heist_grace_over = false
	self._state.heist_token = (self._state.heist_token or 0) + 1
	self:save()
end

function CSRGameManager:in_heist()
	return self._state.in_heist == true
end

function CSRGameManager:heist_grace_over()
	return self._state.heist_grace_over == true
end

function CSRGameManager:heist_grace_seconds()
	return self:constant("heist_grace_seconds") or 120
end

-- A heist in flight at last shutdown (crash / alt-F4 / quit-to-menu) is a loss if its grace had
-- elapsed; within grace it is forgiven. Either way the flag is cleared so it fires only once.
function CSRGameManager:_check_interrupted_heist()
	if not (self._state.is_active and self._state.in_heist) then
		return
	end
	if self._state.heist_grace_over then
		self._state.failed = true
		log_csr("_check_interrupted_heist: heist interrupted past grace -> run marked FAILED")
	else
		log_csr("_check_interrupted_heist: heist interrupted within grace -> forgiven")
	end
	self._state.in_heist = false
	self._state.heist_grace_over = false
	self:save()
end

-- Pending rewards captured from a leftover pre-install VANILLA Crime Spree (see end_spree_rewards.lua).
-- Stored in _meta so they survive a relaunch until the player claims them via the reward screen.
function CSRGameManager:set_pending_vanilla_rewards(rewards)
	self._meta.pending_vanilla_rewards = rewards
	self:save()
end

function CSRGameManager:pending_vanilla_rewards()
	return self._meta.pending_vanilla_rewards
end

function CSRGameManager:clear_pending_vanilla_rewards()
	self._meta.pending_vanilla_rewards = nil
	self:save()
end

function CSRGameManager:constant(name)
	return self._registry.constants and self._registry.constants[name]
end

function CSRGameManager:setting(key)
	return self._meta.settings[key]
end

-- defer_save: update the in-memory setting only (sound.lua etc. read it live) and skip the disk
-- write. Used by slider drag so we don't write csr_save.json every mouse-moved frame; the caller
-- commits one save on mouse_released.
function CSRGameManager:set_setting(key, value, defer_save)
	self._meta.settings[key] = value
	if key == "debug_mode" then
		self._debug = value == true
		_G.CSR_DEBUG = self._debug
	end
	if not defer_save then
		self:save()
	end
end

-- Preference: when true, CSR items must not restore the local player's HP (Turron exempt).
function CSRGameManager:item_heal_blocked()
	return self._meta.settings.block_item_heal == true
end

-- =====================================================
-- Debug logging
-- _debug_stat logs only on value change to avoid flooding per-frame stat bonuses.
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

-- Debug: grant one of every item to the peer (bypasses selection window).
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

-- Debug: force the lobby to a single card for level_id (e.g. "red2") and pre-select it.
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

-- Registers fn and returns an unsubscribe token. UI components MUST call it on teardown
-- or closures stack up for every lobby open.
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
		log("[CSR] ERROR save: json.encode failed -> " .. tostring(encoded))
		return false
	end
	local f = io.open(path, "w")
	if not f then
		log("[CSR] ERROR save: could not open for write -> " .. path)
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
		log("[CSR] ERROR load: json.decode failed -> " .. tostring(decoded))
		return false
	end
	if type(decoded.meta) == "table" then
		for k, v in pairs(decoded.meta) do
			self._meta[k] = v
		end
	end
	-- version tracks the RUNNING mod, not whatever wrote the save (the merge above would
	-- otherwise freeze a stale value forever). decoded.version is kept for the log/migration.
	self._meta.version = CSRGameManager.VERSION
	if type(decoded.state) == "table" then
		for k, v in pairs(decoded.state) do
			self._state[k] = v
		end
	end
	log_csr("load ok <- " .. path .. " (saved_version=" .. tostring(decoded.version) .. ")")
	return true
end

-- Static setting read before managers.csr exists (MenuManager:init runs before init_managers PostHook).
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
-- Attach to managers table (covers both MenuSetup and GameSetup via Setup:init_managers)
-- =====================================================

Hooks:PostHook(Setup, "init_managers", "CSR_AttachGameManager", function(self, managers)
	if managers.csr then
		return
	end
	managers.csr = CSRGameManager:new()
end)

-- Peer ids are reassigned when a new network session loads (join/host). Drop the
-- cached local peer id so the next query re-resolves it for the new session.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_ResetLocalPeerIdCache", function()
	if managers and managers.csr then
		managers.csr._cached_local_peer_id = nil
	end
end)
