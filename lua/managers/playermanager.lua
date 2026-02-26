-- Crime Spree Roguelike Alpha 1 - Apply effects at mission start

if not RequiredScript then
	return
end



-- Global variable for storing active buffs
CSR_ActiveBuffs = CSR_ActiveBuffs or {}

-- Function to count modifier stacks by id prefix
local function count_modifier_stacks(id_prefix)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end

	local count = 0
	local active_modifiers = managers.crime_spree:active_modifiers() or {}
	for _, mod_data in ipairs(active_modifiers) do
		-- Check if id starts with the prefix
		if mod_data.id and string.find(mod_data.id, id_prefix, 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Hook on player spawn - apply buffs after character creation
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_ApplyBuffs", function(self, id, unit)

	-- Reset active buffs
	CSR_ActiveBuffs = {}

	-- Check if we're in Crime Spree
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end


	local player_unit = unit or self:player_unit()
	if not player_unit then
		return
	end

	-- === PASSIVE PROGRESSION: each CS level ===
	local cs_level = managers.crime_spree:spree_level() or 0
	local progression_tiers = cs_level  -- Each level = 1 tier

	if progression_tiers > 0 then

		CSR_ActiveBuffs.passive_progression = true
		CSR_ActiveBuffs.progression_tiers = progression_tiers

		-- ✅ NERF: +0.1% HP per level (5% per 50 levels, 10% per 100 levels)
		local passive_hp_mult = 1 + (0.001 * progression_tiers)
		CSR_ActiveBuffs.passive_hp_multiplier = passive_hp_mult

		-- +0.05% All Damage per level (was +0.5% per 10 levels)
		local passive_dmg_mult = 1 + (0.0005 * progression_tiers)
		CSR_ActiveBuffs.passive_damage_multiplier = passive_dmg_mult
	end

	-- === ARMOR (passive + DOZER GUIDE) ===
	local total_armor_bonus = 0.0

	-- ✅ NERF: +0.1% per level (5% per 50 levels, 10% per 100 levels)
	if progression_tiers > 0 then
		total_armor_bonus = total_armor_bonus + (0.001 * progression_tiers)
	end

	-- DOZER GUIDE: +50% per stack
	local dozer_stacks = count_modifier_stacks("player_dozer_guide")
	if dozer_stacks > 0 then
		CSR_ActiveBuffs.dozer_guide = true
		CSR_ActiveBuffs.dozer_guide_stacks = dozer_stacks
		local dozer_armor_bonus = 0.5 * dozer_stacks
		total_armor_bonus = total_armor_bonus + dozer_armor_bonus
	end

	-- v2.50: GLASS PISTOL armor - MULTIPLICATIVE (divide by 2 per stack)
	-- Applied AFTER all additive bonuses in player_passives.lua PostHook
	-- Example: 1 stack = ÷2, 2 stacks = ÷4, 3 stacks = ÷8
	local glass_stacks = count_modifier_stacks("player_glass_pistol")


	if glass_stacks > 0 then
		CSR_ActiveBuffs.glass_pistol = true
		CSR_ActiveBuffs.glass_pistol_stacks = glass_stacks
		CSR_ActiveBuffs.glass_pistol_armor_mult = math.pow(0.5, glass_stacks)  -- Divide by 2^stacks

	end

	-- Apply total Armor multiplier
	if total_armor_bonus ~= 0 then
		CSR_ActiveBuffs.passive_armor_multiplier = 1 + total_armor_bonus
	else
	end

	-- === COLLECT ALL HP BONUSES ===
	-- Bonuses applied via hook health_skill_multiplier() (ADDITIVE with perks)
	-- DO NOT touch _HEALTH_INIT - let game manage HP
	local health_stacks = count_modifier_stacks("player_health_boost")
	local glass_stacks = count_modifier_stacks("player_glass_pistol")
	local total_hp_bonus = 0.0

	-- Passive progression: +0.1% per level (same as armor)
	if progression_tiers > 0 then
		total_hp_bonus = total_hp_bonus + (0.001 * progression_tiers)
	end

	-- DOG TAGS: +10% per stack
	if health_stacks > 0 then
		CSR_ActiveBuffs.health = true
		CSR_ActiveBuffs.health_stacks = health_stacks
		total_hp_bonus = total_hp_bonus + (0.1 * health_stacks)
	end

	-- v2.50: GLASS PISTOL HP - MULTIPLICATIVE (divide by 2 per stack)
	-- Applied AFTER all additive bonuses in health_skill_multiplier hook
	-- Example: 1 stack = ÷2, 2 stacks = ÷4, 3 stacks = ÷8
	if glass_stacks > 0 then
		CSR_ActiveBuffs.glass_pistol = true
		CSR_ActiveBuffs.glass_pistol_stacks = glass_stacks
		CSR_ActiveBuffs.glass_pistol_hp_mult = math.pow(0.5, glass_stacks)  -- Divide by 2^stacks

	end

	-- Save bonus for hook health_skill_multiplier()
	CSR_ActiveBuffs.hp_bonus = total_hp_bonus

	-- === DAMAGE BOOST ===
	local damage_stacks = count_modifier_stacks("player_damage_boost")
	local total_damage_bonus = 0.0  -- Additive percent stacking

	-- Passive progression: +0.5% per tier
	if progression_tiers > 0 then
		total_damage_bonus = total_damage_bonus + (0.005 * progression_tiers)
	end

	-- ✅ NERF: EVIDENCE ROUNDS: +5% per stack (was +10%)
	if damage_stacks > 0 then
		CSR_ActiveBuffs.damage = true
		CSR_ActiveBuffs.damage_stacks = damage_stacks
		total_damage_bonus = total_damage_bonus + (0.05 * damage_stacks)
	end

	-- Total multiplier (1 + total bonus)
	if total_damage_bonus > 0 then
		CSR_ActiveBuffs.damage = true
		CSR_ActiveBuffs.damage_multiplier = 1.0 + total_damage_bonus
	end

	-- === DOZER GUIDE (Contraband rarity) ===
	-- HP already applied above, here only damage/speed/dodge
	if dozer_stacks > 0 then
		-- === WEAPON DAMAGE: +5% per stack (ranged weapons only, separate multiplier) ===
		local dozer_dmg_bonus = 0.05 * dozer_stacks  -- +5% per stack
		CSR_ActiveBuffs.dozer_guide_weapon_multiplier = 1.0 + dozer_dmg_bonus

		-- === MELEE DAMAGE: +5% per stack ===
		CSR_ActiveBuffs.dozer_guide_melee = true
		CSR_ActiveBuffs.dozer_guide_melee_multiplier = 1 + (0.05 * dozer_stacks)

		-- === SPEED DEBUFF: -15% per stack, cap at 40% minimum ===
		CSR_ActiveBuffs.dozer_guide_speed_debuff = true
		local speed_mult = 1 - (0.15 * dozer_stacks)  -- -15% per stack
		CSR_ActiveBuffs.dozer_guide_speed_multiplier = math.max(0.4, speed_mult)  -- Minimum 40%

		-- === DODGE DEBUFF: -5 per stack ===
		CSR_ActiveBuffs.dozer_guide_dodge_debuff = true
		CSR_ActiveBuffs.dozer_guide_dodge_penalty = 5 * dozer_stacks  -- -5 per stack (absolute value)
	end

	-- === GLASS PISTOL (Contraband rarity) ===
	-- v2.50: HP/Armor already applied above (multiplicative), here only damage
	-- Each stack multiplies by 1.5: 1 stack = ×1.5, 2 stacks = ×2.25, 3 stacks = ×3.375
	if glass_stacks > 0 then
		local glass_damage_mult = math.pow(1.5, glass_stacks)  -- 1.5^stacks

		-- === WEAPON DAMAGE: ×1.5 per stack (ranged weapons only, separate multiplier) ===
		CSR_ActiveBuffs.glass_pistol_weapon_multiplier = glass_damage_mult

		-- === MELEE DAMAGE: ×1.5 per stack (MULTIPLICATIVE) ===
		CSR_ActiveBuffs.glass_pistol_melee = true
		CSR_ActiveBuffs.glass_pistol_melee_multiplier = glass_damage_mult  -- 1.5^stacks
	end

	-- === FALCOGINI KEYS / CAR KEYS (Uncommon) ===
	local keys_stacks = count_modifier_stacks("player_car_keys")
	if keys_stacks > 0 then
		CSR_ActiveBuffs.car_keys = true
		CSR_ActiveBuffs.car_keys_stacks = keys_stacks

		-- Hyperbolic formula (like Tougher Times in RoR2)
		-- dodge = 1 - 1/(1 + k × stacks), where k = 1/19 ≈ 0.0526
		-- 1 stack = ~5%, 2 stacks = ~9.5%, 5 stacks = ~20.8%, 10 stacks = ~34.5%
		-- Approaches 100% but never reaches
		local k = 1.0 / 19.0  -- 0.0526
		local dodge_bonus = 1 - 1/(1 + k * keys_stacks)
		CSR_ActiveBuffs.car_keys_dodge_bonus = dodge_bonus  -- Store as fraction (0-1)
	end

	-- === DUCT TAPE (Common) ===
	-- Increases interaction speed (reduces time)
	-- Buffs stack ADDITIVELY with crew bonus from bots
	local duct_tape_stacks = count_modifier_stacks("player_duct_tape")
	if duct_tape_stacks > 0 then
		CSR_ActiveBuffs.duct_tape = true
		CSR_ActiveBuffs.duct_tape_stacks = duct_tape_stacks
	end

	-- === JIRO'S LAST WISH (Rare) ===
	-- Sprint during melee charge + +50% melee damage per stack
	local jiro_stacks = count_modifier_stacks("player_jiro_last_wish")
	if jiro_stacks > 0 then
		CSR_ActiveBuffs.jiro_last_wish = true
		CSR_ActiveBuffs.jiro_last_wish_stacks = jiro_stacks
		CSR_ActiveBuffs.jiro_last_wish_melee_multiplier = 1 + jiro_stacks * 0.5
	end

	-- === DEAREST POSSESSION (Rare) ===
	-- Overheal at full HP → temporary shields (20%/sec decay, cap 50%×stacks of base max HP)
	local dp_stacks = count_modifier_stacks("player_dearest_possession")
	if dp_stacks > 0 then
		CSR_ActiveBuffs.dearest_possession = dp_stacks
	end

	-- === VIKLUND'S VINYL (Rare) ===
	-- Chain damage: 20% damage to 2 nearby enemies (7m radius), wave-based
	local vv_stacks = count_modifier_stacks("player_viklund_vinyl")
	if vv_stacks > 0 then
		CSR_ActiveBuffs.viklund_vinyl = vv_stacks
	end

	-- === EQUALIZER (Contraband) ===
	-- +50%/stack damage to specials (taser, cloaker, medic, dozer, captain, sniper, shield, marshal)
	-- -50%/stack damage to normals (min 1 damage)
	local eq_stacks = count_modifier_stacks("player_equalizer_")
	if eq_stacks > 0 then
		CSR_ActiveBuffs.equalizer = eq_stacks
	end

	-- === CROOKED BADGE (Contraband) ===
	-- +20% enemy force per stack during assault
	-- Every 2 assaults completed -> +1 revive (up to maximum)
	local cb_stacks = count_modifier_stacks("player_crooked_badge_")
	if cb_stacks > 0 then
		CSR_ActiveBuffs.crooked_badge = cb_stacks
	end

	-- === DEAD MAN'S TRIGGER (Contraband) ===
	-- On going down: explosion in radius (300 × stacks cm), 500 × stacks internal dmg to enemies
	-- Allies take 30% of enemy damage (distance falloff applies to both)
	local dmt_stacks = count_modifier_stacks("player_dead_mans_trigger_")
	if dmt_stacks > 0 then
		CSR_ActiveBuffs.dead_mans_trigger = dmt_stacks
	end

	-- === ESCAPE PLAN (Common) ===
	-- Increases movement speed (hyperbolic, cap 50%)
	-- Formula: speed_bonus = 0.5 * (1 - 1/(1 + k * stacks)), k = 3/47
	local sneakers_stacks = count_modifier_stacks("player_escape_plan")
	if sneakers_stacks > 0 then
		CSR_ActiveBuffs.escape_plan = true
		CSR_ActiveBuffs.escape_plan_stacks = sneakers_stacks
		local k = 3.0 / 47.0
		local speed_bonus = 0.5 * (1 - 1 / (1 + k * sneakers_stacks))
		CSR_ActiveBuffs.escape_plan_speed_bonus = speed_bonus
	end

	-- === WORN BAND-AID (REGEN) ===
	-- +5 HP regeneration (flat value, not percentage)
	local bandaid_stacks = count_modifier_stacks("player_worn_bandaid")
	if bandaid_stacks > 0 then
		CSR_ActiveBuffs.worn_bandaid = true
		CSR_ActiveBuffs.worn_bandaid_stacks = bandaid_stacks
		CSR_ActiveBuffs.worn_bandaid_regen = 5 * bandaid_stacks
	end

	-- === CIVILIAN GUILT (Forced loud modifier) ===
	-- Each civilian killed in loud permanently reduces max HP for this mission (-5% per kill, min 30%)
	local guilt_stacks = count_modifier_stacks("csr_civilian_guilt")
	if guilt_stacks > 0 then
		CSR_ActiveBuffs.civilian_guilt = true
	end
	-- Reset kill counter at mission start (effect is mission-scoped)
	_G.CSR_CivilianGuiltKills = 0


	-- Mark active player items as seen in logbook (for discovery system)
	if _G.CSR_Logbook then
		local ok = pcall(function()
			local active_mods = managers.crime_spree and managers.crime_spree:active_modifiers() or {}
			local item_mapping = {
				["player_health_boost"]       = "dog_tags",
				["player_damage_boost"]       = "evidence_rounds",
				["player_dozer_guide"]        = "dozer_guide",
				["player_bonnie_chip"]        = "bonnie_chip",
				["player_glass_pistol"]       = "glass_pistol",
				["player_car_keys"]           = "falcogini_keys",
				["player_plush_shark"]        = "plush_shark",
				["player_wolfs_toolbox"]      = "wolfs_toolbox",
				["player_duct_tape"]          = "duct_tape",
				["player_escape_plan"]        = "escape_plan",
				["player_worn_bandaid"]       = "worn_bandaid",
				["player_rebar_"]             = "rebar",
				["player_overkill_rush_"]     = "overkill_rush",
				["player_pink_slip_"]         = "pink_slip",
				["player_jiro_last_wish"]     = "jiro_last_wish",
				["player_dearest_possession"] = "dearest_possession",
				["player_viklund_vinyl_"]     = "viklund_vinyl",
				["player_equalizer_"]         = "equalizer",
				["player_crooked_badge_"]     = "crooked_badge",
				["player_dead_mans_trigger_"] = "dead_mans_trigger"
			}
			local already_marked = {}
			for _, mod_data in ipairs(active_mods) do
				if mod_data.id then
					for prefix, logbook_id in pairs(item_mapping) do
						if not already_marked[logbook_id] and string.find(mod_data.id, prefix, 1, true) == 1 then
							_G.CSR_Logbook:mark_seen(logbook_id)
							already_marked[logbook_id] = true
							break
						end
					end
				end
			end
		end)
	end

	-- v2.50: Full buff dump in debug mode

	-- v2.50: CRITICAL - Delay armor/HP update until vanilla finishes initialization
	-- Problem: Vanilla calls _max_armor() multiple times during init with different base values
	-- Solution: Wait 0.5s for vanilla to finish, THEN update armor/HP to correct values
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


			-- ARMOR: Get max with our multiplier applied
			local new_max_armor = char_dmg:_max_armor()

			-- Set current armor directly to new max
			if char_dmg.set_armor then
				char_dmg:set_armor(new_max_armor)
			end

			-- HP: Regenerate to full (sets health = max AND clears _said_hurt flag)
			if char_dmg._regenerated then
				char_dmg:_regenerated()
			end

			-- Force HUD update
			if char_dmg._send_set_health then
				char_dmg:_send_set_health()
			end

		end)
	end)
