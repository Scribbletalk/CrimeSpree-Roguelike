-- Crime Spree Roguelike lobby isolation (host side): kick peers that never complete the CSR handshake.
-- A non-CSR (vanilla) player can still SEE/JOIN a CSR lobby (we cannot hook their game); the host removes
-- them. CSR clients announce themselves via LOBBY_PING/HANDSHAKE (mp_sync / mp_session), which call
-- CSR_MP.mark_peer_verified. Enforcement is gated on hosting an ACTIVE CSR lobby (is_active flips true on
-- _accept_csr_contract_mp, i.e. already in the pre-heist lobby). Hook names are unique to coexist with
-- mp_sync's own on_peer_entered_lobby / _on_peer_removed hooks.

if not RequiredScript or not BaseNetworkSession then
	return
end

if _G._CSR_ISOLATION_HOOKED then
	return
end
_G._CSR_ISOLATION_HOOKED = true

CSR_MP = CSR_MP or {}
CSR_MP._verified_peers = CSR_MP._verified_peers or {}

local VERIFY_TIMEOUT = 8 -- seconds a peer has to announce itself before the warning
local KICK_DELAY = 5 -- seconds between the chat warning and the kick (warning must be visible)

function CSR_MP.mark_peer_verified(pid)
	pid = tonumber(pid)
	if pid then
		CSR_MP._verified_peers[pid] = true
	end
end

function CSR_MP.is_peer_verified(pid)
	return CSR_MP._verified_peers[tonumber(pid) or -1] == true
end

-- Host-only gate: enforce isolation only while hosting an active CSR lobby; never in a vanilla game.
local function csr_lobby_host()
	return CSR_MP.is_host and CSR_MP.is_host() and managers and managers.csr and managers.csr:is_active()
end

local function kick_unverified(pid)
	if CSR_MP.is_peer_verified(pid) then
		return -- announced itself in time; keep.
	end
	local session = managers.network and managers.network:session()
	local peer = session and session:peer(pid)
	if not peer then
		return
	end
	local name = peer:name() or "Unknown"
	if managers.chat and managers.network.account then
		-- Warn everyone (incl. the kicked peer) why, then kick after a short delay.
		managers.chat:send_message(
			1,
			managers.network.account:username_id(),
			managers.localization:text("csr_kick_no_mod", { name = name })
		)
	end
	DelayedCalls:Add("CSR_KickPeer_" .. tostring(pid), KICK_DELAY, function()
		local s = managers.network and managers.network:session()
		local p = s and s:peer(pid)
		if not p or CSR_MP.is_peer_verified(pid) then
			return -- left already, or announced itself during the grace window.
		end
		s:send_to_peers("kick_peer", pid, 0)
		s:on_peer_kicked(p, pid, 0)
	end)
end

-- Start a verification timer when a peer enters the lobby (host-only event).
Hooks:PostHook(BaseNetworkSession, "on_peer_entered_lobby", "CSR_IsolationVerifyTimer", function(self, peer)
	if not csr_lobby_host() or not peer then
		return
	end
	local pid = peer:id()
	if not pid or pid == 1 then
		return -- never the host itself.
	end
	DelayedCalls:Add("CSR_VerifyPeer_" .. tostring(pid), VERIFY_TIMEOUT, function()
		if csr_lobby_host() then
			kick_unverified(pid)
		end
	end)
end)

-- Drop verification state when a peer leaves so a future peer reusing the id starts clean.
Hooks:PostHook(BaseNetworkSession, "_on_peer_removed", "CSR_IsolationClearVerify", function(self, peer, peer_id, reason)
	if peer_id then
		CSR_MP._verified_peers[peer_id] = nil
	end
end)
