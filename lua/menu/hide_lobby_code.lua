-- Crime Spree Roguelike - Reposition lobby code panel during Crime Spree lobby
--
-- When in a multiplayer CS lobby, lobby code is created by MenuComponentManager
-- at its default position (y=80, x=0), overlapping our custom CS tabs.
-- Fix: after creation, move it to the bottom-right like the in-game version does.

if not RequiredScript then
	return
end

if not MenuComponentManager then
	return
end

-- In offline CS lobbies the menu node does not activate the "lobby_chats"
-- component, so _create_lobby_chat_gui is never called. We force-create the
-- chat GUI ourselves inside the create_lobby_code_gui PostHook below, which
-- `set_active_components` re-invokes on every node open/refresh.

Hooks:PostHook(MenuComponentManager, "create_lobby_code_gui", "CSR_RepositionLobbyCode", function(self)
	if not managers.crime_spree then
		return
	end

	-- Use is_active() (gamemode check), not in_progress() (run-state flag).
	-- During fresh-start, start_crime_spree() calls reset_crime_spree() which
	-- sets in_progress=false BEFORE setting it back to true, so create_lobby_code_gui
	-- firing in that window would skip the chat force-create. Vanilla itself uses
	-- is_active() at this same call site (menucomponentmanager.lua:5450).
	if not managers.crime_spree:is_active() then
		return
	end

	local gui = self._lobby_code_gui
	if not gui then
		return
	end

	local panel = gui:panel()

	-- Move above the CS tab bar (tabs start at y=57, default lobby code y=80)
	panel:set_position(panel:x() + 100, 0)

	-- Force chat GUI to exist and be visible in offline lobby so printer system
	-- messages are readable. set_active_components unconditionally re-calls
	-- create_lobby_code_gui on every node open/refresh (menucomponentmanager.lua:600).
	-- The lobby_chats close callback `hide_lobby_chat_gui` hides the chat when
	-- leaving the lobby (e.g. when crime_spree_select_modifiers opens) but does
	-- not reset `_lobby_chat_gui_active`, so we cannot gate on that flag — we
	-- must re-show unconditionally every time this hook fires.
	if SystemInfo:platform() == Idstring("WIN32") then
		self._preplanning_chat_gui_active = false
		self._lobby_chat_gui_active = true
		self._crimenet_chat_gui_active = false
		self._inventory_chat_gui_active = false
		if self._game_chat_gui then
			self:show_game_chat_gui()
		else
			self:add_game_chat()
		end
		if self._game_chat_gui then
			self._game_chat_gui:set_params(self._saved_game_chat_params or "lobby")
			self._saved_game_chat_params = nil
		end
	end
end)
