-- CSR missions GUI wiring — Slice 8.
--
-- Hooks vanilla's MenuComponentManager so the in-lobby mission-select panel is
-- OUR forked CSRMissionsMenuComponent (csr_missions_menu.lua) instead of
-- vanilla's CrimeSpreeMissionsMenuComponent.
--
-- Why this is simpler than the contract wiring: vanilla's
-- create_crime_spree_missions_gui early-returns on `not managers.crime_spree:is_active()`,
-- and we no longer activate vanilla CS (Slice 6), so vanilla NEVER builds or
-- registers its component. Our PostHook fires afterwards and builds ours.
--
-- We intentionally store our component in vanilla's own `self._crime_spree_missions`
-- slot (not a private slot) so:
--   * MenuComponentManager:crime_spree_missions_gui() returns ours for free
--     (the free-reroll callback uses that accessor), and
--   * vanilla close_crime_spree_missions_gui() already does the correct
--     close + nil + unregister on that slot, so no close PostHook is needed.
--
-- The defensive close+unregister-before-recreate guard mirrors csr_contract_wiring.lua
-- and exists because PD2's register_component is first-wins on the id key: a
-- dead-panel'd leftover under "crime_spree_missions" would crash on mouse
-- iteration (see pd2_register_component_first_wins memory).

if not RequiredScript then
	return
end

Hooks:PostHook(
	MenuComponentManager,
	"create_crime_spree_missions_gui",
	"CSR_SwapMissionsGuiCreate",
	function(self, node)
		if not node or not managers.csr or not managers.csr:is_active() then
			return
		end

		-- A run can be active with an empty mission set (old save migrated, or
		-- start_run early-returned on a loaded already-active state). Generate
		-- one now so the panel never builds empty cards. Idempotent — a
		-- populated set is left untouched (no reroll on contract reopen).
		if managers.csr.ensure_mission_set then
			managers.csr:ensure_mission_set()
		end

		if self._crime_spree_missions then
			self._crime_spree_missions:close()

			self._crime_spree_missions = nil

			self:unregister_component("crime_spree_missions")
		end

		self._crime_spree_missions = CSRMissionsMenuComponent:new(self._ws, self._fullscreen_ws, node)

		self:register_component("crime_spree_missions", self._crime_spree_missions)
		log("[CSR] wiring: vanilla CS missions panel swapped for CSRMissionsMenuComponent")
	end
)

log("[CSR] csr_missions_wiring.lua loaded (Slice 8 wiring)")
