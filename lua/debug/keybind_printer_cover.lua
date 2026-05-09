-- SuperBLT keybind callback. Fires once per keypress while in-game.
-- Routes to the cycle's cover-spawn dispatcher in scrapper_spawner.lua, which
-- spawns the currently-cycled prop at the nearest cop cover (delegating to
-- copier_spawner's own cover-spawn for the printer, using the generic helper
-- for the scrapper).
log("[CSR Keybind] csr_debug_spawn_prop_cover fired")
if _G.CSR_SpawnDebugPropAtCover then
	_G.CSR_SpawnDebugPropAtCover()
else
	log("[CSR Keybind] csr_debug_spawn_prop_cover: dispatcher missing")
end
