-- BLT keybind script: runs once per key press.
-- All routing logic lives in wildcard_dispatcher.lua.
log("[CSR Keybind] csr_activate_wildcard fired")
if _G.CSR_TriggerWildcard then
	_G.CSR_TriggerWildcard()
else
	log("[CSR Keybind] csr_activate_wildcard: dispatcher missing (CSR_TriggerWildcard nil)")
end
