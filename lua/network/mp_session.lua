-- Host-state push: broadcasts rank/difficulty/seed/tokens/addons to all peers.
-- Loaded in both Lua states so broadcast_host_state is available at lobby-join and at_enter.

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

-- Join gate: if the host has addons this guest lacks, show a dialog and eject to the main menu.
-- Guest may hold extra addons; only missing host addons block. Once per join via Global flag.
local function csr_addon_join_gate(host_addons_csv)
	if not (CSR_MP and CSR_MP.is_client and CSR_MP.is_client()) then
		return false
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.addon_signature) then
		return false
	end

	local local_set = {}
	for _, name in ipairs(mgr:addon_signature()) do
		local_set[name] = true
	end

	local missing = {}
	for name in tostring(host_addons_csv or ""):gmatch("[^,]+") do
		if name ~= "" and not local_set[name] then
			missing[#missing + 1] = name
		end
	end
	if #missing == 0 then
		-- Clear stale flag so a rejoin to a different host re-checks.
		Global.CSR_addon_gate_fired = nil
		return false
	end

	-- Gate already fired this join session; don't re-show.
	if Global.CSR_addon_gate_fired then
		return true
	end

	Global.CSR_addon_gate_fired = true
	if CSR_MP.log then
		CSR_MP.log("addon join gate: missing " .. table.concat(missing, ", "))
	end

	local L = managers.localization
	local title = (L and L:text("csr_addon_gate_title")) or "MISSING ADD-ONS"
	local body = (L and L:text("csr_addon_gate_text"))
		or "This host uses Crime Spree Roguelike add-ons you do not have installed:"
	local dialog_data = {
		title = title,
		text = body .. "\n\n" .. table.concat(missing, "\n"),
		button_list = {
			{
				text = (L and L:text("dialog_ok")) or "OK",
				callback_func = function()
					-- Vanilla client-leave sequence.
					if managers.network and managers.network.matchmake then
						managers.network.matchmake:leave_game()
					end
					if managers.network and managers.network.voice_chat then
						managers.network.voice_chat:destroy_voice()
					end
					if managers.network and managers.network.queue_stop_network then
						managers.network:queue_stop_network()
					end
					if managers.menu and managers.menu.exit_online_menues then
						managers.menu:exit_online_menues()
					end
					Global.CSR_addon_gate_fired = nil
				end,
			},
		},
	}
	if managers.system_menu and managers.system_menu.show then
		managers.system_menu:show(dialog_data)
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
		-- The CSR card the host has selected (drives the guest's lobby highlight). false = none.
		host_current_mission = (mgr.current_mission and mgr:current_mission()) or false,
		host_tokens_gross = (_G.CSR_Shop and _G.CSR_Shop.gross_earned and _G.CSR_Shop.gross_earned()) or 0,
		-- Addon signature for the MP join-gate (guest missing any of these is blocked).
		host_addons = table.concat((mgr.addon_signature and mgr:addon_signature()) or {}, ","),
	})
	-- Chat tunnel only (native RPC drops pre-heist). JSON can exceed 255-char wire cap, so chunk it.
	for _, chunk in ipairs(CSR_MP.build_raw_chunks("", payload, 180)) do
		LuaNetworking:SendToPeers(CSR_MP.MSG.HANDSHAKE_OK, chunk)
	end
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
		-- Not gated on csr_heist_active() (false in lobby); is_from_host blocks forgery.
		-- Reassemble chunked json ("idx/total~" header).
		CSR_MP._hs_buf = CSR_MP._hs_buf or { chunks = {}, total = 0 }
		local idx, total, body = string.match(tostring(data), "^(%d+)/(%d+)~(.*)$")
		idx, total = tonumber(idx), tonumber(total)
		if not (idx and total) then
			return
		end
		local buf = CSR_MP._hs_buf
		buf.total = total
		buf.chunks[idx] = body
		local filled = 0
		for i = 1, total do
			if buf.chunks[i] then
				filled = filled + 1
			end
		end
		if filled < total then
			return
		end
		local full = table.concat(buf.chunks, "", 1, total)
		CSR_MP._hs_buf = { chunks = {}, total = 0 }
		local ok, payload = pcall(json.decode, full)
		if not ok or type(payload) ~= "table" then
			return
		end
		-- Addon gate before adopting any host state.
		if csr_addon_join_gate(payload.host_addons) then
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
			-- Adopt host's level/mission so the guest loads the same heist map.
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
			-- Sync host's selected mission card for the guest's lobby highlight.
			if mgr.set_mp_host_current_mission then
				local hcm = payload.host_current_mission
				mgr:set_mp_host_current_mission((hcm ~= false and hcm) or nil)
			end
			-- Repaint lobby panel if open.
			local comp = managers.menu_component and managers.menu_component._crime_spree_missions
			if comp and comp.refresh_for_rank_change then
				comp:refresh_for_rank_change()
			end
			-- Mirror host's card pick on guest's mission cards (display only).
			if comp and comp._csr_apply_host_selection then
				comp:_csr_apply_host_selection(mgr.current_mission and mgr:current_mission())
			end
			-- Race guard: if host-state arrives after briefing built, build the CSR sidebar now.
			local brief = managers.menu_component and managers.menu_component._mission_briefing_gui
			if brief and brief._csr_build_sidebar then
				brief:_csr_build_sidebar()
			end
			-- Re-apply modifiers: guest at_enter may fire before host_rank arrives.
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

		-- Catch-up auto-grant for missions the guest missed while offline.
		-- Gated on not in_csr_heist(): host pushes incremented state while guest is still in-game,
		-- before mission_lifecycle bumps accounted. Lobby-only guard prevents stealing the present pick.
		if
			_G.CSR_Shop
			and mgr
			and mgr.guest_grant_missions
			and _G.CSR_Shop.auto_grant_late_join
			and not (mgr.in_csr_heist and mgr:in_csr_heist())
		then
			local pid = CSR_MP.local_peer_id()
			local hrank = tonumber(payload.host_rank) or 0
			local hmissions = tonumber(payload.host_missions_completed) or 0
			local gross = tonumber(payload.host_tokens_gross) or 0
			local accounted = mgr:guest_grant_missions() or 0
			if hmissions > accounted then
				local prev_gross = mgr:guest_grant_gross()
				local leftover = _G.CSR_Shop.auto_grant_late_join(pid, hrank, gross, hmissions, prev_gross)
				-- Add to existing balance (set_tokens leaves gross untouched, no re-trigger).
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
					CSR_MP.log("catch-up grant rank=" .. tostring(hrank) .. " missions=" .. tostring(hmissions))
				end
			else
				-- Present or fully caught-up: update gross baseline so future absences convert only
				-- tokens earned while away, not tokens the guest already earned in present missions.
				mgr:mark_guest_grant(accounted, gross)
			end
		end
	end)

	-- Host: a guest asked for current host-state. Reply with full broadcast.
	CSR_MP.register_handler(CSR_MP.MSG.HANDSHAKE, function(sender, data, sender_num, is_from_host)
		if not (CSR_MP.is_host and CSR_MP.is_host()) then
			return
		end
		-- A HANDSHAKE proves the peer runs CSR; mark it so isolation Task 1 never kicks it.
		if CSR_MP.mark_peer_verified then
			CSR_MP.mark_peer_verified(sender_num or tonumber(sender))
		end
		broadcast_host_state()
	end)
