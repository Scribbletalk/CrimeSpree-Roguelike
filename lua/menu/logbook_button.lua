-- Crime Spree Roguelike - Logbook Button
-- Now shown as a tab in the CS details page (added via populate_tabs_data)
-- This file only registers the callback handler.

if not RequiredScript then
	return
end

if not MenuNodeGui or not MenuCallbackHandler then
	return
end

-- Register callback (used by tab click in logbook_page.lua)
MenuCallbackHandler.CSR_OpenLogbook = function(this, item)
	pcall(function()
		managers.menu:open_node("csr_logbook_screen")
	end)
end
