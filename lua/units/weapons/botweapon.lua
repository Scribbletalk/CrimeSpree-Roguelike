-- Crime Spree Roguelike - Bot Weapon Damage Buff
-- Apply passive damage bonus to bot weapons

if not RequiredScript then
	return
end


-- Hook on bot weapon setup
Hooks:PostHook(NewRaycastWeaponBase, "setup", "CSR_BotWeaponSetup", function(self)
	-- Guard: must be a bot weapon (AI teammate)
	local owner = self._setup and self._setup.user_unit
	if not alive(owner) then
		return
	end

	-- Guard: owner must be an AI teammate (slot 3)
	-- Slot 2 = players, Slot 3 = AI teammates, others = enemies
	if not owner:in_slot(3) then
		return
	end

	-- This is a bot weapon, save reference to owner
	self._csr_bot_owner = owner
end)

-- Hook on fire - apply damage bonus
local original_fire = NewRaycastWeaponBase.fire
function NewRaycastWeaponBase:fire(from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit, ...)
	-- Guard: must be a bot with a damage buff
	if self._csr_bot_owner and alive(self._csr_bot_owner) and _G.CSR_BotDamageBuffs then
		local bot_key = tostring(self._csr_bot_owner:key())
		local damage_bonus = _G.CSR_BotDamageBuffs[bot_key]

		if damage_bonus and damage_bonus > 0 then
			-- Apply bonus to dmg_mul
			dmg_mul = (dmg_mul or 1) * (1 + damage_bonus)
		end
	end

	return original_fire(self, from_pos, direction, dmg_mul, shoot_player, spread_mul, autohit_mul, suppr_mul, target_unit, ...)
end

