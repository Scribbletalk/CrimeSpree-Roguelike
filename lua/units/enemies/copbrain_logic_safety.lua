-- Crime Spree Roguelike - guard against a logic transition to a state the unit's brain lacks.
-- Aggressive enemy-AI mods (LIES MWS) restructure CopLogicTravel:update so it can call
-- CopLogicBase._exit(unit, wanted_state) with a state that is NOT in the unit's self._logics
-- table (wanted_state comes from _get_logic_state_from_reaction, e.g. "attack" on a unit whose
-- brain only registers a subset). Vanilla CopBrain:set_logic then does `local logic =
-- self._logics[name]` -> nil and crashes on `logic.enter(...)` ("attempt to index local 'logic'
-- (a nil value)", copbrain.lua). A nil logic is always a bug; refusing the transition (keep the
-- current logic) is strictly safer than crashing the whole session. No effect when the state
-- exists. NOT a CSR bug (no CSR frame in the stack) - this is a third-party-AI compat heal.

if not RequiredScript or not CopBrain then
	return
end

if _G._CSR_COPBRAIN_LOGIC_SAFETY_HOOKED then
	return
end
_G._CSR_COPBRAIN_LOGIC_SAFETY_HOOKED = true

local orig_set_logic = CopBrain.set_logic
function CopBrain:set_logic(name, enter_params)
	if not name or not self._logics or not self._logics[name] then
		if _G.CSR_DEBUG then
			csr_log("[CSR] copbrain_logic_safety: refused transition to missing logic '" .. tostring(name) .. "'")
		end
		return
	end
	return orig_set_logic(self, name, enter_params)
end
