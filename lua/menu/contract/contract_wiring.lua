-- Swap vanilla CrimeSpreeContractMenuComponent for CSRContractMenuComponent on CrimeNet popup.

if not RequiredScript then
	return
end

-- True once the CSR lobby's own missions component is up, i.e. a contract was accepted rather than
-- backed out of. Also decides CrimeSpreeContractBoxGui (peer panels) over ContractBoxGui.
local function csr_lobby_is_active(mcm)
	local comp = mcm and mcm._crime_spree_missions
	return comp ~= nil and CSRMissionsMenuComponent ~= nil and getmetatable(comp) == CSRMissionsMenuComponent
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

		-- Our create nil'd _crime_spree_contract_menu_comp, so vanilla's close skips enable_crimenet.
		-- Only re-enable when the popup is actually being backed out of. Accepting builds the lobby
		-- FIRST and closes the popup after, and enable_crimenet sets a flag that MenuComponentManager
		-- consumes on the next frame -> CrimeNetGui:enable_crimenet -> managers.crimenet:activate().
		-- CrimeNetManager:update gates on nothing but that flag, so it goes on spawning and removing
		-- job widgets on the CrimeNet map while the lobby transition tears it down: native crash one
		-- frame after this hook returns.
		if self:has_crimenet_gui() and not csr_lobby_is_active(self) then
			self:enable_crimenet()
		end
		csr_log("[CSR] wiring: CSRContractMenuComponent closed")
	end
end)

Hooks:PostHook(MenuComponentManager, "_contract_gui_class", "CSR_ContractGuiClass_UseCSBox", function(self)
	if csr_lobby_is_active(self) then
		return CrimeSpreeContractBoxGui
	end
end)

csr_log("[CSR] contract_wiring.lua loaded")
