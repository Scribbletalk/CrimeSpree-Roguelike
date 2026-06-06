-- Swap vanilla CrimeSpreeContractMenuComponent for CSRContractMenuComponent on CrimeNet popup.

if not RequiredScript then
	return
end

Hooks:PostHook(
	MenuComponentManager,
	"create_crime_spree_contract_gui",
	"CSR_SwapContractGuiCreate",
	function(self, node)
		-- register_component is first-wins; must unregister first or the dead instance crashes mouse iteration.
		if self._crime_spree_contract_menu_comp then
			self._crime_spree_contract_menu_comp:close()
			self._crime_spree_contract_menu_comp = nil
		end

		self:unregister_component("crimenet_crime_spree_contract")

		if self._csr_contract_menu_comp then
			self._csr_contract_menu_comp:close()
		end

		self._csr_contract_menu_comp = CSRContractMenuComponent:new(self._ws, self._fullscreen_ws, node)

		self:register_component("crimenet_crime_spree_contract", self._csr_contract_menu_comp)
		csr_log("[CSR] wiring: vanilla CS contract popup swapped for CSRContractMenuComponent")
	end
)

Hooks:PostHook(MenuComponentManager, "close_crime_spree_contract_gui", "CSR_SwapContractGuiClose", function(self, node)
	if self._csr_contract_menu_comp then
		self._csr_contract_menu_comp:close()
		self._csr_contract_menu_comp = nil
		self:unregister_component("crimenet_crime_spree_contract")

		-- Our create nil'd _crime_spree_contract_menu_comp, so vanilla's close skips enable_crimenet; call it manually.
		self:enable_crimenet()
		csr_log("[CSR] wiring: CSRContractMenuComponent closed")
	end
end)

-- Use CrimeSpreeContractBoxGui (peer panels) instead of ContractBoxGui (placeholder text) in the CSR lobby.
local function csr_lobby_is_active(mcm)
	local comp = mcm and mcm._crime_spree_missions
	return comp ~= nil and CSRMissionsMenuComponent ~= nil and getmetatable(comp) == CSRMissionsMenuComponent
end

Hooks:PostHook(MenuComponentManager, "_contract_gui_class", "CSR_ContractGuiClass_UseCSBox", function(self)
	if csr_lobby_is_active(self) then
		return CrimeSpreeContractBoxGui
	end
end)

csr_log("[CSR] contract_wiring.lua loaded")