end)


-- === DUCT TAPE: Hook on crew_ability_upgrade_value for interaction speed ===
-- Additively stacks with crew bonus "Quick"
local original_crew_ability_upgrade_value = PlayerManager.crew_ability_upgrade_value
function PlayerManager:crew_ability_upgrade_value(category, default)
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

	-- ADDITIVE SPEED STACKING (in percent):
	-- base_value can be either percent bonus (75), or time multiplier (0.25)
	-- If this is percent bonus - just add
	-- If this is time multiplier - convert to speed, add, convert back

	local duct_tape_stacks = CSR_ActiveBuffs.duct_tape_stacks
	local duct_tape_speed_bonus = 5 * duct_tape_stacks  -- +5% per stack

	-- ALWAYS treat as time multiplier (smaller = faster)
	-- Vanilla always returns time multiplier (e.g. 0.25 for Quick with 3 bots = 4x faster)

	-- Convert time multiplier to speed bonus percent: speed = (1/time - 1) * 100
	local crew_speed_bonus = (1 / base_value - 1) * 100
	local total_speed = crew_speed_bonus + duct_tape_speed_bonus

	-- Convert back to time multiplier: time = 1 / (1 + speed/100)
	local final_value = 1 / (1 + total_speed / 100)


	return final_value
end

