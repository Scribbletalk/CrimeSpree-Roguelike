-- Crime Spree Roguelike - Logbook MenuNode Registration
-- Registers a dedicated Logbook screen via CoreMenuData (BLT pattern)



-- Register MenuNode via CoreMenuData.LoadDataMenu (BLT pattern)
Hooks:Add("CoreMenuData.LoadDataMenu", "CSR_LogbookNodeRegister", function(menu_id, menu)

	-- Guard: check that node is not already registered
	for _, node_data in ipairs(menu) do
		if node_data.name == "csr_logbook_screen" then
			return
		end
	end

	-- Add node definition
	-- NO default back item - ESC is handled manually in the component
	local logbook_node = {
		_meta = "node",
		name = "csr_logbook_screen",
		menu_components = "csr_logbook_component",
		scene_state = "crew_management"
		-- Removed [1] back item - ESC now goes to our component
	}
	table.insert(menu, logbook_node)

end)

-- Callback on returning from Logbook
MenuCallbackHandler.csr_logbook_back = function(self, item)
end

