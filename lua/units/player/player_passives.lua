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

function PlayerDamage:_max_armor()
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

	-- Step 3: Add Dearest Possession temporary armor bonus (flat, after all multipliers)
	local dp_bonus = self._csr_dp_armor or 0
	if dp_bonus > 0 then
		result = result + dp_bonus
	end

	return result
end

-- Hook on init — initialise regen timers when the player spawns
Hooks:PostHook(PlayerDamage, "init", "CSR_InitHealthRegen", function(self)
	self._csr_health_regen_timer = 0
	self._csr_last_damage_time = 0
end)

-- Hook on update — passive health regeneration (every 10 seconds)
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

	-- Passive regen: +0.01% max HP per CS level every 10 seconds
	local regen_interval = 10.0
	local regen_percent_per_tier = 0.0001

	self._csr_health_regen_timer = (self._csr_health_regen_timer or 0) + dt

	if self._csr_health_regen_timer >= regen_interval then
		self._csr_health_regen_timer = 0

		local current_hp = self:get_real_health()
		local max_hp = self:_max_health()

		if current_hp < max_hp then
			-- Passive regen (percentage of max HP)
			local passive_regen = max_hp * regen_percent_per_tier * progression_tiers

			-- WORN BAND-AID regen (flat value, converted to internal units)
			local bandaid_regen = 0
			if CSR_ActiveBuffs and CSR_ActiveBuffs.worn_bandaid_regen then
				local display_scale = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 5
				bandaid_regen = CSR_ActiveBuffs.worn_bandaid_regen / display_scale
			end

			-- Total regen
			local regen_amount = passive_regen + bandaid_regen
			local new_hp = math.min(current_hp + regen_amount, max_hp)

			self:set_health(new_hp)

			if regen_amount > 0 then
			end
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

