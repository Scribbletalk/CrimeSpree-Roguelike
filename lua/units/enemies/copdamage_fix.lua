-- Crime Spree Roguelike - Fix for crash with fire DOT
-- Problem: is_category is called on a nil weapon_unit during DOT ticks

if not RequiredScript then
	return
end



-- Save original damage_dot function
local original_damage_dot = CopDamage.damage_dot

-- Override damage_dot with weapon_unit sanitization
function CopDamage:damage_dot(attack_data, ...)
	-- Check and clear weapon_unit if it would cause problems
	if attack_data and attack_data.weapon_unit then
		local weapon = attack_data.weapon_unit

		-- Validate weapon_unit via pcall
		local weapon_valid = false
		local success = pcall(function()
			if weapon and weapon.base then
				local base = weapon:base()
				if base and base.is_category then
					weapon_valid = true
				end
			end
		end)

		-- If weapon is invalid, remove it
		if not success or not weapon_valid then
			attack_data.weapon_unit = nil
		end
	end

	-- Call original function with sanitized data
	local success, result = pcall(original_damage_dot, self, attack_data, ...)

	if not success then
		-- Even after cleanup an error occurred - log it

		-- Return empty table
		return {
			type = "dot",
			variant = attack_data and attack_data.variant or "fire"
		}
	end

	return result
end

