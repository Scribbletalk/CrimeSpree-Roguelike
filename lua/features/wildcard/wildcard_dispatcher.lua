-- Wildcard Active Dispatcher: shared keybind handler for active-use wildcard items.
-- activate_wildcard.lua calls CSR_TriggerWildcard() on keypress; routes to the first
-- owned active. Gate: managers.csr:in_csr_heist() (NOT crime_spree:is_active()).

if not RequiredScript then
	return
end

if _G.CSR_WILDCARD_DISPATCHER_LOADED then
	return
end
_G.CSR_WILDCARD_DISPATCHER_LOADED = true

_G.CSR_WildcardActives = _G.CSR_WildcardActives or {}

-- Active wildcards publish cooldowns here (file-local ends times can't be read from HUD).
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

-- CSR_RegisterWildcardActive is defined in extension_api.lua (must exist before
-- this lib/entry hook; items register from playermanager which fires earlier).

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

-- FSS ("Full Speed Swarm") compat: FSS snapshots state=StateMenu at boot, permanently
-- drops our run_in_game keybind. Re-inject into fs_filtered_keybinds on every heist entry.
local function ensure_wildcard_in_fss_list()
	if not _G.BLT or not BLT.Keybinds or not BLT.Keybinds.fs_filtered_keybinds then
		return
	end
	local bind = BLT.Keybinds:get_keybind("csr_activate_wildcard")
	if not bind then
		return
	end
	-- If FSS skipped us on boot, _key.idstring stays nil; re-call SetKey so FSS's override runs.
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
	-- Re-inject when the user rebinds the key from the menu.
	Hooks:Add("CustomizeControllerOnKeySet", "CSR_FSSFix_WildcardOnKeySet", function(connection_name, _)
		if connection_name == "csr_activate_wildcard" then
			ensure_wildcard_in_fss_list()
		end
	end)

	-- FSS rebuilds fs_filtered_keybinds on every menu<->heist transition. If the snapshot
	-- catches StateMenu our bind is silently dropped for the whole heist. Re-assert once on
	-- GameSetupUpdate (after FSS's rebuild); MenuUpdate rearms it for the next heist.
	-- Only installs these per-frame hooks when FSS is actually present.
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

	-- Key bound from a previous session: FSS bootstrap skipped it at menu, re-inject now.
	-- FSS's bootstrap has already run by LocalizationManagerPostInit, so add_fss_rearm_hooks works.
	Hooks:Add("LocalizationManagerPostInit", "CSR_FSSFix_WildcardOnLocPost", function()
		ensure_wildcard_in_fss_list()
		add_fss_rearm_hooks()
	end)
end
