-- Defense-in-depth nil-guard for CopLogicSniper.enter (vanilla coplogicsniper.lua:72):
--   my_data.weapon_range = data.char_tweak.weapon[<equipped weapon usage>].range
-- Vanilla indexes this unguarded. The 'sniper' behavior preset defines only is_rifle
-- (charactertweakdata _init_sniper), so a sniper-tagged unit holding a non-is_rifle weapon
-- (weapon mods can change NPC usage) -> char_tweak.weapon[usage] nil -> crash. A not-yet-
-- equipped weapon -> equipped_unit() nil -> crash. Inert when the weapon chain is valid.
-- Not CSR-gated: pure guard, same philosophy as mission_element_safety.lua.

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

		-- Root heal (common case): equipped weapon's usage isn't a key in the sniper preset.
		-- Alias it to is_rifle (the preset's only entry) so the vanilla lookup resolves.
		-- Additive + non-destructive; only fills a genuinely missing key.
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

		-- Net for the rarer cases (no equipped weapon yet, dead unit, moved crash point).
		-- Without this the C++ exception kills the session. Log everything to pin the trigger.
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

		-- Mirror vanilla's intended post-state so downstream sniper code does not nil out:
		-- weapon_range is read by the firing logic, and update must be re-enabled.
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
