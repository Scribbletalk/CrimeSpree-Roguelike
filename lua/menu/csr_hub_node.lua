-- CSR Hub menu node — barebones entry screen for 6.6.6-alpha.
--
-- Registers a new "csr_hub" menu node under the main menu tree (via BLT's
-- MenuHelper hooks) and reroutes ALL opens of vanilla's "crime_spree_lobby"
-- node to land on csr_hub instead. That way the existing main-menu "Crime
-- Spree" button (and any other code path that opens crime_spree_lobby) ends
-- up in our screen, without us having to edit the start_menu XML data.
--
-- Items in the hub:
--   - "Start New Run" button → calls managers.csr:start_run()
--   - Back button (BLT-supplied)
--
-- Future sessions will replace this with a custom menu_component for full
-- layout control; for alpha the BLT-rendered button list is enough to prove
-- the wiring works end-to-end.

if not RequiredScript then
	return
end

-- =====================================================
-- Localization
-- =====================================================

Hooks:Add("LocalizationManagerPostInit", "CSR_HubLocalization", function(loc)
	loc:add_localized_strings({
		csr_hub_title = "Crime Spree Roguelike",
		csr_hub_legend = "",
		csr_start_new_run_title = "Start New Run",
		csr_start_new_run_desc = "Begin a fresh Crime Spree Roguelike run.",
	})
end)

-- =====================================================
-- Callbacks
-- =====================================================

Hooks:Add("MenuManagerInitialize", "CSR_HubCallbacks", function(menu_manager)
	log("[CSR] hub: registering MenuCallbackHandler.csr_start_new_run_callback")
	MenuCallbackHandler.csr_start_new_run_callback = function(self, item)
		log("[CSR] csr_start_new_run_callback fired")
		if not managers or not managers.csr then
			log("[CSR] start_new_run: managers.csr unavailable")
			return
		end
		managers.csr:start_run()
	end

	MenuCallbackHandler.csr_hub_back = function(self, item)
		-- BLT's AddBackButton handles navigation; this is a placeholder for
		-- any future cleanup we want to run when leaving the hub.
	end
end)

-- =====================================================
-- Register the hub menu node via BLT MenuHelper
--
-- MenuManagerSetupCustomMenus / MenuManagerBuildCustomMenus fire for
-- menu_main and menu_pause (see SuperBLT/mods/base/lua/MenuManager.lua:53-55).
-- We register only for menu_main — the hub doesn't exist in the pause menu.
-- =====================================================

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_HubSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_hub")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_HubBuild", function(menu_manager, nodes)
	if not MenuHelper:GetMenu("csr_hub") then
		return
	end

	MenuHelper:AddButton({
		id = "csr_start_new_run",
		title = "csr_start_new_run_title",
		desc = "csr_start_new_run_desc",
		callback = "csr_start_new_run_callback",
		menu_id = "csr_hub",
	})

	-- NOTE: MenuHelper:BuildMenu calls AddBackButton internally (see
	-- mods/base/req/core/MenuHelper.lua:458-459). Don't add it again here
	-- or you get a duplicate Back item in the rendered list.
	nodes["csr_hub"] = MenuHelper:BuildMenu("csr_hub", {
		back_callback = "csr_hub_back",
	})
end)

-- =====================================================
-- Reroute the vanilla CS entry nodes → csr_hub
--
-- The main-menu "Crime Spree" button is NOT a regular menu item — it's a
-- custom button rendered by CrimeSpreeMenuComponent. Its callback
-- (_open_crime_spree_contract) calls managers.menu:open_node with one of
-- two node names depending on online/offline state (see
-- lib/managers/menu/crimespreemenucomponent.lua:130-147 in PD2 source):
--   - "crimenet_crime_spree_contract_singleplayer" (offline)
--   - "crimenet_crime_spree_contract_host"          (online)
-- We also catch "crime_spree_lobby" for other entry paths that open the CS
-- lobby directly (accept_crime_spree_contract_sp/mp end with that).
--
-- Raw wrap MenuManager:open_node because we need to swap the first argument
-- BEFORE the original runs — PostHook can't change inputs, and BLT PreHook's
-- return value is discarded. The _G guard prevents re-wrapping on hot-reload.
-- =====================================================

local CSR_REROUTE_NODES = {
	["crimenet_crime_spree_contract_singleplayer"] = true,
	["crimenet_crime_spree_contract_host"] = true,
	["crime_spree_lobby"] = true,
}

if MenuManager and not _G._CSR_HUB_OPEN_NODE_WRAPPED then
	_G._CSR_HUB_OPEN_NODE_WRAPPED = true
	local original_open_node = MenuManager.open_node
	if original_open_node then
		function MenuManager:open_node(node_name, parameter_list)
			if node_name and CSR_REROUTE_NODES[node_name] then
				log("[CSR] reroute: " .. tostring(node_name) .. " -> csr_hub")
				node_name = "csr_hub"
				parameter_list = nil
			elseif
				node_name
				and (string.find(node_name, "crime_spree", 1, true) or string.find(node_name, "crimenet", 1, true))
			then
				-- Diagnostic: log any CS/Crime.net related open_node we DON'T reroute,
				-- so if the player clicks CS and the hub still doesn't appear, we can
				-- see the exact node name to add to CSR_REROUTE_NODES. Strip once
				-- the reroute is confirmed working.
				log("[CSR] open_node (not rerouted): " .. tostring(node_name))
			end
			return original_open_node(self, node_name, parameter_list)
		end
	end
end
