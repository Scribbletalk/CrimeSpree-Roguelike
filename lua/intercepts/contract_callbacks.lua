-- Fork of vanilla menumanagercrimespreecallbacks.lua. Callbacks renamed crime_spree→csr
-- so our forked nodes call ours while vanilla menu items still hit vanilla callbacks.

require("lib/utils/accelbyte/TelemetryConst")

function MenuCallbackHandler:csr_is_active()
	return managers.crime_spree:is_active()
end

function MenuCallbackHandler:csr_not_is_active()
	return not managers.crime_spree:is_active()
end

function MenuCallbackHandler:csr_in_progress()
	return managers.crime_spree:in_progress()
end

function MenuCallbackHandler:csr_not_in_progress()
	return not managers.crime_spree:in_progress()
end

function MenuCallbackHandler:csr_not_failed()
	return not managers.csr:has_failed()
end

function MenuCallbackHandler:csr_failed()
	return managers.csr:has_failed()
end

function MenuCallbackHandler:show_csr_start()
	return not self:show_csr_select_modifier()
end

function MenuCallbackHandler:show_csr_reroll()
	return self:show_csr_start()
end

function MenuCallbackHandler:csr_is_playing()
	return Global.game_settings.is_playing
end

function MenuCallbackHandler:csr_is_not_playing()
	return not Global.game_settings.is_playing
end

function MenuCallbackHandler:show_csr_select_modifier()
	local loud = managers.crime_spree:modifiers_to_select("loud")
	local stealth = managers.crime_spree:modifiers_to_select("stealth")

	return loud > 0 or stealth > 0
end

function MenuCallbackHandler:show_csr_claim_rewards()
	return managers.crime_spree:reward_level() > 0
end

function MenuCallbackHandler:not_show_csr_claim_rewards()
	return managers.crime_spree:reward_level() <= 0
end

function MenuCallbackHandler:return_to_csr_lobby_visible()
	-- Pause-menu "Return to Lobby" — CSR sessions only, host/SP only.
	-- Gate on is_active() (a CSR run is in flight), NOT is_run_active() (always-true alpha stub),
	-- so the button never leaks onto a vanilla heist's victory/gameover screen.
	if not (managers.csr and managers.csr.is_active and managers.csr:is_active()) then
		return false
	end
	if Network and Network.is_client and Network:is_client() then
		return false
	end

	local state = game_state_machine:current_state_name()

	if state == "victoryscreen" or state == "gameoverscreen" then
		return true
	end

	-- Briefing and lobby share ingame_waiting_for_players; _mission_briefing_gui is nil in lobby.
	if
		state == "ingame_waiting_for_players"
		and managers.menu_component
		and managers.menu_component._mission_briefing_gui
	then
		return true
	end

	return false
end

function MenuCallbackHandler:change_csr_contract_difficulty(item)
	-- Guard in case the menu item isn't visually disabled when a run is active.
	if managers.csr and managers.csr:is_active() then
		return
	end

	local difficulty_id = item:value()
	local difficulty = tweak_data:index_to_difficulty(difficulty_id)

	if managers.csr and managers.csr.set_difficulty then
		managers.csr:set_difficulty(difficulty)
	end

	local mcm = managers.menu_component
	local comp = mcm and mcm._csr_contract_menu_comp

	if comp and comp.set_difficulty_id then
		comp:set_difficulty_id(difficulty_id)
	end
end

