-- Crime Spree Roguelike - Gage Services (Black Market) MenuNode Registration.
-- Registers a dedicated full-screen screen via CoreMenuData (BLT pattern),
-- mirroring logbook_node_register.lua. Opened from the lobby sidebar "Black
-- Market" row (missions_menu.lua csr_open_shop -> MenuCallbackHandler:CSR_OpenGageServices).

log("[CSR Shop] gage_services_node_register.lua loaded")

Hooks:Add("CoreMenuData.LoadDataMenu", "CSR_GageServicesNodeRegister", function(menu_id, menu)
	-- Guard: don't double-register the node.
	for _, node_data in ipairs(menu) do
		if node_data.name == "gage_services_screen" then
			return
		end
	end

	-- No default back item — ESC pops the node via the menu's default navigation.
	table.insert(menu, {
		_meta = "node",
		name = "gage_services_screen",
		menu_components = "gage_services_component",
		scene_state = "crew_management",
	})
	log("[CSR Shop] LoadDataMenu(" .. tostring(menu_id) .. "): node gage_services_screen ADDED")
end)

-- Callback on returning from the screen (parity with the logbook node).
MenuCallbackHandler.csr_gage_services_back = function(self, item) end
