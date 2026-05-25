-- CSR debug keybind: cycle the debug-prop spawner to the next prop in the
-- registry (lua/core/scrapper_spawner.lua DEBUG_PROPS: shredder -> printer).
--
-- DEV keybind. MUST be stripped from the staging mod.txt before any
-- preview/release build (project_pack_time_strip_debug_keybinds).

if type(_G.CSR_CycleDebugProp) ~= "function" then
	log("[CSR][debug] cycle-prop: scrapper_spawner not loaded")
	return
end
_G.CSR_CycleDebugProp()