function MenuCallbackHandler:start_new_csr_spree(item, node)
	local is_active = managers.csr and managers.csr:is_active()
	local function do_start()
		local mgr = managers.csr

		-- Pay out rewards from the run being replaced (same pattern as _dialog_end_csr_yes).
		-- Compute reward totals BEFORE start_run resets rank/state.
		local show_rewards = false
		if is_active then
			local own_rank = (mgr.rank and mgr:rank()) or 0
			local has_b = mgr.has_mp_earnings and mgr:has_mp_earnings()
			show_rewards = own_rank > 0 or has_b
			if show_rewards and mgr.projected_rewards then
				local a = mgr:projected_rewards()
				local b = (mgr.mp_earnings and mgr:mp_earnings()) or {}
				mgr._pending_end_rewards = {
					cash = (a.cash or 0) + (b.cash or 0),
					experience = (a.experience or 0) + (b.experience or 0),
					continental_coins = (a.continental_coins or 0) + (b.continental_coins or 0),
					loot_drop = (a.loot_drop or 0) + (b.loot_drop or 0),
				}
			end
			if mgr.reset_mp_earnings then
				mgr:reset_mp_earnings()
			end
		end

		mgr:start_run()
		MenuCallbackHandler:save_progress()

		-- Show rewards screen for the ended run; player returns and clicks Continue to lobby.
		-- Skip straight to lobby when nothing to pay out.
		if show_rewards then
			managers.menu:open_node("crime_spree_claim_rewards", {})
		else
			MenuCallbackHandler:accept_csr_contract(item, node)
		end
	end
	if is_active then
		local rank = managers.csr:rank()
		local dialog_data = {
			title = managers.localization:text("dialog_warning_title"),
			text = managers.localization:text("csr_dialog_start_new_while_active", { rank = rank }),
			id = "csr_start_new_spree",
		}
		local yes_button = {
			text = managers.localization:text("dialog_yes"),
			callback_func = do_start,
		}
		local no_button = {
			text = managers.localization:text("dialog_no"),
			cancel_button = true,
		}
		dialog_data.button_list = { yes_button, no_button }
		managers.system_menu:show(dialog_data)
	else
		do_start()
	end
end

function MenuCallbackHandler:accept_csr_contract(item, node)
	csr_log(
		"[CSR] accept_csr_contract body running (single_player=" .. tostring(Global.game_settings.single_player) .. ")"
	)
	if Global.game_settings.single_player then
		self:_accept_csr_contract_sp(item, node)
	else
		self:_accept_csr_contract_mp(item, node)
	end
end

function MenuCallbackHandler:_accept_csr_contract_sp(item, node)
	-- Re-accepting the contract is the only way back to lobby, so guard to avoid wiping an active run.
	if not managers.csr:is_active() then
		managers.csr:start_run()
	end
	MenuCallbackHandler:save_progress()
	managers.menu:active_menu().logic:select_node("crime_spree_lobby", true, {})
end

function MenuCallbackHandler:_accept_csr_contract_mp(item, node)
	-- Same guard as SP to avoid wiping an active run.
	if not managers.csr:is_active() then
		managers.csr:start_run()
	end

	-- MP lobby is async; routing flag consumed by lobby_routing.lua's on_enter_lobby hook.
	Global.CSR_RETURN_TO_LOBBY = true

	local matchmake_attributes = self:get_matchmake_attributes()

	if Network:is_server() then
		managers.network.matchmake:set_server_attributes(matchmake_attributes)
	else
		managers.network.matchmake:create_lobby(matchmake_attributes)
	end

	managers.menu_component:set_max_lines_game_chat(tweak_data.crime_spree.gui.max_chat_lines.lobby)
	MenuCallbackHandler:save_progress()
end

function MenuCallbackHandler:accept_crimenet_contract_csr(item, node)
	if not managers.crime_spree:in_progress() and managers.crime_spree:starting_level() >= 0 then
		managers.crime_spree:start_crime_spree(managers.crime_spree:starting_level())
	end

	self:accept_crimenet_contract(item, node)
end

