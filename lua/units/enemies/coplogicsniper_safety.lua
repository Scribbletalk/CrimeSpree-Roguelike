-- Guard for CopLogicSniper.enter crash (coplogicsniper.lua:72): sniper preset only declares
-- is_rifle, so a non-is_rifle weapon -> char_tweak.weapon[usage] nil -> crash.
-- Aliases missing usage to is_rifle, pcall-wraps the remainder. See pd2_coplogicsniper_enter_weapon_usage_crash.md.

if not RequiredScript then
	return
end

if CopLogicSniper and CopLogicSniper.enter and not _G._CSR_SNIPER_ENTER_GUARD then
	_G._CSR_SNIPER_ENTER_GUARD = true

	local orig_enter = CopLogicSniper.enter

	local function dbg(msg)
		if _G.CSR_DEBUG then
			log("[CSR][sniper-guard] " .. tostring(msg))
		end
	end

	function CopLogicSniper.enter(data, new_logic_name, enter_params)
		local weap = data.char_tweak and data.char_tweak.weapon
		local inv = data.unit and alive(data.unit) and data.unit:inventory()
		local eq = inv and inv:equipped_unit()
		local base = eq and eq:base()
		local wtd = base and base.weapon_tweak_data and base:weapon_tweak_data()
		local usage = wtd and wtd.usage

		-- Alias missing usage key to is_rifle (the preset's only entry).
		if weap and usage and weap[usage] == nil and weap.is_rifle then
			weap[usage] = weap.is_rifle
			dbg(
				"aliased weapon usage '"
					.. tostring(usage)
					.. "' -> is_rifle on unit '"
					.. tostring(data.unit:name())
					.. "'"
			)
		end

		local ok, err = pcall(orig_enter, data, new_logic_name, enter_params)
		if ok then
			return
		end

		-- pcall catches rarer failures (no weapon yet, dead unit). Log to pin the trigger.
		local keys = {}
		if weap then
			for k in pairs(weap) do
				keys[#keys + 1] = tostring(k)
			end
		end
		dbg(
			"enter() crashed, suppressed. unit="
				.. tostring(data.unit and data.unit:name())
				.. " eq="
				.. tostring(eq ~= nil)
				.. " usage="
				.. tostring(usage)
				.. " preset_keys="
				.. table.concat(keys, ",")
				.. " err="
				.. tostring(err)
		)

		-- Restore expected post-enter state: weapon_range (used by firing logic) + re-enable update.
		local my_data = data.internal_data
		if my_data then
			if my_data.weapon_range == nil then
				my_data.weapon_range = (weap and weap.is_rifle and weap.is_rifle.range)
					or { close = 3000, optimal = 3000, far = 3000 }
			end
			if alive(data.unit) then
				data.unit:brain():set_update_enabled_state(true)
			end
		end
	end

	dbg("CopLogicSniper.enter guard installed")
end
