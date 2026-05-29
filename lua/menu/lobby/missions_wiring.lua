-- Swap vanilla's CrimeSpreeMissionsMenuComponent for CSRMissionsMenuComponent in the lobby.
-- Store in vanilla's _crime_spree_missions slot so its accessor + close path work for free.

if not RequiredScript then
	return
end

Hooks:PostHook(
	MenuComponentManager,
	"create_crime_spree_missions_gui",
	"CSR_SwapMissionsGuiCreate",
	function(self, node)
		-- Gate on node identity, not managers.csr:is_active(): the flag persists across sessions
		-- and would leak our panel into normal post-heist lobbies. Also allow guests (they have
		-- no active own run but still need the CSR lobby UI via CSR_MP reroute).
		local is_guest = _G.CSR_MP and _G.CSR_MP.is_client and _G.CSR_MP.is_client()
		if not node or not managers.csr or not (managers.csr:is_active() or is_guest) then
			return
		end

		local params = node.parameters and node:parameters()
		-- Two valid build surfaces: crime_spree_lobby node (lobby), and "main" node
		-- when the active job is "crime_spree" (end screen — job id is the safe boundary
		-- because "main" is also the normal crew-lobby node).
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

		-- Ensure mission set exists (old saves may load with an empty set).
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
		csr_log("[CSR] wiring: vanilla CS missions panel swapped for CSRMissionsMenuComponent")

		-- MP only: hosting online enters normal "lobby" first, which builds a vanilla
		-- ContractBoxGui. Force a rebuild now that _crime_spree_missions is set so
		-- contract_wiring returns CrimeSpreeContractBoxGui (no crewpage overlap).
		if in_lobby and not Global.game_settings.single_player and self.create_contract_gui then
			self:create_contract_gui()
			csr_log("[CSR] wiring: forced contract-box rebuild for CSR lobby (MP)")
		end

		-- Sync inventories and pull host-state on both lobby and end screen builds.
		-- Guest needs fresh host rank/items/mission-set at both surfaces.
		if (in_lobby or in_endscreen) and _G.CSR_MP and _G.CSR_MP.is_multiplayer and _G.CSR_MP.is_multiplayer() then
			_G.CSR_MP.broadcast_own_items()
			if _G.CSR_MP.is_client and _G.CSR_MP.is_client() then
				if managers.csr and managers.csr.clear_remote_peers then
					managers.csr:clear_remote_peers()
				end
				_G.CSR_MP.request_all_items()
				-- Pull host-state here (reliable is_client-ready point) to avoid
				-- the race in on_enter_lobby where is_client() can still be false.
				if _G.CSR_MP.request_host_state then
					_G.CSR_MP.request_host_state()
				end
			end
		end
	end
)

-- Reposition the MP lobby-code widget when it is created after our missions component.
-- (The other order is handled by _create_title calling _reposition_lobby_code directly.)
Hooks:PostHook(MenuComponentManager, "create_lobby_code_gui", "CSR_RepositionLobbyCode", function(self, node)
	local comp = self._crime_spree_missions
	if comp and CSRMissionsMenuComponent ~= nil and getmetatable(comp) == CSRMissionsMenuComponent then
		if comp._reposition_lobby_code then
			comp:_reposition_lobby_code()
		end
	end
end)

csr_log("[CSR] missions_wiring.lua loaded (Slice 8 wiring)")