function MenuCallbackHandler:claim_csr_rewards(item, node)
	if managers.crime_spree:reward_level() > 0 then
		local dialog_data = {
			title = managers.localization:text("dialog_cs_claim_rewards"),
			text = managers.localization:text("dialog_cs_claim_rewards_text"),
			id = "crime_spree_rewards",
		}
		local yes_button = {
			text = managers.localization:text("dialog_yes"),
			callback_func = callback(self, self, "_dialog_csr_claim_rewards_yes"),
		}
		local no_button = {
			text = managers.localization:text("dialog_no"),
			callback_func = callback(self, self, "_dialog_csr_claim_rewards_no"),
			cancel_button = true,
		}
		dialog_data.button_list = {
			yes_button,
			no_button,
		}

		managers.system_menu:show(dialog_data)
	else
		local dialog_data = {
			title = managers.localization:text("dialog_cs_claim_rewards"),
			text = managers.localization:text("dialog_cs_cant_claim_rewards_text"),
			id = "crime_spree_rewards",
		}
		local no_button = {
			text = managers.localization:text("dialog_ok"),
			callback_func = callback(self, self, "_dialog_csr_claim_rewards_no"),
			cancel_button = true,
		}
		dialog_data.button_list = {
			no_button,
		}

		managers.system_menu:show(dialog_data)
	end
end

function MenuCallbackHandler:_dialog_csr_claim_rewards_yes()
	self:_dialog_leave_lobby_yes()
	managers.menu:open_node("crime_spree_claim_rewards", {})
end

function MenuCallbackHandler:_dialog_csr_claim_rewards_no() end

