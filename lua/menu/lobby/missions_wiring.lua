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

		-- Tear down the leftover end-screen HUD backdrop (the faded mission-name ghost) before the
		-- lobby header draws. Vanilla relies on a full main-menu rebuild to clear it; CSR's
		-- return-to-lobby reuses the "menu" workspace, so the backdrop bleeds through under the
		-- "CRIME SPREE ROGUELIKE" header. Lobby surface only; the end-screen still needs its ghost.
		if in_lobby and managers.hud and managers.hud._hud_stage_endscreen then
			local es = managers.hud._hud_stage_endscreen
			if CSRHUDStageEndScreen and getmetatable(es) == CSRHUDStageEndScreen and es.close then
				es:close()
				managers.hud._hud_stage_endscreen = nil
				csr_log("[CSR] wiring: closed leftover end-screen HUD backdrop on lobby build")
			end
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

		-- Force a contract-box rebuild now that _crime_spree_missions is set, so contract_wiring's
		-- _contract_gui_class hook returns CrimeSpreeContractBoxGui (no vanilla "PLANNING PHASE"
		-- crewpage ghost overlapping the header). Needed in SP too: after a heist->lobby reinit the
		-- "contract" box is rebuilt with vanilla ContractBoxGui before this swap runs, leaking the ghost.
		if in_lobby and self.create_contract_gui then
			self:create_contract_gui()
			csr_log("[CSR] wiring: forced contract-box rebuild for CSR lobby")
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

-- Hide ONLY the mission-cards cluster (cards + their status bar + Start/Reroll/action buttons +
-- the reminders) when a sub-screen (Options / Edit Game Settings / Player List) is open on top of
-- the lobby; the sidebar and the "Crime Spree Roguelike" header are siblings and stay visible.
--
-- Why a per-frame poll, not an open_node / show_node / set_active_components hook: in-game testing
-- proved NONE of those fire for these lobby buttons -- they open a separate menu/dialog OVER the
-- lobby without changing the lobby menu's selected node, so the component stays live underneath.
-- update() ticks on every live component (MenuComponentManager:run_on_all_live_components), so the
-- poll runs even while the overlay is up and self-heals against the lobby's ~1Hz rebuild loop.
if CSRMissionsMenuComponent and not _G._CSR_LOBBY_OVERLAY_HIDE_HOOKED then
	_G._CSR_LOBBY_OVERLAY_HIDE_HOOKED = true

	-- Always part of the cluster: force-toggled both ways.
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

	-- Conditionally-visible members: hidden with the cluster, but on reveal restored to whatever
	-- their own logic had set (captured at hide time) -- never force-shown.
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
			-- Re-assert each frame while hidden so the lobby's ~1Hz rebuild can't reveal the cluster.
			-- Use cached lists to avoid allocating tables every frame; rebuild the cache if the first
			-- panel died (lobby rebuild replaces all panels atomically).
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
		-- Lobby surface only: the end-screen surface reuses this component under node "main".
		if not self._is_lobby or not alive(self._panel) then
			return
		end

		-- Read the top menu's current node. nil-safe: on any read failure default to NOT covered,
		-- so a glitch can never leave the lobby permanently hidden.
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
