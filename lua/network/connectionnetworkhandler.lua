-- Receive handlers for CSR native RPCs (csr_net_sc / csr_net_cs from csr_network_tweak.xml).
-- Uses ConnectionNetworkHandler (receiver="connection") - active in both lobby and heist.
-- Both messages funnel into CSR_MP.dispatch_native.

if not RequiredScript then
	return
end

_G.CSR_MP = _G.CSR_MP or {}

if ConnectionNetworkHandler and not ConnectionNetworkHandler._csr_net_hooked then
	ConnectionNetworkHandler._csr_net_hooked = true

	-- Host -> client (check="server_to_client" ensures sender is always peer 1).
	function ConnectionNetworkHandler:csr_net_sc(msg_id, payload, sender)
		if _G.CSR_MP and _G.CSR_MP.dispatch_native then
			_G.CSR_MP.dispatch_native(msg_id, payload, 1, true)
		end
	end

	-- Client -> host. Resolve real sender peer id; drop if unverifiable.
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
