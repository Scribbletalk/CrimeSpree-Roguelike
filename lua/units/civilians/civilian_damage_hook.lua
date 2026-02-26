-- Crime Spree Roguelike - Civilian Damage Hook
-- Calls OnCivilianKilled() for active Civilian Alarm modifiers when a civilian dies

if not RequiredScript then
	return
end


-- Hook on civilian death
local original_die = CivilianDamage.die

function CivilianDamage:die(...)
	-- Call original method
	local result = original_die(self, ...)

	-- Check active Crime Spree modifiers
	if managers.crime_spree and managers.crime_spree:is_active() then
		-- NOTE: Civilian Alarm modifier only works in stealth
		-- Check if we are in stealth mode (whisper_mode)
		local in_stealth = managers.groupai and managers.groupai:state():whisper_mode()

		if not in_stealth then
			-- CIVILIAN GUILT: each civilian killed in loud permanently reduces player max HP
			if CSR_ActiveBuffs and CSR_ActiveBuffs.civilian_guilt then
				_G.CSR_CivilianGuiltKills = (_G.CSR_CivilianGuiltKills or 0) + 1

				-- Cap current HP to new (reduced) max HP
				pcall(function()
					local player_unit = managers.player and managers.player:player_unit()
					if not player_unit or not alive(player_unit) then return end
					local char_dmg = player_unit:character_damage()
					if not char_dmg then return end

					local new_max = char_dmg:_max_health()
					local current = char_dmg:get_real_health()
					if current > new_max then
						char_dmg:set_health(new_max)
						if char_dmg._send_set_health then char_dmg:_send_set_health() end
					end
						" current_was=" .. string.format("%.1f", current))
				end)
			end

			-- In loud mode - skip stealth modifiers
			return result
		end

		local active_modifiers = managers.crime_spree:active_modifiers()

		if active_modifiers then
			for _, modifier_data in ipairs(active_modifiers) do
				-- Look for Civilian Alarm modifiers (all 3 tiers)
				if modifier_data.id and (
					modifier_data.id:match("civilian_alarm_1_") or
					modifier_data.id:match("civilian_alarm_2_") or
					modifier_data.id:match("civilian_alarm_3_")
				) then

					-- Get the modifier class
					local modifier_class = modifier_data.class
					if modifier_class and modifier_class.OnCivilianKilled then
						-- Call OnCivilianKilled on the modifier
						modifier_class:OnCivilianKilled()
					end
				end
			end
		end
	end

	return result
end

