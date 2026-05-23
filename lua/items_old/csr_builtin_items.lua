-- CSR's own items, registered through the SAME public API addons use.
--
-- This is the dogfooding contract: if CSR.register_item can't express a CSR
-- item, it can't express a modder's either, and we find out here first. Slice
-- 1 ships Dog Tags only; lua/items/dogtags.lua is deleted and its mechanic now
-- flows through the generic stat_mul dispatcher (csr_item_effects_playerstats.lua) driven
-- by this registration.
--
-- Runs at file-load (lib/setups/setup) — _G.CSR exists by then (the API shim
-- is hooked earlier on lib/entry), and the manager may or may not be up yet;
-- the API queues if needed and CSRGameManager:init() drains. The _G guard
-- keeps a hot-reload from double-registering (register_item also rejects the
-- duplicate type, so this is belt-and-braces).
--
-- Ordering: grouped by rarity (common -> uncommon -> rare -> contraband ->
-- wildcard), alphabetical by type within each group. Registration order has no
-- mechanical effect (the registry is type-keyed); this is purely for humans.

if not RequiredScript then
	return
end

if _G.CSR and _G.CSR.register_item and not _G._CSR_BUILTINS_REGISTERED then
	_G._CSR_BUILTINS_REGISTERED = true

	-- ============ COMMON ============
	-- NOTE: cup_of_joe migrated to the per-item-file model (lua/item_defs/cup_of_joe.lua,
	-- auto-loaded). Remaining items below still use the kind/dispatcher model until
	-- they migrate too.

	_G.CSR.register_item({
		type = "dog_tags",
		rarity = "common",
		name = "DOG TAGS",
		-- Short flavor line, verbatim from the pre-refactor authored source
		-- (localization.lua ITEMS_EN + items_page.lua, identical per Rule #15).
		-- The detailed "+10%/stack" breakdown is Logbook-tier, not the card.
		desc = "Increases your max health.",
		-- per_stack mirrors the legacy CSR constant dog_tags_hp_bonus (0.10).
		icon = "csr_dog_tags",
		effect = { kind = "stat_mul", stat = "max_health", per_stack = 0.10 },
	})

	_G.CSR.register_item({
		type = "duct_tape",
		rarity = "common",
		name = "DUCT TAPE",
		-- Short flavor; the +10% detail and the revive/uncuff exclusion live
		-- in the Logbook (csr_logbook_duct_tape_effect). Per Rule #15 the
		-- card desc stays short.
		desc = "Increases your interaction speed.",
		-- per_stack mirrors the legacy CSR constant duct_tape_speed_bonus
		-- (0.10). Applied as time-divide by (1 + sum) on
		-- BaseInteractionExt:_get_timer (csr_item_effects_interaction.lua).
		-- Player-facing exclusions: "revive" and "free" interactions are
		-- unaffected -- mirrored from 6.x.
		icon = "csr_duct_tape",
		effect = { kind = "stat_mul", stat = "interaction_speed", per_stack = 0.10 },
	})

	_G.CSR.register_item({
		type = "escape_plan",
		rarity = "common",
		name = "ESCAPE PLAN",
		-- Short flavor, verbatim from the 6.2 authored source (Rule #15). The
		-- hyperbolic cap / per-stack detail is Logbook-tier.
		desc = "Increases your movement speed.",
		icon = "csr_escape_plan",
		-- cap / k_num / k_den mirror the 6.2 constants (escape_plan_cap = 0.50,
		-- _k_num = 3, _k_den = 47): bonus = 0.50 * (1 - 1/(1 + (3/47)*stacks)),
		-- ~3% at 1 stack, asymptotes to 50%. Applied multiplicatively on
		-- PlayerStandard:_get_max_walk_speed (csr_item_effects_playerstandard.lua).
		effect = { kind = "stat_hyperbolic", stat = "movement_speed", cap = 0.50, k_num = 3, k_den = 47 },
	})

	_G.CSR.register_item({
		type = "rebar",
		rarity = "common",
		name = "PIECE OF REBAR",
		-- Short flavor, verbatim from the 6.2 authored source (Rule #15). The
		-- +15%/+10%-per-stack breakdown is Logbook-tier, not the card.
		desc = "Your first hit on an enemy deals bonus damage.",
		icon = "csr_rebar",
		-- First-hit-per-enemy damage amplifier: the first time the local player
		-- damages a given enemy, that hit is multiplied by (1 + base_bonus +
		-- (stacks-1)*extra_bonus). base_bonus / extra_bonus mirror the 6.2
		-- constants (rebar_base_bonus = 0.15, rebar_extra_bonus = 0.10): 1 stack
		-- = +15%, 2 = +25%, 3 = +35%. Applied by csr_item_effects_weapon.lua
		-- (the weapon-damage dispatcher, alongside Evidence Rounds).
		effect = { kind = "first_hit_damage", base_bonus = 0.15, extra_bonus = 0.10 },
	})

	_G.CSR.register_item({
		type = "worn_bandaid",
		rarity = "common",
		name = "WORN BAND-AID",
		-- Short flavor; the hyperbolic % / interval / cap detail is Logbook
		-- tier (csr_logbook_worn_bandaid_effect). Per Rule #15.
		desc = "Regenerates your health over time.",
		icon = "csr_worn_bandaid",
		-- first_pct / max_pct / interval mirror the 6.2 shipping line constants
		-- (worn_bandaid_first_pct = 0.02, _max_pct = 0.20, _interval = 5). Each
		-- tick the dispatcher (csr_item_effects_regen.lua) heals the local
		-- player by max_hp * (max_pct * stacks / (stacks + k)) where
		-- k = (max_pct - first_pct) / first_pct. First non-stat_mul effect ->
		-- exercises the registry API's effect-kind extensibility.
		effect = {
			kind = "regen_max_hp_pct",
			first_pct = 0.02,
			max_pct = 0.20,
			interval = 5,
		},
	})

	-- ============ UNCOMMON ============

	_G.CSR.register_item({
		type = "evidence_rounds",
		rarity = "uncommon",
		name = "EVIDENCE ROUNDS",
		-- Short flavor; the +10% detail belongs in the Logbook (Rule #15).
		desc = "Increases your damage.",
		-- per_stack mirrors the legacy CSR constant ap_rounds_damage_bonus
		-- (0.10) -- shipping line called the variable AP rounds, the item is
		-- "Evidence Rounds" to the player. Applied multiplicatively on top
		-- of RaycastWeaponBase:_get_current_damage by the stat="damage"
		-- branch of the dispatcher (csr_item_effects_weapon.lua). Because
		-- stat="damage" is ALL damage, csr_item_effects_melee.lua also adds it
		-- to melee swings.
		icon = "csr_evidence_rounds",
		effect = { kind = "stat_mul", stat = "damage", per_stack = 0.10 },
	})

	_G.CSR.register_item({
		type = "falcogini_keys",
		rarity = "uncommon",
		name = "FALCOGINI KEYS",
		desc = "Gives you a chance to dodge incoming damage.",
		icon = "csr_falcogini_keys",
		-- cap 1.0 + k_den 32 mirror the 6.2 constant car_keys_k_den (32):
		-- dodge = 1 - 1/(1 + (1/32)*stacks), ~3% at 1 stack, approaches but
		-- never reaches 100%. Combined with vanilla dodge probabilistically
		-- (1 - (1-base)*(1-bonus)) on PlayerManager:skill_dodge_chance
		-- (csr_item_effects_playerstats.lua).
		effect = { kind = "stat_hyperbolic", stat = "dodge", cap = 1.0, k_num = 1, k_den = 32 },
	})

	_G.CSR.register_item({
		type = "overkill_rush",
		rarity = "uncommon",
		name = "OVERKILL RUSH",
		desc = "Killing enemies temporarily increases fire rate and reload speed.",
		icon = "csr_overkill_rush",
		-- Kill-streak buff. Each local-player kill adds a stack (max max_kill_stacks),
		-- decaying after `duration` seconds without a kill. Active bonus =
		-- kill_stacks * (item_stacks + 1) * bonus_per_kill, applied EQUALLY to fire
		-- rate and reload speed (NewRaycastWeaponBase). bonus_per_kill / max_kill_stacks
		-- / duration mirror the 6.2 constants (overkill_rush_extra_bonus = 0.01,
		-- _max_stacks = 4, _duration = 4.0): 1 item -> +2/4/6/8% at 1-4 kills.
		-- The legacy overkill_rush_first_bonus (0.02) was never read by the live
		-- formula -- it equals (1+1)*0.01 incidentally -- so it is intentionally
		-- dropped here. Streak state + consumer live in csr_item_effects_kill.lua.
		effect = { kind = "weapon_speed_streak", bonus_per_kill = 0.01, max_kill_stacks = 4, duration = 4.0 },
	})

	_G.CSR.register_item({
		type = "pink_slip",
		rarity = "uncommon",
		name = "PINK SLIP",
		desc = "Killing an enemy restores health.",
		icon = "csr_pink_slip",
		-- Heal per local-player kill = max_hp*base_pct + (base_flat + (stacks-1)*extra_flat)
		-- display HP, converted to internal. Applied by csr_item_effects_kill.lua.
		effect = { kind = "heal_on_kill", base_pct = 0.01, base_flat = 4, extra_flat = 6 },
	})

	_G.CSR.register_item({
		type = "the_edge",
		rarity = "uncommon",
		name = "THE EDGE",
		-- Short flavor, verbatim from the 6.2 authored source (Rule #15). The
		-- threshold / heal / cooldown numbers are Logbook-tier, not the card.
		desc = "When critically low on health,\nrestores health and grants brief invulnerability.",
		icon = "csr_the_edge",
		-- Cooldown-gated emergency heal. When the local player's HP drops below
		-- hp_threshold (of max) -- or a hit would be lethal -- and the cooldown is
		-- ready, heal max_hp*heal_pct + (heal_flat + (stacks-1)*heal_flat_extra)
		-- display HP (flat part /stats_present_multiplier to internal), then grant
		-- `invuln` seconds of invulnerability. All values mirror the 6.2 constants
		-- (the_edge_hp_threshold 0.10 / _heal_pct 0.20 / _heal_flat 20 /
		-- _heal_flat_extra 40 / _invuln 1.0 / _cooldown 120). Applied by
		-- csr_item_effects_regen.lua; the invuln shares one _chk_can_take_dmg
		-- PostHook with Plush Shark.
		effect = {
			kind = "emergency_heal",
			hp_threshold = 0.10,
			heal_pct = 0.20,
			heal_flat = 20,
			heal_flat_extra = 40,
			invuln = 1.0,
			cooldown = 120,
		},
	})

	_G.CSR.register_item({
		type = "wolfs_toolbox",
		rarity = "uncommon",
		name = "WOLF'S TOOLBOX",
		desc = "Killing enemies reduces the timer\non active drills and saws.",
		-- Icon id is "csr_toolbox" in hudicons.lua (legacy name), not csr_wolfs_toolbox.
		icon = "csr_toolbox",
		-- Each local-player kill cuts active drill/saw timers; always triggers (no
		-- RNG), specials cut more. normal/special _base/_extra mirror the 6.2
		-- constants (wolfs_toolbox_normal_base 0.2 / _normal_extra 0.1 /
		-- _special_base 1.0 / _special_extra 0.5). Reductions SUM across owned
		-- drill_timer_on_kill items. TimerGui drills are host-authoritative (client
		-- kills RPC the host); saw INTERACTIONS are locally owned. Applied by
		-- csr_item_effects_kill.lua.
		effect = {
			kind = "drill_timer_on_kill",
			normal_base = 0.2,
			normal_extra = 0.1,
			special_base = 1.0,
			special_extra = 0.5,
		},
	})

	-- ============ RARE ============

	_G.CSR.register_item({
		type = "bonnie_chip",
		rarity = "rare",
		name = "BONNIE'S LUCKY CHIP",
		desc = "Each hit has a small chance to instantly kill the target.",
		icon = "csr_bonnie_chip",
		-- Bespoke proc: a bullet hit on a non-civilian/non-converted enemy rolls
		-- an instakill (chance per chip, combined 1-(1-chance)^stacks), and on a
		-- win the attack's damage is amplified so vanilla damage_bullet lands the
		-- kill itself -- which routes the death through vanilla MP networking
		-- (client RPCs host, host syncs back) instead of a local self:die() that
		-- would desync. chance / cooldown mirror the 6.2 constants
		-- (bonnie_chip_chance = 0.10, _cooldown = 1.5). The cooldown is armed on
		-- EVERY attempt (win or lose) to stop minigun spam. Logic lives in
		-- csr_item_effects_weapon.lua. NOTE: the proc sound + its MP broadcast
		-- are deferred until the sound subsystem (CSR_PlaySound) ports; the
		-- instakill itself is fully functional now.
		effect = { kind = "instakill_on_hit", chance = 0.10, cooldown = 1.5 },
	})

	_G.CSR.register_item({
		type = "jiro_last_wish",
		rarity = "rare",
		name = "JIRO'S LAST WISH",
		-- Two-part item: the +melee-damage half is declarative (stat_mul below);
		-- the "sprint while charging a melee attack" half is bespoke behavior
		-- carried in csr_item_effects_playerstandard.lua (gated on ownership),
		-- not expressible as a declarative kind. Short flavor verbatim from 6.2.
		desc = "Sprint while charging a melee attack. Increases melee damage.",
		icon = "csr_jiro_last_wish",
		-- per_stack mirrors the 6.2 constant jiro_melee_bonus (0.5 = +50%/stack).
		-- stat = "melee_damage" applies to melee swings only (csr_item_effects_melee.lua);
		-- contrast stat = "damage" (Evidence Rounds) which scales bullet AND melee.
		effect = { kind = "stat_mul", stat = "melee_damage", per_stack = 0.5 },
	})

	_G.CSR.register_item({
		type = "plush_shark",
		rarity = "rare",
		name = "PLUSH SHARK",
		desc = "Saves you from custody once per life,\nrestores 1 down, full health and armor,\nthen grants brief invulnerability.",
		icon = "csr_plush_shark",
		-- Guardian angel: fires on the LAST down before custody (revives == 1, the
		-- next bleed-out would route to custody). Cancels it by healing to full,
		-- restoring one down (revives +1, capped at the player's max lives) and
		-- armor, then granting invuln_base + (stacks-1)*invuln_extra seconds of
		-- invulnerability. One charge per life, refreshed on (re)spawn -- including
		-- custody release -- but NOT on a teammate bleed-out revive. Values mirror
		-- the 6.2 constants (plush_shark_heal_pct 1.00 / _restore_armor true /
		-- _invuln_base 10 / _invuln_extra 20). Applied by
		-- csr_item_effects_regen.lua; the invuln shares one _chk_can_take_dmg
		-- PostHook with The Edge.
		effect = {
			kind = "guardian_revive",
			heal_pct = 1.00,
			restore_armor = true,
			invuln_base = 10,
			invuln_extra = 20,
		},
	})
end
