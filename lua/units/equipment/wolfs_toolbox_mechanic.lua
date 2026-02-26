-- Wolf's Toolbox Mechanic - Drill/Saw timer reduction on kills
-- Always triggers (no RNG), different values for normal/special enemies
-- Formula: Normal -0.1s base + -0.05s per stack, Special -1s base + -0.5s per stack
-- Does NOT affect jammed drills

if not RequiredScript then
	return
end



-- === GLOBAL VARIABLES ===
CSR_WolfsToolbox = CSR_WolfsToolbox or {
	stacks = 0,                  -- Number of Wolf's Toolbox stacks
	active_equipment = {}        -- Table of active drills/saws: {unit = {is_active, equipment_type}}
}

-- === STACK COUNTING ON SPAWN ===
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_WolfsToolboxInit", function(self)
	-- Reset state
	CSR_WolfsToolbox.active_equipment = {}

	-- Check Crime Spree
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		CSR_WolfsToolbox.stacks = 0
		return
	end

	-- Count Wolf's Toolbox stacks
	local stacks = 0
	local modifiers = managers.crime_spree:active_modifiers() or {}

	for _, mod in ipairs(modifiers) do
		if mod.id and string.find(mod.id, "player_wolfs_toolbox", 1, true) then
			stacks = stacks + 1
		end
	end

	-- Update global variables
	CSR_WolfsToolbox.stacks = stacks

	if stacks > 0 then
	else
	end
end)

-- === KILL TRACKING ===
-- Hook on enemy death (same as bonnie_instakill.lua)
Hooks:PostHook(CopDamage, "die", "CSR_WolfsToolboxKillTracking", function(self, attack_data)
	-- Check if mechanic is active
	if CSR_WolfsToolbox.stacks == 0 then
		return
	end

	-- Check if damage is from player
	if not attack_data or not attack_data.attacker_unit or not attack_data.attacker_unit:base() then
		return
	end

	if not attack_data.attacker_unit:base().is_local_player then
		return
	end

	-- Check if there's active equipment (drill/saw)
	local has_active_equipment = false
	for unit, data in pairs(CSR_WolfsToolbox.active_equipment) do
		if alive(unit) and data.is_active then
			has_active_equipment = true
			break
		end
	end

	if not has_active_equipment then
		-- No active drills/saws - don't count kill
		return
	end

	-- === MECHANIC: Always triggers, different values for normal/special ===
	-- Check if enemy is special unit
	local is_special = false
	if self._unit and self._unit:base() then
		local char_tweak = self._char_tweak
		-- Check enemy category (tank, shield, taser, medic, spooc, etc.)
		if char_tweak and char_tweak.priority_shout then
			is_special = true
		end
	end

	-- Calculate time reduction based on enemy type
	-- Formula: base + (additional_stacks × bonus)
	-- 1st stack gives base reduction, additional stacks give bonus
	local normal_reduction = 0.1 + ((CSR_WolfsToolbox.stacks - 1) * 0.05)
	local special_reduction = 1.0 + ((CSR_WolfsToolbox.stacks - 1) * 0.5)

	-- Use ONLY the appropriate reduction (not both)
	local reduction_seconds = is_special and special_reduction or normal_reduction

	local enemy_type = is_special and "special" or "normal"

	-- Reduce timers of all active drills/saws
	local reduced_count = 0

	for unit, data in pairs(CSR_WolfsToolbox.active_equipment) do
		if alive(unit) and data.is_active then
			-- === JAMMED DRILL FIX ===
			-- Check if drill/saw is NOT jammed
			local base = unit:base()
			if base and base._jammed then
				goto continue
			end

			local timer_gui = unit:timer_gui()
			if timer_gui and timer_gui._current_timer and timer_gui._current_timer > 0 then
				local old_timer = timer_gui._current_timer
				timer_gui._current_timer = math.max(0, timer_gui._current_timer - reduction_seconds)
				reduced_count = reduced_count + 1

				        string.format("%.1fs", old_timer) .. " → " ..
				        string.format("%.1fs", timer_gui._current_timer) ..
				        " (-" .. string.format("%.2fs", reduction_seconds) .. ")")
			end

			::continue::
		end
	end

	if reduced_count > 0 then
		        string.format("%.2fs", reduction_seconds) .. " for " ..
		        reduced_count .. " devices")
	end
end)

-- === TRACKING ACTIVE DRILLS/SAWS ===
-- Hook on TimerGui:_start to register active devices
Hooks:PostHook(TimerGui, "_start", "CSR_WolfsToolboxTimerStart", function(self, timer)
	-- Check if mechanic is active
	if CSR_WolfsToolbox.stacks == 0 then
		return
	end

	local unit = self._unit
	if not unit or not alive(unit) then
		return
	end

	-- Check equipment type
	local base = unit:base()
	if not base then
		return
	end

	-- Filter only drills and saws (NOT thermite, NOT hacking)
	local is_valid_equipment = false
	local equipment_type = "unknown"

	-- Check equipment type
	-- is_drill is a BOOLEAN property, NOT a function!
	-- is_saw is a BOOLEAN property
	if base.is_drill then
		is_valid_equipment = true
		equipment_type = "drill"
	elseif base.is_saw then
		is_valid_equipment = true
		equipment_type = "saw"
	end

	if not is_valid_equipment then
		return
	end

	-- Register as active device
	CSR_WolfsToolbox.active_equipment[unit] = {
		is_active = true,
		equipment_type = equipment_type
	}

end)

-- Hook on TimerGui:done to remove finished devices
Hooks:PostHook(TimerGui, "done", "CSR_WolfsToolboxTimerDone", function(self)
	local unit = self._unit
	if unit and CSR_WolfsToolbox.active_equipment[unit] then
		local equipment_type = CSR_WolfsToolbox.active_equipment[unit].equipment_type
		CSR_WolfsToolbox.active_equipment[unit] = nil
	end
end)

