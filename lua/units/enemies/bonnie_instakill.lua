-- Bonnie's Lucky Chip - Instant Kill Mechanic
-- Chance to instantly kill an enemy on hit

if not RequiredScript then
	return
end



-- Instakill chance (5% base, scales with stacks)
local INSTAKILL_CHANCE = 5  -- 5% per stack

-- Cooldown system to prevent spam (miniguns, shotguns)
local INSTAKILL_COOLDOWN = 1.5  -- seconds between instakills
local last_instakill_time = 0

-- Count Bonnie's Lucky Chip stacks
local function count_bonnie_chips()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end

	local count = 0
	local active_modifiers = managers.crime_spree:active_modifiers() or {}
	for _, mod_data in ipairs(active_modifiers) do
		if mod_data.id and string.find(mod_data.id, "player_bonnie_chip", 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Hook on enemy damage
Hooks:PostHook(CopDamage, "damage_bullet", "CSR_BonnieChipInstakill", function(self, attack_data)
	-- Guard: damage must come from a player
	if not attack_data or not attack_data.attacker_unit or not attack_data.attacker_unit:base() then
		return
	end

	-- Guard: attacker must be the local player
	if not attack_data.attacker_unit:base().is_local_player then
		return
	end

	-- Guard: player must have Bonnie's Lucky Chip
	local chip_count = count_bonnie_chips()
	if chip_count == 0 then
		return
	end

	-- Guard: enemy must still be alive
	if not self._unit or not alive(self._unit) or self._dead then
		return
	end

	-- Check cooldown (protection against minigun/shotgun spam)
	local current_time = TimerManager:game():time()
	local time_since_last = current_time - last_instakill_time
	if time_since_last < INSTAKILL_COOLDOWN then
		-- Cooldown active, skip the roll
		return
	end

	-- Roll instakill chance (per stack)
	-- Formula: 1 - (1 - chance)^stacks (independent rolls)
	local total_chance = 1 - math.pow(1 - INSTAKILL_CHANCE / 100, chip_count)
	local roll = math.random()

	if roll <= total_chance then
		-- Update last instakill timestamp
		last_instakill_time = current_time

		-- Instantly kill the enemy (crash-safe)
		if self._unit and alive(self._unit) and not self._dead then
			local success, err = pcall(function()
				-- Use damage_explosion for instant kill
				self:damage_explosion({
					damage = 999999,
					variant = "explosion",
					col_ray = attack_data.col_ray,
					attacker_unit = attack_data.attacker_unit
				})
			end)

			if not success then
			end
		end
	end
end)

