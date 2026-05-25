-- CSR debug keybind: spawn the currently-cycled debug prop at the nav cover
-- nearest the player (shredder uses the generic cover-spawn; printer delegates
-- to copier_spawner's own cover-spawn). Cycle with the other debug keybind.
--
-- DEV keybind. MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if type(_G.CSR_SpawnDebugPropAtCover) ~= "function" then
	log("[CSR][debug] spawn-prop-cover: scrapper_spawner not loaded")
	return
end
_G.CSR_SpawnDebugPropAtCover()
