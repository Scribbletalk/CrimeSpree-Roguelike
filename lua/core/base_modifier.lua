-- CSRBaseModifier - fully standalone base class for all mod modifiers
-- Does NOT inherit from any vanilla class
-- Implements the minimal interface expected by CrimeSpreeManager:
--   :new(data)            → instance creation (provided by PD2 class())
--   :init(data)           → data initialization
--   :modify_value(id, value) → hook for modifying game values
--   :destroy()            → cleanup on removal

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSRBaseModifier = CSRBaseModifier or class()

CSRBaseModifier.desc_id = "csr_base_modifier"
CSRBaseModifier.icon = ""

function CSRBaseModifier:init(data)
	self._data = data
end

function CSRBaseModifier:modify_value(id, value)
	return value
end

function CSRBaseModifier:value()
	if self._data and self._data[self.default_value] then
		local val = self._data[self.default_value]
		if type(val) == "table" then
			return val[1] or 0
		end
		return val
	end
	return 0
end

function CSRBaseModifier:destroy() end

-- === ITEM BALANCE CONSTANTS ===
-- Change values here — logbook descriptions and gameplay will update automatically.
-- All item/modifier code MUST read from this table instead of hardcoding numbers.
_G.CSR_ItemConstants = {
	-- === PASSIVE PROGRESSION (per CS level) ===
	passive_hp_per_level = 0.002, -- +0.2% Max HP per level
	passive_armor_per_level = 0.002, -- +0.2% Max Armor per level
	passive_damage_per_level = 0.0004, -- +0.04% All Damage per level
	passive_regen_flat_per_level = 0.02, -- +0.02 display HP regen per level per tick (flat)
	passive_regen_interval = 5.0, -- Regen tick interval (seconds)
	bullseye_bonus_per_level = 0.01, -- +1% Bullseye armor regen per level

	-- === BOT PASSIVE PROGRESSION (per CS level) ===
	bot_damage_per_level = 0.01, -- +1% weapon damage per level
	bot_hp_per_level = 0.0004, -- +0.04% max HP per level
	bot_fire_rate_per_level = 0.005, -- +0.5% fire rate per level (lower recoil delay)
	bot_reload_per_level = 0.005, -- +0.5% reload speed per level
	bot_fire_reload_max_bonus = 0.50, -- cap at 50% (reached at level 100)

	-- === PRINTER MECHANIC ===
	printer_damage_taken_per_use = 0.004, -- +0.4% incoming damage per printer use (matches enemy dmg per rank)

	-- === COMMON ITEMS ===

	-- DOG TAGS
	dog_tags_hp_bonus = 0.10, -- +10% Max HP per stack

	-- DUCT TAPE
	duct_tape_speed_bonus = 0.10, -- +10% Interaction Speed per stack (excludes reviving/uncuffing)

	-- ESCAPE PLAN
	escape_plan_cap = 0.50, -- Movement speed cap: 50%
	escape_plan_k_num = 3, -- Hyperbolic formula: k = k_num / k_den
	escape_plan_k_den = 47, -- First stack ≈ 3%

	-- WORN BAND-AID
	worn_bandaid_first_pct = 0.02, -- 2% of max HP at 1 stack
	worn_bandaid_max_pct = 0.20, -- Hyperbolic asymptote: 20% of max HP
	worn_bandaid_interval = 5, -- Regen interval (seconds)

	-- CUP OF JOE
	cup_of_joe_per_stack = 0.10, -- +10% max stamina per stack, additive linear (1 stack: +10%, 2: +20%, etc.)

	-- PIECE OF REBAR
	rebar_base_bonus = 0.15, -- +15% damage on first hit (1 stack)
	rebar_extra_bonus = 0.10, -- +10% per each additional stack

	-- HALF-A-GLASS
	half_a_glass_max_ammo_first = 0.04, -- +4% max ammo for first stack
	half_a_glass_max_ammo_extra = 0.02, -- +2% per additional stack
	half_a_glass_refill = 0.15, -- 15% of new max ammo refilled on pickup

	-- === UNCOMMON ITEMS ===

	-- EVIDENCE ROUNDS / AP ROUNDS
	ap_rounds_damage_bonus = 0.10, -- +10% to ALL damage per stack

	-- FALCOGINI KEYS
	car_keys_k_den = 32, -- Hyperbolic formula: k = 1/k_den, first stack ≈ 3%

	-- WOLF'S TOOLBOX
	wolfs_toolbox_normal_base = 0.2, -- -0.2s base from drill/saw per normal kill
	wolfs_toolbox_normal_extra = 0.1, -- -0.1s per additional stack
	wolfs_toolbox_special_base = 1.0, -- -1.0s base per special kill
	wolfs_toolbox_special_extra = 0.5, -- -0.5s per additional stack

	-- OVERKILL RUSH - Kill Streak: Fire Rate + Reload Speed
	overkill_rush_first_bonus = 0.02, -- 2% for the first kill in the streak (per item stack)
	overkill_rush_extra_bonus = 0.01, -- +1% per each subsequent kill (per item stack)
	overkill_rush_max_stacks = 4, -- max kill streak stacks
	overkill_rush_duration = 4.0, -- seconds before streak resets

	-- PINK SLIP - Kill to Heal
	pink_slip_base_percent = 0.01, -- 1% of max HP (first stack only)
	pink_slip_base_flat = 4, -- +flat HP on first stack
	pink_slip_extra_heal = 6, -- +flat HP per additional stack

	-- === RARE ITEMS ===

	-- BONNIE'S LUCKY CHIP
	bonnie_chip_chance = 0.10, -- 10% instakill chance per stack (independent rolls)
	bonnie_chip_cooldown = 1.5, -- Instakill cooldown (seconds)

	-- PLUSH SHARK
	plush_shark_invuln_base = 10, -- Base invulnerability duration (seconds)
	plush_shark_invuln_extra = 20, -- +N seconds per additional stack
	plush_shark_heal_pct = 1.00, -- 100% HP restored on activation
	plush_shark_restore_armor = true, -- Also restore armor to full on activation

	-- JIRO'S LAST WISH
	jiro_melee_bonus = 0.5, -- +50% melee damage per stack

	-- PICKLE JAR
	pickle_jar_k = 0.05, -- Hyperbolic absorption: 1-1/(1+k×enemies×stacks)
	pickle_jar_radius = 1500, -- Enemy scan radius (cm, ~15m)
	pickle_jar_interval = 0.5, -- Rescan interval (seconds)

	-- DEAREST POSSESSION
	dearest_armor_cap = 0.5, -- Armor cap: 50% of base MaxArmor per stack
	dearest_decay_rate = 0.01666, -- Linear: ~1.666%/sec of base MaxArmor. Combined with the 5s tick interval in dearestpossession.lua, that's 8.33% per tick. 1 stack cap (50% of base) drains in 6 ticks = 30s; each extra stack adds another 30s to the full-drain time.

	-- === CONTRABAND ITEMS ===

	-- DOZER GUIDE
	dozer_armor_bonus = 0.50, -- +50% Armor per stack
	dozer_damage_bonus = 0.05, -- +5% Damage per stack
	dozer_speed_penalty = 0.15, -- -15% Speed per stack
	dozer_speed_min = 0.40, -- Minimum movement speed (cap)
	dozer_dodge_penalty = 5, -- -5 Dodge per stack

	-- GLASS PISTOL — multiplicative stacking!
	glass_pistol_dmg_per_stack = 1.75, -- x1.75 damage per stack (multiplicative)
	glass_pistol_div_per_stack = 2, -- /2 HP and Armor per stack

	-- EQUALIZER
	equalizer_bonus = 0.5, -- +50% damage to specials per stack
	equalizer_penalty = 0.5, -- -50% damage to normals per stack (min 1)

	-- CROOKED BADGE
	crooked_badge_k = 0.05, -- Hyperbolic K for revive/bleedout curves
	crooked_badge_enemy_mult = 0.20, -- +20% enemy force per stack

	-- THE EDGE
	the_edge_hp_threshold = 0.10, -- Trigger below 10% max HP
	the_edge_heal_pct = 0.20, -- 20% max HP restored
	the_edge_heal_flat = 20, -- +20 flat display HP (1 stack)
	the_edge_heal_flat_extra = 40, -- +40 flat display HP per extra stack
	the_edge_invuln = 1.0, -- 1s invulnerability after trigger
	the_edge_cooldown = 120, -- Cooldown in seconds between activations

	-- DEAD MAN'S TRIGGER
	dmt_base_radius = 300, -- cm at 1 stack
	dmt_radius_per_stack = 200, -- cm per additional stack (+2m)
	dmt_base_damage = 2400, -- internal at 1 stack (= 480 display HP)
	dmt_damage_per_stack = 1200, -- internal per additional stack
	dmt_level_damage = 10, -- internal per CS level
	dmt_ally_mult = 0.20, -- allies take 20% of enemy damage

	-- VIKLUND VINYL
	viklund_radius_base = 500, -- centimeters (5m)
	viklund_radius_step = 200, -- +2m per additional stack
	viklund_chain_count = 2, -- enemies hit per chain
	viklund_chain_dmg_pct = 0.25, -- 25% of original damage
	viklund_chain_spec_mult = 0.25, -- specials take 25% of chain damage
	viklund_proc_chance = 0.80, -- 80% chance on hit (fixed, does not scale with stacks)

	-- LOCKE'S BERET — periodic team heal (hyperbolic, capped near 50%)
	lockes_beret_first_pct = 0.10, -- 10% of max HP at 1 stack
	lockes_beret_max_pct = 0.50, -- Hyperbolic asymptote: 50% of max HP
	lockes_beret_interval = 30, -- Pulse interval (seconds)

	-- === WILDCARD ITEMS ===

	-- FAMILIAR FRIEND — Spike Nova: 360° AoE damage on key press
	familiar_friend_radius = 1000, -- AoE radius (cm, 10m)
	familiar_friend_damage = 2000, -- internal damage at rank 0 (= 400 display HP)
	familiar_friend_level_pct = 0.0035, -- +0.35% damage per CS rank (additive linear)
	familiar_friend_cooldown = 60, -- seconds between activations
	familiar_friend_charge_delay = 0.6, -- wind-up time before nova fires (matches charge SFX)

	-- TURRON — instant heal + 5s damage reduction window
	turron_heal_pct = 0.33, -- +33% of max HP, instant on press
	turron_dr_pct = 0.33, -- 33% damage reduction during window
	turron_dr_duration = 5, -- seconds of DR after press
	turron_cooldown = 90, -- seconds between presses

	-- SIDE SATCHEL — additive movement-speed bump while a loot bag is on the back
	side_satchel_carry_speed_mult = 1.20, -- 1.20 = +20% (additive vs vanilla baseline)

	-- HIPPOCRATIC OATH — passive medic joker that heals via aura
	hippocratic_aura_radius = 500, -- 5m heal aura around the medic (PD2 units, 1m = 100)
	hippocratic_aura_tick = 5.0, -- heal pulse cadence (seconds)
	hippocratic_heal_pct_per_tick = 0.05, -- 5% max HP per pulse (1%/sec sustained)
	hippocratic_respawn_delay = 360, -- 6 minutes between deaths (cooldown only, no per-heist cap)
	hippocratic_spawn_min_distance = 1500, -- spawn medic at least 15m from owner (offscreen feel)
	hippocratic_spawn_max_distance = 4000, -- but no farther than 40m (so they actually arrive)
	hippocratic_medic_dr = 0.80, -- 80% damage reduction on incoming damage to the medic
	hippocratic_pulse_duration = 0.5, -- expanding-ring visual lifetime per heal pulse (seconds)
	hippocratic_pulse_alpha = 0.08, -- peak opacity of the expanding ring (0..1, fades linearly to 0 over duration)
	hippocratic_voice_event = "f47", -- Wwise event the medic shouts on heal (vanilla medic priority_shout)
	hippocratic_voice_throttle = 30, -- minimum seconds between heal voicelines per machine

	-- === FORCED MODIFIERS ===

	-- EXPLOSIVE RESISTANCE (Bulldozer explosion immunity override)
	dozer_explosion_resistance = 0.50, -- 50% explosion damage reduction (vanilla = 100% immunity)

	-- IMMOVABLE (No Hurt Anims)
	no_hurt_anims_block_chance = 0.80, -- 80% chance to block stagger (vanilla = 100%)

	-- GUILTY CONSCIENCE
	guilt_hp_penalty = 0.05, -- -5% max HP per civilian kill
	guilt_max_penalty = 0.30, -- Maximum 30% HP reduction (6 kills)

	-- SHOCKING SURPRISE
	shocking_surprise_radius = 500, -- 5 meters (cm)
	shocking_surprise_slow_mul = 0.5, -- 50% movement speed during effect
	shocking_surprise_duration = 3, -- Slowdown duration (seconds)
	shocking_surprise_decay = 0.5, -- Fade-out duration (seconds)

	-- === KILL CASH ===
	kill_cash_per_kill = 100, -- Base instant cash per enemy kill (rank 0)
	kill_cash_per_rank = 1, -- +$1 per CS rank

	-- === BONUS ITEM DROP (Pity System) ===
	bonus_drop_cash_per_percent = 10000, -- $10,000 instant cash = +1% drop chance
	bonus_drop_min_chance = 0.01, -- 1% minimum chance (0.01 = 1%)
	bonus_drop_escalation = 200000, -- Each drop increases 100% threshold by $200k

	-- === CASH-TO-RANK CONVERSION RATES ===
	-- Cash-to-rank conversion rates per difficulty (display names).
	-- One unit = value of one money bag at that difficulty.
	-- Used by crimespree_mission_bonus.lua (math) and cash_convert_animation.lua (UI).
	cash_per_rank = {
		normal = 7500,
		hard = 37500,
		very_hard = 75000,
		overkill = 157500,
		mayhem = 270000,
		death_wish = 307500,
		death_sentence = 345000,
	},
	-- Linear additive escalation per rank within ONE mission (resets next mission).
	-- Rank N cost = cash_per_rank * (1 + step * (N-1)). Step is fraction of base.
	cash_per_rank_step = 0.10,

	-- === SHOP (Gage's Services → Shop sub-tab) ===
	-- Chest slots shown per player. Each chest holds one pre-rolled non-contraband item.
	shop_chest_count = 3,
	-- Price formula: floor(base + host_rank * per_rank). Scales with host's CS rank.
	shop_chest_base_price = 2,
	shop_chest_price_per_rank = 0.1,
}

-- Per-icon display scale overrides (applied in both items_page and logbook_menu)
-- 1.0 = default size, >1.0 = larger, <1.0 = smaller
_G.CSR_IconScale = {
	csr_evidence_rounds = 0.95,
	csr_dozer_guide = 0.95,
	csr_pink_slip = 1.05,
	csr_overkill_rush = 0.9,
	csr_equalizer = 0.9,
}

-- Cached k constant for Worn Band-Aid hyperbolic stacking — computed once at file load.
local _bandaid_first = _G.CSR_ItemConstants.worn_bandaid_first_pct or 0.01
local _bandaid_max = _G.CSR_ItemConstants.worn_bandaid_max_pct or 0.20
local _bandaid_k = (_bandaid_max - _bandaid_first) / _bandaid_first

function _G.CSR_BandaidRegenPct(stacks)
	if not stacks or stacks <= 0 then
		return 0
	end
	return _bandaid_max * stacks / (stacks + _bandaid_k)
end

-- Cached k constant for Locke's Beret hyperbolic team heal — same shape as Worn Band-Aid.
local _beret_first = _G.CSR_ItemConstants.lockes_beret_first_pct or 0.10
local _beret_max = _G.CSR_ItemConstants.lockes_beret_max_pct or 0.50
local _beret_k = (_beret_max - _beret_first) / _beret_first

function _G.CSR_LockesBeretHealPct(stacks)
	if not stacks or stacks <= 0 then
		return 0
	end
	return _beret_max * stacks / (stacks + _beret_k)
end

CSR_log("[CSR] CSRBaseModifier loaded — standalone base class")
