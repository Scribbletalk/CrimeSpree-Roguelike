-- CSRGameManager item + modifier registration & enemy scaling (Tier 1 split from game_manager.lua).
if not CSRGameManager then
	return
end

local function log_csr(msg)
	if _G.CSR_DEBUG then
		log("[CSR] " .. tostring(msg))
	end
end

-- Registration

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
	-- effect is optional (hooks may live entirely in the item file).
	local effect = def.effect
	if effect ~= nil then
		if type(effect) ~= "table" or not KNOWN_EFFECT_KINDS[effect.kind] then
			log_csr(
				"register_item: '" .. t .. "' bad effect kind '" .. tostring(effect and effect.kind) .. "' — skipped"
			)
			return false
		end
	end

	-- Optional addon attribution for MP mismatch warnings; non-string values are dropped silently.
	local addon = def.addon
	if addon ~= nil and type(addon) ~= "string" then
		log_csr("register_item: '" .. t .. "' ignoring non-string 'addon' field (got " .. type(addon) .. ")")
		addon = nil
	end

	-- Optional icon scale multiplier (1.0 = default); non-number values dropped silently.
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
		full_desc = def.full_desc,
		notes = def.notes,
		icon = def.icon,
		icon_scale = icon_scale,
		is_scrap = def.is_scrap == true or nil, -- excluded from the selection-window roll
		-- $-macro substitution in loc strings; single-sourced from the def's tuning constants.
		loc_macros = def.loc_macros,
		effect = effect,
		on_apply = def.on_apply,
		on_remove = def.on_remove,
		on_tick = def.on_tick,
		addon = addon,
	}
	table.insert(self._registry.items, entry)
	self._registry.by_type[t] = entry
	-- Index by effect kind for fast dispatcher iteration.
	if effect then
		local bucket = self._registry.by_kind[effect.kind]
		if not bucket then
			bucket = {}
			self._registry.by_kind[effect.kind] = bucket
		end
		bucket[#bucket + 1] = entry
	end
	-- Items may have both an effect kind and callbacks; index both.
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

-- Sorted unique addon names across all registrations (lowercased).
-- Reads raw _G.CSR lists so modifier-only addons are included; drives the MP join-gate.
function CSRGameManager:addon_signature()
	local seen = {}
	local function collect(list)
		if type(list) ~= "table" then
			return
		end
		for _, def in ipairs(list) do
			local a = def and def.addon
			if type(a) == "string" and a ~= "" then
				seen[a:lower()] = true
			end
		end
	end
	collect(_G.CSR and _G.CSR._registrations)
	collect(_G.CSR and _G.CSR._modifier_registrations)
	local out = {}
	for name in pairs(seen) do
		out[#out + 1] = name
	end
	table.sort(out)
	return out
end

-- Icon scale multiplier for one item type (1.0 default).
function CSRGameManager:item_icon_scale(item_type)
	local entry = item_type and self._registry.by_type[item_type]
	return (entry and entry.icon_scale) or 1
end

-- =====================================================
-- Modifiers (Crime Spree difficulty mods)
-- One loud + one stealth unlocks every 2 ranks; order derived deterministically from (seed, rank).
-- =====================================================

-- Park-Miller LCG: reproducible per-spree shuffle without touching math.random state.
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

-- Fisher-Yates shuffle; returns a new array (catalog is never mutated).
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

-- Stealth sequence: seeded-random family order, ascending tier within each family.
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
			loc_macros = tier.loc_macros,
		}
	end
	return out
end

-- Stable sort so the shuffle is independent of file load order.
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

-- Register a modifier; validates and dedupes by id. Missing class = listed in UI but not applied.
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
			loc_macros = def.loc_macros,
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

-- Read-only registry { loud, stealth_families, by_id }.
function CSRGameManager:modifier_catalog()
	return self._registry.modifiers
end

-- Build the per-spree modifier order from seed (Park-Miller LCG + Fisher-Yates).
-- Loud stored as ids (re-resolved through by_id; removed mods drop out), stealth as full entries.
-- Host and guest build the SAME sequence from the same seed; frozen on first use per spree.
function CSRGameManager:_build_modifier_seq(seed)
	seed = seed or 0
	local mods = self._registry.modifiers
	local loud = csr_shuffled(csr_sorted_by_id(mods.loud), seed * 2)
	-- +1 salt keeps loud/stealth orders independent.
	local stealth = csr_stealth_sequence(csr_sorted_by_id(mods.stealth_families), seed * 2 + 1)
	local loud_ids = {}
	for i = 1, #loud do
		loud_ids[i] = loud[i].id
	end
	return { loud = loud_ids, stealth = stealth }
end

function CSRGameManager:_ensure_modifier_seq()
	if self._state.modifier_seq then
		return
	end
	self._state.modifier_seq = self:_build_modifier_seq(self:seed())
	self:save()
end

-- Return the frozen sequence for the active run. While guesting, build transiently from the
-- host's seed (cached per host_seed, never persisted -- the guest's own seq is their own spree).
function CSRGameManager:_resolve_modifier_seq()
	if self:_is_guesting() then
		local hseed = self._state.mp_session and self._state.mp_session.host_seed or 0
		local cache = self._guest_modifier_seq
		if not (cache and cache.seed == hseed) then
			cache = { seed = hseed, seq = self:_build_modifier_seq(hseed) }
			self._guest_modifier_seq = cache
		end
		return cache.seq
	end
	self:_ensure_modifier_seq()
	return self._state.modifier_seq
