-- CSR missions GUI wiring — Slice 8.
--
-- Hooks vanilla's MenuComponentManager so the in-lobby mission-select panel is
-- OUR forked CSRMissionsMenuComponent (missions_menu.lua) instead of
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
-- The defensive close+unregister-before-recreate guard mirrors contract_wiring.lua
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
		-- end_run() is never driven in U1, so after the first start_run() it stays
		-- true across sessions. Vanilla create_crime_spree_missions_gui is invoked
		-- as a registered component create-callback for EVERY node that lists the
		-- crime_spree_missions component (vanilla no-ops via its own
		-- managers.crime_spree:is_active() guard); our PostHook fired anyway and a
		-- leaked is_active=true rebuilt the CSR sidebar/start/reroll panel in the
		-- normal post-heist crew lobby (user report 2026-05-18).
		--
		-- The correctly-scoped signal is node identity, not the flag: the CSR
		-- lobby is always entered via select_node("crime_spree_lobby", ...)
		-- (contract_callbacks.lua, menumanagerpd2.lua) — the same node vanilla
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
		--    mission_lifecycle.lua:csr_heist_active().
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

		-- MP lobby: force the contract/crew box to rebuild now that
		-- _crime_spree_missions is stored. Hosting online enters the normal "lobby"
		-- node FIRST -- which builds a plain ContractBoxGui whose crewpage
		-- "PLANNING PHASE" title overlaps the CSR header -- and only then reroutes
		-- to crime_spree_lobby (lobby_routing.lua). The contract component's own
		-- create callback no-ops when a box already exists, so that stale vanilla
		-- box survives the reroute. create_contract_gui() closes + recreates it,
		-- re-running _contract_gui_class -> our PostHook (contract_wiring.lua) now
		-- returns CrimeSpreeContractBoxGui (no crewpage) because _crime_spree_missions
		-- is set. SP builds the CSR box on the first try (no normal-lobby detour), so
		-- this is MP + lobby only (user report 2026-05-25).
		if in_lobby and not Global.game_settings.single_player and self.create_contract_gui then
			self:create_contract_gui()
			log("[CSR] wiring: forced contract-box rebuild for CSR lobby (MP)")
		end
	end
)

-- Reposition the MP lobby-code widget when it is (re)created for the CSR lobby.
-- Covers the build order where the lobby_code component is created AFTER our
-- missions component (the other order is handled by _create_title calling
-- _reposition_lobby_code directly). The reposition geometry lives on the
-- component, which owns the header. MP-only by nature (no lobby code in SP);
-- scoped to the live CSR missions component (same getmetatable idiom as
-- contract_wiring.lua's csr_lobby_is_active).
Hooks:PostHook(MenuComponentManager, "create_lobby_code_gui", "CSR_RepositionLobbyCode", function(self, node)
	local comp = self._crime_spree_missions
	if comp and CSRMissionsMenuComponent ~= nil and getmetatable(comp) == CSRMissionsMenuComponent then
		if comp._reposition_lobby_code then
			comp:_reposition_lobby_code()
		end
	end
end)

log("[CSR] missions_wiring.lua loaded (Slice 8 wiring)")
