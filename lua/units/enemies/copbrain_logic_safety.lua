-- Crime Spree Roguelike - make CopBrain:set_logic transitions safe (LIES MWS / aggressive-AI compat).
-- Two third-party-AI heals on the single funnel every logic transition passes through. NOT CSR bugs
-- (no CSR frame in any stack).
--
-- (1) MISSING LOGIC: aggressive enemy-AI mods (LIES MWS) restructure CopLogicTravel so it can call
--     CopLogicBase._exit(unit, wanted_state) with a state NOT in the unit's self._logics table
--     (wanted_state from _get_logic_state_from_reaction, e.g. "attack" on a unit whose brain registers
--     only a subset). Vanilla set_logic then indexes a nil logic and crashes on logic.enter(...). Refuse
--     the transition (keep the current logic) - strictly safer than killing the session.
--
-- (2) WEAPON-USAGE / PRESET MISMATCH: vanilla coplogicsniper:72, LIES coplogicsniper:49 and LIES
--     coplogictravel:166 all inline the same lookup
--         my_data.weapon_range = data.char_tweak.weapon[<equipped weapon usage>].range
--     If the unit's equipped weapon usage is not a key in its char_tweak.weapon preset (weapon mods can
--     change an NPC's weapon to a usage the preset never declared), that indexes nil -> "attempt to index
--     a nil value" -> C++ exception. We alias the missing usage key to an existing preset entry (is_rifle
--     preferred) BEFORE the transition, so the logic's enter resolves it and completes normally. This is
--     the funnel fix: data.char_tweak is the SAME table as self._logic_data.char_tweak
--     (copbrain.lua:436/872), so one alias here heals every logic's enter (sniper, travel, attack, ...).
--     Additive + idempotent; only fills a genuinely missing key. Mirrors coplogicsniper_safety's alias.
--     Applied on BOTH set_logic AND set_init_logic (copbrain.lua:453) - the spawn-time initial logic
--     enter (idle) goes through set_init_logic, NOT set_logic, and idle.enter also reads the idiom.
--     Because char_tweak is shared per unit-type, the spawn-time alias also covers later non-enter
--     readers of the same type (CopActionShoot/Tase/Hurt:init, logic update paths) - they see the key.

if not RequiredScript or not CopBrain then
	return
end

if _G._CSR_COPBRAIN_LOGIC_SAFETY_HOOKED then
	return
end
_G._CSR_COPBRAIN_LOGIC_SAFETY_HOOKED = true

-- Fill a missing char_tweak.weapon[usage] key so the weapon_range lookup in a logic's enter resolves.
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

-- Spawn-time initial logic enter goes through set_init_logic (copbrain.lua:453), not set_logic.
-- Alias the weapon usage key here too so the first logic's enter (idle) can't crash on the idiom.
local orig_set_init_logic = CopBrain.set_init_logic
if orig_set_init_logic then
	function CopBrain:set_init_logic(name, enter_params)
		ensure_weapon_usage_key(self)

		return orig_set_init_logic(self, name, enter_params)
	end
end
