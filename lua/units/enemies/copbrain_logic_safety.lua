-- CopBrain:set_logic safety for aggressive-AI mods (LIES MWS). NOT CSR bugs.
-- (1) Missing-logic guard: refuse transitions to states not in self._logics (LIES can request
--     states the unit never registered -> nil-index crash on logic.enter).
-- (2) Weapon-usage alias: char_tweak.weapon[equipped_usage] nil-crashes any logic enter that reads
--     weapon_range. Alias missing key to is_rifle before the transition. Applied on set_init_logic
--     too (spawn-time idle enter bypasses set_logic). See diesel_quirks_brief.md.

if not RequiredScript or not CopBrain then
	return
end

if _G._CSR_COPBRAIN_LOGIC_SAFETY_HOOKED then
	return
end
_G._CSR_COPBRAIN_LOGIC_SAFETY_HOOKED = true

-- Alias a missing char_tweak.weapon[usage] key so logic enter's weapon_range lookup doesn't crash.
local function ensure_weapon_usage_key(brain)
	local ld = brain._logic_data
	local weap = ld and ld.char_tweak and ld.char_tweak.weapon
	if not weap then
		return
	end

	local unit = brain._unit
	local inv = unit and alive(unit) and unit:inventory()
	local eq = inv and inv:equipped_unit()
	local base = eq and eq:base()
	local wtd = base and base.weapon_tweak_data and base:weapon_tweak_data()
	local usage = wtd and wtd.usage

	if not usage or weap[usage] ~= nil then
		return
	end

	local donor = weap.is_rifle
	if not donor then
		local _, first_entry = next(weap)
		donor = first_entry
	end

	if donor then
		weap[usage] = donor
		if _G.CSR_DEBUG then
			csr_log("[CSR] copbrain_logic_safety: aliased weapon usage '" .. tostring(usage) .. "' to a preset entry")
		end
	end
end

local orig_set_logic = CopBrain.set_logic
function CopBrain:set_logic(name, enter_params)
	if not name or not self._logics or not self._logics[name] then
		if _G.CSR_DEBUG then
			csr_log("[CSR] copbrain_logic_safety: refused transition to missing logic '" .. tostring(name) .. "'")
		end
		return
	end

	ensure_weapon_usage_key(self)

	return orig_set_logic(self, name, enter_params)
end

-- Spawn-time enter goes through set_init_logic (copbrain.lua:453), not set_logic; alias here too.
local orig_set_init_logic = CopBrain.set_init_logic
if orig_set_init_logic then
	function CopBrain:set_init_logic(name, enter_params)
		ensure_weapon_usage_key(self)

		return orig_set_init_logic(self, name, enter_params)
	end
end