end

-- Tombstone loud-seq slots whose modifier is no longer registered (add-on removed).
-- Slot becomes `false`; re-installing the add-on does NOT restore it until a fresh spree.
-- Stealth slots are left as-is (active_modifiers re-resolves them live).
function CSRGameManager:_prune_modifier_seq()
	local seq = self._state.modifier_seq
	if not (seq and type(seq.loud) == "table") then
		return
	end
	local by_id = self._registry.modifiers.by_id
	local changed = false
	for i = 1, #seq.loud do
		local id = seq.loud[i]
		if id and id ~= false and not by_id[id] then
			seq.loud[i] = false
			changed = true
		end
	end
	if changed then
		self:save()
	end
end

-- Re-synthesize a stealth slot from the LIVE registry by parsing "family_<tier>" from the stored id.
-- Mirrors loud's by_id re-resolution: reworked mechanics update in-progress sprees; removed families return nil.
function CSRGameManager:_resolve_stealth_entry(stored)
	if not stored or stored == false then
		return nil
	end
	local fam_id, tier_n = string.match(tostring(stored.id), "^(.-)_(%d+)$")
	local fam = fam_id and self._registry.modifiers.by_id[fam_id]
	local tier = fam and fam.tiers and fam.tiers[tonumber(tier_n)]
	if not tier then
		return nil
	end
	return {
		id = stored.id,
		loc = tier.loc,
		icon = fam.icon,
		class = fam.class,
		data = tier.data,
		loc_macros = tier.loc_macros,
	}
end

