-- Crime Spree Roguelike - Gage Services GUI Component Registration.
-- Registers the component with MenuHelper so MenuComponentManager instantiates
-- it when the gage_services_screen node opens. Mirrors logbook_component_register.lua.

log(
	"[CSR Shop] gage_services_component_register.lua loaded; MenuHelper="
		.. tostring(MenuHelper ~= nil)
		.. " CrimeSpreeGageServicesMenuComponent="
		.. tostring(CrimeSpreeGageServicesMenuComponent ~= nil)
)

if MenuHelper and CrimeSpreeGageServicesMenuComponent then
	MenuHelper:AddComponent("gage_services_component", CrimeSpreeGageServicesMenuComponent)
	log("[CSR Shop] gage_services_component registered immediately")
else
	-- Defer: the component class may not have loaded yet (SuperBLT inter-file order).
	Hooks:Add("MenuManagerInitialize", "CSR_GageServicesComponentDeferred", function(menu_manager)
		if MenuHelper and CrimeSpreeGageServicesMenuComponent then
			MenuHelper:AddComponent("gage_services_component", CrimeSpreeGageServicesMenuComponent)
			log("[CSR Shop] gage_services_component registered (deferred via MenuManagerInitialize)")
		else
			log("[CSR Shop] DEFERRED REGISTER FAILED: component class still missing")
		end
	end)
end
