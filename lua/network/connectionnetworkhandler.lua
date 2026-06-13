-- CSR native-RPC receive handlers, attached to ConnectionNetworkHandler (the receiver="connection"
-- class). Vanilla routes ALL lobby-time traffic (join handshake, peer exchange) through this handler,
-- and it stays live in a heist too, so it serves CSR's lobby host-state push AND in-heist sync.
-- receiver="unit" was tried first but unit-RPCs are only delivered once the engine is in multiplayer
-- gameplay (set_multiplayer) — they silently drop in the lobby. The two messages are defined in
-- csr_network_tweak.xml; both funnel into CSR_MP.dispatch_native (shared CSR_MP._handlers registry).

if not RequiredScript then
	return
end

_G.CSR_MP = _G.CSR_MP or {}

if ConnectionNetworkHandler and not ConnectionNetworkHandler._csr_net_hooked then
	ConnectionNetworkHandler._csr_net_hooked = true

	-- Host -> client. check="server_to_client" guarantees the sender is the host, so peer id 1.
	function ConnectionNetworkHandler:csr_net_sc(msg_id, payload, sender)
		if _G.CSR_MP and _G.CSR_MP.dispatch_native then
			_G.CSR_MP.dispatch_native(msg_id, payload, 1, true)
		end
	end

	-- Client -> host. Resolve the real sender peer id (drop the message if unverifiable).
	function ConnectionNetworkHandler:csr_net_cs(msg_id, payload, sender)
		local peer = self._verify_sender(sender)
		if not peer then
			return
		end
		local pid = peer:id()
		if _G.CSR_MP and _G.CSR_MP.dispatch_native then
			_G.CSR_MP.dispatch_native(msg_id, payload, pid, pid == 1)
		end
	end
end
