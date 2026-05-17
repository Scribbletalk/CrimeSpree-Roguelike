-- Crime Spree Roguelike - Logbook GUI Component Registration
-- Registers GUI component via MenuHelper:AddComponent

log(
	"[CSR Logbook] logbook_component_register.lua loaded; MenuHelper="
		.. tostring(MenuHelper ~= nil)
		.. " CrimeSpreeLogbookMenuComponent="
		.. tostring(CrimeSpreeLogbookMenuComponent ~= nil)
)

-- Register component (MenuComponentManager will instantiate it)
if MenuHelper and CrimeSpreeLogbookMenuComponent then
	MenuHelper:AddComponent("csr_logbook_component", CrimeSpreeLogbookMenuComponent)
	log("[CSR Logbook] csr_logbook_component registered immediately")
else
	-- Defer: try registering later
	Hooks:Add("MenuManagerInitialize", "CSR_LogbookComponentDeferred", function(menu_manager)
		if MenuHelper and CrimeSpreeLogbookMenuComponent then
			MenuHelper:AddComponent("csr_logbook_component", CrimeSpreeLogbookMenuComponent)
			log("[CSR Logbook] csr_logbook_component registered (deferred via MenuManagerInitialize)")
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
