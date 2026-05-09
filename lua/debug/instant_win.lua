-- Instant Win - keybind script
-- Force mission completion for testing (assign key in Mod Keybinds).
-- The actual logic lives in lua/debug/debug_menu.lua as _G.CSR_DEBUG_InstantWin
-- so the Heists debug menu button and this keybind share one codepath.

log("[CSR Instant Win] Keybind triggered!")

local ok, err = pcall(function()
	if _G.CSR_DEBUG_InstantWin then
		_G.CSR_DEBUG_InstantWin()
	else
		log("[CSR Instant Win] CSR_DEBUG_InstantWin not loaded - debug menu missing?")
	end
end)

if not ok then
	log("[CSR Instant Win] ERROR: " .. tostring(err))
end
