-- Crime Spree Roguelike - Multiplayer session sync (M1: host-state push).
--
-- The host announces its run rank + difficulty to all peers at heist start; a
-- guest stores them (managers.csr:set_mp_host_state) so its per-rank player
-- scaling + item-selection quota follow the host via host_rank(). No
-- client->host handshake yet -- the host is authoritative and simply pushes.
-- The request/response handshake + per-peer item sync land in M2.
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
	local payload = json.encode({
		version = (mgr.mod_version and mgr:mod_version()) or "unknown",
		host_rank = mgr:rank(),
		host_difficulty = mgr:difficulty(),
		run_seed = mgr:seed(),
	})
	LuaNetworking:SendToPeers(CSR_MP.MSG.HANDSHAKE_OK, payload)
	if CSR_MP.log then
		CSR_MP.log("broadcast_host_state rank=" .. tostring(mgr:rank()) .. " diff=" .. tostring(mgr:difficulty()))
	end
end

-- Client receives the host-state push: store host_rank + host_difficulty.
if CSR_MP and CSR_MP.register_handler then
	CSR_MP.register_handler(CSR_MP.MSG.HANDSHAKE_OK, function(sender, data, sender_num, is_from_host)
		if not (CSR_MP.is_client and CSR_MP.is_client() and is_from_host) then
			return
		end
		-- Defensive: the host gates on csr_heist_active() before sending, but never
		-- apply host scaling into a non-CSR session on our side either.
		if not csr_heist_active() then
			return
		end
		local ok, payload = pcall(json.decode, data)
		if not ok or type(payload) ~= "table" then
			return
		end
		local mgr = managers and managers.csr
		if mgr and mgr.set_mp_host_state then
			mgr:set_mp_host_state(tonumber(payload.host_rank), payload.host_difficulty)
			-- If the guest is in the CSR lobby when the host rank arrives, repaint
			-- its RANK readout + item quota immediately (no-op otherwise).
			local comp = managers.menu_component and managers.menu_component._crime_spree_missions
			if comp and comp.refresh_for_rank_change then
				comp:refresh_for_rank_change()
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
	end)
end

if IngameWaitingForPlayersState and not _G._CSR_MP_SESSION_HOOKED then
	_G._CSR_MP_SESSION_HOOKED = true

	Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_MP_HostStatePush", function(self)
		if not CSR_MP then
			return
		end
		-- Guest: clear stale host state from the prior heist BEFORE the (delayed)
		-- push lands. If this host isn't running CSR, no push comes and host_rank()
		-- falls back to the own rank -- no leak.
		if CSR_MP.is_client and CSR_MP.is_client() then
			if managers.csr and managers.csr.clear_mp_host_state then
				managers.csr:clear_mp_host_state()
			end
			return
		end
		-- Host: announce rank/difficulty shortly after load so it arrives after
		-- every guest's at_enter clear.
		if CSR_MP.is_host and CSR_MP.is_host() and CSR_MP.is_multiplayer() and csr_heist_active() then
			DelayedCalls:Add("CSR_MP_HostStatePush", 0.75, broadcast_host_state)
		end
	end)
end

log("[CSR] mp_session.lua loaded (host-state push on IngameWaitingForPlayersState)")
