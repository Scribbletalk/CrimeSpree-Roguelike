-- CSR debug keybind: toggle the forked item-selection window.
--
-- Opens/closes CSRItemSelectionComponent (lua/menu/csr_item_selection.lua) as
-- a registered menu-component overlay. Pure visual shell — the selection pool
-- and "when does it appear" logic are NOT wired (deliberate, see that file).
--
-- Menu-only: the window builds on managers.menu_component's workspaces, so it
-- is meaningless in-game (run_in_menu = true / run_in_game = false in mod.txt).
--
-- This is a DEV keybind. It MUST be stripped from the staging mod.txt before
-- any preview/release build (project_pack_time_strip_debug_keybinds).

if _G.CSR_ToggleItemSelectionDebug then
	CSR_ToggleItemSelectionDebug()
else
	log("[CSR][debug] item selection: toggle not available (csr_item_selection.lua not loaded?)")
end
