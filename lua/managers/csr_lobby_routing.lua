-- CSR lobby routing (Slice B navigation fix).
--
-- Problem: "Return to Lobby" (csr_contract_callbacks.lua return_to_csr_lobby ->
-- load_start_menu_lobby) lands the player in the EMPTY normal "lobby" node
-- instead of the CSR lobby.
--
-- Root cause: vanilla MenuManager:on_enter_lobby (menumanagerpd2.lua:28-47)
-- routes the node by gamemode:
--   if game_state_machine:gamemode().id == GamemodeCrimeSpree.id then
--     ...logic:select_node("crime_spree_lobby", true, {})
--   else
--     ...logic:select_node("lobby", true, {})
--   end
-- A CSR run launches a temporary "crime_spree" job WITHOUT enabling the vanilla
-- Crime Spree gamemode (Slice 6), so the gamemode id never matches and vanilla
-- always takes the else branch.
--
-- Fix: a one-shot intent flag (Global.CSR_RETURN_TO_LOBBY) set by
-- return_to_csr_lobby's yes-callback immediately before load_start_menu_lobby.
-- This PostHook fires AFTER vanilla's select_node("lobby"), and when the flag
-- is present re-selects "crime_spree_lobby" (the exact call vanilla itself uses
-- in its CS branch), overriding the wrong node. The flag is cleared on consume.
--
-- Critical Rule #2 / cross-Lua-state: load_start_menu_lobby from the
-- victoryscreen (game) state triggers a FULL PD2 Lua-environment reinit on the
-- way to the menu state. The game-state _G and the menu-state _G are DIFFERENT
-- tables, so a _G.* flag set in-game is WIPED before the menu-state
-- on_enter_lobby runs. Global is PD2's cross-state persistent store and is the
-- ONLY table that survives the reinit. Vanilla precedent: Setup:load_start_menu
-- _lobby sets Global.load_start_menu_lobby (setup.lua:741), read back in
-- menumainstate.lua:24 AFTER the state transition. We mirror that 1:1.
--
-- No-leak (feedback_csr_only_no_vanilla_leak): the gate is the transient
-- one-shot flag, NOT the persisted managers.csr:is_active() (which leaks true
-- into normal vanilla sessions). on_enter_lobby runs for EVERY lobby entry
-- (vanilla MP lobbies included); without the flag this PostHook is a pure
-- no-op, so a leaked is_active cannot reroute a vanilla lobby.
--
-- Critical Rule #1: PostHook, not OverrideFunction. The double select_node
-- ("lobby" then "crime_spree_lobby") is a cheap one-shot menu transition, not a
-- hot path, and mirrors the existing csr_contract_wiring.lua swap pattern
-- (vanilla builds, we re-register). Override would also clobber the
-- gamemode-agnostic setup around it (rich presence, network session,
-- local-lobby character) and break other mods' hooks.
--
-- Hooked on lib/managers/menumanagerpd2: on_enter_lobby is DEFINED there
-- (menumanagerpd2.lua extends MenuManager from menumanager.lua, which loads
-- first), so the method exists when this PostHook registers. Hooking on
-- lib/managers/menumanager would attach to a still-nil on_enter_lobby.

if not RequiredScript then
	return
end

-- Tear down the stale end-screen HUD backdrop that leaks into the CSR lobby.
--
-- CSRHUDStageEndScreen._backdrop is a MenuBackdropGUI whose "stage_text"
-- children ("<HeistName>: SUCCESS", set by the delegated HUDStageEndScreen
-- .set_success) live on HUDManager's PERSISTENT workspace("fullscreen_workspace",
-- "menu"). Nothing in vanilla lib ever destroys _hud_stage_endscreen or calls
-- _backdrop:close() (verified: StageEndScreenGui:close()/our fork only remove
-- their own component panels). Vanilla relies on an implicit menu-workspace
-- recreation that CSR's temporary "crime_spree" job return path never triggers
-- (same "vanilla-CS-aware path not taken" class as the briefing/lobby leaks),
-- so the orphaned backdrop title survives into the CSR lobby and overlaps the
-- "Crime Spree Roguelike" header (user report 2026-05-18).
--
-- MenuBackdropGUI:close() -> destroy() removes _panel and guard-handles
-- _blackborder_workspace / _black_bg_ws (menubackdropgui.lua:651-675). Because
-- NOTHING else frees this object, an explicit close here cannot double-free.
-- We also nil managers.hud._hud_stage_endscreen so HUDManager's nil-guarded
-- *_endscreen_hud methods become safe no-ops and the next setup_endscreen_hud
-- builds a fresh instance. Host and client each run on_enter_lobby locally and
-- each built their own local CSRHUDStageEndScreen, so both tear down their own;
-- no network packet is involved (feedback_check_host_and_client).
local function csr_teardown_endscreen_hud()
	local hud = managers and managers.hud
	local screen = hud and hud._hud_stage_endscreen

	if screen and screen._backdrop then
		screen._backdrop:close()
		hud._hud_stage_endscreen = nil
		log("[CSR] lobby routing: tore down stale end-screen HUD backdrop")
	end
end

Hooks:PostHook(MenuManager, "on_enter_lobby", "CSR_OnEnterLobbyRoute", function(self)
	log("[CSR] lobby routing: on_enter_lobby PostHook fired (flag=" .. tostring(Global.CSR_RETURN_TO_LOBBY) .. ")")

	if not Global.CSR_RETURN_TO_LOBBY then
		return
	end

	Global.CSR_RETURN_TO_LOBBY = nil

	-- The end-screen backdrop leaks regardless of whether the reroute below
	-- succeeds, so tear it down first (before the logic nil-check bail-out).
	csr_teardown_endscreen_hud()

	local active = managers.menu and managers.menu:active_menu()
	local logic = active and active.logic

	if not logic then
		log("[CSR] lobby routing: no active menu logic, cannot reroute to CSR lobby")

		return
	end

	logic:select_node("crime_spree_lobby", true, {})
	log("[CSR] lobby routing: rerouted on_enter_lobby -> crime_spree_lobby node")
end)

log("[CSR] csr_lobby_routing.lua loaded (Slice B navigation fix)")
