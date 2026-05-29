-- CSRGameManager — single source of truth for Crime Spree Roguelike state.
-- Hierarchical singleton: _meta (persists across runs), _state (active run), _registry (static content).

CSRGameManager = CSRGameManager or class()
CSRGameManager.VERSION = "U1-alpha"

local SAVE_FILE = "csr_save.json"
local LEGACY_SETTINGS_FILE = "crime_spree_roguelike.json"
local LEGACY_MP_SESSIONS_FILE = "csr_mp_sessions.json"

-- Per-host guest inventory is pruned after this many days (items only; bucket B cash has no TTL).
local MP_SESSION_TTL_DAYS = 7

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
		-- A failed run stays active but locked until the player pays Continue or ends the run.
		failed = false,
		-- Internal difficulty id (e.g. "overkill_145"); nil until start_run seeds it.
		difficulty = nil,
		seed = nil,
		mission_set = {}, -- array of mission ids currently offered in the lobby
		current_mission = nil, -- id of the mission the player picked to play next
		peer_items = {},
		-- Accumulated looted cash toward the next loot-rank; remainder carries across heists.
		loot_rank_cash = 0,
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
			-- Continue cost = continue_cost_base + continue_cost_per_mission * missions_completed
			continue_cost_base = 10,
			continue_cost_per_mission = 10,
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
	-- Replay registrations into the fresh _registry every init (idempotent, never drains).
	if _G.CSR and _G.CSR._apply_registrations then
		_G.CSR._apply_registrations(self)
	end
	if _G.CSR and _G.CSR._apply_modifier_registrations then
		_G.CSR._apply_modifier_registrations(self)
	end
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

function CSRGameManager:rank()
	return self._state.rank or 0
end

function CSRGameManager:missions_completed()
	return self._state.missions_completed or 0
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

-- =====================================================
-- End-of-run rewards (projection + award source of truth)
-- =====================================================

-- Per-rank cash multiplier by CSR difficulty index (1=normal..7=death_sentence). Mirrors moneytweakdata.
local REWARD_PAYOUT_MULT = { 1, 2, 5, 10, 11, 13, 14 }

-- tweak_data.difficulties leads with "easy" (index 1), so CSR index = difficulty_to_index - 1.
function CSRGameManager:reward_difficulty_index()
	local di = (tweak_data and tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(self:difficulty()))
		or 2
	return math.max(1, math.min(7, di - 1))
end

-- Reward components for `rank` ranks at CSR difficulty index `idx`.
-- Shared by projected_rewards (bucket A) and accrue_mp_earnings (bucket B).
function CSRGameManager:_rewards_for(rank, idx)
	rank = tonumber(rank) or 0
	local XP_MULT = { 0, 2, 5, 10, 11.5, 13, 14 }

	local cash = 200000 * (REWARD_PAYOUT_MULT[idx] or 1) * rank
	local xp = 12000 * (1 + (XP_MULT[idx] or 0)) * rank
	-- pcall-isolated so a menu projection never errors.
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
	-- Bucket A: own rank/difficulty (guest bucket B is summed in separately at End Spree).
	return self:_rewards_for(self:rank(), self:reward_difficulty_index())
end

-- CSR difficulty index for the host's synced difficulty (bucket B). Falls back to own when not guesting.
function CSRGameManager:host_reward_difficulty_index()
	local hd = self:mp_host_difficulty()
	if type(hd) ~= "string" then
		return self:reward_difficulty_index()
	end
	local di = (tweak_data and tweak_data.difficulty_to_index and tweak_data:difficulty_to_index(hd)) or 2
	return math.max(1, math.min(7, di - 1))
end

-- =====================================================
-- Guest earnings bucket B
-- =====================================================

-- Bank one guest heist's reward into _meta.mp_earnings at host difficulty. Called only from the guest fork.
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

-- Guest analogue of accrue_loot_rank: converts looted cash to bucket B ranks at host difficulty.
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

