-- Crime Spree Roguelike - Gage Services (Black Market) MenuNode Registration.
-- Registers a dedicated full-screen screen via CoreMenuData (BLT pattern),
-- mirroring logbook_node_register.lua. Opened from the lobby sidebar "Black
-- Market" row (missions_menu.lua csr_open_shop -> MenuCallbackHandler:CSR_OpenBlackMarket).

csr_log("[CSR Shop] black_market_node_register.lua loaded")

Hooks:Add("CoreMenuData.LoadDataMenu", "CSR_BlackMarketNodeRegister", function(menu_id, menu)
	-- Guard: don't double-register the node.
	for _, node_data in ipairs(menu) do
		if node_data.name == "black_market_screen" then
			return
		end
	end

	-- No default back item — ESC pops the node via the menu's default navigation.
	table.insert(menu, {
		_meta = "node",
		name = "black_market_screen",
		menu_components = "black_market_component",
		scene_state = "crew_management",
	})
	csr_log("[CSR Shop] LoadDataMenu(" .. tostring(menu_id) .. "): node black_market_screen ADDED")
end)

-- Callback on returning from the screen (parity with the logbook node).
MenuCallbackHandler.csr_black_market_back = function(self, item) end
