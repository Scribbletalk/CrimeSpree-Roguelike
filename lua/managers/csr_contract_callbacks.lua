-- CSR contract callbacks — fork of vanilla menumanagercrimespreecallbacks.lua.
--
-- Origin: pd2_source_code/lib/managers/menu/menumanagercrimespreecallbacks.lua (691 lines)
-- Strategy: byte-for-byte copy with every callback name renamed `crime_spree`
-- -> `csr`. All `managers.crime_spree.*`, `tweak_data.crime_spree.*` and
-- `Global.crime_spree.*` body references intentionally left intact for this
-- slice — backend swap to managers.csr happens in a later slice.
--
-- Why rename every callback (even ones not referencing crime_spree directly):
-- vanilla menu items in start_menu.menu reference these by string. If we kept
-- the same names, our copies would REPLACE vanilla's via redefinition, which
-- means vanilla CS would invoke OUR forks. Renaming everything keeps a clean
-- separation: vanilla CS menu items still call vanilla callbacks; our forked
-- menu nodes (Slice 4) will call our renamed callbacks.
--
-- Strings kept as-is: vanilla node names ("crime_spree_lobby",
-- "crime_spree_claim_rewards", "crime_spree_select_modifiers"), dialog IDs
-- ("stop_crime_spree", "continue_crime_spree", etc.), TelemetryConst keys.

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
	local state = game_state_machine:current_state_name()

	return state == "victoryscreen" or state == "gameoverscreen"
end

function MenuCallbackHandler:accept_csr_contract(item, node)
	log("[CSR] accept_csr_contract body running (single_player=" .. tostring(Global.game_settings.single_player) .. ")")
	if Global.game_settings.single_player then
		self:_accept_csr_contract_sp(item, node)
	else
		self:_accept_csr_contract_mp(item, node)
	end
end

function MenuCallbackHandler:_accept_csr_contract_sp(item, node)
	-- Slice 6 full-replace: vanilla start_crime_spree + enable_crime_spree_gamemode
	-- removed. managers.csr:start_run() is now the sole run-state activator.
	--
	-- STOPGAP (2026-05-18): only start_run() when NO run is active. start_run()
	-- unconditionally resets rank + missions_completed to 0; re-accepting the
	-- CrimeNet CSR contract is currently the ONLY way back into the lobby
	-- because the CS end-screen "continue" loop is an unported slice, so an
	-- unconditional start_run() wiped the player's run progress every time they
	-- returned from a completed heist (progress IS saved to disk; it was just
	-- discarded here on re-entry). Guarding on is_active() makes re-entry
	-- CONTINUE the in-flight run; a fresh run still starts when none is active.
	-- The proper fix (end-screen fork with a real Continue/Return + end_run on
	-- cash-out/return) is planned -- see project_endscreen_fork_plan.md. Known
	-- stopgap edge: a stale is_active=true from an abandoned/never-ended run
	-- continues instead of starting fresh; not balance-wrecking under the
	-- locked flat-1-rank rebalance, and there is no reset UI in alpha anyway.
	if not managers.csr:is_active() then
		managers.csr:start_run()
	end
	MenuCallbackHandler:save_progress()
	managers.menu:active_menu().logic:select_node("crime_spree_lobby", true, {})
end

