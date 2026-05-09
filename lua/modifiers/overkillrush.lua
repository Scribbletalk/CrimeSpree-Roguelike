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
	last_kill_time = -999,
}

-- Read constants from _G.CSR_ItemConstants per call so debug-menu retuning
-- takes effect without a game restart.
local function CC_max_kill_stacks()
	return (_G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_max_stacks) or 4
end
local function CC_duration()
	return (_G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_duration) or 4.0
end
local function CC_extra_bonus()
	return (_G.CSR_ItemConstants and _G.CSR_ItemConstants.overkill_rush_extra_bonus) or 0.01
end

-- Count how many Overkill Rush items player has
local function get_item_stacks()
	return CSR_CountStacks("player_overkill_rush_")
end

-- Get current active bonus (0 if expired or no items)
-- Formula: kill_stacks * (item_stacks + 1) * extra_bonus
-- 1 item: 2%/4%/6%/8% for 1/2/3/4 kills, 2 items: 3%/6%/9%/12%, etc.
function CSR_OverkillRush_GetActiveBonus()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end
	local state = _G.CSR_OverkillRush
	if state.kill_stacks <= 0 then
		return 0
	end

	local ok, current_time = pcall(function()
		return TimerManager:game():time()
	end)
	if not ok then
		return 0
	end

	if current_time - state.last_kill_time >= CC_duration() then
		state.kill_stacks = 0
		-- VHUDPlus: streak expired
		if CSR_VHUDPlusEvent then
			CSR_VHUDPlusEvent("timed_buff", "deactivate", "csr_overkill_rush")
		end
		if CSR_WFHudEvent then
			CSR_WFHudEvent("deactivate", "overkill_rush")
		end
		if CSR_PocoHudEvent then
			CSR_PocoHudEvent("deactivate", "overkill_rush")
		end
		return 0
	end

	local item_stacks = get_item_stacks()
	if item_stacks <= 0 then
		return 0
	end

	return state.kill_stacks * (item_stacks + 1) * CC_extra_bonus()
end

-- Kill handler
local function on_kill(self, attack_data)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	-- Check that the killer is the local player
	if not attack_data or not attack_data.attacker_unit then
		return
	end
	if not attack_data.attacker_unit:base() then
		return
	end
	if not attack_data.attacker_unit:base().is_local_player then
		return
	end

	-- Check that the enemy just died
	if not self._dead then
		return
	end

	-- Guard against multiple triggers on the same enemy
	if self._csr_overkill_processed then
		return
	end
	self._csr_overkill_processed = true

	local item_stacks = get_item_stacks()
	if item_stacks <= 0 then
		return
	end

	local state = _G.CSR_OverkillRush
	local ok, current_time = pcall(function()
		return TimerManager:game():time()
	end)
	if not ok then
		return
	end

	-- Reset if streak expired
	if current_time - state.last_kill_time >= CC_duration() then
		state.kill_stacks = 0
	end

	-- Add kill stack (max 4)
	state.kill_stacks = math.min(state.kill_stacks + 1, CC_max_kill_stacks())
	state.last_kill_time = current_time

	-- VHUDPlus: show/refresh streak timer
	if CSR_VHUDPlusEvent then
		CSR_VHUDPlusEvent("timed_buff", "activate", "csr_overkill_rush", {
			t = current_time,
			duration = CC_duration(),
		})
		CSR_VHUDPlusEvent("buff", "set_stack_count", "csr_overkill_rush", {
			stack_count = state.kill_stacks,
		})
	end
	-- Warframe HUD: show/refresh with active fire rate & reload speed bonus
	if CSR_WFHudEvent then
		local bonus_pct = state.kill_stacks * (item_stacks + 1) * (CC_extra_bonus() * 100)
		CSR_WFHudEvent("activate", "overkill_rush", {
			duration = CC_duration(),
			value = "+" .. math.floor(bonus_pct + 0.5) .. "%",
		})
	end
	-- PocoHud3: show/refresh streak timer
	if CSR_PocoHudEvent then
		local bonus_pct = state.kill_stacks * (item_stacks + 1) * (CC_extra_bonus() * 100)
		CSR_PocoHudEvent("activate", "overkill_rush", {
			duration = CC_duration(),
			value = "+" .. math.floor(bonus_pct + 0.5) .. "% ",
		})
	end
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
