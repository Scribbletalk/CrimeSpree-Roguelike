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
	-- Runtime-only; filled by mp_sync.lua, never saved.
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
	-- Commit any heist that was still in-flight at last shutdown (crash/quit).
	self:_check_interrupted_heist()
	-- Replay item + modifier registrations into the fresh _registry (idempotent).
	if _G.CSR and _G.CSR._apply_registrations then
		_G.CSR._apply_registrations(self)
	end
	if _G.CSR and _G.CSR._apply_modifier_registrations then
		_G.CSR._apply_modifier_registrations(self)
	end
	-- Tombstone removed-addon modifier slots; runs after replay so by_id is current.
	self:_prune_modifier_seq()
	-- Drop owned items whose addon is no longer registered; re-arms the lobby pick reminder.
	self:_drop_orphan_items()
	self:_prune_expired_sessions()
	-- Fresh _callbacks each init prevents stacking duplicate listeners across re-inits.
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
	-- MissionAssetsManager ran before our chain was set; rebuild it so the Assets tab isn't empty.
	if self:is_run_active() and managers.assets and managers.assets._setup_mission_assets then
		if managers.assets._global then
			managers.assets._global.assets = {}
		end
		managers.assets:_setup_mission_assets()
	end
	log_csr("CSRGameManager initialised; version=" .. tostring(self._meta.version))
end

-- Re-establish the crime_spree narrative chain each time managers init.
-- Without this, HUDMissionBriefing nil-crashes on heist launch (chain only set by select_mission on menu side).
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

-- Guest only: JobManager has no active job (job_id nil) because the guest never runs select_mission.
-- Mirrors the host's job wiring so briefing surfaces (HUDMissionBriefing, Assets tab) aren't empty.
-- Must run before IngameWaitingForPlayersState:at_enter builds the briefing. See csr_guest_temp_job_briefing_gap.md.
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

-- Gate for all gameplay hooks. True inside a CSR heist on host AND guest.
-- Bails if vanilla CS is active (same job_id, but CSR runs STANDARD gamemode). See csr_in_csr_heist_gameplay_gate.md.
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

-- Career (cross-run) stat read from _meta.stats; survives start_run(). Nil-safe -> default.
function CSRGameManager:career_stat(key, default)
	local v = self._meta.stats and self._meta.stats[key]
	return v or default or 0
end

-- Career stat writers: add_career_stat accumulates a total; record_career_max keeps an all-time peak.
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

-- Counts heists completed while holding each wildcard; drives the Logbook "Favorite Wildcard" stat.
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

-- Returns (type, count) for the most-used wildcard; nil if none recorded. Ties broken by name.
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

-- Runtime per-heist accumulator; banked into _meta.stats once at heist end (never written per-bullet).
-- reset at heist start, flush at heist end (mission_lifecycle.lua).
function CSRGameManager:reset_heist_tally()
	self._heist_tally = { kills = 0, specials_killed = 0, damage_dealt = 0, damage_taken = 0, max_hit = 0 }
end

function CSRGameManager:tally_combat(key, amount)
	local tally = self._heist_tally
	if not tally then
		return
	end
	tally[key] = (tally[key] or 0) + (tonumber(amount) or 0)
end

-- Per-heist peak tracker (not a running sum); flushed via record_career_max at heist end.
function CSRGameManager:tally_combat_max(key, amount)
	local tally = self._heist_tally
	if not tally then
		return
	end
	amount = tonumber(amount) or 0
	if amount > (tally[key] or 0) then
		tally[key] = amount
	end
end

function CSRGameManager:flush_heist_tally()
	local tally = self._heist_tally
	if not tally then
		return
	end
	self._meta.stats = self._meta.stats or {}
	local s = self._meta.stats
	s.total_kills = (s.total_kills or 0) + (tally.kills or 0)
	s.total_specials = (s.total_specials or 0) + (tally.specials_killed or 0)
	s.total_damage_dealt = (s.total_damage_dealt or 0) + (tally.damage_dealt or 0)
	s.total_damage_taken = (s.total_damage_taken or 0) + (tally.damage_taken or 0)
	self:save()
	self:record_career_max("most_damage_hit", tally.max_hit or 0)
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
	-- Also persists as the preference for the next contract open; rejects unknown ids.
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
	-- Cached (queried per-hit); cleared on session load (CSR_ResetLocalPeerIdCache).
	-- Only a real resolved id is cached so a pre-session call doesn't pin the cache to 1.
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
	-- Always resets; no "continue" flow (a stale rank would break balance).
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
	-- Logbook: a finished run permanently unlocks everything collected during it.
	if _G.CSR_Logbook and _G.CSR_Logbook.unlock_seen then
		_G.CSR_Logbook:unlock_seen()
	end
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

-- Bumps per-spree purchase count and updates the "Most Purchases" career peak.
function CSRGameManager:record_purchase()
	self._state.run_purchases = (self._state.run_purchases or 0) + 1
	self:record_career_max("most_purchases", self._state.run_purchases)
end

-- Updates "Most Items Collected" career peak from live non-scrap holdings.
-- Called from add_item; excludes is_scrap so printer fodder can't inflate the record.
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

-- Mark run failed (locked until Continue or End Spree); does not end the run.
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
	-- 3x per-rank sits above the 2x/rank end-spree payout, making continues a real sting.
	local per = self:constant("continue_cost_per_rank") or 0
	return per * (self._state.rank or 0)
end

-- =====================================================
-- Loss penalty: heist commit-on-start flag (host/SP)
-- =====================================================

-- Arm the in-flight flag. Returns a token; a later token invalidates any pending grace timer.
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

-- Heist resolved cleanly (win or wipe) -> clear flag and bump token so any pending grace timer no-ops.
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

-- On init: in_heist still set at last shutdown means the game died mid-heist (crash / alt-F4 /
-- quit-to-desktop). Always forgive it -- the game crashes too often to punish process death.
-- Deliberate quit-to-menu still counts as a loss, but that path resolves live in quit_penalty.lua
-- (clears in_heist before shutdown), so it never reaches here.
function CSRGameManager:_check_interrupted_heist()
	if not (self._state.is_active and self._state.in_heist) then
		return
	end
	log_csr("_check_interrupted_heist: heist interrupted (crash/alt-F4/quit-to-desktop) -> forgiven")
	self._state.in_heist = false
	self._state.heist_grace_over = false
	self:save()
end

-- Leftover vanilla CS rewards captured before CSR was installed; claimed on next reward screen.
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

-- defer_save: update in-memory only (skip disk write). Use for slider drag; caller saves on mouse_released.
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
-- Debug logging (_debug_stat logs only on value change to avoid per-frame flood)
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
		csr_log(string.format("[CSR][dbg] %s '%s' bonus -> %.4f", group, stat, value))
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

-- Returns an unsubscribe token; UI components MUST call it on teardown or closures stack per lobby open.
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
	-- Always stamp the RUNNING version (not the saved one) so stale values don't freeze.
	self._meta.version = CSRGameManager.VERSION
	if type(decoded.state) == "table" then
		for k, v in pairs(decoded.state) do
			self._state[k] = v
		end
	end
	log_csr("load ok <- " .. path .. " (saved_version=" .. tostring(decoded.version) .. ")")
	return true
end

-- Read a setting before managers.csr exists (MenuManager:init precedes init_managers PostHook).
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

-- Peer ids are reassigned per session; drop the cache so the next query re-resolves.
Hooks:Add("BaseNetworkSessionOnLoadComplete", "CSR_ResetLocalPeerIdCache", function()
	if managers and managers.csr then
		managers.csr._cached_local_peer_id = nil
	end
end)
