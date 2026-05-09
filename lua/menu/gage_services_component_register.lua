-- Crime Spree Roguelike - Gage's Services GUI Component Registration
-- Mirrors logbook_component_register.lua exactly.

log(
	"[CSR GAGE] component_register top: MenuHelper="
		.. tostring(MenuHelper ~= nil)
		.. " Component="
		.. tostring(_G.CrimeSpreeGageServicesMenuComponent ~= nil)
)
if MenuHelper and CrimeSpreeGageServicesMenuComponent then
	MenuHelper:AddComponent("csr_gage_services_component", CrimeSpreeGageServicesMenuComponent)
	log("[CSR GAGE] component registered immediately")
else
	Hooks:Add("MenuManagerInitialize", "CSR_GageServicesComponentDeferred", function(menu_manager)
		log(
			"[CSR GAGE] deferred fire: MenuHelper="
				.. tostring(MenuHelper ~= nil)
				.. " Component="
				.. tostring(_G.CrimeSpreeGageServicesMenuComponent ~= nil)
		)
		if MenuHelper and CrimeSpreeGageServicesMenuComponent then
			MenuHelper:AddComponent("csr_gage_services_component", CrimeSpreeGageServicesMenuComponent)
			log("[CSR GAGE] component registered via deferred path")
		else
			log("[CSR GAGE] component STILL not available after MenuManagerInitialize")
		end
	end)
end
