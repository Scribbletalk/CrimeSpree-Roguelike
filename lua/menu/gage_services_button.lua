-- Crime Spree Roguelike - Gage's Services Entry Button
-- Mirrors logbook_button.lua + logbook_page.lua tab-intercept pattern.
-- mod.txt should load this file BEFORE logbook_page.lua for tab-positioning
-- aesthetics (Gage's Services before Logbook), but load order is no longer
-- functionally critical — the tab is detected by name_id, not absolute position.

log("[CSR GAGE] gage_services_button.lua loaded; RequiredScript=" .. tostring(RequiredScript))

if not RequiredScript then
	log("[CSR GAGE] EXIT: no RequiredScript")
	return
end

if not MenuCallbackHandler then
	log("[CSR GAGE] EXIT: MenuCallbackHandler missing")
	return
end

MenuCallbackHandler.CSR_OpenGageServices = function(this, item)
	pcall(function()
		managers.menu:open_node("csr_gage_services_screen")
	end)
end
log("[CSR GAGE] CSR_OpenGageServices callback registered")

if not CrimeSpreeDetailsMenuComponent then
	log("[CSR GAGE] EXIT: CrimeSpreeDetailsMenuComponent NOT available at this hook point")
	return
end

log("[CSR GAGE] CrimeSpreeDetailsMenuComponent available -- registering PostHooks")

Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddGageServicesTab", function(self, tabs_data)
	log("[CSR GAGE] populate_tabs_data fired; inserting GAGE'S SERVICES tab")
	table.insert(tabs_data, {
		name_id = "menu_csr_gage_services",
		width_multiplier = 1,
		page_class = "CrimeSpreeModifierDetailsPage",
	})
end)

-- Intercept tab switch — Gage's Services is the second-to-last tab
-- (Logbook is last; Gage was inserted first by mod.txt load order, so Logbook ends up last).
Hooks:PostHook(
	CrimeSpreeDetailsMenuComponent,
	"set_active_page",
	"CSR_GageServicesTabIntercept",
	function(self, new_index)
		if not self._tabs then
			return
		end
		log(
			"[CSR GAGE] set_active_page PostHook fired; new_index="
				.. tostring(new_index)
				.. " total_tabs="
				.. tostring(#self._tabs)
		)
		if new_index == #self._tabs - 1 then
			pcall(function()
				managers.menu:open_node("csr_gage_services_screen")
			end)
			self:set_active_page(1)
		end
	end
)

log("[CSR GAGE] PostHooks installed successfully")
