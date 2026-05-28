-- Registers the black_market_screen MenuNode (BLT CoreMenuData pattern).

csr_log("[CSR Shop] black_market_node_register.lua loaded")

Hooks:Add("CoreMenuData.LoadDataMenu", "CSR_BlackMarketNodeRegister", function(menu_id, menu)
	for _, node_data in ipairs(menu) do
		if node_data.name == "black_market_screen" then
			return
		end
	end

	-- No default back item — ESC pops via the menu's default nav.
	table.insert(menu, {
		_meta = "node",
		name = "black_market_screen",
		menu_components = "black_market_component",
		scene_state = "crew_management",
	})
	csr_log("[CSR Shop] LoadDataMenu(" .. tostring(menu_id) .. "): node black_market_screen ADDED")
end)

MenuCallbackHandler.csr_black_market_back = function(self, item) end