-- Read-only copy of bucket B; always a full table (zeros when empty).
function CSRGameManager:mp_earnings()
	local b = self._meta.mp_earnings or {}
	return {
		cash = b.cash or 0,
		experience = b.experience or 0,
		continental_coins = b.continental_coins or 0,
		loot_drop = b.loot_drop or 0,
	}
end

-- True when bucket B has claimable earnings (lets a rank-0 guest still cash out at End Spree).
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

-- True while the local player is a client in an announced CSR run.
function CSRGameManager:is_guesting()
	return self:_is_guesting()
end

-- Cash value of one rank at the current earning difficulty.
-- Returns host difficulty while guesting so shared loot converts at the same rate as the host.
function CSRGameManager:reward_per_rank_cash()
	local idx = self:_is_guesting() and self:host_reward_difficulty_index() or self:reward_difficulty_index()
	return 200000 * (REWARD_PAYOUT_MULT[idx] or 1)
end

-- Feed completed-heist loot into the rank accumulator; every full reward_per_rank_cash() grants +1 rank.
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
	-- Returns host's synced rank while guesting (for enemy scaling + item quota); own rank otherwise.
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

-- Store host's synced rank/difficulty/seed from the MP host-state push (client only).
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

-- Host's completed-heist count while guesting (nil on host/SP). Gated to prevent stale value leaking after leaving.
function CSRGameManager:mp_host_missions_completed()
	if not self:_is_guesting() then
		return nil
	end
	local mp = self._state.mp_session
	return mp and mp.host_missions or nil
end

-- Drop synced host state on leave/between heists; guest falls back to own _state during the load window.
function CSRGameManager:clear_mp_host_state()
	local mp = self._state.mp_session
	if not mp then
		return
	end
	mp.host_rank = nil
	mp.host_difficulty = nil
	mp.host_seed = nil
	mp.host_missions = nil
	-- Also clear so the guest re-pulls a fresh mission set on the next lobby open.
	mp.host_mission_set = nil
end

-- Host difficulty while guesting (nil otherwise). Gated to prevent stale value leaking into own-host lobby.
function CSRGameManager:mp_host_difficulty()
	if not self:_is_guesting() then
		return nil
	end
	local mp = self._state.mp_session
	return mp and mp.host_difficulty or nil
end

-- Guards the one-time token seed grant per host run; lives in the session record so re-joining the same host doesn't re-seed.
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
	self:_guest_session_entry(true)
	local sess = self._meta.mp_sessions and self._meta.mp_sessions[key]
	if sess then
		sess.tokens_seeded = true
		self:save()
	end
end

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

local function get_or_create_peer_entry(state, peer_id)
	local entry = state.peer_items[peer_id]
	if not entry then
		entry = { counts = {} }
		state.peer_items[peer_id] = entry
	end
	-- Migrate legacy { items = [...] } save shape to { counts = { [type]=n } }.
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
	-- Tracks first-acquire order for the Items panel sort; self-heals from counts when absent.
	entry.order = entry.order or {}
	return entry
end

-- pcall-guarded os.time(); returning 0 on error makes TTL pruning never fire (safe default).
function CSRGameManager:_now()
	local ok, t = pcall(os.time)
	return (ok and type(t) == "number") and t or 0
end

-- True when acting as a client in an announced CSR run (host_seed known).
function CSRGameManager:_is_guesting()
	local mp = self._state.mp_session
	local net = _G.CSR_MP
	if not (net and net.is_client and net.is_client()) then
		return false
	end
	return mp ~= nil and mp.host_seed ~= nil
end

-- Key for the active guest session store ("h<seed>"); nil when not guesting.
function CSRGameManager:_guest_session_key()
	local mp = self._state.mp_session
	local seed = mp and mp.host_seed
	if seed == nil then
		return nil
	end
	return "h" .. tostring(seed)
end

-- Per-host guest session entry (same shape as peer_items entry). Lazily created when create=true.
-- Lives in _meta so it survives the guest's own run transitions; pruned only by age.
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

