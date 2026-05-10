-- Crime Spree Roguelike Alpha 1 - Apply effects at mission start

if not RequiredScript then
	return
end

-- Global variable for storing active buffs
CSR_ActiveBuffs = CSR_ActiveBuffs or {}

-- Debug logger: no-op unless the user enables debug_mode in settings.
local function CSR_pm_dbg(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR PM] " .. tostring(msg))
	end
end

-- Refresh CSR_ActiveBuffs so mid-heist item swaps (printer) take effect.
-- Called from spawned_player (mission start) AND from copier_spawner after an
-- exchange. Covers live-readable flags AND live-capped stats (HP/armor/damage)
-- by recomputing multipliers and clamping current values to the new max.
--
-- Skips per-heist reset state that would break on swap:
--   CSR_HalfAGlass_BaseAmmo, HalfAGlass pickup counter, CivilianGuiltKills.
-- Known limitation: Anarchist's _damage_to_armor.armor_value is mutated
-- in-place at spawn (see spawned_player) — its original is lost, so its flat
-- armor regen value stays at the spawn-time armor multiplier. Minor gameplay
-- inconsistency only; a full fix would need to cache the pristine value.
function CSR_RefreshItemBuffFlags()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	CSR_ActiveBuffs = CSR_ActiveBuffs or {}
	local C = _G.CSR_ItemConstants or {}

	local function clear(...)
		for _, k in ipairs({ ... }) do
			CSR_ActiveBuffs[k] = nil
		end
	end

	-- CS level drives passive HP/damage/armor scaling. Use host's rank in MP client.
	local cs_level = managers.crime_spree:spree_level() or 0
	if _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and _G.CSR_MP_HostRank then
		cs_level = _G.CSR_MP_HostRank
	end
	local progression_tiers = cs_level

	CSR_pm_dbg(string.format("Refresh: cs_level=%d, tiers=%d", cs_level, progression_tiers))

	if progression_tiers > 0 then
		CSR_ActiveBuffs.passive_progression = true
		CSR_ActiveBuffs.progression_tiers = progression_tiers
	else
		clear("passive_progression", "progression_tiers")
	end

	-- Civilian Guilt: the forced-loud CS modifier, not a player item → query active_modifiers.
	local guilt_stacks = 0
	for _, mod in ipairs(managers.crime_spree:active_modifiers() or {}) do
		if mod.id and string.find(mod.id, "csr_civilian_guilt", 1, true) == 1 then
			guilt_stacks = guilt_stacks + 1
		end
	end
	if guilt_stacks > 0 then
		CSR_ActiveBuffs.civilian_guilt = true
	else
		clear("civilian_guilt")
	end

	local dozer_stacks = CSR_CountStacks("player_dozer_guide")
	if dozer_stacks > 0 then
		CSR_ActiveBuffs.dozer_guide = true
		CSR_ActiveBuffs.dozer_guide_stacks = dozer_stacks
		CSR_ActiveBuffs.dozer_guide_weapon_multiplier = 1.0 + (C.dozer_damage_bonus or 0.05) * dozer_stacks
		CSR_ActiveBuffs.dozer_guide_melee = true
		CSR_ActiveBuffs.dozer_guide_melee_multiplier = 1 + (C.dozer_damage_bonus or 0.05) * dozer_stacks
		CSR_ActiveBuffs.dozer_guide_speed_debuff = true
		local speed_mult = 1 - (C.dozer_speed_penalty or 0.15) * dozer_stacks
		CSR_ActiveBuffs.dozer_guide_speed_multiplier = math.max((C.dozer_speed_min or 0.40), speed_mult)
		CSR_ActiveBuffs.dozer_guide_dodge_debuff = true
		CSR_ActiveBuffs.dozer_guide_dodge_penalty = (C.dozer_dodge_penalty or 5) * dozer_stacks
	else
		clear(
			"dozer_guide",
			"dozer_guide_stacks",
			"dozer_guide_weapon_multiplier",
			"dozer_guide_melee",
			"dozer_guide_melee_multiplier",
			"dozer_guide_speed_debuff",
			"dozer_guide_speed_multiplier",
			"dozer_guide_dodge_debuff",
			"dozer_guide_dodge_penalty"
		)
	end

	local keys_stacks = CSR_CountStacks("player_car_keys")
	if keys_stacks > 0 then
		CSR_ActiveBuffs.car_keys = true
		CSR_ActiveBuffs.car_keys_stacks = keys_stacks
		local k = 1.0 / (C.car_keys_k_den or 32)
		CSR_ActiveBuffs.car_keys_dodge_bonus = 1 - 1 / (1 + k * keys_stacks)
	else
		clear("car_keys", "car_keys_stacks", "car_keys_dodge_bonus")
	end

	local duct_tape_stacks = CSR_CountStacks("player_duct_tape")
	if duct_tape_stacks > 0 then
		CSR_ActiveBuffs.duct_tape = true
		CSR_ActiveBuffs.duct_tape_stacks = duct_tape_stacks
	else
		clear("duct_tape", "duct_tape_stacks")
	end

	local jiro_stacks = CSR_CountStacks("player_jiro_last_wish")
	if jiro_stacks > 0 then
		CSR_ActiveBuffs.jiro_last_wish = true
		CSR_ActiveBuffs.jiro_last_wish_stacks = jiro_stacks
		CSR_ActiveBuffs.jiro_last_wish_melee_multiplier = 1 + jiro_stacks * (C.jiro_melee_bonus or 0.5)
	else
		clear("jiro_last_wish", "jiro_last_wish_stacks", "jiro_last_wish_melee_multiplier")
	end

	local dp_stacks = CSR_CountStacks("player_dearest_possession")
	if dp_stacks > 0 then
		CSR_ActiveBuffs.dearest_possession = dp_stacks
	else
		if CSR_ActiveBuffs.dearest_possession then
			-- Item just removed — clear stale _csr_dp_armor so _max_armor() no longer
			-- grants the bonus. Without this, the decay hook early-returns (flag gone)
			-- and _csr_dp_armor stays non-zero forever → permanent armor boost.
			local pu = managers.player and managers.player:player_unit()
			if pu and alive(pu) then
				local cd = pu:character_damage()
				if cd then
					CSR_pm_dbg(
						string.format(
							"Dearest Possession removed: cleared _csr_dp_armor (was %.2f)",
							cd._csr_dp_armor or 0
						)
					)
					cd._csr_dp_armor = 0
					cd._csr_dp_fill = nil
				end
			end
			CSR_ActiveBuffs.dearest_possession = nil
		end
	end

	local vv_stacks = CSR_CountStacks("player_viklund_vinyl")
	CSR_ActiveBuffs.viklund_vinyl = vv_stacks > 0 and vv_stacks or nil

	local lockes_stacks = CSR_CountStacks("player_lockes_beret")
	CSR_ActiveBuffs.lockes_beret_stacks = lockes_stacks > 0 and lockes_stacks or nil

	local eq_stacks = CSR_CountStacks("player_equalizer_")
	CSR_ActiveBuffs.equalizer = eq_stacks > 0 and eq_stacks or nil

	local cb_stacks = CSR_CountStacks("player_crooked_badge_")
	CSR_ActiveBuffs.crooked_badge = cb_stacks > 0 and cb_stacks or nil

	local dmt_stacks = CSR_CountStacks("player_dead_mans_trigger_")
	CSR_ActiveBuffs.dead_mans_trigger = dmt_stacks > 0 and dmt_stacks or nil

	local sneakers_stacks = CSR_CountStacks("player_escape_plan")
	if sneakers_stacks > 0 then
		CSR_ActiveBuffs.escape_plan = true
		CSR_ActiveBuffs.escape_plan_stacks = sneakers_stacks
		local k = (C.escape_plan_k_num or 3) / (C.escape_plan_k_den or 47)
		CSR_ActiveBuffs.escape_plan_speed_bonus = (C.escape_plan_cap or 0.50) * (1 - 1 / (1 + k * sneakers_stacks))
	else
		clear("escape_plan", "escape_plan_stacks", "escape_plan_speed_bonus")
	end

	local bandaid_stacks = CSR_CountStacks("player_worn_bandaid")
	if bandaid_stacks > 0 then
		CSR_ActiveBuffs.worn_bandaid = true
		CSR_ActiveBuffs.worn_bandaid_stacks = bandaid_stacks
		CSR_ActiveBuffs.worn_bandaid_regen_pct = CSR_BandaidRegenPct(bandaid_stacks)
	else
		clear("worn_bandaid", "worn_bandaid_stacks", "worn_bandaid_regen_pct")
	end

	local coffee_stacks = CSR_CountStacks("player_cup_of_joe")
	if coffee_stacks > 0 then
		CSR_ActiveBuffs.cup_of_joe = true
		CSR_ActiveBuffs.cup_of_joe_stacks = coffee_stacks
		CSR_ActiveBuffs.cup_of_joe_stamina_bonus = (C.cup_of_joe_per_stack or 0.10) * coffee_stacks
	else
		clear("cup_of_joe", "cup_of_joe_stacks", "cup_of_joe_stamina_bonus")
	end

	local half_glass_stacks = CSR_CountStacks("player_half_a_glass")
	if half_glass_stacks > 0 then
		CSR_ActiveBuffs.half_a_glass = true
		CSR_ActiveBuffs.half_a_glass_stacks = half_glass_stacks
	else
		clear("half_a_glass", "half_a_glass_stacks")
	end

	-- === HP: passive progression + Dog Tags (additive) + Glass Pistol (multiplicative) ===
	local health_stacks = CSR_CountStacks("player_health_boost")
	local glass_stacks = CSR_CountStacks("player_glass_pistol")
	local total_hp_bonus = 0.0

	if progression_tiers > 0 then
		total_hp_bonus = total_hp_bonus + ((C.passive_hp_per_level or 0.001) * progression_tiers)
	end

	if health_stacks > 0 then
		CSR_ActiveBuffs.health = true
		CSR_ActiveBuffs.health_stacks = health_stacks
		total_hp_bonus = total_hp_bonus + ((C.dog_tags_hp_bonus or 0.1) * health_stacks)
	else
		clear("health", "health_stacks")
	end

	CSR_ActiveBuffs.hp_bonus = total_hp_bonus

	-- === GLASS PISTOL: HP/armor divide + damage multiply ===
	if glass_stacks > 0 then
		local div_per_stack = C.glass_pistol_div_per_stack or 2
		local penalty_mult = math.pow(1 / div_per_stack, glass_stacks)
		local damage_mult = math.pow((C.glass_pistol_dmg_per_stack or 1.5), glass_stacks)

		CSR_ActiveBuffs.glass_pistol = true
		CSR_ActiveBuffs.glass_pistol_stacks = glass_stacks
		CSR_ActiveBuffs.glass_pistol_hp_mult = penalty_mult
		CSR_ActiveBuffs.glass_pistol_armor_mult = penalty_mult
		CSR_ActiveBuffs.glass_pistol_weapon_multiplier = damage_mult
		CSR_ActiveBuffs.glass_pistol_melee = true
		CSR_ActiveBuffs.glass_pistol_melee_multiplier = damage_mult
	else
		clear(
			"glass_pistol",
			"glass_pistol_stacks",
			"glass_pistol_hp_mult",
			"glass_pistol_armor_mult",
			"glass_pistol_weapon_multiplier",
			"glass_pistol_melee",
			"glass_pistol_melee_multiplier"
		)
	end

	-- === ARMOR: passive progression + Dozer Guide (additive). Glass Pistol applied above. ===
	local total_armor_bonus = 0.0
	if progression_tiers > 0 then
		total_armor_bonus = total_armor_bonus + ((C.passive_armor_per_level or 0.001) * progression_tiers)
	end
	local dozer_stacks_for_armor = CSR_CountStacks("player_dozer_guide")
	if dozer_stacks_for_armor > 0 then
		total_armor_bonus = total_armor_bonus + (C.dozer_armor_bonus or 0.5) * dozer_stacks_for_armor
	end

	if total_armor_bonus ~= 0 then
		CSR_ActiveBuffs.passive_armor_multiplier = 1 + total_armor_bonus
	else
		clear("passive_armor_multiplier")
	end

	-- === DAMAGE: passive progression + Evidence Rounds (additive) ===
	local damage_stacks = CSR_CountStacks("player_damage_boost")
	local total_damage_bonus = 0.0
	if progression_tiers > 0 then
		total_damage_bonus = total_damage_bonus + ((C.passive_damage_per_level or 0.0004) * progression_tiers)
	end
	if damage_stacks > 0 then
		CSR_ActiveBuffs.damage_stacks = damage_stacks
		total_damage_bonus = total_damage_bonus + ((C.ap_rounds_damage_bonus or 0.05) * damage_stacks)
	else
		clear("damage_stacks")
	end

	if total_damage_bonus > 0 then
		CSR_ActiveBuffs.damage = true
		CSR_ActiveBuffs.damage_multiplier = 1.0 + total_damage_bonus
	else
		clear("damage", "damage_multiplier")
	end

	-- === PLUSH SHARK: stacks live-updated. Newly-acquired item grants an unused charge. ===
	-- Note: removing + re-adding via printer refreshes a spent charge (printer cost balances this).
	local shark_stacks = CSR_CountStacks("player_plush_shark_")
	if _G.CSR_PlushShark then
		local old_stacks = _G.CSR_PlushShark.stacks or 0
		_G.CSR_PlushShark.stacks = shark_stacks
		if shark_stacks > 0 and old_stacks == 0 then
			_G.CSR_PlushShark.charge_available = true
			_G.CSR_PlushShark.invulnerability_end_time = 0
			CSR_pm_dbg(string.format("Plush Shark: %d -> %d stacks, charge granted", old_stacks, shark_stacks))
		elseif shark_stacks == 0 and old_stacks > 0 then
			-- Keep invulnerability_end_time as-is so an active invuln window isn't cut short.
			_G.CSR_PlushShark.charge_available = false
			CSR_pm_dbg(string.format("Plush Shark: %d -> 0 stacks, charge revoked", old_stacks))
		elseif old_stacks ~= shark_stacks then
			CSR_pm_dbg(string.format("Plush Shark: %d -> %d stacks", old_stacks, shark_stacks))
		end
	end

	-- === WOLF'S TOOLBOX: stacks live-updated ===
	if _G.CSR_WolfsToolbox then
		local wolf_old = _G.CSR_WolfsToolbox.stacks or 0
		local wolf_new = CSR_CountStacks("player_wolfs_toolbox_")
		_G.CSR_WolfsToolbox.stacks = wolf_new
		if wolf_old ~= wolf_new then
			CSR_pm_dbg(string.format("Wolf's Toolbox: %d -> %d stacks", wolf_old, wolf_new))
		end
	end

	-- Active-items summary: non-zero stacks only (skip spam when nothing's equipped).
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		local parts = {}
		local function add(name, n)
			if n and n > 0 then
				table.insert(parts, name .. "=" .. n)
			end
		end
		add("dog", CSR_CountStacks("player_health_boost"))
		add("damage", CSR_CountStacks("player_damage_boost"))
		add("glass", CSR_CountStacks("player_glass_pistol"))
		add("dozer", CSR_CountStacks("player_dozer_guide"))
		add("keys", CSR_CountStacks("player_car_keys"))
		add("duct", CSR_CountStacks("player_duct_tape"))
		add("jiro", CSR_CountStacks("player_jiro_last_wish"))
		add("dp", CSR_CountStacks("player_dearest_possession"))
		add("viklund", CSR_CountStacks("player_viklund_vinyl"))
		add("eq", CSR_CountStacks("player_equalizer_"))
		add("cb", CSR_CountStacks("player_crooked_badge_"))
		add("dmt", CSR_CountStacks("player_dead_mans_trigger_"))
		add("escape", CSR_CountStacks("player_escape_plan"))
		add("bandaid", CSR_CountStacks("player_worn_bandaid"))
		add("half", CSR_CountStacks("player_half_a_glass"))
		add("coffee", CSR_CountStacks("player_cup_of_joe"))
		add("shark", shark_stacks)
		add("wolf", _G.CSR_WolfsToolbox and _G.CSR_WolfsToolbox.stacks or 0)
		add("bonnie", CSR_CountStacks("player_bonnie_chip"))
		add("rebar", CSR_CountStacks("player_rebar_"))
		add("overkill", CSR_CountStacks("player_overkill_rush_"))
		add("pinkslip", CSR_CountStacks("player_pink_slip_"))
		add("edge", CSR_CountStacks("player_the_edge_"))
		CSR_pm_dbg("stacks: " .. (#parts > 0 and table.concat(parts, " ") or "(none)"))
		CSR_pm_dbg(
			string.format(
				"buffs: hp_bonus=%.3f dmg_mul=%.3f armor_mul=%.3f glass_hp_mul=%s glass_armor_mul=%s",
				CSR_ActiveBuffs.hp_bonus or 0,
				CSR_ActiveBuffs.damage_multiplier or 1,
				CSR_ActiveBuffs.passive_armor_multiplier or 1,
				tostring(CSR_ActiveBuffs.glass_pistol_hp_mult or "nil"),
				tostring(CSR_ActiveBuffs.glass_pistol_armor_mult or "nil")
			)
		)
	end

	-- === STAT SYNC: push new max HP/armor to the live player unit ===
	-- Order matters: DP cleanup (above) already ran → _csr_dp_armor is clean →
	-- _max_armor() reflects the base, not stale DP bonus.
	pcall(function()
		local player_unit = managers.player and managers.player:player_unit()
		if not player_unit or not alive(player_unit) then
			CSR_pm_dbg("stat sync skipped: no live player_unit")
			return
		end
		local char_dmg = player_unit:character_damage()
		if not char_dmg then
			CSR_pm_dbg("stat sync skipped: no character_damage")
			return
		end

		-- HP: clamp down if current exceeds new max (no auto-heal on max increase → no exploit).
		local new_max_hp = char_dmg:_max_health()
		local current_hp = char_dmg:get_real_health()
		local hp_clamped = current_hp > new_max_hp
		if hp_clamped then
			char_dmg:set_health(new_max_hp)
		end
		if char_dmg._send_set_health then
			char_dmg:_send_set_health()
		end

		-- Armor: sync _current_max_armor BEFORE clamping so _check_update_max_armor
		-- on the next update() tick sees no delta and skips proportional rescaling.
		-- Direct digest write avoids set_armor → consume_armor_stored_health recursion
		-- (same pattern as dearestpossession.lua).
		local new_max_armor = char_dmg:_max_armor()
		local current_armor = char_dmg:get_real_armor()
		local armor_clamped = current_armor > new_max_armor
		char_dmg._current_max_armor = new_max_armor
		if armor_clamped then
			char_dmg._armor = Application:digest_value(new_max_armor, true)
		end
		if managers.hud and managers.hud.set_player_armor then
			managers.hud:set_player_armor({ current = char_dmg:get_real_armor(), total = new_max_armor })
		end

		CSR_pm_dbg(
			string.format(
				"stat sync: HP %.1f/%.1f (clamped=%s) | Armor %.1f/%.1f (clamped=%s)",
				char_dmg:get_real_health(),
				new_max_hp,
				tostring(hp_clamped),
				char_dmg:get_real_armor(),
				new_max_armor,
				tostring(armor_clamped)
			)
		)
	end)
end

-- Hook on player spawn: reset per-heist state, populate buffs, spawn-only rituals.
-- The per-item buff math lives entirely in CSR_RefreshItemBuffFlags() so there's
-- exactly one place to edit when a new item is added.
local _csr_spawn_count = 0
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_ApplyBuffs", function(self, id, unit)
	_csr_spawn_count = _csr_spawn_count + 1

	-- Gate on (is_active OR in_progress). is_active() reads the live gamemode, which
	-- briefly flips to non-CS during Golden Grin Casino's civilian -> mask transition
	-- (game_state_machine rebuilds the gamemode mid-heist). in_progress() is persisted
	-- CS state set by start_crime_spree and cleared by reset_crime_spree, so it stays
	-- true throughout the run — using it as a fallback prevents the transient flicker
	-- from wiping CSR_ActiveBuffs (which would silently disable Dearest Possession,
	-- Wolf's Toolbox, Pink Slip, etc. for the rest of the heist).
	local cs = managers and managers.crime_spree
	local in_cs = cs and (cs:is_active() or (cs.in_progress and cs:in_progress()))
	if not in_cs then
		CSR_ActiveBuffs = {}
		CSR_pm_dbg("spawned_player #" .. _csr_spawn_count .. ": not in CS, skipped")
		return
	end

	CSR_ActiveBuffs = {}
	CSR_pm_dbg("spawned_player #" .. _csr_spawn_count .. ": in CS, running refresh + spawn rituals")

	-- Per-heist state resets (destructive — would break mid-heist printer swaps).
	_G.CSR_HalfAGlass_BaseAmmo = {}
	_G.CSR_HalfAGlass_Pickups = 0
	_G.CSR_CivilianGuiltKills = 0

	-- Populate every CSR_ActiveBuffs field + push new stat caps to the live player.
	CSR_RefreshItemBuffFlags()

	-- Mark active player items as seen in the Logbook (discovery system, spawn-only).
	if _G.CSR_Logbook then
		pcall(function()
			local my_items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
			local item_mapping = {
				["player_health_boost"] = "dog_tags",
				["player_damage_boost"] = "evidence_rounds",
				["player_dozer_guide"] = "dozer_guide",
				["player_bonnie_chip"] = "bonnie_chip",
				["player_glass_pistol"] = "glass_pistol",
				["player_car_keys"] = "falcogini_keys",
				["player_plush_shark"] = "plush_shark",
				["player_wolfs_toolbox"] = "wolfs_toolbox",
				["player_duct_tape"] = "duct_tape",
				["player_escape_plan"] = "escape_plan",
				["player_worn_bandaid"] = "worn_bandaid",
				["player_cup_of_joe_"] = "cup_of_joe",
				["player_rebar_"] = "rebar",
				["player_overkill_rush_"] = "overkill_rush",
				["player_pink_slip_"] = "pink_slip",
				["player_the_edge_"] = "the_edge",
				["player_jiro_last_wish"] = "jiro_last_wish",
				["player_dearest_possession"] = "dearest_possession",
				["player_viklund_vinyl_"] = "viklund_vinyl",
				["player_lockes_beret_"] = "lockes_beret",
				["player_equalizer_"] = "equalizer",
				["player_crooked_badge_"] = "crooked_badge",
				["player_dead_mans_trigger_"] = "dead_mans_trigger",
				["player_half_a_glass_"] = "half_a_glass",
				["player_familiar_friend_"] = "familiar_friend",
				["player_side_satchel_"] = "side_satchel",
				["player_turron_"] = "turron",
				["player_hippocratic_oath_"] = "hippocratic_oath",
			}
			local already_marked = {}
			for _, item_data in ipairs(my_items) do
				if item_data.id then
					for prefix, logbook_id in pairs(item_mapping) do
						if not already_marked[logbook_id] and string.find(item_data.id, prefix, 1, true) == 1 then
							_G.CSR_Logbook:mark_seen(logbook_id)
							already_marked[logbook_id] = true
							break
						end
					end
				end
			end
		end)
	end

	-- Vanilla calls _max_armor() multiple times during init with different base
	-- values. Wait 0.5s for that to settle, then do spawn-only work that the
	-- refresh's clamp-only stat sync intentionally skips: refill armor to max,
	-- mutate Anarchist's _damage_to_armor in-place, fully regenerate HP.
	DelayedCalls:Add("CSR_UpdateArmorHP_AfterInit", 0.5, function()
		pcall(function()
			local player_unit = managers.player and managers.player:player_unit()
			if not player_unit or not alive(player_unit) then
				return
			end
			local char_dmg = player_unit:character_damage()
			if not char_dmg then
				return
			end

			local new_max_armor = char_dmg:_max_armor()
			if char_dmg.set_armor then
				char_dmg:set_armor(new_max_armor)
			end

			-- One-shot Anarchist scaling. See docstring on CSR_RefreshItemBuffFlags
			-- for the mid-heist-drift caveat.
			local anarchist_scaled = false
			if char_dmg._damage_to_armor and char_dmg._damage_to_armor.armor_value then
				local armor_mult = CSR_ActiveBuffs and CSR_ActiveBuffs.passive_armor_multiplier
				if armor_mult and armor_mult ~= 1.0 then
					char_dmg._damage_to_armor.armor_value = char_dmg._damage_to_armor.armor_value * armor_mult
					anarchist_scaled = true
				end
			end

			if char_dmg._regenerated then
				char_dmg:_regenerated()
			end
			if char_dmg._send_set_health then
				char_dmg:_send_set_health()
			end

			CSR_pm_dbg(
				string.format(
					"spawn delayed: armor_max=%.1f, HP fully regen'd, anarchist_scaled=%s",
					new_max_armor,
					tostring(anarchist_scaled)
				)
			)
		end)
	end)
end)

-- === DUCT TAPE: Hook on crew_ability_upgrade_value for interaction speed ===
-- Additively stacks with crew bonus "Quick"
local original_crew_ability_upgrade_value = PlayerManager.crew_ability_upgrade_value
_G.CSR_SafeOverride(
	PlayerManager,
	"crew_ability_upgrade_value",
	"Duct Tape",
	original_crew_ability_upgrade_value,
	function(self, category, default)
		local base_value = original_crew_ability_upgrade_value(self, category, default)

		-- Apply bonus only to crew_interact
		if category ~= "crew_interact" then
			return base_value
		end

		-- DEBUG: Log what vanilla function returns

		-- Check if there is DUCT TAPE
		if not CSR_ActiveBuffs or not CSR_ActiveBuffs.duct_tape or not CSR_ActiveBuffs.duct_tape_stacks then
			return base_value
		end

		-- Skip revive/uncuff interactions — Duct Tape should not speed those up.
		local cur_tweak = _G.CSR_CurrentInteractionTweak
		if cur_tweak == "revive" or cur_tweak == "free" then
			return base_value
		end

		-- ADDITIVE SPEED STACKING (in percent):
		-- base_value can be either percent bonus (75), or time multiplier (0.25)
		-- If this is percent bonus - just add
		-- If this is time multiplier - convert to speed, add, convert back

		local duct_tape_stacks = CSR_ActiveBuffs.duct_tape_stacks
		local C = _G.CSR_ItemConstants or {}
		local duct_tape_speed_bonus = (C.duct_tape_speed_bonus or 0.05) * 100 * duct_tape_stacks

		-- ALWAYS treat as time multiplier (smaller = faster)
		-- Vanilla always returns time multiplier (e.g. 0.25 for Quick with 3 bots = 4x faster)

		-- Convert time multiplier to speed bonus percent: speed = (1/time - 1) * 100
		local crew_speed_bonus = (1 / base_value - 1) * 100
		local total_speed = crew_speed_bonus + duct_tape_speed_bonus

		-- Convert back to time multiplier: time = 1 / (1 + speed/100)
		local final_value = 1 / (1 + total_speed / 100)

		return final_value
	end
)

-- Wrapper for skill_dodge_chance for application dodge modifiers
local original_skill_dodge_chance = PlayerManager.skill_dodge_chance

-- Returns vanilla dodge (suit + skills + perk deck) without CSR item bonuses.
-- Used by stats_page.lua to display accurate base dodge.
function PlayerManager:csr_base_dodge_chance()
	return original_skill_dodge_chance(self) or 0
end

_G.CSR_SafeOverride(
	PlayerManager,
	"skill_dodge_chance",
	"Falcogini Keys",
	original_skill_dodge_chance,
	function(self, running, crouching, on_zipline)
		local base_dodge = original_skill_dodge_chance(self, running, crouching, on_zipline)

		if not CSR_ActiveBuffs then
			return base_dodge
		end

		local result = base_dodge

		-- Apply bonus from CAR KEYS (multiplicatively)
		-- Formula: final = 1 - (1 - base) × (1 - keys)
		-- Guarantees result never reaches 100%
		if CSR_ActiveBuffs.car_keys and CSR_ActiveBuffs.car_keys_dodge_bonus then
			local keys_dodge = CSR_ActiveBuffs.car_keys_dodge_bonus
			-- Multiplicative combination (like in RoR2)
			result = 1 - (1 - base_dodge) * (1 - keys_dodge)
		end

		-- Apply debuff from DOZER GUIDE (additively, after combination)
		if CSR_ActiveBuffs.dozer_guide_dodge_debuff and CSR_ActiveBuffs.dozer_guide_dodge_penalty then
			-- Dodge in PD2 measured from 0 to 1 (0% - 100%)
			-- -5 units = -0.05 (5%)
			local penalty = CSR_ActiveBuffs.dozer_guide_dodge_penalty / 100
			result = math.max(0, result - penalty)
		end

		-- Limit result from 0 to 1 (0% - 100%)
		result = math.max(0, math.min(1, result))

		return result
	end
)

-- === HP: Hook on health_skill_multiplier for application HP bonuses ===
-- v2.50: ADDITIVELY add bonuses, then MULTIPLICATIVELY apply Glass Pistol
-- Step 1: base + hp_bonus (additive: passive, DOG TAGS)
-- Step 2: result × glass_pistol_hp_mult (multiplicative: divide by 2)
-- _raw_max_health() = (HEALTH_INIT + addend) × health_skill_multiplier()
local original_health_skill_multiplier = PlayerManager.health_skill_multiplier
_G.CSR_SafeOverride(
	PlayerManager,
	"health_skill_multiplier",
	"Dog Tags",
	original_health_skill_multiplier,
	function(self)
		local base = original_health_skill_multiplier(self)
		local result = base

		-- Guard: only apply CSR modifiers during active Crime Spree
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return result
		end

		-- Step 1: Apply additive bonuses (passive progression + DOG TAGS)
		if CSR_ActiveBuffs and CSR_ActiveBuffs.hp_bonus and CSR_ActiveBuffs.hp_bonus ~= 0 then
			result = result + CSR_ActiveBuffs.hp_bonus

			-- HP mult log removed (too frequent, called on every health_skill_multiplier)
		end

		-- Step 2: Apply Glass Pistol multiplicative penalty (divide by 2)
		local glass_mult = CSR_ActiveBuffs and CSR_ActiveBuffs.glass_pistol_hp_mult
		if glass_mult then
			local before_glass = result
			result = result * glass_mult
		end

		-- Step 3: Apply Civilian Guilt penalty (per kill, max reduction)
		local guilt_kills = _G.CSR_CivilianGuiltKills or 0
		if CSR_ActiveBuffs and CSR_ActiveBuffs.civilian_guilt and guilt_kills > 0 then
			local GC = _G.CSR_ItemConstants or {}
			local guilt_reduction =
				math.min(guilt_kills * (GC.guilt_hp_penalty or 0.05), (GC.guilt_max_penalty or 0.30))
			result = result * (1 - guilt_reduction)
		end

		return math.max(0.01, result) -- Ensure positive value
	end
)

-- === STAMINA: Hook on stamina_multiplier for CUP OF JOE (additive +10% per stack) ===
-- PlayerMovement:_max_stamina() = base * body_armor_value("stamina") * stamina_multiplier()
-- We add cup_of_joe_stamina_bonus on top of the vanilla multiplier so the stamina pool
-- grows linearly with stacks (1 stack: ×1.10, 2 stacks: ×1.20, etc.).
local original_stamina_multiplier = PlayerManager.stamina_multiplier
_G.CSR_SafeOverride(PlayerManager, "stamina_multiplier", "Cup of Joe", original_stamina_multiplier, function(self)
	local base = original_stamina_multiplier(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return base
	end
	if CSR_ActiveBuffs and CSR_ActiveBuffs.cup_of_joe_stamina_bonus then
		return base + CSR_ActiveBuffs.cup_of_joe_stamina_bonus
	end
	return base
end)

-- v2.49: armor_skill_multiplier hook REMOVED (was duplicating _max_armor hook from player_passives.lua)
-- Armor is now applied ONLY through PlayerDamage:_max_armor() in player_passives.lua

-- === BULLSEYE SCALING: headshot armor regen scales with CS rank armor bonus ===
-- Vanilla Bullseye restores a fixed amount of armor on headshot.
-- We add extra armor proportional to the CSR passive armor multiplier from rank.
-- PreHook saves cooldown timestamp, PostHook checks if vanilla fired, then adds bonus.

Hooks:PreHook(PlayerManager, "on_headshot_dealt", "CSR_Bullseye_Pre", function(self)
	self._csr_bullseye_pre_t = self._on_headshot_dealt_t
end)

Hooks:PostHook(PlayerManager, "on_headshot_dealt", "CSR_Bullseye_Post", function(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end

	-- Check if vanilla actually triggered (cooldown timestamp was updated)
	if self._on_headshot_dealt_t == self._csr_bullseye_pre_t then
		return
	end

	local C = _G.CSR_ItemConstants or {}
	local cs_level = managers.crime_spree:server_spree_level() or 0
	if cs_level <= 0 then
		return
	end

	local bullseye_mult = 1 + (C.bullseye_bonus_per_level or 0.01) * cs_level
	if bullseye_mult <= 1.0 then
		return
	end

	local player_unit = self:player_unit()
	if not player_unit then
		return
	end
	local damage_ext = player_unit:character_damage()
	if not damage_ext or not damage_ext.restore_armor then
		return
	end

	local base_value = self:upgrade_value("player", "headshot_regen_armor_bonus", 0)
	if base_value <= 0 then
		return
	end

	-- Add extra armor: base_value × (bullseye_mult - 1)
	local bonus = base_value * (bullseye_mult - 1)
	damage_ext:restore_armor(bonus)
end)
