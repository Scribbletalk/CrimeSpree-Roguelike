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
		-- Gate on node identity, not is_active(): that flag leaks into post-heist lobbies.
		-- Allow guests: they have no own run but need CSR lobby UI via CSR_MP reroute.
		local is_guest = _G.CSR_MP and _G.CSR_MP.is_client and _G.CSR_MP.is_client()
		if not node or not managers.csr or not (managers.csr:is_active() or is_guest) then
			return
		end

		local params = node.parameters and node:parameters()
		-- "main" node doubles as normal crew-lobby; job id is the safe boundary for end-screen.
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

		-- Close the leftover end-screen HUD backdrop before the lobby header draws.
		-- Vanilla clears it via full main-menu rebuild; CSR reuses the "menu" workspace so it bleeds through.
		if in_lobby and managers.hud and managers.hud._hud_stage_endscreen then
			local es = managers.hud._hud_stage_endscreen
			if CSRHUDStageEndScreen and getmetatable(es) == CSRHUDStageEndScreen and es.close then
				es:close()
				managers.hud._hud_stage_endscreen = nil
				csr_log("[CSR] wiring: closed leftover end-screen HUD backdrop on lobby build")
			end
		end

		-- Old saves may load with an empty mission set.
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

		-- Force contract-box rebuild so contract_wiring returns CrimeSpreeContractBoxGui.
		-- Without this, heist->lobby reinit rebuilds the box with vanilla ContractBoxGui before this swap runs.
		if in_lobby and self.create_contract_gui then
			self:create_contract_gui()
			csr_log("[CSR] wiring: forced contract-box rebuild for CSR lobby")
		end

		-- Sync inventories and pull host-state on both surfaces.
		-- Guest needs fresh rank/items/mission-set; pull host-state here (reliable is_client-ready point).
		if (in_lobby or in_endscreen) and _G.CSR_MP and _G.CSR_MP.is_multiplayer and _G.CSR_MP.is_multiplayer() then
			_G.CSR_MP.broadcast_own_items()
			if _G.CSR_MP.is_client and _G.CSR_MP.is_client() then
				if managers.csr and managers.csr.clear_remote_peers then
					managers.csr:clear_remote_peers()
				end
				_G.CSR_MP.request_all_items()
				if _G.CSR_MP.request_host_state then
					_G.CSR_MP.request_host_state()
				end
			end
		end
	end
)

-- Reposition the MP lobby-code widget when created after our missions component.
-- (Opposite order: _create_title calls _reposition_lobby_code directly.)
Hooks:PostHook(MenuComponentManager, "create_lobby_code_gui", "CSR_RepositionLobbyCode", function(self, node)
	local comp = self._crime_spree_missions
	if comp and CSRMissionsMenuComponent ~= nil and getmetatable(comp) == CSRMissionsMenuComponent then
		if comp._reposition_lobby_code then
			comp:_reposition_lobby_code()
		end
	end
end)

-- Per-frame poll to hide the mission-cards cluster when a sub-screen (Options / Player List / etc.)
-- overlays the lobby. open_node/show_node/set_active_components do NOT fire for these buttons --
-- they open a dialog over the lobby without changing the selected node. update() self-heals against
-- the lobby's ~1Hz rebuild loop.
if CSRMissionsMenuComponent and not _G._CSR_LOBBY_OVERLAY_HIDE_HOOKED then
	_G._CSR_LOBBY_OVERLAY_HIDE_HOOKED = true

	-- Panels always force-toggled both ways.
	function CSRMissionsMenuComponent:_csr_always_cluster()
		local list = {}
		local function add(p)
			if p and alive(p) then
				list[#list + 1] = p
			end
		end
		add(self._buttons_panel)
		add(self._title_panel)
		add(self._actions_bg)
		if self._start_button then
			add(self._start_button:panel())
		end
		if self._reroll_button then
			add(self._reroll_button:panel())
		end
		if self._action_button then
			add(self._action_button:panel())
		end
		return list
	end

	-- Panels hidden with the cluster but restored to their pre-hide visibility -- never force-shown.
	function CSRMissionsMenuComponent:_csr_cond_cluster()
		local list = {}
		local function add(p)
			if p and alive(p) then
				list[#list + 1] = p
			end
		end
		add(self._unselected_panel)
		add(self._unselected_bg)
		add(self._csr_bm_lobby_panel)
		add(self._csr_bm_lobby_bg)
		return list
	end

	function CSRMissionsMenuComponent:_csr_set_cards_hidden(hidden)
		if self._csr_overlay_active == nil then
			self._csr_overlay_active = false
		end

		if self._csr_overlay_active == hidden then
			-- Re-assert every frame while hidden; lobby's ~1Hz rebuild can revive panels.
			-- Cache panel lists; rebuild if the first entry died (rebuild replaced all panels).
			if hidden then
				local always = self._csr_always_cache
				local cond = self._csr_cond_cache
				if not always or (always[1] ~= nil and not alive(always[1])) then
					always = self:_csr_always_cluster()
					cond = self:_csr_cond_cluster()
					self._csr_always_cache = always
					self._csr_cond_cache = cond
				end
				for _, p in ipairs(always) do
					p:set_visible(false)
				end
				for _, p in ipairs(cond) do
					p:set_visible(false)
				end
			end
			return
		end

		self._csr_overlay_active = hidden

		if hidden then
			local always = self:_csr_always_cluster()
			local cond = self:_csr_cond_cluster()
			self._csr_always_cache = always
			self._csr_cond_cache = cond
			self._csr_cond_vis = {}
			for i, p in ipairs(cond) do
				self._csr_cond_vis[i] = p:visible()
				p:set_visible(false)
			end
			for _, p in ipairs(always) do
				p:set_visible(false)
			end
			csr_log("[CSR] lobby cards hidden (sub-screen open)")
		else
			local always = self._csr_always_cache or self:_csr_always_cluster()
			for _, p in ipairs(always) do
				if alive(p) then
					p:set_visible(true)
				end
			end
			if self._csr_cond_vis then
				local cond = self._csr_cond_cache or self:_csr_cond_cluster()
				for i, p in ipairs(cond) do
					if alive(p) then
						p:set_visible(self._csr_cond_vis[i] == true)
					end
				end
				self._csr_cond_vis = nil
			end
			self._csr_always_cache = nil
			self._csr_cond_cache = nil
			csr_log("[CSR] lobby cards restored (sub-screen closed)")
		end
	end

	Hooks:PostHook(CSRMissionsMenuComponent, "update", "CSR_HideUnderSubscreen", function(self)
		-- End-screen reuses this component under node "main"; skip it.
		if not self._is_lobby or not alive(self._panel) then
			return
		end

		-- Default to NOT covered on any read failure so a glitch never permanently hides the lobby.
		local node_name
		local am = managers.menu and managers.menu:active_menu()
		if am and am.logic and am.logic.selected_node and am.logic:selected_node() then
			node_name = am.logic:selected_node():parameters().name
		end

		local covered = node_name ~= nil and node_name ~= "crime_spree_lobby"
		self:_csr_set_cards_hidden(covered)
	end)
end

csr_log("[CSR] missions_wiring.lua loaded (Slice 8 wiring)")