-- Frozen sequence sliced to rank (one new modifier per 2 ranks).
-- Both categories re-resolve payload from the live registry so reworks apply and removed mods drop out.
function CSRGameManager:active_modifiers(category)
	local rank = self:host_rank() or 0
	if rank <= 0 then
		return {}
	end
	local seq_table = self:_resolve_modifier_seq()
	local seq = seq_table and seq_table[category]
	if not seq then
		return {}
	end
	local n = math.min(math.ceil(rank / 2), #seq)
	local by_id = self._registry.modifiers.by_id
	local out = {}
	for i = 1, n do
		local entry = seq[i]
		if category == "loud" then
			entry = by_id[entry] -- re-resolve by id; removed mods return nil and drop out
		else
			entry = self:_resolve_stealth_entry(entry) -- re-synthesize from live registry
		end
		if entry then
			out[#out + 1] = entry
		end
	end
	return out
end

-- =====================================================
-- New-modifier highlight (Modifiers panel)
-- Entries above modifier_hl_floor are newly unlocked by the latest mission. Drives blue tint + siren.
-- =====================================================

function CSRGameManager:_modifier_unlock_count()
	local rank = self:host_rank() or 0
	if rank <= 0 then
		return 0
	end
	return math.ceil(rank / 2)
end

-- Update the floor when the unlock count grows; arms the glow for the panel siren.
-- Nil seen-count (old save) baselines silently; shrink (fresh spree) re-baselines without flash.
function CSRGameManager:refresh_modifier_highlight()
	local count = self:_modifier_unlock_count()
	local seen = self._state.modifier_hl_count
	if seen == nil then
		self._state.modifier_hl_count = count
		self:save()
		return
	end
	if count > seen then
		self._state.modifier_hl_floor = seen
		self._state.modifier_hl_count = count
		self._state.modifier_glow_pending = true
		self:save()
	elseif count < seen then
		self._state.modifier_hl_floor = nil
		self._state.modifier_hl_count = count
		self:save()
	end
end

-- Entries at sequence index > floor are newly unlocked; nil means nothing highlighted.
function CSRGameManager:modifier_highlight_floor()
	return self._state.modifier_hl_floor
end

-- One-shot: true once after new modifiers unlock, then cleared (drives the 3s siren).
function CSRGameManager:consume_modifier_glow()
	if self._state.modifier_glow_pending then
		self._state.modifier_glow_pending = nil
		self:save()
		return true
	end
	return false
end

-- Clear the floor after the panel's 5s fade; leaves hl_count intact so the next unlock re-arms it.
function CSRGameManager:clear_modifier_highlight()
	if self._state.modifier_hl_floor ~= nil then
		self._state.modifier_hl_floor = nil
		self:save()
	end
end

-- Per-rank enemy scaling. +5%/rank each (host-only for HP; each client applies damage independently).
local ENEMY_HEALTH_PCT_PER_RANK = 5
local ENEMY_DAMAGE_PCT_PER_RANK = 5

-- Restore pristine HEALTH_INIT before each apply (ModifierEnemyHealth multiplies in place, never reverts).
-- Runs on host AND client; each machine must inflate its own tweak_data to prevent tanky-vs-host-only.
-- See pd2_enemy_hp_must_scale_on_client_too.md.
function CSRGameManager:_restore_enemy_health_baseline()
	local ctd = tweak_data and tweak_data.character
	if not (ctd and ctd.enemy_list) then
		return 0, false
	end
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
	return restored, snapshotted
end

function CSRGameManager:apply_modifiers()
	if not managers or not managers.modifiers then
		return
	end
	-- Clear CSR category first for idempotency (hook may re-fire within a heist).
	if managers.modifiers._modifiers then
		managers.modifiers._modifiers.csr = nil
	end

	-- Client: apply HP + damage scaling locally (spawn/pager/group_ai mutations are host-only).
	-- Re-applied when host_rank arrives mid-load (HANDSHAKE_OK in mp_session.lua).
	if not Network:is_server() then
		local rank = self:host_rank() or 0
		if rank > 0 then
			if _G.ModifierEnemyHealth then
				self:_restore_enemy_health_baseline()
				managers.modifiers:add_modifier(
					_G.ModifierEnemyHealth:new({ health = rank * ENEMY_HEALTH_PCT_PER_RANK }),
					"csr"
				)
			end
			if _G.ModifierEnemyDamage then
				managers.modifiers:add_modifier(
					_G.ModifierEnemyDamage:new({ damage = rank * ENEMY_DAMAGE_PCT_PER_RANK }),
					"csr"
				)
			end
			self:debug_log(
				string.format(
					"client enemy scaling: rank=%d -> +%d%% HP, +%d%% DMG",
					rank,
					rank * ENEMY_HEALTH_PCT_PER_RANK,
					rank * ENEMY_DAMAGE_PCT_PER_RANK
				)
			)
		end
		return
	end

	-- Pager modifiers mutate alarm_pager in place (BaseModifier:destroy is a no-op); snapshot + restore to prevent compounding.
	local ap = tweak_data and tweak_data.player and tweak_data.player.alarm_pager
	if ap and type(ap.bluff_success_chance) == "table" then
		_G.CSR_PagerBaseline = _G.CSR_PagerBaseline
			or {
				bluff = clone(ap.bluff_success_chance),
				skill = clone(ap.bluff_success_chance_w_skill),
				call_duration = clone(ap.call_duration),
			}
		ap.bluff_success_chance = clone(_G.CSR_PagerBaseline.bluff)
		if _G.CSR_PagerBaseline.skill then
			ap.bluff_success_chance_w_skill = clone(_G.CSR_PagerBaseline.skill)
		end
		if _G.CSR_PagerBaseline.call_duration then
			ap.call_duration = clone(_G.CSR_PagerBaseline.call_duration)
		end
	end

	-- Restore pristine HEALTH_INIT before applying (ModifierEnemyDamage uses modify_value, no snapshot needed).
	local restored, snapshotted = self:_restore_enemy_health_baseline()
	self:debug_log(
		string.format(
			"enemy HP baseline %s, restored pristine HEALTH_INIT for %d enemies (no compounding)",
			snapshotted and "snapshotted" or "reused",
			restored
		)
	)

	-- group_ai fields (spawn limits, FBI_tank unit types, marshal amounts) also mutate in place; snapshot + restore.
	local gai = tweak_data and tweak_data.group_ai
	if gai then
		local ssl = gai.special_unit_spawn_limits
		if type(ssl) == "table" then
			_G.CSR_SpecialSpawnLimitsBaseline = _G.CSR_SpecialSpawnLimitsBaseline or clone(ssl)
			for key, value in pairs(_G.CSR_SpecialSpawnLimitsBaseline) do
				ssl[key] = value
			end
		end

		local fbi_tank = gai.unit_categories and gai.unit_categories.FBI_tank
		local unit_types = fbi_tank and fbi_tank.unit_types
		if type(unit_types) == "table" then
			_G.CSR_FBITankUnitTypesBaseline = _G.CSR_FBITankUnitTypesBaseline or clone(unit_types)
			-- Fresh clone per region so table.insert can't grow the baseline.
			for region, list in pairs(_G.CSR_FBITankUnitTypesBaseline) do
				unit_types[region] = clone(list)
			end
		end

		local marshal_squad = gai.enemy_spawn_groups and gai.enemy_spawn_groups.marshal_squad
		if marshal_squad and type(marshal_squad.amount) == "table" then
			_G.CSR_MarshalSquadAmountBaseline = _G.CSR_MarshalSquadAmountBaseline or clone(marshal_squad.amount)
			for i, value in pairs(_G.CSR_MarshalSquadAmountBaseline) do
				marshal_squad.amount[i] = value
			end
		end

		-- ModifierShieldPhalanx overwrites shield categories and never restores; snapshot for sprees without phalanx.
		local uc = gai.unit_categories
		if uc and uc.CS_shield and uc.FBI_shield then
			_G.CSR_ShieldCategoryBaseline = _G.CSR_ShieldCategoryBaseline
				or { CS_shield = clone(uc.CS_shield), FBI_shield = clone(uc.FBI_shield) }
			uc.CS_shield = clone(_G.CSR_ShieldCategoryBaseline.CS_shield)
			uc.FBI_shield = clone(_G.CSR_ShieldCategoryBaseline.FBI_shield)
		end
	end

	-- Aggregate active modifiers by engine class; same class from multiple slots gets merged.
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

	-- Per-rank HP/damage scaling injected directly (not passport-registered).
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

-- HP%/DMG% for the Modifiers panel header; mirrors apply_modifiers' constants.
function CSRGameManager:enemy_scaling()
	local rank = self:host_rank() or 0
	return rank * ENEMY_HEALTH_PCT_PER_RANK, rank * ENEMY_DAMAGE_PCT_PER_RANK
end
