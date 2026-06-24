-- Loss penalty: arms an in-flight flag on heist start (host/SP); after a grace period any
-- interruption (crash/alt-F4/quit/restart) counts as a loss. Crash path lives in
-- CSRGameManager:_check_interrupted_heist. See design_docs/2026-06-03-loss-penalty.md.

if not RequiredScript then
	return
end

-- True after grace has elapsed on a committed host/SP heist (flag never set for guests).
local function past_grace_heist()
	local mgr = managers and managers.csr
	return mgr ~= nil and mgr.in_heist and mgr:in_heist() and mgr.heist_grace_over and mgr:heist_grace_over()
end

-- ============================================================
-- Arm the flag + grace timer on heist start (host/SP only)
-- ============================================================
-- Hook sync_start, not at_enter: at_enter opens at the READY screen; backing out before readying
-- would wrongly count as a loss. sync_start is the real commit point (blackscreen begins).
if RequiredScript == "lib/states/ingamewaitingforplayers" then
	if IngameWaitingForPlayersState and not _G._CSR_QuitPenalty_HeistStart then
		_G._CSR_QuitPenalty_HeistStart = true

		Hooks:PostHook(IngameWaitingForPlayersState, "sync_start", "CSR_QuitPenalty_HeistStart", function()
			local mgr = managers and managers.csr
			if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
				return
			end
			-- Guests are never penalized (mission_lifecycle handles their forgiveness).
			if mgr.is_guesting and mgr:is_guesting() then
				return
			end

			local token = mgr:begin_heist()
			local grace = mgr:heist_grace_seconds()
			-- Unique token per attempt; mark_heist_grace_over checks it to reject stale timers.
			DelayedCalls:Add("CSR_HeistGrace_" .. tostring(token), grace, function()
				if managers and managers.csr then
					managers.csr:mark_heist_grace_over(token)
				end
			end)
			csr_log(
				"[CSR] quit_penalty: heist committed (token="
					.. tostring(token)
					.. ", grace="
					.. tostring(grace)
					.. "s)"
			)
		end)
	end
end

-- ============================================================
-- Quit warning + restart gate
-- (raw overrides: PostHook can't block callbacks or change return values)
-- ============================================================
if RequiredScript == "lib/managers/menumanager" then
	if MenuCallbackHandler and not _G._CSR_QuitPenalty_Menu then
		_G._CSR_QuitPenalty_Menu = true

		-- Replace the quit-to-menu confirm with a loss warning after grace. Yes marks failed then
		-- calls vanilla's _dialog_end_game_yes (no double-confirm). Alt-F4/crash hit CSRGameManager.
		local orig_end_game = MenuCallbackHandler.end_game
		if orig_end_game then
			function MenuCallbackHandler:end_game()
				if not past_grace_heist() then
					return orig_end_game(self)
				end
				local mgr = managers.csr
				local cost = (mgr.get_continue_cost and mgr:get_continue_cost()) or 0
				local dialog_data = {
					title = managers.localization:text("csr_dialog_quit_heist_loss_title"),
					text = managers.localization:text("csr_dialog_quit_heist_loss_text", { cost = cost }),
					id = "csr_quit_heist_loss",
				}
				dialog_data.button_list = {
					{
						text = managers.localization:text("dialog_yes"),
						callback_func = function()
							mgr:mark_failed()
							mgr:clear_in_heist()
							self:_dialog_end_game_yes()
						end,
					},
					{
						text = managers.localization:text("dialog_no"),
						cancel_button = true,
					},
				}
				managers.system_menu:show(dialog_data)
			end
		end

		-- Block restart after grace (would dodge the loss); within grace it's fine.
		local function wrap_restart(method_name)
			local orig = MenuCallbackHandler[method_name]
			if not orig then
				return
			end
			MenuCallbackHandler[method_name] = function(self, ...)
				if past_grace_heist() then
					if managers.menu then
						managers.menu:post_event("menu_error")
					end
					csr_log("[CSR] quit_penalty: restart blocked (past grace)")
					return
				end
				return orig(self, ...)
			end
		end

		wrap_restart("restart_game") -- SP restart action
		wrap_restart("restart_level") -- MP restart-vote action

		-- Hide SP restart item past grace (raw override: PostHook can't change a return value).
		local orig_sp_restart_visible = MenuCallbackHandler.singleplayer_restart
		if orig_sp_restart_visible then
			function MenuCallbackHandler:singleplayer_restart()
				if past_grace_heist() then
					return false
				end
				return orig_sp_restart_visible(self)
			end
		end
	end
end

csr_log("[CSR] quit_penalty.lua loaded")
