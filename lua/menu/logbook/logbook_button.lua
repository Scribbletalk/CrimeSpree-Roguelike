-- Open callback for the Logbook. Triggered from the CSR lobby sidebar
-- (missions_menu.lua csr_open_logbook). Hooked on menumanager so
-- MenuCallbackHandler exists.

if not RequiredScript then
	return
end

if not MenuCallbackHandler then
	csr_log("[CSR Logbook] logbook_button: early return (MenuCallbackHandler missing)")
	return
end

csr_log("[CSR Logbook] logbook_button.lua loaded; CSR_OpenLogbook registered")

MenuCallbackHandler.CSR_OpenLogbook = function(this, item)
	csr_log("[CSR Logbook] CSR_OpenLogbook fired -> open_node(csr_logbook_screen)")

	local ok, err = pcall(function()
		managers.menu:open_node("logbook_screen")
	end)

	if not ok then
		log("[CSR Logbook] ERROR open_node(csr_logbook_screen) failed: " .. tostring(err))
	end
end
