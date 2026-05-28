-- Swap vanilla CrimeSpreeContractMenuComponent for CSRContractMenuComponent on the
-- CrimeNet CS contract popup. Vanilla create runs first (one-frame allocation,
-- discarded), then our PostHook closes it + registers ours under the same id.
-- Slice 5 accept-callback wrap moved to contract_callbacks.lua.

if not RequiredScript then
	return
end

Hooks:PostHook(
	MenuComponentManager,
	"create_crime_spree_contract_gui",
	"CSR_SwapContractGuiCreate",
	function(self, node)
		-- Vanilla's component is already in _alive_components under the id;
		-- close + unregister or register_component silently no-ops (first-wins)
		-- and the dead instance crashes on later mouse iteration.
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

		-- Vanilla close calls enable_crimenet only inside `if self._crime_spree_contract_menu_comp`.
		-- Our create nil'd that field, so vanilla's close skips enable_crimenet → CrimeNet stays
		-- frozen after closing the contract. Re-enable manually.
		self:enable_crimenet()
		csr_log("[CSR] wiring: CSRContractMenuComponent closed")
	end
end)

-- Lobby contract-box class swap. Vanilla's _contract_gui_class returns
-- ContractBoxGui (which draws "CHOOSE NEW CONTRACT FROM CRIME.NET" placeholder)
-- because managers.crime_spree:is_active() is false for CSR. We want vanilla's
-- CrimeSpreeContractBoxGui look (peer panels only, no placeholder text).
-- Scope signal: our CSRMissionsMenuComponent in self._crime_spree_missions — the
-- exact "we built the CSR lobby" flag, no leak even if managers.csr:is_active leaks.
local function csr_lobby_is_active(mcm)
	local comp = mcm and mcm._crime_spree_missions
	return comp ~= nil and CSRMissionsMenuComponent ~= nil and getmetatable(comp) == CSRMissionsMenuComponent
end

Hooks:PostHook(MenuComponentManager, "_contract_gui_class", "CSR_ContractGuiClass_UseCSBox", function(self)
	if csr_lobby_is_active(self) then
		return CrimeSpreeContractBoxGui
	end
end)

Hooks:Add("LocalizationManagerPostInit", "CSR_ContractHeaderLocalization", function(loc)
	loc:add_localized_strings({
		csr_header_title = "Crime Spree Roguelike",
		csr_end_spree = "End Spree",
		csr_return_to_lobby = "Return to Lobby",
		csr_contract_difficulty = "Difficulty",
		-- SuperBLT macro syntax: $name with optional ";" terminator (single $, not closing).
		csr_current_spree = "Current Spree: $status",
		csr_current_spree_active = "active",
		csr_current_spree_none = "none",
		-- CSR-owned key (NOT vanilla's dialog_are_you_sure_you_want_stop_cs — overriding that
		-- would leak into vanilla CS). End Spree ends the run AND grants rewards.
		csr_dialog_end_spree = "End your Crime Spree Roguelike run now and claim your rewards?",
	})
end)

csr_log("[CSR] contract_wiring.lua loaded")
