-- Wildcard ("*") hook: notifies extension_api after every engine script load.
-- Stays tiny — SuperBLT re-dofiles a wildcard script on every require.

if not RequiredScript then
	return
end

if _G.CSR and _G.CSR.on_script_loaded then
	_G.CSR.on_script_loaded(RequiredScript)
else
	-- Buffer scripts that loaded inside lib/entry before the shim's PostHook ran.
	-- extension_api.lua drains this at the end of its bootstrap.
	_G.__CSR_pending_reqs = _G.__CSR_pending_reqs or {}
	_G.__CSR_pending_reqs[#_G.__CSR_pending_reqs + 1] = RequiredScript
end
