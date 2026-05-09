-- SuperBLT keybind callback. Cycles the debug-prop spawner to the next prop
-- in the registry (lua/core/scrapper_spawner.lua DEBUG_PROPS).
log("[CSR Keybind] csr_debug_cycle_prop fired")
if _G.CSR_CycleDebugProp then
	_G.CSR_CycleDebugProp()
else
	log("[CSR Keybind] csr_debug_cycle_prop: dispatcher missing")
end
