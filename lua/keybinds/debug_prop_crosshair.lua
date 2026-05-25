-- CSR debug keybind: spawn the currently-cycled debug prop where the camera is
-- looking (shredder uses the generic crosshair-spawn; printer delegates to
-- copier_spawner's own crosshair-spawn + rolls an offer). Cycle with the other
-- debug keybind.
--
-- DEV keybind. MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if type(_G.CSR_SpawnDebugPropAtCrosshair) ~= "function" then
	log("[CSR][debug] spawn-prop-crosshair: scrapper_spawner not loaded")
	return
end
_G.CSR_SpawnDebugPropAtCrosshair()
