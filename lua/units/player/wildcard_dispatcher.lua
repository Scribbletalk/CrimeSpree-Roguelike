-- Wildcard Active Dispatcher
-- Shared keybind handler for active-use wildcard items. Each active wildcard
-- registers an `activate(player_unit)` callback keyed by its id_prefix.
-- The BLT keybind script (lua/keybinds/csr_activate_wildcard.lua) calls
-- _G.CSR_TriggerWildcard() on key press, which scans local items and routes
-- to the first owned active wildcard.
--
-- Multiple owned actives at once aren't possible today (carry-1 wildcards),
-- but the dispatch order is registration order so future passive+active
-- combos still resolve deterministically.

if not RequiredScript then
	return
end

if _G.CSR_WILDCARD_DISPATCHER_LOADED then
	return
end
_G.CSR_WILDCARD_DISPATCHER_LOADED = true

_G.CSR_WildcardActives = _G.CSR_WildcardActives or {}

-- Public: register an active wildcard.
--   id_prefix: e.g. "player_familiar_friend_" (matches CSR_CountStacks input)
--   activate:  function(player_unit) — runs on key press if owned
function _G.CSR_RegisterWildcardActive(id_prefix, activate)
	if not id_prefix or type(activate) ~= "function" then
		return
	end
	_G.CSR_WildcardActives[id_prefix] = activate
end

local function get_local_player()
	if not managers or not managers.player then
		return nil
	end
	local unit = managers.player:player_unit()
	if not unit or not alive(unit) then
		return nil
	end
	return unit
end

-- Called by the BLT keybind script on key press.
function _G.CSR_TriggerWildcard()
	log("[CSR Wildcard] CSR_TriggerWildcard entry")

	-- In-CS only; suppresses the key entirely outside Crime Spree.
	if not managers or not managers.crime_spree or not managers.crime_spree:is_active() then
		log("[CSR Wildcard] gate fail: not in active Crime Spree")
		return
	end

	-- End-screen: vanilla is_active() can stay true through victoryscreen /
	-- gameoverscreen until Continue is pressed. Block actives there.
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		if state == "victoryscreen" or state == "gameoverscreen" then
			log("[CSR Wildcard] gate fail: end screen state=" .. tostring(state))
			return
		end
	end

	local player_unit = get_local_player()
	if not player_unit then
		log("[CSR Wildcard] gate fail: no local player unit")
		return
	end

	-- Down / arrested / custody states: don't fire actives.
	local cdmg = player_unit:character_damage()
	if cdmg then
		if cdmg.dead and cdmg:dead() then
			log("[CSR Wildcard] gate fail: player dead")
			return
		end
		if cdmg.bleed_out and cdmg:bleed_out() then
			log("[CSR Wildcard] gate fail: player bleed_out")
			return
		end
		if cdmg.arrested and cdmg:arrested() then
			log("[CSR Wildcard] gate fail: player arrested")
			return
		end
	end

	if not _G.CSR_CountStacks then
		log("[CSR Wildcard] gate fail: CSR_CountStacks missing")
		return
	end

	local registered = 0
	for _ in pairs(_G.CSR_WildcardActives) do
		registered = registered + 1
	end
	log("[CSR Wildcard] dispatching, registered actives=" .. tostring(registered))

	for prefix, activate in pairs(_G.CSR_WildcardActives) do
		local owned = CSR_CountStacks(prefix) or 0
		if owned > 0 then
			log("[CSR Wildcard] firing active: " .. tostring(prefix) .. " (owned=" .. tostring(owned) .. ")")
			pcall(activate, player_unit)
			return
		end
	end

	log("[CSR Wildcard] no owned wildcard actives — no-op")
end
