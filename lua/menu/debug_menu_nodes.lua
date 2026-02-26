-- DEBUG: Dump ALL MenuNodeGui nodes with items
if not RequiredScript then return end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.debug_mode then
		log("[CSR DEBUG MENU] " .. tostring(msg))
	end
end

Hooks:PostHook(MenuNodeGui, "init", "CSR_DebugMenuInit", function(self)
	local ok, err = pcall(function()
		local node_name = "?"
		pcall(function() node_name = tostring(self.node._parameters.name) end)

		CSR_log("=== Node: " .. node_name .. " items:" .. (self.row_items and #self.row_items or 0) .. " ===")

		-- Only log items if there are any
		if self.row_items and #self.row_items > 0 then
			for i, row_item in ipairs(self.row_items) do
				local name = "?"
				pcall(function() name = row_item.item:name() end)
				local pos_str = ""
				pcall(function()
					local gp = row_item.gui_panel
					if gp and alive(gp) then
						local wx, wy = gp:world_position()
						local w, h = gp:size()
						pos_str = " world(" .. math.floor(wx) .. "," .. math.floor(wy) .. ") " .. math.floor(w) .. "x" .. math.floor(h)
					end
				end)
				CSR_log("  [" .. i .. "] " .. name .. pos_str)
			end
		end
	end)
	if not ok then CSR_log("ERROR: " .. tostring(err)) end
end)
