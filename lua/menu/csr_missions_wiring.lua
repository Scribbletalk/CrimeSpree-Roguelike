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
		-- No-leak gate (feedback_csr_only_no_vanilla_leak). managers.csr:is_active()
		-- alone is NOT a safe gate here: it is a persisted csr_save.json flag and
		-- end_run() is never driven in 6.3, so after the first start_run() it stays
		-- true across sessions. Vanilla create_crime_spree_missions_gui is invoked
		-- as a registered component create-callback for EVERY node that lists the
		-- crime_spree_missions component (vanilla no-ops via its own
		-- managers.crime_spree:is_active() guard); our PostHook fired anyway and a
		-- leaked is_active=true rebuilt the CSR sidebar/start/reroll panel in the
		-- normal post-heist crew lobby (user report 2026-05-18).
		--
		-- The correctly-scoped signal is node identity, not the flag: the CSR
		-- lobby is always entered via select_node("crime_spree_lobby", ...)
		-- (csr_contract_callbacks.lua, menumanagerpd2.lua) — the same node vanilla
		-- CS uses. node:parameters().name is vanilla's own node-name idiom
		-- (menucomponentmanager.lua:2525). We also exclude a real vanilla CS run
		-- (not managers.crime_spree:is_active()) to mirror the briefing/contract
		-- no-leak pattern; CSR never activates vanilla CS (Slice 6).
		if not node or not managers.csr or not managers.csr:is_active() then
			return
		end

		local params = node.parameters and node:parameters()
		-- Two safe build surfaces, each with its own no-leak boundary
		-- (feedback_csr_only_no_vanilla_leak — the persisted
		-- managers.csr:is_active() flag is required above but is NOT a
		-- safe boundary by itself on a generic node):
		--  * LOBBY: node name "crime_spree_lobby" is itself the boundary
		--    (CSR-specific node — the verified-correct lobby signal). The
		--    user-tested working path; unchanged.
		--  * END SCREEN: mission_end_menu's ONLY node is the GENERIC name
		--    "main" (verified gamedata/menus/mission_end_menu.menu lists
		--    crime_spree_missions among that node's menu_components).
		--    "main" is also the normal crew-lobby / main-menu node, so
		--    node-name alone is unsafe here. The safe boundary for the
		--    generic node is the RUN-SCOPED CSR-heist signal: the active
		--    job is the temporary "crime_spree" job (still set on the end
		--    screen — MissionEndState deactivates it later, in
		--    :at_exit -> _load_start_menu) AND vanilla CS NOT active
		--    (excluded just below). Byte-identical to
		--    csr_mission_lifecycle.lua:csr_heist_active().
		local in_lobby = params and params.name == "crime_spree_lobby"
		local in_endscreen = params
			and params.name == "main"
			and managers.job
			and managers.job:current_job_id() == "crime_spree"
		if not (in_lobby or in_endscreen) then
			return
		end

		if managers.crime_spree and managers.crime_spree:is_active() then
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
