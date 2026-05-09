-- SuperBLT keybind callback. Fires once per keypress while in-game.
-- Routes to the global exposed by lua/core/scrapper_spawner.lua.
log("[CSR Keybind] csr_debug_spawn_prop_crosshair fired")
if _G.CSR_SpawnScrapperAtCrosshair then
	_G.CSR_SpawnScrapperAtCrosshair()
else
	log("[CSR Keybind] csr_debug_spawn_prop_crosshair: dispatcher missing")
end