function MenuCallbackHandler:show_csr_crash_dialog()
	local dialog_data = {
		title = managers.localization:text("dialog_cs_crash_fail"),
		text = managers.localization:text("dialog_cs_crash_fail_text"),
		id = "crime_spree_fail",
	}
	local no_button = {
		text = managers.localization:text("dialog_ok"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		no_button,
	}

	managers.system_menu:show(dialog_data)

	return true
end

function MenuCallbackHandler:end_csr(item, node)
	local dialog_data = {
		title = managers.localization:text("dialog_warning_title"),
	}

	-- Use a CSR-owned key so this dialog can't accidentally affect vanilla CS.
	dialog_data.text = managers.localization:text("csr_dialog_end_spree")

	dialog_data.id = "stop_crime_spree"
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = callback(self, self, "_dialog_end_csr_yes"),
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		callback_func = callback(self, self, "_dialog_end_csr_no"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		yes_button,
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:_dialog_end_csr_yes()
	-- Pay bucket A (own run) + bucket B (guest earnings), so a guest with rank 0 still cashes out.
	local mgr = managers.csr
	local own_rank = (mgr and mgr.rank and mgr:rank()) or 0
	local has_b = mgr and mgr.has_mp_earnings and mgr:has_mp_earnings()
	local show_rewards = own_rank > 0 or has_b

	if show_rewards and mgr.projected_rewards then
		local a = mgr:projected_rewards()
		local b = (mgr.mp_earnings and mgr:mp_earnings()) or {}
		mgr._pending_end_rewards = {
			cash = (a.cash or 0) + (b.cash or 0),
			experience = (a.experience or 0) + (b.experience or 0),
			continental_coins = (a.continental_coins or 0) + (b.continental_coins or 0),
			loot_drop = (a.loot_drop or 0) + (b.loot_drop or 0),
		}
	end

	-- Zero bucket B so a later End Spree can't pay it twice.
	if mgr.reset_mp_earnings then
		mgr:reset_mp_earnings()
	end

	mgr:end_run()
	self:_dialog_leave_lobby_yes()

	if show_rewards then
		managers.menu:open_node("crime_spree_claim_rewards", {})
	end

	MenuCallbackHandler:save_progress()
end

function MenuCallbackHandler:_dialog_end_csr_no() end

function MenuCallbackHandler:return_to_csr_lobby()
	if game_state_machine:current_state_name() == "disconnected" then
		return
	end

	local dialog_data = {
		title = managers.localization:text("dialog_warning_title"),
		text = managers.localization:text("dialog_return_to_cs_lobby"),
	}
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = function()
			if game_state_machine:current_state_name() ~= "disconnected" then
				-- Must be Global.*: _G dies across the Lua-state reinit triggered by load_start_menu_lobby.
				Global.CSR_RETURN_TO_LOBBY = true
				csr_log("[CSR] return_to_csr_lobby: flag set, calling load_start_menu_lobby")
				self:load_start_menu_lobby()
			end
		end,
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		yes_button,
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:leave_csr_lobby()
	if game_state_machine:current_state_name() == "ingame_lobby_menu" then
		self:end_game()

		return
	end

	local dialog_data = {
		title = managers.localization:text("dialog_warning_title"),
		text = managers.localization:text("dialog_are_you_sure_you_want_leave_cs"),
		id = "leave_lobby",
	}
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = callback(self, self, "_dialog_leave_lobby_yes"),
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		callback_func = callback(self, self, "_dialog_leave_lobby_no"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		yes_button,
		no_button,
	}

	managers.system_menu:show(dialog_data)

	return true
end

function MenuCallbackHandler:end_game_csr()
	local fail_on_quit = true

	if not Global.game_settings.is_playing then
		fail_on_quit = false
	end

	local dialog_data = {
		title = managers.localization:text("dialog_warning_title"),
	}

	if Global.game_settings.is_playing then
		if managers.crime_spree:has_failed() then
			dialog_data.text = managers.localization:text("dialog_are_you_sure_you_want_to_leave_game")
		else
			dialog_data.text = managers.localization:text("dialog_are_you_sure_you_want_to_leave_game_crime_spree")
		end
	else
		dialog_data.text = managers.localization:text("dialog_are_you_sure_you_want_leave_cs")
	end

	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = callback(self, self, "_dialog_end_game_csr_yes", fail_on_quit),
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		callback_func = callback(self, self, "_dialog_end_game_csr_no"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		yes_button,
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:_dialog_end_game_csr_no() end

function MenuCallbackHandler:_dialog_end_game_csr_yes(failed)
	managers.platform:set_playing(false)
	managers.job:clear_saved_ghost_bonus()
	managers.statistics:stop_session({
		quit = true,
	})
	managers.savefile:save_progress()
	managers.job:deactivate_current_job()
	managers.gage_assignment:deactivate_assignments()
	managers.custom_safehouse:flush_completed_trophies()

	if failed == nil or failed then
		managers.crime_spree:on_mission_failed(managers.crime_spree:current_mission())
	end

	managers.crime_spree:on_left_lobby()

	if Network:multiplayer() then
		Network:set_multiplayer(false)
		managers.network:session():send_to_peers("set_peer_left")
		managers.network:queue_stop_network()
	end

	managers.network.matchmake:destroy_game()
	managers.network.voice_chat:destroy_voice()

	if managers.groupai then
		managers.groupai:state():set_AI_enabled(false)
	end

	managers.menu:post_event("menu_exit")
	managers.menu:close_menu("menu_pause")
	setup:load_start_menu()
end

function MenuCallbackHandler:csr_continue()
	local cost = managers.csr:get_continue_cost()
	local params = {
		level = managers.csr:rank(),
		cost = cost,
	}
	local coins = 0
	coins = managers.custom_safehouse:coins()

	if coins < cost then
		local dialog_data = {
			title = managers.localization:text("dialog_cant_continue_cs_title"),
			text = managers.localization:text("dialog_cant_continue_cs_text", params),
			id = "continue_crime_spree",
		}
		local no_button = {
			text = managers.localization:text("dialog_ok"),
			callback_func = callback(self, self, "_dialog_csr_continue_no"),
			cancel_button = true,
		}
		dialog_data.button_list = {
			no_button,
		}

		managers.system_menu:show(dialog_data)
	else
		local dialog_data = {
			title = managers.localization:text("dialog_continue_cs_title"),
			text = managers.localization:text("dialog_continue_cs_text", params),
			id = "continue_crime_spree",
		}
		local yes_button = {
			text = managers.localization:text("dialog_yes"),
			callback_func = callback(self, self, "_dialog_csr_continue_yes"),
		}
		local no_button = {
			text = managers.localization:text("dialog_no"),
			callback_func = callback(self, self, "_dialog_csr_continue_no"),
			cancel_button = true,
		}
		dialog_data.button_list = {
			yes_button,
			no_button,
		}

		managers.system_menu:show(dialog_data)
	end

	return true
end

function MenuCallbackHandler:_dialog_csr_continue_yes()
	-- Rebuild the missions panel so failed-lock re-evaluates after clearing.
	local cost = managers.csr:get_continue_cost()

	managers.custom_safehouse:deduct_coins(cost, TelemetryConst.economy_origin.continue_crime_spree)
	managers.csr:clear_failed()

	local logic = managers.menu:active_menu() and managers.menu:active_menu().logic
	if logic then
		local node = logic:selected_node()
		local name = node and node.parameters and node:parameters() and node:parameters().name

		if name then
			logic:refresh_node(name)
		end

		managers.menu_component:create_crime_spree_missions_gui(node)
	end

	WalletGuiObject.refresh()
	MenuCallbackHandler:save_progress()
end

function MenuCallbackHandler:_dialog_csr_continue_no() end

function MenuCallbackHandler:create_server_left_csr_dialog()
	local dialog_data = {
		title = managers.localization:text("dialog_warning_title"),
	}

	if Global.on_server_left_message then
		dialog_data.text = managers.localization:text("dialog_on_server_left_message_cs", {
			message = managers.localization:text(Global.on_server_left_message),
		})
		Global.on_server_left_message = nil
	else
		dialog_data.text = managers.localization:text("dialog_the_host_has_left_the_game_cs")
	end

	dialog_data.id = "server_left_dialog"
	local ok_button = {
		text = managers.localization:text("dialog_ok"),
		callback_func = callback(self, self, "_on_server_left_ok_pressed_csr"),
	}
	dialog_data.button_list = {
		ok_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:_on_server_left_ok_pressed_csr()
	self:_dialog_end_game_csr_yes(false)
end

function MenuCallbackHandler:show_peer_kicked_csr_dialog(params)
	local dialog_data = {
		title = managers.localization:text(
			Global.on_remove_peer_message and "dialog_information_title" or "dialog_mp_kicked_out_title"
		),
	}

	if Global.on_remove_peer_message then
		dialog_data.text = managers.localization:text("dialog_on_server_left_message_cs", {
			message = managers.localization:text(Global.on_remove_peer_message),
		})
	else
		dialog_data.text = managers.localization:text("dialog_on_server_left_message_cs", {
			message = managers.localization:text("dialog_mp_kicked_out_message"),
		})
	end

	local ok_button = {
		text = managers.localization:text("dialog_ok"),
		callback_func = callback(self, self, "_on_server_left_ok_pressed_csr"),
	}
	dialog_data.button_list = {
		ok_button,
	}

	managers.system_menu:show(dialog_data)

	Global.on_remove_peer_message = nil
end

-- Reroll costs continental coins = max(1, missions completed this spree). Confirm modal warns the cost first.
function MenuCallbackHandler:csr_reroll_cost()
	return math.max(1, (managers.csr and managers.csr:missions_completed()) or 0)
end

function MenuCallbackHandler:csr_reroll()
	local mission_gui = managers.menu_component:crime_spree_missions_gui()

	if mission_gui and mission_gui:is_randomizing() then
		managers.menu:post_event("menu_error")

		return
	end

	local cost = self:csr_reroll_cost()
	local can_afford = managers.custom_safehouse and managers.custom_safehouse:coins() >= cost

	local dialog_data = {
		title = managers.localization:text("csr_reroll_confirm_title"),
		id = "csr_reroll_confirm",
	}

	if can_afford then
		dialog_data.text = managers.localization:text("csr_reroll_confirm_text", { cost = cost })
		dialog_data.button_list = {
			{
				text = managers.localization:text("dialog_yes"),
				callback_func = callback(self, self, "_csr_reroll_confirm_yes"),
			},
			{
				text = managers.localization:text("dialog_no"),
				callback_func = callback(self, self, "_csr_reroll_confirm_no"),
				cancel_button = true,
			},
		}
	else
		dialog_data.text = managers.localization:text("csr_reroll_confirm_cant_afford", { cost = cost })
		dialog_data.button_list = {
			{
				text = managers.localization:text("dialog_ok"),
				callback_func = callback(self, self, "_csr_reroll_confirm_no"),
				cancel_button = true,
			},
		}
	end

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:_csr_reroll_confirm_yes()
	-- Guard against a second spin if the user clicks Yes while the animation is already running.
	local mission_gui = managers.menu_component:crime_spree_missions_gui()
	if mission_gui and mission_gui:is_randomizing() then
		managers.menu:post_event("menu_error")
		return
	end
	-- Re-resolve cost at confirm time; rank can't change in the lobby, but stay defensive.
	local cost = self:csr_reroll_cost()
	if managers.custom_safehouse then
		managers.custom_safehouse:deduct_coins(cost, TelemetryConst.economy_origin.crime_spree_reroll)
	end

	if managers.csr then
		managers.csr:reroll_mission_set()
	end

	mission_gui = managers.menu_component:crime_spree_missions_gui()
	if mission_gui then
		mission_gui:randomize_crimespree()
	end

	if WalletGuiObject then
		WalletGuiObject.refresh()
	end

	MenuCallbackHandler:save_progress()
end

function MenuCallbackHandler:_csr_reroll_confirm_no() end

function MenuCallbackHandler:csr_select_modifier()
	if self:show_csr_select_modifier() then
		managers.menu:open_node("crime_spree_select_modifiers", {})
	end
end

function MenuCallbackHandler:csr_start_game()
	if not managers.csr or managers.csr:current_mission() == nil then
		managers.menu:post_event("menu_error")
	else
		self:start_the_game()
	end
end

function MenuManager:show_confirm_mission_csr_asset_buy(params)
	local asset_tweak_data = tweak_data.crime_spree.assets[params.asset_id]
	local dialog_data = {
		title = managers.localization:text("dialog_assets_buy_title"),
		text = managers.localization:text("dialog_mission_asset_buy", {
			asset_desc = managers.localization:text(
				asset_tweak_data.unlock_desc_id or "menu_asset_unknown_unlock_desc",
				asset_tweak_data.data
			),
			cost = managers.localization:text("bm_cs_continental_coin_cost", {
				cost = managers.experience:cash_string(asset_tweak_data.cost, ""),
			}),
		}),
		focus_button = 2,
	}
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = params.yes_func,
	}
	local no_button = {
		text = managers.localization:text("dialog_no"),
		callback_func = params.no_func,
		cancel_button = true,
	}
	dialog_data.button_list = {
		yes_button,
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuManager:show_csr_assets_unlock_prevented(params)
	local asset_tweak_data = tweak_data.crime_spree.assets[params.asset_id]
	local dialog_data = {}

	if managers.crime_spree:can_unlock_asset_is_in_game() then
		dialog_data.title = managers.localization:text("dialog_cs_ga_in_progress")
		dialog_data.text = managers.localization:text("dialog_cs_ga_in_progress_text")
	else
		dialog_data.title = managers.localization:text("dialog_cs_ga_already_purchased")
		dialog_data.text = managers.localization:text("dialog_cs_ga_already_purchased_text")
	end

	dialog_data.focus_button = 1
	local no_button = {
		text = managers.localization:text("dialog_ok"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuManager:show_csr_asset_desc(params)
	local asset_tweak_data = tweak_data.crime_spree.assets[params.asset_id]
	local dialog_data = {
		title = managers.localization:text(asset_tweak_data.name_id),
		text = managers.localization:text(
			asset_tweak_data.unlock_desc_id or "menu_asset_unknown_unlock_desc",
			asset_tweak_data.data
		),
		focus_button = 1,
	}
	local no_button = {
		text = managers.localization:text("dialog_ok"),
		cancel_button = true,
	}
	dialog_data.button_list = {
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:choice_csr_difference_filter(item)
	Global.game_settings.crime_spree_max_lobby_diff = item:value()

	managers.user:set_setting("crime_spree_lobby_diff", item:value())
end

function MenuCallbackHandler:debug_csr_reset()
	managers.crime_spree:reset_crime_spree()
	MenuCallbackHandler:save_progress()
end

function MenuCallbackHandler:clear_csr_record()
	local dialog_data = {
		title = managers.localization:text("dialog_warning_title"),
		text = managers.localization:text("dialog_clear_crime_spree_record_confirmation_text"),
	}
	local yes_button = {
		text = managers.localization:text("dialog_yes"),
		callback_func = callback(self, self, "_dialog_clear_csr_record_yes"),
	}
	local no_button = {
		cancel_button = true,
		text = managers.localization:text("dialog_no"),
		callback_func = callback(self, self, "_dialog_clear_csr_record_no"),
	}
	dialog_data.button_list = {
		yes_button,
		no_button,
	}

	managers.system_menu:show(dialog_data)
end

function MenuCallbackHandler:_dialog_clear_csr_record_yes()
	Global.crime_spree.highest_level = nil

	managers.savefile:save_progress()
end

function MenuCallbackHandler:_dialog_clear_csr_record_no() end

-- Redirect vanilla menu-item callbacks to our forks. Hooked on lib/managers/menumanager
-- so we capture the final vanilla definition after its internal require overwrites these.

if MenuCallbackHandler and not _G._CSR_ACCEPT_CONTRACT_WRAPPED then
	_G._CSR_ACCEPT_CONTRACT_WRAPPED = true

	local original_accept = MenuCallbackHandler.accept_crime_spree_contract

	function MenuCallbackHandler:accept_crime_spree_contract(item, node)
		csr_log("[CSR] wiring: accept_crime_spree_contract intercepted -> accept_csr_contract")

		if self.accept_csr_contract then
			self:accept_csr_contract(item, node)
		elseif original_accept then
			log("[CSR] wiring: accept_csr_contract missing, falling back to vanilla")
			original_accept(self, item, node)
		end
	end
end

if MenuCallbackHandler and not _G._CSR_START_GAME_WRAPPED then
	_G._CSR_START_GAME_WRAPPED = true

	local original_start = MenuCallbackHandler.crime_spree_start_game

	function MenuCallbackHandler:crime_spree_start_game()
		if self.csr_start_game then
			self:csr_start_game()
		elseif original_start then
			original_start(self)
		end
	end
end

if MenuCallbackHandler and not _G._CSR_REROLL_WRAPPED then
	_G._CSR_REROLL_WRAPPED = true

	local original_reroll = MenuCallbackHandler.crime_spree_reroll

	function MenuCallbackHandler:crime_spree_reroll()
		if self.csr_reroll then
			self:csr_reroll()
		elseif original_reroll then
			original_reroll(self)
		end
	end
end

-- Drop the chosen mission on genuine lobby exit. Not in path for sub-screen round-trips
-- or Start→briefing, so picks survive those correctly.
Hooks:PostHook(MenuCallbackHandler, "_dialog_leave_lobby_yes", "CSR_ClearMissionOnLeaveLobby", function(self)
	if managers and managers.csr and managers.csr.select_mission then
		managers.csr:select_mission(false)
	end
end)

csr_log("[CSR] contract_callbacks.lua loaded")
