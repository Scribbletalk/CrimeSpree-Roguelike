-- Crime Spree Roguelike - Player Damage Hooks
-- Armor buff and health regeneration

if not RequiredScript then
	return
end

-- Save original _max_health for Stats Page and dearestpossession.lua.
_G.CSR_Original_MaxHealth = PlayerDamage._max_health

-- v2.51: CRITICAL FIX - Function override to properly apply armor modifiers
-- PostHook doesn't work because self._armor_init is 0 when hook fires (vanilla hasn't calculated it yet)
-- Solution: Override function, call original to get base value, apply modifiers, return result
-- No infinite recursion because we call saved local reference, not self:_max_armor()

-- Save original for Stats Page AND for our override
_G.CSR_Original_MaxArmor = PlayerDamage._max_armor
local original_max_armor = PlayerDamage._max_armor

_G.CSR_SafeOverride(PlayerDamage, "_max_armor", "Passive Progression", original_max_armor, function(self)
	-- Anti-recursion guard: vanilla set_armor() calls self:_max_armor() internally multiple times
	-- (lines 2047, 2056, 2059 in playerdamage.lua) which causes Glass Pistol to stack on each call
	-- e.g. 22.1 -> 11.8 -> 6.3 -> 3.4 (3 levels deep = armor/8 instead of armor/2)
	if self._csr_in_max_armor then
		return original_max_armor(self)
	end
	self._csr_in_max_armor = true

	-- Call vanilla (or other mods) to get base armor
	local base_armor = original_max_armor(self)

	self._csr_in_max_armor = false

	if not base_armor or base_armor == 0 then
		return base_armor -- No armor to modify
	end

	local result = base_armor

	-- Guard: only apply CSR modifiers during active Crime Spree
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return result
	end

	-- Step 1: Apply passive/item ADDITIVE bonuses
	local additive_mult = CSR_ActiveBuffs and CSR_ActiveBuffs.passive_armor_multiplier
	if additive_mult and additive_mult ~= 1.0 then
		result = result * additive_mult
	end

	-- Step 2: Apply Glass Pistol MULTIPLICATIVE penalty (divide by 2^stacks)
	local glass_mult = CSR_ActiveBuffs and CSR_ActiveBuffs.glass_pistol_armor_mult
	if glass_mult then
		result = result * glass_mult
	end

	-- Dearest Possession's shield is NOT folded into _max_armor anymore. It lives
	-- in self._csr_dp_armor as an external absorb pool that damage drains first
	-- (see dearestpossession.lua's _calc_armor_damage PreHook). Leaving it out
	-- here is what lets the white armor bar stay full while the blinking shield
	-- chunk drains — adding it back would re-inflate _max_armor and base armor
	-- would visually shrink in lockstep with the shield again.

	return result
end)

-- Hook on init — initialise regen timers when the player spawns
Hooks:PostHook(PlayerDamage, "init", "CSR_InitHealthRegen", function(self)
	self._csr_health_regen_timer = 0
	self._csr_last_damage_time = 0
end)

-- Hook on update — passive health regeneration (flat HP per level, every N seconds)
Hooks:PostHook(PlayerDamage, "update", "CSR_HealthRegen", function(self, unit, t, dt)
	-- Only run during Crime Spree
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end

	-- Guard: player must be alive and not in bleedout
	if self:is_downed() or self:dead() then
		return
	end

	-- Guard: passive progression must be active
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.passive_progression then
		return
	end

	local progression_tiers = CSR_ActiveBuffs.progression_tiers or 0
	if progression_tiers <= 0 then
		return
	end

	-- Disable passive regen for Berserker/Frenzy builds (items like Worn Band-Aid still work)
	local has_berserker = managers.player
		and (
			managers.player:has_category_upgrade("player", "damage_health_ratio_multiplier")
			or managers.player:has_category_upgrade("player", "melee_damage_health_ratio_multiplier")
			or managers.player:has_category_upgrade("player", "max_health_reduction")
		)

	-- Passive regen: flat display HP per CS level every N seconds
	local C = _G.CSR_ItemConstants or {}
	local regen_interval = C.passive_regen_interval or 5.0
	local flat_hp_per_tier = has_berserker and 0 or (C.passive_regen_flat_per_level or 0.02)

	self._csr_health_regen_timer = (self._csr_health_regen_timer or 0) + dt

	if self._csr_health_regen_timer >= regen_interval then
		self._csr_health_regen_timer = 0

		-- VHUDPlus: restart regen cycle timer (only if Worn Band-Aid is active)
		if CSR_VHUDPlusEvent and CSR_ActiveBuffs and CSR_ActiveBuffs.worn_bandaid_regen_pct then
			CSR_VHUDPlusEvent("timed_buff", "activate", "csr_bandaid_regen", {
				t = TimerManager:game():time(),
				duration = regen_interval,
			})
		end
		if CSR_WFHudEvent and CSR_ActiveBuffs and CSR_ActiveBuffs.worn_bandaid_regen_pct then
			CSR_WFHudEvent("activate", "bandaid_regen", { duration = regen_interval })
		end
		if CSR_PocoHudEvent and CSR_ActiveBuffs and CSR_ActiveBuffs.worn_bandaid_regen_pct then
			CSR_PocoHudEvent("activate", "bandaid_regen", { duration = regen_interval })
		end

		local current_hp = self:get_real_health()
		local max_hp = self:_max_health()

		-- Run regen even at full HP and pass an uncapped target. If DP is
		-- inactive, vanilla set_health clamps internally; if DP is active,
		-- the overheal flows through its interceptor and converts to shields.
		-- Passive regen (flat display HP per level, converted to internal units)
		local display_scale = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 10
		local passive_regen = (flat_hp_per_tier * progression_tiers) / display_scale

		-- WORN BAND-AID regen (hyperbolic % of max HP, applied directly in internal units)
		-- Blocked by "Block Item Healing" setting (Berserker/Frenzy builds)
		local bandaid_regen = 0
		if
			CSR_ActiveBuffs
			and CSR_ActiveBuffs.worn_bandaid_regen_pct
			and not (CSR_Settings and CSR_Settings.values.block_item_healing)
		then
			bandaid_regen = max_hp * CSR_ActiveBuffs.worn_bandaid_regen_pct
		end

		local regen_amount = passive_regen + bandaid_regen
		if regen_amount > 0 then
			self:set_health(current_hp + regen_amount)
		end
	end
end)

-- Track the last damage timestamp (reserved for a future regen-cooldown feature)
Hooks:PostHook(PlayerDamage, "damage_bullet", "CSR_TrackDamage", function(self)
	self._csr_last_damage_time = TimerManager:game():time()
end)

Hooks:PostHook(PlayerDamage, "damage_melee", "CSR_TrackDamageMelee", function(self)
	self._csr_last_damage_time = TimerManager:game():time()
end)

Hooks:PostHook(PlayerDamage, "damage_explosion", "CSR_TrackDamageExplosion", function(self)
	self._csr_last_damage_time = TimerManager:game():time()
end)
