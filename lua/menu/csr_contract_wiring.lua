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

-- Lobby contract-box class swap.
--
-- The in-lobby contract/crew box is built by MenuComponentManager:create_contract_gui,
-- which picks its class via _contract_gui_class(). Vanilla returns
-- CrimeSpreeContractBoxGui when managers.crime_spree:is_active(); we never
-- activate vanilla CS (Slice 6), so it falls through to plain ContractBoxGui.
-- ContractBoxGui draws the "CHOOSE NEW CONTRACT FROM CRIME.NET" placeholder
-- (contractboxgui.lua:42, shown when not managers.job:has_active_job()), which
-- then bleeds through the translucent mission cards.
--
-- CrimeSpreeContractBoxGui is backend-agnostic (no managers.crime_spree reads):
-- in single player _can_update() is false so it renders nothing; in MP it shows
-- only peer character panels — exactly the vanilla CS-lobby behaviour. We mirror
-- vanilla's branch with our own active check.
--
-- SuperBLT PostHook return-override is intentional and verified
-- (mods/base/req/core/Hooks.lua:272-285): a post hook returning a non-nil value
-- replaces the original return; returning nothing leaves vanilla's choice
-- (ContractBoxGui / SkirmishContractBoxGui / real-CS CrimeSpreeContractBoxGui)
-- untouched. This keeps Critical Rule #1 (no raw override / hook shadowing).
--
-- CSR-only scoping (no vanilla leak): managers.csr:is_active() alone is NOT
-- sufficient. _state.is_active is a persisted save flag (csr_save.json) that
-- CSRGameManager:load() restores verbatim; a run whose end_run() never fired
-- (backed out / crash / alpha has no robust run-state machine) leaves it true
-- across sessions. create_contract_gui()/_contract_gui_class() runs for EVERY
-- lobby (normal "lobby" node AND "crime_spree_lobby" node), so a leaked
-- is_active=true would suppress the vanilla "CHOOSE NEW CONTRACT" box in a
-- normal lobby too.
--
-- The exact, correctly-scoped "we are in the CSR lobby" signal: our forked
-- CSRMissionsMenuComponent. set_active_components builds a node's components in
-- list order via ipairs (menucomponentmanager.lua:596-601); the crime_spree_lobby
-- node lists "crime_spree_missions" BEFORE "contract", so the
-- create_crime_spree_missions_gui PostHook has already stored our component in
-- self._crime_spree_missions by the time _contract_gui_class runs for the
-- contract component. That component is built ONLY for crime_spree_lobby (the
-- normal "lobby" node has no crime_spree_missions component), and the missions
-- wiring itself gates on managers.csr:is_active() — so checking it here pins the
-- contract-box swap to exactly the cards' lifecycle. In any normal/vanilla
-- lobby self._crime_spree_missions is nil -> we return nil -> vanilla's box is
-- preserved byte-for-byte, even with a leaked is_active.
--
-- Class identity via getmetatable is the same pattern vanilla uses at
-- menucomponentmanager.lua:660 (getmetatable(self._contract_gui) == class).
--
-- MP note: still implicitly gated on managers.csr:is_active() (the missions
-- wiring won't have built our component otherwise). Until the MP sync slice
-- lands a client whose managers.csr is not yet active gets vanilla
-- ContractBoxGui; same scope boundary as the rest of the alpha (host/SP first).
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
		csr_header_level = "Crime Spree Roguelike Level $level$",
		csr_header_level_no_num = "Crime Spree Roguelike Level ",
		csr_end_spree = "End Spree",
		csr_return_to_lobby = "Return to Lobby",
	})
end)

-- NOTE: the Slice 5 accept-callback wrap moved to csr_contract_callbacks.lua
-- (hooked at lib/managers/menumanager). It must wrap AFTER vanilla's
-- MenuManagerCrimeSpreeCallbacks finishes loading, otherwise vanilla's late
-- definition of accept_crime_spree_contract overwrites our wrap.

log("[CSR] csr_contract_wiring.lua loaded (Slice 4 wiring)")
