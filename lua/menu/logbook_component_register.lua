-- Crime Spree Roguelike - Logbook GUI Component Registration
-- Registers GUI component via MenuHelper:AddComponent



-- Register component (MenuComponentManager will instantiate it)
if MenuHelper and CrimeSpreeLogbookMenuComponent then
	MenuHelper:AddComponent("csr_logbook_component", CrimeSpreeLogbookMenuComponent)
else

	-- Defer: try registering later
	Hooks:Add("MenuManagerInitialize", "CSR_LogbookComponentDeferred", function(menu_manager)
		if MenuHelper and CrimeSpreeLogbookMenuComponent then
			MenuHelper:AddComponent("csr_logbook_component", CrimeSpreeLogbookMenuComponent)
		else
		end
	end)
end

