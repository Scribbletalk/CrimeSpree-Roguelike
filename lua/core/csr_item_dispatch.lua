-- Wildcard ("*") hook: runs after EVERY engine script load. Routes the just-
-- loaded script path to the item auto-loader so per-item files (lua/item_defs/)
-- install their behavior hooks the moment their target class exists.
--
-- Deliberately tiny: SuperBLT re-dofiles a wildcard script on every require (see
-- mods/base/base.lua BLT:RunHookFile), i.e. hundreds of times at boot. The heavy
-- work (folder scan, hook index, dispatch) lives in csr_extension_api.lua and
-- runs once; this file is just the per-load notification.

if not RequiredScript then
	return
end

if _G.CSR and _G.CSR.on_script_loaded then
	_G.CSR.on_script_loaded(RequiredScript)
else
	-- The CSR shim (csr_extension_api.lua) loads as a POST-hook on lib/entry, but
	-- lib/entry's body synchronously requires much of the game (PlayerManager, ...)
	-- BEFORE that post-hook runs. Those requires fire this wildcard while
	-- on_script_loaded does not exist yet, so buffer them in a plain bootstrap
	-- global; the shim drains the buffer once it is up and its hook index is built.
	_G.__CSR_pending_reqs = _G.__CSR_pending_reqs or {}
	_G.__CSR_pending_reqs[#_G.__CSR_pending_reqs + 1] = RequiredScript
end
