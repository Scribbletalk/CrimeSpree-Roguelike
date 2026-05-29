-- Host-state push: broadcasts rank/difficulty/seed/tokens to peers; loaded in both Lua states so broadcast_host_state exists for lobby-join and at_enter.

if not RequiredScript then
	return
end

local CSR_MP = _G.CSR_MP

local function csr_heist_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

local function broadcast_host_state()
	if not (CSR_MP and CSR_MP.is_host and CSR_MP.is_host() and CSR_MP.is_multiplayer()) then
		return
	end
	local mgr = managers and managers.csr
	if not mgr then
		return
	end
	local gs = Global and Global.game_settings
	local payload = json.encode({
		version = (mgr.mod_version and mgr:mod_version()) or "unknown",
		host_rank = mgr:rank(),
		host_difficulty = mgr:difficulty(),
		host_missions_completed = (mgr.missions_completed and mgr:missions_completed()) or 0,
		run_seed = mgr:seed(),
		host_level_id = (gs and gs.level_id) or false,
		host_mission = (gs and gs.mission) or "none",
		host_tokens_gross = (_G.CSR_Shop and _G.CSR_Shop.gross_earned and _G.CSR_Shop.gross_earned()) or 0,
	})
	LuaNetworking:SendToPeers(CSR_MP.MSG.HANDSHAKE_OK, payload)
	-- Mission set rides the same triggers so guest cards match host's.
	if CSR_MP.broadcast_mission_set then
		CSR_MP.broadcast_mission_set()
	end
	if CSR_MP.log then
		CSR_MP.log("broadcast_host_state rank=" .. tostring(mgr:rank()) .. " diff=" .. tostring(mgr:difficulty()))
	end
end

-- Exposed so mp_sync.lua's LOBBY_PING handler can push host state on lobby join.
if CSR_MP then
	CSR_MP.broadcast_host_state = broadcast_host_state
end

if CSR_MP and CSR_MP.register_handler then
	CSR_MP.register_handler(CSR_MP.MSG.HANDSHAKE_OK, function(sender, data, sender_num, is_from_host)
		if not (CSR_MP.is_client and CSR_MP.is_client() and is_from_host) then
			return
		end
		-- Not gated on csr_heist_active() — it's false in lobby; is_from_host blocks forgery.
		local ok, payload = pcall(json.decode, data)
		if not ok or type(payload) ~= "table" then
			return
		end
		local mgr = managers and managers.csr
		if mgr and mgr.set_mp_host_state then
			mgr:set_mp_host_state(
				tonumber(payload.host_rank),
				payload.host_difficulty,
				tonumber(payload.run_seed),
				tonumber(payload.host_missions_completed)
			)
			-- Adopt host's level/mission so the guest loads the same heist.
			if Global and Global.game_settings then
				if type(payload.host_level_id) == "string" then
					Global.game_settings.level_id = payload.host_level_id
				end
				if payload.host_mission ~= nil then
					Global.game_settings.mission = payload.host_mission
				end
				if type(payload.host_difficulty) == "string" then
					Global.game_settings.difficulty = payload.host_difficulty
				end
			end
			-- Repaint lobby rank + item quota if currently open.
			local comp = managers.menu_component and managers.menu_component._crime_spree_missions
			if comp and comp.refresh_for_rank_change then
				comp:refresh_for_rank_change()
			end
			-- Re-apply modifiers with fresh host_rank; guest at_enter often fires before state arrives.
			if mgr.apply_modifiers then
				mgr:apply_modifiers()
			end
			if CSR_MP.log then
				CSR_MP.log(
					"applied host state rank="
						.. tostring(payload.host_rank)
						.. " diff="
						.. tostring(payload.host_difficulty)
				)
			end
		end

		-- Late-join auto-grant: convert the host's progress into items for the guest (no choosing).
		-- Runs as a first grant, or an INCREMENTAL delta when the host has completed more missions
		-- since the last grant (snapshot keyed per host run). Guest-only; host/SP never reach here.
		if _G.CSR_Shop and mgr and mgr.guest_grant_missions and _G.CSR_Shop.auto_grant_late_join then
			local pid = CSR_MP.local_peer_id()
			local hrank = tonumber(payload.host_rank) or 0
			local hmissions = tonumber(payload.host_missions_completed) or 0
			local gross = tonumber(payload.host_tokens_gross) or 0
			local prev = mgr:guest_grant_missions() -- nil before the first grant
			if prev ~= hmissions then
				local prev_gross = mgr:guest_grant_gross()
				local leftover = _G.CSR_Shop.auto_grant_late_join(pid, hrank, gross, hmissions, prev_gross)
				-- Add (don't overwrite) the leftover: the guest may already hold a balance. set_tokens
				-- leaves gross untouched so this never re-triggers the grant.
				_G.CSR_Shop.set_tokens(pid, _G.CSR_Shop.tokens(pid) + leftover)
				mgr:mark_guest_grant(hmissions, gross)
				if _G.CSR_MP.broadcast_own_items then
					_G.CSR_MP.broadcast_own_items()
				end
				local comp = managers.menu_component and managers.menu_component._crime_spree_missions
				if comp and comp.refresh_for_rank_change then
					comp:refresh_for_rank_change()
				end
				if CSR_MP.log then
					CSR_MP.log(
						"late-join grant rank="
							.. tostring(hrank)
							.. " missions="
							.. tostring(hmissions)
							.. " leftover="
							.. tostring(leftover)
					)
				end
			end
		end
	end)

	-- Host: a guest asked for current host-state. Reply with full broadcast.
	CSR_MP.register_handler(CSR_MP.MSG.HANDSHAKE, function(sender, data, sender_num, is_from_host)
		if not (CSR_MP.is_host and CSR_MP.is_host()) then
			return
		end
		broadcast_host_state()
	end)
end

if IngameWaitingForPlayersState and not _G._CSR_MP_SESSION_HOOKED then
	_G._CSR_MP_SESSION_HOOKED = true

	Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_MP_HostStatePush", function(self)
		if not CSR_MP then
			return
		end
		-- Guest: clear stale state then pull fresh — request-reply is more reliable than waiting on a push.
		if CSR_MP.is_client and CSR_MP.is_client() then
			if managers.csr and managers.csr.clear_mp_host_state then
				managers.csr:clear_mp_host_state()
			end
			if CSR_MP.request_host_state then
				CSR_MP.request_host_state()
			end
			return
		end
		-- Host: delayed push so state arrives after guests have cleared stale data.
		if CSR_MP.is_host and CSR_MP.is_host() and CSR_MP.is_multiplayer() and csr_heist_active() then
			DelayedCalls:Add("CSR_MP_HostStatePush", 0.75, broadcast_host_state)
		end
	end)
end

csr_log("[CSR] mp_session.lua loaded")