-- Own-side inventory entry: guest session store while guesting, else _state.peer_items.
-- create=true lazily allocates; false returns nil for unknown peers.
function CSRGameManager:_own_entry(peer_id, create)
	if peer_id == self:local_peer_id() and self:_is_guesting() then
		return self:_guest_session_entry(create)
	end
	if create then
		return get_or_create_peer_entry(self._state, peer_id)
	end
	return self._state.peer_items[peer_id]
end

-- Counts table for any peer: remote synced items win over own-side. Returns nil when no record.
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

-- Raw acquisition-order array for a peer (remote synced wins over own-side; may be stale/missing).
function CSRGameManager:_peer_order(peer_id)
	local remote = self._remote_peer_items and self._remote_peer_items[peer_id]
	if remote then
		return remote.order
	end
	local entry = self:_own_entry(peer_id, false)
	return entry and entry.order
end

-- Item types in acquisition order; self-heals against live counts (handles legacy saves and remote peers without order).
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

-- Total stacks across all types (used by the lobby "unselected items" reminder).
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

-- Items obtained outside rank picks (shop purchases). These don't count toward the rank quota.
-- Scrapper/copier is net-zero on total_item_count, so rank_item_count stays correct through transforms.
function CSRGameManager:shop_item_count(peer_id)
	local entry = self:_own_entry(peer_id or self:local_peer_id(), false)
	return (entry and entry.shop_item_count) or 0
end

-- Stacks from rank picks = total minus shop purchases (what the lobby reminder compares against host rank).
function CSRGameManager:rank_item_count(peer_id)
	peer_id = peer_id or self:local_peer_id()
	return math.max(0, self:total_item_count(peer_id) - self:shop_item_count(peer_id))
end

-- =====================================================
-- Remote peers' synced inventories (runtime-only, never saved)
-- =====================================================

-- Store a remote peer's synced counts + name. Does not fire callbacks or save (display-only).
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

