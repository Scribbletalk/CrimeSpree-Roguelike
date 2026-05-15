-- CSR contract wiring — Slice 4.
--
-- Hooks vanilla's MenuComponentManager so the popup that opens when the player
-- clicks the CrimeNet sidebar's "Crime Spree" entry is OUR forked
-- CSRContractMenuComponent (Slice 2) instead of vanilla's CrimeSpreeContractMenuComponent.
--
-- Sequence on each open:
--   1. Vanilla create_crime_spree_contract_gui runs:
--      - instantiates CrimeSpreeContractMenuComponent into self._crime_spree_contract_menu_comp
--      - registers it under "crimenet_crime_spree_contract"
--   2. Our PostHook fires:
--      - closes vanilla's just-created component (one-frame allocation, throwaway)
--      - instantiates CSRContractMenuComponent into self._csr_contract_menu_comp
--      - re-registers under the same name so the menu manager finds OUR component
--
-- Sequence on close:
--   1. Vanilla close_crime_spree_contract_gui runs:
--      - vanilla's cache is nil (we nil'd it during create), so vanilla no-ops
--   2. Our PostHook fires:
--      - closes our component, unregisters from the named slot
--
-- This swap does NOT touch the accept callback. Vanilla's accept_crime_spree_contract
-- still fires when the player clicks Accept. Wiring our accept_csr_contract is Slice 5.

if not RequiredScript then
	return
end

Hooks:PostHook(
	MenuComponentManager,
	"create_crime_spree_contract_gui",
	"CSR_SwapContractGuiCreate",
	function(self, node)
		-- Vanilla already created its component AND inserted it into _alive_components
		-- under id "crimenet_crime_spree_contract". We must :close() AND
		-- :unregister_component() before re-registering ours, otherwise vanilla's
		-- dead-panel'd instance stays in the iteration list and crashes on mouse events
		-- (PD2's register_component is first-wins on the id key — silently no-ops the second register).
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
		log("[CSR] wiring: vanilla CS contract popup swapped for CSRContractMenuComponent")
	end
)

Hooks:PostHook(MenuComponentManager, "close_crime_spree_contract_gui", "CSR_SwapContractGuiClose", function(self, node)
	if self._csr_contract_menu_comp then
		self._csr_contract_menu_comp:close()

		self._csr_contract_menu_comp = nil

		self:unregister_component("crimenet_crime_spree_contract")
		log("[CSR] wiring: CSRContractMenuComponent closed")
	end
end)

Hooks:Add("LocalizationManagerPostInit", "CSR_ContractHeaderLocalization", function(loc)
	loc:add_localized_strings({
		csr_header_title = "Crime Spree Roguelike",
		csr_header_level = "Crime Spree Roguelike Level $level$",
		csr_header_level_no_num = "Crime Spree Roguelike Level ",
	})
end)

-- NOTE: the Slice 5 accept-callback wrap moved to csr_contract_callbacks.lua
-- (hooked at lib/managers/menumanager). It must wrap AFTER vanilla's
-- MenuManagerCrimeSpreeCallbacks finishes loading, otherwise vanilla's late
-- definition of accept_crime_spree_contract overwrites our wrap.

log("[CSR] csr_contract_wiring.lua loaded (Slice 4 wiring)")
