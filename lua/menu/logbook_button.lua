-- Crime Spree Roguelike - Logbook Button
-- Adds LOGBOOK entry to the crime_spree_lobby node

if not RequiredScript then
	return
end



if not MenuNodeGui then
	return
end


-- PreHook: add/update LOGBOOK entry in node before GUI is built
Hooks:PreHook(MenuNodeGui, "_setup_item_rows", "CSR_AddLogbookItem", function(self)
	local ok, err = pcall(function()
		if not self.node or not self.node._parameters then return end
		local node_name = tostring(self.node._parameters.name)

		if node_name ~= "crime_spree_lobby" then return end

		-- Remove existing button (to update its text when new items are available)
		if self.node._items then
			for i, existing in ipairs(self.node._items) do
				if existing:name() == "csr_logbook" then
					table.remove(self.node._items, i)
					break
				end
			end
		end

		-- Choose text: with "!" if new items are available
		local has_new = _G.CSR_Logbook and _G.CSR_Logbook:has_new()
		local text_id = has_new and "menu_csr_logbook_new" or "menu_csr_logbook"


		-- Register callback to navigate to the Logbook screen
		MenuCallbackHandler.CSR_OpenLogbook = function(this, item)

			local ok, err = pcall(function()
				managers.menu:open_node("csr_logbook_screen")
			end)

			if not ok then
			else
			end
		end

		-- Create item with callback
		local data = {type = "CoreMenuItem.Item"}
		local params = {
			name = "csr_logbook",
			text_id = text_id,
			help_id = "",
			callback = "CSR_OpenLogbook",
		}

		local item = self.node:create_item(data, params)
		if not item then
			return
		end

		-- CRITICAL: set callback handler
		if self.node.callback_handler then
			item:set_callback_handler(self.node.callback_handler)
		end

		-- Insert after "inventory"
		if self.node._items then
			local insert_pos = nil
			for i, existing in ipairs(self.node._items) do
				if existing:name() == "inventory" then
					insert_pos = i + 1
					break
				end
			end
			if insert_pos then
				table.insert(self.node._items, insert_pos, item)
			else
				self.node:add_item(item)
			end
		else
			self.node:add_item(item)
		end
	end)
end)