-- Peer ids we hold synced inventories for (includes the SP debug fake peer).
function CSRGameManager:remote_peer_ids()
	local ids = {}
	if self._remote_peer_items then
		for pid in pairs(self._remote_peer_items) do
			ids[#ids + 1] = pid
		end
	end
	return ids
end

-- Convenience: owned stacks for the local player (saves hooks from calling local_peer_id() explicitly).
function CSRGameManager:owned(item_type)
	return self:item_count(self:local_peer_id(), item_type)
end

-- Mutable per-peer state record (counts + shop wallet/lineup). Lazy-created.
-- Returns the guest session entry while guesting so tokens/offers never touch the paused run.
function CSRGameManager:peer_entry(peer_id)
	return self:_own_entry(peer_id or self:local_peer_id(), true)
end

function CSRGameManager:add_item(peer_id, item_type)
	if not self._registry.by_type[item_type] then
		log("[CSR] add_item: unknown type '" .. tostring(item_type) .. "' — ignored")
		return false
	end
	local entry = self:_own_entry(peer_id, true)
	local was = entry.counts[item_type] or 0
	entry.counts[item_type] = was + 1
	-- First copy: append to acquisition order. Duplicates only bump the count.
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
		-- Last copy gone: remove from order so a future re-acquire counts as new.
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

local KNOWN_RARITIES = {
	common = true,
	uncommon = true,
	rare = true,
	contraband = true,
	wildcard = true,
}
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
		log("[CSR] register_item: definition not a table — skipped")
		return false
	end
	local t = def.type
	if type(t) ~= "string" or t == "" then
		log("[CSR] register_item: missing/invalid 'type' — skipped")
		return false
	end
	if self._registry.by_type[t] then
		log("[CSR] register_item: duplicate type '" .. t .. "' — skipped")
		return false
	end
	if not KNOWN_RARITIES[def.rarity] then
		log("[CSR] register_item: '" .. t .. "' unknown rarity '" .. tostring(def.rarity) .. "' — skipped")
		return false
	end
	-- effect is optional: declarative kind, callback escape-hatch, or passport-only (hooks in the item file).
	local effect = def.effect
	if effect ~= nil then
		if type(effect) ~= "table" or not KNOWN_EFFECT_KINDS[effect.kind] then
			log_csr(
				"register_item: '" .. t .. "' bad effect kind '" .. tostring(effect and effect.kind) .. "' — skipped"
			)
			return false
		end
	end

	-- Optional addon attribution for MP mismatch warnings. Non-string values are dropped but don't block registration.
	local addon = def.addon
	if addon ~= nil and type(addon) ~= "string" then
		log_csr("register_item: '" .. t .. "' ignoring non-string 'addon' field (got " .. type(addon) .. ")")
		addon = nil
	end

	-- Optional icon scale multiplier (1.0 = default). Non-number values are dropped but don't block registration.
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
		-- Logbook detail text (optional).
		full_desc = def.full_desc,
		notes = def.notes,
		icon = def.icon,
		icon_scale = icon_scale,
		-- Scrapper output; excluded from the selection-window roll.
		is_scrap = def.is_scrap == true or nil,
		effect = effect,
		on_apply = def.on_apply,
		on_remove = def.on_remove,
		on_tick = def.on_tick,
		addon = addon,
	}
	table.insert(self._registry.items, entry)
	self._registry.by_type[t] = entry
	-- Index by kind so dispatchers iterate only the relevant items (rebuilt on each init).
	if effect then
		local bucket = self._registry.by_kind[effect.kind]
		if not bucket then
			bucket = {}
			self._registry.by_kind[effect.kind] = bucket
		end
		bucket[#bucket + 1] = entry
	end
	-- An item may have both an effect kind and callbacks; index them independently.
	if entry.on_apply or entry.on_remove or entry.on_tick then
		self._registry.callback_items[#self._registry.callback_items + 1] = entry
	end
	local from = addon and (" from '" .. addon .. "'") or ""
	log_csr("register_item: '" .. t .. "' (" .. def.rarity .. ")" .. from)
	return true
end

function CSRGameManager:registered_items()
	return self._registry.items
end

-- Icon scale multiplier for one item type (1.0 default). Used by all three icon-drawing surfaces.
function CSRGameManager:item_icon_scale(item_type)
	local entry = item_type and self._registry.by_type[item_type]
	return (entry and entry.icon_scale) or 1
end

-- =====================================================
-- Modifiers (Crime Spree difficulty mods)
-- Each rank adds 1 loud + 1 stealth modifier, derived deterministically from (seed, rank).
-- Registry-driven: each modifier self-registers from lua/modifiers/<id>.lua.

-- Park-Miller LCG: reproducible shuffle from the run seed without touching math.random state.
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

-- Deterministic Fisher-Yates shuffle; returns a new array (catalog is never mutated).
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

-- Deterministic stealth sequence: seeded-random family pick + ascending tier order.
-- Returns the full sequence; active_modifiers slices the first n entries.
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

-- Stable id-sorted copy so the shuffle is independent of file load order.
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

-- Register one modifier from its passport; validates, dedupes by id, replayed on each init.
-- category "loud" or "stealth"; class/data optional (missing class is listed in UI but not applied).
function CSRGameManager:register_modifier(def)
	if type(def) ~= "table" then
		log("[CSR] register_modifier: definition not a table — skipped")
		return false
	end
	local id = def.id
	if type(id) ~= "string" or id == "" then
		log("[CSR] register_modifier: missing/invalid 'id' — skipped")
		return false
	end
	local mods = self._registry.modifiers
	if mods.by_id[id] then
		log("[CSR] register_modifier: duplicate id '" .. id .. "' — skipped")
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
		log("[CSR] register_modifier: '" .. id .. "' unknown category '" .. tostring(def.category) .. "' — skipped")
		return false
	end
	log_csr("register_modifier: '" .. id .. "' (" .. tostring(def.category) .. ")")
	return true
end

-- Read-only modifier registry { loud = {...}, stealth_families = {...}, by_id }.
function CSRGameManager:modifier_catalog()
	return self._registry.modifiers
end

-- Active modifiers for the current run, derived from (host_rank, seed). Cumulative: rank R = first R entries.
function CSRGameManager:active_modifiers(category)
	local rank = self:host_rank() or 0
	if rank <= 0 then
		return {}
	end
	local seed = self:seed() or 0
	local mods = self._registry.modifiers
	local seq
	if category == "stealth" then
		seq = csr_stealth_sequence(csr_sorted_by_id(mods.stealth_families), seed * 2 + 1) -- +1 salt keeps loud/stealth orders independent
	else
		seq = csr_shuffled(csr_sorted_by_id(mods.loud), seed * 2)
	end
	local n = math.min(math.ceil(rank / 2), #seq)
	local out = {}
	for i = 1, n do
		out[i] = seq[i]
	end
	return out
end

-- Per-rank enemy scaling. +5%/rank each (host-only for HP; each client applies damage independently).
local ENEMY_HEALTH_PCT_PER_RANK = 5
local ENEMY_DAMAGE_PCT_PER_RANK = 5

function CSRGameManager:apply_modifiers()
	if not managers or not managers.modifiers then
		return
	end
	-- Clear our category first for idempotency (managers.modifiers is rebuilt per heist, but the hook may re-fire).
	if managers.modifiers._modifiers then
		managers.modifiers._modifiers.csr = nil
	end

	-- Client: only enemy damage modifier runs locally (PlayerDamage is per-peer; HP scaling is host-only).
	-- Re-applied when host_rank arrives mid-load (see HANDSHAKE_OK in mp_session.lua).
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

	-- ModifierLessPagers mutates alarm_pager in place and never reverts (BaseModifier:destroy is a no-op).
	-- Snapshot pristine arrays once; restore before every apply to prevent compounding.
	local ap = tweak_data and tweak_data.player and tweak_data.player.alarm_pager
	if ap and type(ap.bluff_success_chance) == "table" then
		_G.CSR_PagerBaseline = _G.CSR_PagerBaseline
			or { bluff = clone(ap.bluff_success_chance), skill = clone(ap.bluff_success_chance_w_skill) }
		ap.bluff_success_chance = clone(_G.CSR_PagerBaseline.bluff)
		if _G.CSR_PagerBaseline.skill then
			ap.bluff_success_chance_w_skill = clone(_G.CSR_PagerBaseline.skill)
		end
	end

	-- Same trap for ModifierEnemyHealth: multiplies HEALTH_INIT in place, never reverts.
	-- Restore from snapshot before every apply. (ModifierEnemyDamage uses modify_value, no mutation needed.)
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

	-- Aggregate active loud + stealth modifiers by engine class for vanilla stacking.
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

	-- Per-rank HP/damage scaling is continuous so it's injected directly, not passport-registered.
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
			log("[CSR] apply_modifiers: class '" .. tostring(class) .. "' not loaded -- effect skipped")
		end
	end
	log_csr("apply_modifiers: applied " .. applied .. " modifier(s)")
end

-- Enemy HP% and DMG% scaling for the Modifiers panel header (single source of truth with apply_modifiers).
function CSRGameManager:enemy_scaling()
	local rank = self:host_rank() or 0
	return rank * ENEMY_HEALTH_PCT_PER_RANK, rank * ENEMY_DAMAGE_PCT_PER_RANK
end

-- =====================================================
-- Effect dispatch helpers (local-player-scoped; return neutral outside a run)
-- =====================================================

local EMPTY_ITEM_LIST = {}

-- O(1) lookup of entries by effect.kind (empty list when none).
function CSRGameManager:items_of_kind(kind)
	return self._registry.by_kind[kind] or EMPTY_ITEM_LIST
end

-- Additive bonus for a stat across all owned stat_mul items: sum(per_stack * stacks). 0 outside a run.
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

-- Diminishing-returns bonus: each item b=cap*(1-1/(1+k*n)); combined as 1-prod(1-b). 0 outside a run.
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
-- Callback escape-hatch (on_apply / on_remove / on_tick)
-- Fires with exactly-once semantics; all callbacks are pcall-isolated.
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
		log("[CSR] " .. which .. " error for '" .. tostring(type_id) .. "': " .. tostring(err))
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

-- Drop owned counts for item types no longer in the registry (addon removed/renamed).
-- Dropping a rank-pick orphan re-arms the lobby pick reminder.
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
	for _, entry in pairs(self._state.peer_items) do
		sweep(entry.counts)
	end
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

-- Prune guest session stores older than MP_SESSION_TTL_DAYS (items-only TTL; bucket B cash is untouched).
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

-- Selection-window roll weights: contraband is 0 (never offered; still reachable via shop/scrapper).
local RARITY_WEIGHTS = {
	common = 60,
	uncommon = 24,
	rare = 4,
	wildcard = 12,
}
local MAX_WILDCARDS_PER_WINDOW = 1
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
	-- Float epsilon: r > cum; take the last key seen.
	local last
	for k in pairs(weights) do
		last = k
	end
	return last
end

-- Roll count distinct items from the weighted pool. No duplicates within a window.
-- Shallow-copies buckets so the registry is never mutated.
function CSRGameManager:roll_item_pool(peer_id, count)
	count = math.max(1, tonumber(count) or 3)

	local buckets = {}
	for _, item in ipairs(self._registry.items) do
		local r = item.rarity
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
-- Each rank materialises a stored offer (frozen 3-card list) before the window opens.
-- Re-opening shows the same cards; only a confirmed pick pops it.
-- =====================================================

-- Ensure the peer has at least n pre-rolled stored offers. Idempotent (no-op if already >= n).
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
			break -- registry too thin; UI shows "NO ITEMS" via peek_offer returning nil
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

-- Read the first stored offer (resolved to live defs; filtered if addon vanished). Does NOT pop.
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

-- Pop the first stored offer (called after add_item; discards all unchosen cards with it).
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
-- =====================================================

-- 3-tier mission list from tweak_data with DLC filter. Cached because the reroll animation queries it per-frame.
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

-- Rank for completing a mission: short(add≤5)=1, medium(≤7)=2, long=3.
-- Uses the same thresholds as CrimeSpreeMissionButton so rank matches the clock icon.
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

-- Rank for the just-played heist. Resolves from Global.game_settings.level_id because
-- current_mission() is already cleared by the time the end screen builds.
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

-- Single random mission for the card spin animation flavor text.
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

-- Roll a fresh set of mission ids (dense; no nil holes) and clear the current pick.
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
	if _G.CSR_MP and _G.CSR_MP.broadcast_mission_set then
		_G.CSR_MP.broadcast_mission_set()
	end
	return ids
end

function CSRGameManager:reroll_mission_set()
	return self:generate_mission_set()
end

-- Ensure a non-empty set exists before the lobby renders (old saves + run that starts without rolling).
-- Guests skip: they mirror the host's set via MISSION_SET sync.
function CSRGameManager:ensure_mission_set()
	if self:_is_guesting() then
		return
	end
	local set = self._state.mission_set
	if type(set) ~= "table" or #set == 0 then
		self:generate_mission_set()
	end
end

-- Resolve stored ids to full tweak_data mission tables. Unresolvable slots return nil (panel skips them).
-- While guesting, mirrors the host's synced set.
function CSRGameManager:mission_set()
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

function CSRGameManager:mission_set_ids()
	return self._state.mission_set or {}
end
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

	-- Engine wiring: mirrors vanilla _setup_temporary_job + activate_temporary_job + _setup_global_from_mission_id.
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
	-- Sync level selection to guests immediately so they load the same level on Start.
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
	-- Save immediately; the in-game manager is a fresh init that reads from disk.
	self:save()
end

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
	self._state.rank = 0
	self._state.missions_completed = 0
	self._state.difficulty = self:_default_difficulty()
	self._state.seed = math.random(1, 2 ^ 30)
	-- Wipe inventory so Items panel doesn't carry stacks from a prior run.
	self._state.peer_items = {}
	self._state.loot_rank_cash = 0
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
		_G.CSR_DEBUG = self._debug
	end
	self:save()
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
