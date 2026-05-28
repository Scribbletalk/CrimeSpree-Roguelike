-- Host-state push for MP. Broadcasts {rank, difficulty, run_seed, level_id,
-- tokens_gross} to all peers; guests apply via set_mp_host_state and copy host's
-- level into Global.game_settings so they load the same heist. Late-joining guest
-- wallet seeded to host's GROSS earned tokens. See csr_mp_architecture.md.
--
-- LOADS IN BOTH Lua states (mod.txt: lib/entry AND lib/states/ingamewaitingforplayers).
-- The host pushes from the lobby-join handshake (menu state), but at_enter lives in
-- the game state. broadcast_host_state must exist in both.

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
		-- Host's currently-selected heist; guests adopt this so they load the same level.
		host_level_id = (gs and gs.level_id) or false,
		host_mission = (gs and gs.mission) or "none",
		-- Host's GROSS tokens earned this run — seeds a late-joining guest's wallet.
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
		-- NOT gated on csr_heist_active() — false in the lobby. is_from_host blocks forgery
		-- and the host only sends this in a CSR context, so receiving it IS the CSR signal.
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
			-- Adopt host's level/mission/difficulty so this guest loads the same heist.
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
			-- Repaint guest's lobby RANK + item quota if it's currently open.
			local comp = managers.menu_component and managers.menu_component._crime_spree_missions
			if comp and comp.refresh_for_rank_change then
				comp:refresh_for_rank_change()
			end
			-- Re-apply enemy-damage modifier with fresh host_rank — guest's own at_enter
			-- often runs before host state arrives, leaving scaling at rank 0 all heist.
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

		-- Late-join token seed: wallet = host's GROSS earned, ONCE per host run.
		-- set_tokens (not credit) so the seed doesn't inflate gross.
		local gross = tonumber(payload.host_tokens_gross)
		if
			gross
			and gross > 0
			and _G.CSR_Shop
			and mgr
			and mgr.guest_tokens_seeded
			and not mgr:guest_tokens_seeded()
		then
			_G.CSR_Shop.set_tokens(CSR_MP.local_peer_id(), gross)
			if mgr.mark_guest_tokens_seeded then
				mgr:mark_guest_tokens_seeded()
			end
			if CSR_MP.log then
				CSR_MP.log(
					"late-join token seed: wallet=" .. tostring(gross) .. " run_seed=" .. tostring(payload.run_seed)
				)
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
		-- Guest: clear stale host state then PULL fresh state from host. The pull makes
		-- in-heist re-acquire reliable (request-reply, not waiting on a timed push).
		if CSR_MP.is_client and CSR_MP.is_client() then
			if managers.csr and managers.csr.clear_mp_host_state then
				managers.csr:clear_mp_host_state()
			end
			if CSR_MP.request_host_state then
				CSR_MP.request_host_state()
			end
			return
		end
		-- Host: belt-and-suspenders timed push so state arrives after every guest's clear.
		if CSR_MP.is_host and CSR_MP.is_host() and CSR_MP.is_multiplayer() and csr_heist_active() then
			DelayedCalls:Add("CSR_MP_HostStatePush", 0.75, broadcast_host_state)
		end
	end)
end

csr_log("[CSR] mp_session.lua loaded")
