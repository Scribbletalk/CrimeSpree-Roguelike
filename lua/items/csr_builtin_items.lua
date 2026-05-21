-- CSR's own items, registered through the SAME public API addons use.
--
-- This is the dogfooding contract: if CSR.register_item can't express a CSR
-- item, it can't express a modder's either, and we find out here first. Slice
-- 1 ships Dog Tags only; lua/items/dogtags.lua is deleted and its mechanic now
-- flows through the generic stat_mul dispatcher (csr_item_effects.lua) driven
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

	_G.CSR.register_item({
		type = "cup_of_joe",
		rarity = "common",
		name = "CUP OF JOE",
		desc = "Increases your stamina.",
		-- per_stack mirrors the legacy CSR constant cup_of_joe_per_stack
		-- (0.10). Applied additively on top of PlayerManager:stamina_multiplier
		-- (vanilla returns 1 + skill_bonuses; we add 0.10*stacks). Same shape
		-- as Dog Tags / max_health -- see csr_item_effects.lua.
		icon = "csr_cup_of_joe",
		effect = { kind = "stat_mul", stat = "max_stamina", per_stack = 0.10 },
	})

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
		-- (csr_item_effects.lua).
		effect = { kind = "stat_hyperbolic", stat = "dodge", cap = 1.0, k_num = 1, k_den = 32 },
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

	-- ============ RARE ============

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
end
