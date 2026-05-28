-- Registers the Gage Services GUI component with MenuHelper so
-- MenuComponentManager instantiates it when black_market_screen opens.

csr_log(
	"[CSR Shop] black_market_component_register.lua loaded; MenuHelper="
		.. tostring(MenuHelper ~= nil)
		.. " CrimeSpreeBlackMarketMenuComponent="
		.. tostring(CrimeSpreeBlackMarketMenuComponent ~= nil)
)

if MenuHelper and CrimeSpreeBlackMarketMenuComponent then
	MenuHelper:AddComponent("black_market_component", CrimeSpreeBlackMarketMenuComponent)
	csr_log("[CSR Shop] black_market_component registered immediately")
else
	-- Defer: component class may not have loaded yet (inter-file order).
	Hooks:Add("MenuManagerInitialize", "CSR_BlackMarketComponentDeferred", function(menu_manager)
		if MenuHelper and CrimeSpreeBlackMarketMenuComponent then
			MenuHelper:AddComponent("black_market_component", CrimeSpreeBlackMarketMenuComponent)
			csr_log("[CSR Shop] black_market_component registered (deferred via MenuManagerInitialize)")
		else
			log("[CSR Shop] DEFERRED REGISTER FAILED: component class still missing")
		end
	end)
end
