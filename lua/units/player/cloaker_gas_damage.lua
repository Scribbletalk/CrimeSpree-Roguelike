-- Crime Spree Roguelike - Cloaker Tear Gas Damage Override
-- Changes cloaker gas damage from 30/s to 5% max HP/s

if not RequiredScript then
	return
end



-- Damage as a percentage of max HP per second
local GAS_DAMAGE_PERCENT = 0.05  -- 5% max HP per second

-- Hook on damage_fire - handles fire, gas, and poison damage
local original_damage_fire = PlayerDamage.damage_fire
function PlayerDamage:damage_fire(attack_data)
	-- Guard: must be cloaker gas damage
	if attack_data and attack_data.variant and attack_data.variant == "poison" then
		-- Guard: must have an attacker (the cloaker)
		if attack_data.attacker_unit then
			local attacker = attack_data.attacker_unit
			-- Identify cloaker by tweak_data name
			if alive(attacker) and attacker:base() then
				local enemy_data = attacker:base()._tweak_table
				if enemy_data and string.find(tostring(enemy_data), "spooc") then
					-- This is cloaker gas - replace damage with percent-based value
					local max_hp = self:_max_health()
					local new_damage = max_hp * GAS_DAMAGE_PERCENT


					attack_data.damage = new_damage
				end
			end
		end
	end

	-- Call original method with modified damage
	return original_damage_fire(self, attack_data)
end

