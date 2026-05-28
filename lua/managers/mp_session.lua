-- Crime Spree Roguelike - Multiplayer session sync (host-state push).
--
-- At heist start the host announces { rank, difficulty, run_seed, tokens_gross }
-- to all peers. A guest stores rank/difficulty (managers.csr:set_mp_host_state) so
-- its per-rank player scaling + item-selection quota follow the host via
-- host_rank(), and seeds its Gage Token wallet to the host's gross-earned ONCE per
-- run (project_csr_late_join_grant_model). Host-authoritative push -- no
-- client->host handshake. Per-peer item visibility is a separate channel
-- (mp_sync.lua M2: broadcast/relay/request).
--
-- Hook point mirrors combat_modifiers.lua: IngameWaitingForPlayersState:at_enter,
-- gated by the no-leak job signal csr_heist_active() (current_job_id ==
-- "crime_spree", vanilla CS NOT active). The broadcast rides a short DelayedCall
-- so it always arrives AFTER a guest's own at_enter clear (which wipes stale host
-- state from a prior heist) -- the pre-refactor timing trick. If the host is NOT
-- running CSR, no push arrives and the guest correctly falls back to its own rank.
--
-- Transport rides CSR_MP (mp_sync.lua); the HANDSHAKE_OK message id is reused for
-- the host-state payload. Non-CSR peers have no router and ignore it.
--
-- LOADS IN BOTH Lua states. Hooked on lib/entry (menu state, where the lobby
-- lives) AND lib/states/ingamewaitingforplayers (game state). broadcast_host_state
-- + the HANDSHAKE_OK receive handler MUST exist in the MENU state too: the host
-- pushes host-state from the lobby-join handshake (mp_sync.lua LOBBY_PING /
-- on_peer_entered_lobby), and lib/states/* scripts are not loaded in the menu Lua
-- state -- so before this dual hook, CSR_MP.broadcast_host_state was nil in the
-- lobby and the guest never received the host's rank/difficulty/seed (no item
-- quota, own rank shown, mismatched mission set). The at_enter hook below
-- self-skips when IngameWaitingForPlayersState is nil (menu), so only the game
-- state registers it; the broadcast fn + handler assignment are idempotent.

if not RequiredScript then
	return
end

local CSR_MP = _G.CSR_MP

-- Byte-identical to combat_modifiers.lua / mission_lifecycle.lua: the verified
-- CSR-exclusive runtime signal that does NOT leak the way the persisted
-- is_active() flag does (feedback_csr_only_no_vanilla_leak).
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

-- Host -> all peers: { version, host_rank, host_difficulty, run_seed }. Solo/SP
-- short-circuits (no peers). CSR guests apply it under their own gate; non-CSR
-- peers silently ignore an unknown message id.
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
		-- The host's CURRENTLY-SELECTED heist. CSR runs a temp "crime_spree" job whose
		-- chain each peer builds LOCALLY from its own Global.game_settings.level_id, so
		-- the host's pick never reaches a guest (the dropped gamemode means vanilla's
		-- level sync doesn't carry it) -> the guest loaded its OWN stale level. The guest
		-- applies these to Global.game_settings so it loads the SAME heist as the host.
		host_level_id = (gs and gs.level_id) or false,
		host_mission = (gs and gs.mission) or "none",
		-- Host's GROSS tokens earned this run -> seeds a late-joining guest's wallet
		-- (project_csr_late_join_grant_model). 0 when the shop logic isn't loaded.
		host_tokens_gross = (_G.CSR_Shop and _G.CSR_Shop.gross_earned and _G.CSR_Shop.gross_earned()) or 0,
	})
	LuaNetworking:SendToPeers(CSR_MP.MSG.HANDSHAKE_OK, payload)
	-- Ride the same triggers (lobby join / HANDSHAKE reply) with the lobby mission set
	-- so a guest's cards match the host's the moment it has host-state.
	if CSR_MP.broadcast_mission_set then
		CSR_MP.broadcast_mission_set()
	end
	if CSR_MP.log then
		CSR_MP.log("broadcast_host_state rank=" .. tostring(mgr:rank()) .. " diff=" .. tostring(mgr:difficulty()))
	end
end

-- Exposed so the lobby-join handshake (mp_sync.lua LOBBY_PING handler) can push
-- host state the MOMENT a guest enters the CSR lobby. Without this, the host only
-- announces at heist start, so a guest's lobby shows ITS OWN rank + item quota
-- (host_rank fallback) until the first heist -- and is_guesting() stays false, so
-- the whole guest model (rank/difficulty/inventory redirect/token seed) never
-- engages in the lobby. broadcast_host_state does NOT gate on csr_heist_active, so
-- it's valid in the lobby (the host's run is active there from contract-accept).
if CSR_MP then
	CSR_MP.broadcast_host_state = broadcast_host_state
end

-- Client receives the host-state push: store host_rank + host_difficulty.
if CSR_MP and CSR_MP.register_handler then
	CSR_MP.register_handler(CSR_MP.MSG.HANDSHAKE_OK, function(sender, data, sender_num, is_from_host)
		if not (CSR_MP.is_client and CSR_MP.is_client() and is_from_host) then
			return
		end
		-- Do NOT re-gate on csr_heist_active() here: it is false in the lobby. The host
		-- only SENDS host state in a CSR context (heist start / lobby-join handshake)
		-- and is_from_host blocks forgery, so receiving it IS the CSR signal. Gating
		-- here left the guest lobby on its OWN rank until the first heist; host_rank()
		-- only consumes this while is_client(), so storing it elsewhere is inert.
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
			-- Adopt the host's SELECTED heist + difficulty into Global.game_settings so
			-- the guest LOADS the same level. CSR's temp "crime_spree" job builds its
			-- chain locally from Global.game_settings.level_id, and a guest would
			-- otherwise keep its OWN stale level (it loaded branchbank/pbr2 while the host
			-- was on a different heist). Applied in the lobby/briefing BEFORE the load, so
			-- the start uses the host's level. Client-only path (is_client + is_from_host
			-- already gated above).
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
			-- If the guest is in the CSR lobby when the host rank arrives, repaint
			-- its RANK readout + item quota immediately (no-op otherwise).
			local comp = managers.menu_component and managers.menu_component._crime_spree_missions
			if comp and comp.refresh_for_rank_change then
				comp:refresh_for_rank_change()
			end
			-- Re-apply the client-side enemy-damage modifier with the now-fresh
			-- host_rank. The guest's combat_modifiers at_enter often runs while host
			-- state is still cleared (the guest wipes it on its OWN at_enter, before
			-- the host's delayed heist-start push lands), so enemy-damage scaling would
			-- otherwise sit at rank 0 all heist and enemies hit soft. apply_modifiers is
			-- idempotent + self-guards on managers.modifiers.
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

		-- Late-join token seed (project_csr_late_join_grant_model): set the guest's
		-- wallet EXACTLY to the host's GROSS earned tokens, ONCE per host run. The
		-- once-guard rides the guest SESSION record (managers.csr:guest_tokens_seeded,
		-- in _meta, keyed by host run_seed) -- so re-joining the SAME host preserves the
		-- guest's agency (no re-seed over what they spent/hoarded) even across a game
		-- restart, while a DIFFERENT host re-seeds. set_mp_host_state above stored
		-- host_seed, so _is_guesting() is now true and set_tokens (NOT credit, so the
		-- seed doesn't inflate gross) writes the GUEST SESSION wallet (M5), not the
		-- paused solo run. gross>0 guard avoids wiping a wallet to 0 on a host that
		-- earned nothing yet.
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

	-- Host: a guest asked for the current host-state (HANDSHAKE, sent from its heist
	-- at_enter / lobby). Reply with the full broadcast -- SendToPeers reaches every
	-- guest and each re-applies idempotently. Self-gated to the host; a guest's own
	-- echo is a no-op (broadcast_host_state bails unless is_host).
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
		-- Guest: clear stale host state, then PULL fresh state from the host
		-- (request-reply). The clear keeps no-leak (a non-CSR host never replies, so
		-- host-state stays cleared -> is_guesting false there); the request makes the
		-- in-heist re-acquire RELIABLE instead of depending on the host's timed push
		-- landing in the load window (which it often missed -- enemy damage stayed
		-- unscaled, the endscreen fell back to vanilla). The host's HANDSHAKE handler
		-- replies HANDSHAKE_OK, whose client handler applies rank/seed AND re-applies
		-- the client enemy-damage modifier.
		if CSR_MP.is_client and CSR_MP.is_client() then
			if managers.csr and managers.csr.clear_mp_host_state then
				managers.csr:clear_mp_host_state()
			end
			if CSR_MP.request_host_state then
				CSR_MP.request_host_state()
			end
			return
		end
		-- Host: also announce shortly after load (belt-and-suspenders alongside the
		-- guest's pull above) so the state arrives after every guest's at_enter clear.
		if CSR_MP.is_host and CSR_MP.is_host() and CSR_MP.is_multiplayer() and csr_heist_active() then
			DelayedCalls:Add("CSR_MP_HostStatePush", 0.75, broadcast_host_state)
		end
	end)
end

csr_log("[CSR] mp_session.lua loaded (host-state push on IngameWaitingForPlayersState)")
