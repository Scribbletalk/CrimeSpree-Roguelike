-- OVERKILL RUSH - Kill Streak: Fire Rate + Reload Speed
-- Each kill grants a flat bonus that accumulates up to 4 kill stacks
-- Bonus per kill: (item_stacks + 1) * 1%
-- 1 item: +2% per kill (max +8%), 2 items: +3% per kill (max +12%), etc.
-- All stacks expire 4 seconds after last kill

if not RequiredScript then
	return
end



ModifierOverkillRush = ModifierOverkillRush or class(CSRBaseModifier)
ModifierOverkillRush.desc_id = "csr_overkill_rush_desc"

-- Kill streak state
_G.CSR_OverkillRush = _G.CSR_OverkillRush or {
	kill_stacks = 0,
	last_kill_time = -999
}

-- Read constants from base_modifier.lua (change values there)
local OVERKILL_RUSH_MAX_KILL_STACKS = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_max_stacks   or 4
local OVERKILL_RUSH_DURATION        = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_duration      or 4.0
local OVERKILL_RUSH_FIRST_BONUS     = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_first_bonus   or 0.02
local OVERKILL_RUSH_EXTRA_BONUS     = _G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_extra_bonus   or 0.01

-- Count how many Overkill Rush items player has
local function get_item_stacks()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end
	local count = 0
	for _, mod in ipairs(managers.crime_spree:active_modifiers() or {}) do
		if mod.id and string.find(mod.id, "player_overkill_rush_", 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Get current active bonus (0 if expired or no items)
-- Formula: kill_stacks * (item_stacks + 1) * extra_bonus
-- 1 item: 2%/4%/6%/8% for 1/2/3/4 kills, 2 items: 3%/6%/9%/12%, etc.
function CSR_OverkillRush_GetActiveBonus()
	local state = _G.CSR_OverkillRush
	if state.kill_stacks <= 0 then return 0 end

	local ok, current_time = pcall(function() return TimerManager:game():time() end)
	if not ok then return 0 end

	if current_time - state.last_kill_time >= OVERKILL_RUSH_DURATION then
		state.kill_stacks = 0
		return 0
	end

	local item_stacks = get_item_stacks()
	if item_stacks <= 0 then return 0 end

	return state.kill_stacks * (item_stacks + 1) * OVERKILL_RUSH_EXTRA_BONUS
end

-- Kill handler
local function on_kill(self, attack_data)
	-- Check that the killer is the local player
	if not attack_data or not attack_data.attacker_unit then return end
	if not attack_data.attacker_unit:base() then return end
	if not attack_data.attacker_unit:base().is_local_player then return end

	-- Check that the enemy just died
	if not self._dead then return end

	-- Guard against multiple triggers on the same enemy
	if self._csr_overkill_processed then return end
	self._csr_overkill_processed = true

	local item_stacks = get_item_stacks()
	if item_stacks <= 0 then return end

	local state = _G.CSR_OverkillRush
	local ok, current_time = pcall(function() return TimerManager:game():time() end)
	if not ok then return end

	-- Reset if streak expired
	if current_time - state.last_kill_time >= OVERKILL_RUSH_DURATION then
		state.kill_stacks = 0
	end

	-- Add kill stack (max 4)
	state.kill_stacks = math.min(state.kill_stacks + 1, OVERKILL_RUSH_MAX_KILL_STACKS)
	state.last_kill_time = current_time

		.. " (bonus: +" .. string.format("%.1f", CSR_OverkillRush_GetActiveBonus() * 100) .. "%)")
end

-- Hooks on all damage types
if CopDamage then
	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_OverkillRush_Bullet", function(self, attack_data)
		on_kill(self, attack_data)
	end)

	if CopDamage.damage_melee then
		Hooks:PostHook(CopDamage, "damage_melee", "CSR_OverkillRush_Melee", function(self, attack_data)
			on_kill(self, attack_data)
		end)
	end

	if CopDamage.damage_explosion then
		Hooks:PostHook(CopDamage, "damage_explosion", "CSR_OverkillRush_Explosion", function(self, attack_data)
			on_kill(self, attack_data)
		end)
	end

	if CopDamage.damage_dot then
		Hooks:PostHook(CopDamage, "damage_dot", "CSR_OverkillRush_Dot", function(self, attack_data)
			on_kill(self, attack_data)
		end)
	end

else
end

