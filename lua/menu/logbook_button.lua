-- Crime Spree Roguelike - Logbook open callback
-- 6.3 refactor: opened from the CSR lobby sidebar "Logbook" button
-- (csr_missions_menu.lua -> csr_open_logbook -> this). Registers the callback
-- handler only; the screen itself is csr_logbook_screen (logbook_node_register
-- + logbook_component_register + logbook_menu.lua).

if not RequiredScript then
	return
end

-- Only MenuCallbackHandler is actually needed (the old MenuNodeGui guard was
-- legacy from the pre-refactor CS-details tab and fired too early on the
-- menunodegui hook). Hooked on lib/managers/menumanager now, where
-- MenuCallbackHandler is already defined (same proven point csr_contract_callbacks
-- uses).
if not MenuCallbackHandler then
	log("[CSR Logbook] logbook_button: early return (MenuCallbackHandler missing)")
	return
end

-- Diagnostic load trace (click-triggered subsystem, kept per debug policy).
log("[CSR Logbook] logbook_button.lua loaded; CSR_OpenLogbook registered")

-- Register callback (invoked by the sidebar Logbook row)
MenuCallbackHandler.CSR_OpenLogbook = function(this, item)
	log("[CSR Logbook] CSR_OpenLogbook fired -> open_node(csr_logbook_screen)")

	local ok, err = pcall(function()
		managers.menu:open_node("csr_logbook_screen")
	end)

	if not ok then
		log("[CSR Logbook] ERROR open_node(csr_logbook_screen) failed: " .. tostring(err))
	end
end