function MenuCallbackHandler:_accept_csr_contract_mp(item, node)
	-- Slice 6 full-replace: vanilla start_crime_spree + enable_crime_spree_gamemode
	-- removed. Matchmaking + chat-line + save_progress paths kept — they don't
	-- depend on vanilla CS state directly. Note: get_matchmake_attributes via
	-- apply_matchmake_attributes will now write lobby_attributes.crime_spree = -1
	-- because vanilla CS isn't in_progress; lobby will look like a normal one
	-- to other clients until MP carve-out lands.
	--
	-- STOPGAP (2026-05-18): see _accept_csr_contract_sp — only start_run() when
	-- no run is active so re-entering the lobby CONTINUES the in-flight run
	-- instead of resetting rank/missions to 0. Proper fix tracked in
	-- project_endscreen_fork_plan.md.
	if not managers.csr:is_active() then
		managers.csr:start_run()
	end

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

	-- CSR has no continental-coin entry fee, so the vanilla CS refund branch
	-- (can_refund_entry_fee / get_start_cost) is dropped — plain confirm only.
	-- CSR-owned key (csr_contract_wiring.lua), NOT the vanilla
	-- dialog_are_you_sure_you_want_stop_cs: End Spree ends the run AND grants
	-- rewards, and overriding the vanilla key would leak into vanilla CS.
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
	-- End Spree: end the CSR run (THE persisted-is_active leak-class
	-- dissolver — see project_endscreen_fork_plan) and leave the lobby back to
	-- the main menu. No refund branch (CSR has no entry fee).
	-- _dialog_leave_lobby_yes is the verified vanilla leave-lobby path
	-- (menumanager.lua:3574 -> managers.menu:on_leave_lobby; its
	-- crime_spree:disable_crime_spree_gamemode is a harmless no-op for CSR).
	managers.csr:end_run()
	self:_dialog_leave_lobby_yes()
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
				-- One-shot routing intent: vanilla MenuManager:on_enter_lobby
				-- (menumanagerpd2.lua:31) only selects the "crime_spree_lobby"
				-- node when the CS gamemode is enabled, which CSR never does
				-- (Slice 6 runs a temp "crime_spree" job under the vanilla
				-- gamemode). Without this flag the player lands in the empty
				-- normal "lobby" node. csr_lobby_routing.lua consumes the flag
				-- in an on_enter_lobby PostHook and re-selects the CSR node.
				-- Transient (cleared on consume), NOT the persisted
				-- managers.csr:is_active() — avoids the vanilla-leak class.
				-- MUST be Global.* not _G.*: load_start_menu_lobby from the
				-- victoryscreen state triggers a full Lua-environment reinit
				-- (game-state _G ≠ menu-state _G). Global survives it; _G does
				-- not. Mirrors vanilla Global.load_start_menu_lobby.
				Global.CSR_RETURN_TO_LOBBY = true
				log("[CSR] return_to_csr_lobby: flag set, calling load_start_menu_lobby")
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
	-- Paid Continue: spend the continental-coin cost, clear the failed flag
	-- (the run continues), then rebuild the CSR missions panel so its
	-- failed-lock re-evaluates and Start / Reroll / mission-select unlock.
	-- The vanilla-CS mission-end / details gui plumbing is dropped — those
	-- components are not part of the CSR fork. deduct_coins is the verified
	-- vanilla spend (crimespreemanager.lua:751 uses the identical call +
	-- telemetry origin). csr_continue already guarded coins >= cost before
	-- showing the yes button.
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

function MenuCallbackHandler:csr_reroll()
	-- Slice 8: free reroll (no continental-coin cost). Vanilla's escalating-cost
	-- reroll economy is intentionally dropped for the alpha mission-select slice.
	local mission_gui = managers.menu_component:crime_spree_missions_gui()

	if mission_gui and mission_gui:is_randomizing() then
		managers.menu:post_event("menu_error")

		return
	end

	if managers.csr then
		managers.csr:reroll_mission_set()
	end

	if mission_gui then
		mission_gui:randomize_crimespree()
	end

	MenuCallbackHandler:save_progress()
end

function MenuCallbackHandler:csr_select_modifier()
	if self:show_csr_select_modifier() then
		managers.menu:open_node("crime_spree_select_modifiers", {})
	end
end

function MenuCallbackHandler:csr_start_game()
	-- Slice 8: mission state lives in managers.csr now, not vanilla CS.
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

-- Slice 5 wiring: redirect vanilla's accept_crime_spree_contract -> our forked
-- accept_csr_contract. This MUST live in this file (not csr_contract_wiring.lua)
-- because vanilla MenuManagerCrimeSpreeCallbacks is required at menumanager.lua:35
-- and overwrites accept_crime_spree_contract. Our wrap has to install AFTER that
-- happens. The lib/managers/menumanager hook fires after menumanager.lua finishes
-- loading (including its requires), so our wrap captures the FINAL vanilla
-- definition and stays installed.

if MenuCallbackHandler and not _G._CSR_ACCEPT_CONTRACT_WRAPPED then
	_G._CSR_ACCEPT_CONTRACT_WRAPPED = true

	local original_accept = MenuCallbackHandler.accept_crime_spree_contract

	function MenuCallbackHandler:accept_crime_spree_contract(item, node)
		log("[CSR] wiring: accept_crime_spree_contract intercepted -> accept_csr_contract")

		if self.accept_csr_contract then
			self:accept_csr_contract(item, node)
		elseif original_accept then
			log("[CSR] wiring: accept_csr_contract missing, falling back to vanilla")
			original_accept(self, item, node)
		end
	end
end

-- Slice 8 wiring: redirect vanilla's lobby start + reroll callbacks (invoked by
-- the vanilla crime_spree_lobby node's menu items by string name) to our forked
-- csr_* versions, which run against managers.csr. Same rationale and install
-- timing as the accept wrap above (vanilla MenuManagerCrimeSpreeCallbacks is
-- required at menumanager.lua:35, so a raw wrap here captures the final vanilla
-- definition).

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

log("[CSR] csr_contract_callbacks.lua loaded (Slice 3 fork + Slice 5 accept wrap + Slice 8 start/reroll wrap)")
