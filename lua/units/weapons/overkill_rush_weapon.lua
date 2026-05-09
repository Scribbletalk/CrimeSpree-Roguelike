-- Overkill Rush - NewRaycastWeaponBase weapon hooks
-- Fire rate and reload speed bonuses for player weapons

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

-- fire_rate_multiplier: HIGHER value = FASTER fire rate
-- delay = base_fire_rate / fire_rate_multiplier()
local original_fire_rate = NewRaycastWeaponBase.fire_rate_multiplier
_G.CSR_SafeOverride(
	NewRaycastWeaponBase,
	"fire_rate_multiplier",
	"Overkill Rush",
	original_fire_rate,
	function(self, ...)
		local result = original_fire_rate(self, ...)

		if CSR_OverkillRush_GetActiveBonus then
			local bonus = CSR_OverkillRush_GetActiveBonus()
			if bonus > 0 then
				result = result * (1 + bonus) -- multiply = faster fire rate
			end
		end

		return result
	end
)

-- reload_speed_multiplier: HIGHER value = FASTER reload
-- reload_time = base_time / reload_speed_multiplier()
local original_reload_speed = NewRaycastWeaponBase.reload_speed_multiplier
if original_reload_speed then
	_G.CSR_SafeOverride(
		NewRaycastWeaponBase,
		"reload_speed_multiplier",
		"Overkill Rush",
		original_reload_speed,
		function(self)
			local base = original_reload_speed(self)

			if CSR_OverkillRush_GetActiveBonus then
				local bonus = CSR_OverkillRush_GetActiveBonus()
				if bonus > 0 then
					return base * (1 + bonus) -- multiply = faster reload
				end
			end

			return base
		end
	)
	CSR_log("[CSR OverkillRush] reload_speed_multiplier hook registered (NewRaycastWeaponBase)")
else
	log("[CSR OverkillRush] WARNING: reload_speed_multiplier not found on NewRaycastWeaponBase")
end

CSR_log("[CSR OverkillRush] fire_rate_multiplier + reload_speed_multiplier hooks registered")
