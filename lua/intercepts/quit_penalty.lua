-- Loss penalty: a CSR heist's outcome commits on START. Arms an in-flight flag on heist start
-- (host/SP), and after a grace period an interruption (crash / alt-F4 / quit-to-menu / restart)
-- counts as a loss. Crash/alt-F4 enforcement lives in CSRGameManager:_check_interrupted_heist
-- (runs every init); this file owns the in-session pieces: arm-on-start, the quit warning dialog,
-- and the restart gate. See design_docs/2026-06-03-loss-penalty.md.

if not RequiredScript then
	return
end

-- True only while the warning/penalty should apply: a committed CSR heist (host/SP — the flag is
-- never set for guests) whose grace has elapsed. Reads the flag directly, so it's MP-safe.
local function past_grace_heist()
	local mgr = managers and managers.csr
	return mgr ~= nil and mgr.in_heist and mgr:in_heist() and mgr.heist_grace_over and mgr:heist_grace_over()
end

-- ============================================================
-- Arm the flag + grace timer on heist start (host/SP only)
-- ============================================================
-- Hook sync_start, NOT at_enter: at_enter fires when the briefing (READY screen) opens, so backing
-- out before readying would (past grace) wrongly count as a loss. sync_start fires only once the
-- briefing is actually started (all ready / skip) and the blackscreen begins — the real commit point.
if RequiredScript == "lib/states/ingamewaitingforplayers" then
	if IngameWaitingForPlayersState and not _G._CSR_QuitPenalty_HeistStart then
		_G._CSR_QuitPenalty_HeistStart = true

		Hooks:PostHook(IngameWaitingForPlayersState, "sync_start", "CSR_QuitPenalty_HeistStart", function()
			local mgr = managers and managers.csr
			if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
				return
			end
			-- Guests are never penalized; host forgiveness for them stays in mission_lifecycle.
			if mgr.is_guesting and mgr:is_guesting() then
				return
			end

			local token = mgr:begin_heist()
			local grace = mgr:heist_grace_seconds()
			-- Unique id per attempt; the token guard inside mark_heist_grace_over is the real
			-- protection against a stale timer (restart / fast finish).
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
-- Quit warning + restart gate (raw overrides — PostHook can't
-- block a callback or change a visibility predicate's return)
-- ============================================================
if RequiredScript == "lib/managers/menumanager" then
	if MenuCallbackHandler and not _G._CSR_QuitPenalty_Menu then
		_G._CSR_QuitPenalty_Menu = true

		-- Replace the quit-to-main-menu confirm with a loss warning once past grace. Yes commits the
		-- loss and runs the REAL quit action directly (vanilla's own Yes-handler), so there's no
		-- second confirm and we only mark failed on a quit that actually executes. No cancels.
		-- end_game is the in-heist "quit to main menu" callback (standard gamemode; CSR doesn't fork
		-- it). Quit-to-desktop / alt-F4 / crash are caught by the init-path instead (no dialog there).
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

		-- Restart after grace = a free retry that dodges the loss; block it. Within grace it's a
		-- legitimate redo (re-entering the heist re-arms a fresh grace window).
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

		-- Hide the SP restart item once past grace (visibility predicate; raw override because
		-- PostHook can't change a return value). Untouched outside a committed CSR heist.
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
