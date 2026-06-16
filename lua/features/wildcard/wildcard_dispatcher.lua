-- Wildcard Active Dispatcher (U1)
-- Shared keybind handler for active-use wildcard items. Each active wildcard
-- registers an `activate(player_unit)` callback keyed by its item type.
-- The BLT keybind script (lua/features/wildcard/activate_wildcard.lua) calls
-- _G.CSR_TriggerWildcard() on key press, which scans owned items and routes
-- to the first owned active wildcard.
--
-- U1 notes: gameplay gate is managers.csr:in_csr_heist() (NOT the legacy
-- crime_spree:is_active(), which is always false under CSR's standard gamemode).
-- Ownership is managers.csr:owned("<type>") on the bare item type.

if not RequiredScript then
	return
end

if _G.CSR_WILDCARD_DISPATCHER_LOADED then
	return
end
_G.CSR_WILDCARD_DISPATCHER_LOADED = true

_G.CSR_WildcardActives = _G.CSR_WildcardActives or {}

-- Active wildcards publish their cooldown here so the HUD slot can draw the radial
-- recharge. cooldown_end lives as a file-local in each item file (unreadable from the
-- HUD), so each active reports it via CSR_SetWildcardCooldown on activate AND on reset.
--   { [item_type] = { ends = game_time, duration = seconds } }
_G.CSR_WildcardCooldowns = _G.CSR_WildcardCooldowns or {}

function _G.CSR_SetWildcardCooldown(item_type, ends, duration)
	if not item_type then
		return
	end
	_G.CSR_WildcardCooldowns[item_type] = { ends = ends or 0, duration = duration or 0 }
end

local function dbg(msg)
	local mgr = managers and managers.csr
	if mgr and mgr.debug_enabled and mgr:debug_enabled() then
		mgr:debug_log("[Wildcard] " .. tostring(msg))
	end
end

-- CSR_RegisterWildcardActive is defined in lua/core/extension_api.lua (it must
-- exist before this lib/entry POST-hook loads, since items register their active
-- from a playermanager hook that fires earlier — see the comment there).

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
	dbg("CSR_TriggerWildcard entry")

	-- In-CS heist gameplay only; suppresses the key entirely elsewhere.
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		dbg("gate fail: not in active CSR heist")
		return
	end

	-- End-screen: block actives on the victory/gameover screens.
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		if state == "victoryscreen" or state == "gameoverscreen" then
			dbg("gate fail: end screen state=" .. tostring(state))
			return
		end
	end

	local player_unit = get_local_player()
	if not player_unit then
		dbg("gate fail: no local player unit")
		return
	end

	-- Down / arrested / custody states: don't fire actives.
	local cdmg = player_unit:character_damage()
	if cdmg then
		if cdmg.dead and cdmg:dead() then
			dbg("gate fail: player dead")
			return
		end
		if cdmg.bleed_out and cdmg:bleed_out() then
			dbg("gate fail: player bleed_out")
			return
		end
		if cdmg.arrested and cdmg:arrested() then
			dbg("gate fail: player arrested")
			return
		end
	end

	for item_type, activate in pairs(_G.CSR_WildcardActives) do
		local owned = (mgr.owned and mgr:owned(item_type)) or 0
		if owned > 0 then
			dbg("firing active: " .. tostring(item_type) .. " (owned=" .. tostring(owned) .. ")")
			pcall(activate, player_unit)
			return
		end
	end

	dbg("no owned wildcard actives — no-op")
end

-- Workaround for "Full Speed Swarm" mod, which replaces BLTKeybindsManager:update
-- with a cached-list version. FSS captures `state = Global.load_level and StateGame
-- or StateMenu` at file-scope when its lib/managers/menumanager hook fires (at main
-- menu → state=StateMenu) and excludes any keybind whose CanExecuteInState(state)
-- returns false. Our csr_activate_wildcard is run_in_game only, so FSS permanently
-- filters it out — until a Lua reload mid-heist re-runs FSS with state=StateGame.
-- Symptom: rebinding the wildcard key mid-heist does nothing until heist restart.
local function ensure_wildcard_in_fss_list()
	if not _G.BLT or not BLT.Keybinds or not BLT.Keybinds.fs_filtered_keybinds then
		return
	end
	local bind = BLT.Keybinds:get_keybind("csr_activate_wildcard")
	if not bind then
		return
	end
	-- FSS's _SetKey override populates _key.idstring and _key.input. If our key
	-- was restored from save before FSS bootstrap and FSS skipped us in its
	-- initial sweep, idstring stays nil. Re-call SetKey so the override runs.
	local key_str = bind._key and bind._key.pc
	if key_str and key_str ~= "" and not bind._key.idstring and bind.SetKey then
		bind:SetKey(key_str)
	end
	for _, b in ipairs(BLT.Keybinds.fs_filtered_keybinds) do
		if b == bind then
			return
		end
	end
	table.insert(BLT.Keybinds.fs_filtered_keybinds, bind)
	dbg("FSS workaround: added csr_activate_wildcard to fs_filtered_keybinds")
end

if Hooks then
	-- Re-attach when the user binds the key from the menu (covers mid-heist rebind).
	Hooks:Add("CustomizeControllerOnKeySet", "CSR_FSSFix_WildcardOnKeySet", function(connection_name, _)
		if connection_name == "csr_activate_wildcard" then
			ensure_wildcard_in_fss_list()
		end
	end)

	-- FSS re-runs blt_keybinds_manager.lua on EVERY menu<->heist transition and rebuilds
	-- fs_filtered_keybinds from a file-scope `state` snapshot, REPLACING the table. If that
	-- snapshot lands on StateMenu (Global.load_level still false at the instant FSS re-runs),
	-- our run_in_game bind is dropped for the whole heist -> key is silently dead. The boot
	-- hooks above can't cover this: they fire once, the rebuild happens again every heist.
	-- Re-assert exactly once per heist entry, from GameSetupUpdate (fires only in-heist,
	-- strictly after FSS's transition rebuild); MenuUpdate re-arms it for the next heist.
	-- These per-frame hooks exist solely to patch FSS, so only register them when FSS is
	-- actually present -- players without FSS add zero per-frame work.
	local _fss_rearm_hooks_added = false
	local function add_fss_rearm_hooks()
		if _fss_rearm_hooks_added then
			return
		end
		if not (_G.BLT and BLT.Keybinds and BLT.Keybinds.fs_filtered_keybinds) then
			return
		end
		_fss_rearm_hooks_added = true
		local _fss_rearm = false
		Hooks:Add("GameSetupUpdate", "CSR_FSSFix_WildcardInHeist", function()
			if not _fss_rearm then
				_fss_rearm = true
				ensure_wildcard_in_fss_list()
			end
		end)
		Hooks:Add("MenuUpdate", "CSR_FSSFix_WildcardRearm", function()
			_fss_rearm = false
		end)
	end

	-- Cover the case where the key was already bound from a previous session:
	-- FSS's bootstrap (which runs after lib/entry but before LocalizationManagerPostInit)
	-- skipped our bind because state==StateMenu at main menu. Re-attach here, and -- now that
	-- FSS's bootstrap has run -- register the per-heist re-assert hooks iff FSS is loaded.
	Hooks:Add("LocalizationManagerPostInit", "CSR_FSSFix_WildcardOnLocPost", function()
		ensure_wildcard_in_fss_list()
		add_fss_rearm_hooks()
	end)
end
