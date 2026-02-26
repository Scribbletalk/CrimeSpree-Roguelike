-- Crime Spree Roguelike Alpha 1 - Enable filter for Modifiers tab UI

if not RequiredScript then
	return
end



-- Hook on add_modifiers_panel - enable filter before rendering
if CrimeSpreeModifierDetailsPage then
	Hooks:PreHook(CrimeSpreeModifierDetailsPage, "add_modifiers_panel", "CSR_EnableFilter", function(self)
		CSR_FilterForUI = true
	end)

	Hooks:PostHook(CrimeSpreeModifierDetailsPage, "add_modifiers_panel", "CSR_DisableFilter", function(self)
		CSR_FilterForUI = false
	end)

else
end
