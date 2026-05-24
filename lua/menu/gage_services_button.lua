-- Crime Spree Roguelike - Gage Services open callback.
-- Opened from the CSR lobby sidebar "Black Market" row (missions_menu.lua ->
-- csr_open_shop -> this). Registers the callback only; the screen itself is
-- gage_services_screen (node_register + component_register + gage_services_menu.lua).
-- Mirrors logbook_button.lua.

if not RequiredScript then
	return
end

if not MenuCallbackHandler then
	log("[CSR Shop] gage_services_button: early return (MenuCallbackHandler missing)")
	return
end

log("[CSR Shop] gage_services_button.lua loaded; CSR_OpenGageServices registered")

MenuCallbackHandler.CSR_OpenGageServices = function(this, item)
	log("[CSR Shop] CSR_OpenGageServices fired -> open_node(gage_services_screen)")

	local ok, err = pcall(function()
		managers.menu:open_node("gage_services_screen")
	end)

	if not ok then
		log("[CSR Shop] ERROR open_node(gage_services_screen) failed: " .. tostring(err))
	end
end
