-- Crime Spree Roguelike - Gage's Services MenuNode Registration
-- Mirrors logbook_node_register.lua exactly.

Hooks:Add("CoreMenuData.LoadDataMenu", "CSR_GageServicesNodeRegister", function(menu_id, menu)
	for _, node_data in ipairs(menu) do
		if node_data.name == "csr_gage_services_screen" then
			return
		end
	end

	local node = {
		_meta = "node",
		name = "csr_gage_services_screen",
		menu_components = "csr_gage_services_component",
		scene_state = "crew_management",
	}
	table.insert(menu, node)
end)

-- No-op back callback (ESC handled inside the component)
MenuCallbackHandler.csr_gage_services_back = function(self, item) end