end

if IngameWaitingForPlayersState and not _G._CSR_MP_SESSION_HOOKED then
	_G._CSR_MP_SESSION_HOOKED = true

	-- Activate guest's crime_spree temp job before briefing HUD builds (HUDMissionBriefing:reload
	-- bails if no active job). See csr_guest_temp_job_briefing_gap.md.
	Hooks:PreHook(IngameWaitingForPlayersState, "at_enter", "CSR_MP_GuestTempJob", function()
		if managers and managers.csr and managers.csr.ensure_guest_temp_job then
			managers.csr:ensure_guest_temp_job()
		end
	end)

	Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_MP_HostStatePush", function(self)
		if not CSR_MP then
			return
		end
		-- Guest: clear stale state then pull fresh (pull is more reliable than waiting for a push).
		if CSR_MP.is_client and CSR_MP.is_client() then
			if managers.csr and managers.csr.clear_mp_host_state then
				managers.csr:clear_mp_host_state()
			end
			-- Retry until host_seed lands; a lost reply leaves the guest non-guesting -> catch-up steals its pick.
			if CSR_MP.ensure_host_state then
				CSR_MP.ensure_host_state()
			elseif CSR_MP.request_host_state then
				CSR_MP.request_host_state()
			end
			return
		end
		-- Host: delayed push so state arrives after guests clear stale data.
		if CSR_MP.is_host and CSR_MP.is_host() and CSR_MP.is_multiplayer() and csr_heist_active() then
			DelayedCalls:Add("CSR_MP_HostStatePush", 0.75, broadcast_host_state)
		end
	end)
end

csr_log("[CSR] mp_session.lua loaded")
