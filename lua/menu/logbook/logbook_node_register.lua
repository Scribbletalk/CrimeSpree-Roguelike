-- Registers the logbook_screen MenuNode (BLT CoreMenuData pattern).

csr_log("[CSR Logbook] logbook_node_register.lua loaded; CSR_LogbookNodeRegister listener added")

Hooks:Add("CoreMenuData.LoadDataMenu", "CSR_LogbookNodeRegister", function(menu_id, menu)
	for _, node_data in ipairs(menu) do
		if node_data.name == "logbook_screen" then
			csr_log("[CSR Logbook] LoadDataMenu(" .. tostring(menu_id) .. "): node already present, skip")
			return
		end
	end

	-- No default back item — ESC is handled manually in the component.
	local logbook_node = {
		_meta = "node",
		name = "logbook_screen",
		menu_components = "logbook_component",
		scene_state = "crew_management",
	}
	table.insert(menu, logbook_node)
	csr_log("[CSR Logbook] LoadDataMenu(" .. tostring(menu_id) .. "): node csr_logbook_screen ADDED")
end)

MenuCallbackHandler.csr_logbook_back = function(self, item) end