-- Wrapper for skill_dodge_chance for application dodge modifiers
local original_skill_dodge_chance = PlayerManager.skill_dodge_chance
function PlayerManager:skill_dodge_chance(running, crouching, on_zipline)
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

-- === HP: Hook on health_skill_multiplier for application HP bonuses ===
-- v2.50: ADDITIVELY add bonuses, then MULTIPLICATIVELY apply Glass Pistol
-- Step 1: base + hp_bonus (additive: passive, DOG TAGS)
-- Step 2: result × glass_pistol_hp_mult (multiplicative: divide by 2)
-- _raw_max_health() = (HEALTH_INIT + addend) × health_skill_multiplier()
local original_health_skill_multiplier = PlayerManager.health_skill_multiplier
function PlayerManager:health_skill_multiplier()
	local base = original_health_skill_multiplier(self)
	local result = base

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

	-- Step 3: Apply Civilian Guilt penalty (5% per kill, max 70% reduction, min 30% HP remaining)
	local guilt_kills = _G.CSR_CivilianGuiltKills or 0
	if CSR_ActiveBuffs and CSR_ActiveBuffs.civilian_guilt and guilt_kills > 0 then
		local guilt_reduction = math.min(guilt_kills * 0.05, 0.70)
		result = result * (1 - guilt_reduction)
	end

	return math.max(0.01, result)  -- Ensure positive value
end

-- v2.49: armor_skill_multiplier hook REMOVED (was duplicating _max_armor hook from player_passives.lua)
-- Armor is now applied ONLY through PlayerDamage:_max_armor() in player_passives.lua
