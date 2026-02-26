-- Crime Spree Roguelike - Debug Mode Forced Modifiers Fix
-- In debug mode, backfills all forced modifiers from previous levels

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.debug_mode then
		log("[CSR Debug Mods] " .. tostring(msg))
	end
end

CSR_log("Debug Mods Fix loaded!")

-- Hook on get_mission_modifiers - returns modifiers applicable to the current mission/level
local original_get_mission_modifiers = CrimeSpreeManager.get_mission_modifiers
function CrimeSpreeManager:get_mission_modifiers()
	local result = original_get_mission_modifiers(self)

	-- In debug mode, inject all forced modifiers from levels below the current one
	if CSR_DEBUG_MODE and self:is_active() then
		local current_level = self:spree_level()

		-- Only relevant when starting at level 50 or higher
		if current_level >= 50 then
			local forced_mods = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.modifiers and tweak_data.crime_spree.modifiers.forced or {}

			CSR_log("DEBUG: get_mission_modifiers called, level: " .. current_level)
			CSR_log("DEBUG: Original modifier count: " .. #result)

			-- Add all forced modifiers assigned to levels below the current level
			local added_count = 0
			for _, mod_data in ipairs(forced_mods) do
				if mod_data.level and mod_data.level < current_level then
					-- Skip dummy placeholder modifiers
					if mod_data.id and string.find(mod_data.id, "csr_dummy", 1, true) then
						-- skip dummy
					else
						-- Guard: skip if this modifier is already in the result list
						local already_in_result = false
						for _, existing_mod in ipairs(result) do
							if existing_mod.id == mod_data.id then
								already_in_result = true
								break
							end
						end

						if not already_in_result then
							table.insert(result, mod_data)
							added_count = added_count + 1
							CSR_log("  + Added: " .. mod_data.id .. " (level " .. mod_data.level .. ")")
						end
					end
				end
			end

			CSR_log("DEBUG: Modifiers added: " .. added_count)
			CSR_log("DEBUG: Final modifier count: " .. #result)
		end
	end

	return result
end

CSR_log("Hook on get_mission_modifiers installed!")
