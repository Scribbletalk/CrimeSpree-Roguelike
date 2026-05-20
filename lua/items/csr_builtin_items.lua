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

if not RequiredScript then
	return
end

if _G.CSR and _G.CSR.register_item and not _G._CSR_BUILTINS_REGISTERED then
	_G._CSR_BUILTINS_REGISTERED = true

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
		type = "evidence_rounds",
		rarity = "uncommon",
		name = "EVIDENCE ROUNDS",
		-- Short flavor; the +10% detail belongs in the Logbook (Rule #15).
		desc = "Increases your damage.",
		-- per_stack mirrors the legacy CSR constant ap_rounds_damage_bonus
		-- (0.10) -- shipping line called the variable AP rounds, the item is
		-- "Evidence Rounds" to the player. Applied multiplicatively on top
		-- of RaycastWeaponBase:_get_current_damage by the stat="damage"
		-- branch of the dispatcher (csr_item_effects_weapon.lua).
		icon = "csr_evidence_rounds",
		effect = { kind = "stat_mul", stat = "damage", per_stack = 0.10 },
	})

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
end
