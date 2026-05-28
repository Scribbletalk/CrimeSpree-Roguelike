-- Registers the Logbook GUI component with MenuHelper.

csr_log(
	"[CSR Logbook] logbook_component_register.lua loaded; MenuHelper="
		.. tostring(MenuHelper ~= nil)
		.. " CrimeSpreeLogbookMenuComponent="
		.. tostring(CrimeSpreeLogbookMenuComponent ~= nil)
)

if MenuHelper and CrimeSpreeLogbookMenuComponent then
	MenuHelper:AddComponent("logbook_component", CrimeSpreeLogbookMenuComponent)
	csr_log("[CSR Logbook] csr_logbook_component registered immediately")
else
	-- Defer if component class hasn't loaded yet.
	Hooks:Add("MenuManagerInitialize", "CSR_LogbookComponentDeferred", function(menu_manager)
		if MenuHelper and CrimeSpreeLogbookMenuComponent then
			MenuHelper:AddComponent("logbook_component", CrimeSpreeLogbookMenuComponent)
			csr_log("[CSR Logbook] csr_logbook_component registered (deferred via MenuManagerInitialize)")
		else
			log(
				"[CSR Logbook] DEFERRED REGISTER FAILED: MenuHelper="
					.. tostring(MenuHelper ~= nil)
					.. " CrimeSpreeLogbookMenuComponent="
					.. tostring(CrimeSpreeLogbookMenuComponent ~= nil)
			)
		end
	end)
end
