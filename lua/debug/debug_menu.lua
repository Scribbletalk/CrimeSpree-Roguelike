-- CSR Debug Tools: builds the "Debug Tools" sub-menu under csr_options_menu.
-- Self-contained; strip before release (options_menu.lua keeps working without it).
-- Loads after options_menu.lua in mod.txt so csr_options_menu exists at attach time.

-- Wildcards are carry-1; granting one replaces the current wildcard (handled in add_item).
local CSR_WILDCARD_GRANTS = {
	{ type = "familiar_friend", callback = "csr_grant_wc_familiar_friend", title = "csr_grant_wc_ff_title" },
	{ type = "side_satchel", callback = "csr_grant_wc_side_satchel", title = "csr_grant_wc_ss_title" },
	{ type = "turron", callback = "csr_grant_wc_turron", title = "csr_grant_wc_tu_title" },
	{ type = "hippocratic_oath", callback = "csr_grant_wc_hippocratic_oath", title = "csr_grant_wc_ho_title" },
}

Hooks:Add("LocalizationManagerPostInit", "CSR_DebugLocalization", function(loc)
	loc:add_localized_strings({
		csr_debug_menu_title = "Debug Tools",
		csr_debug_menu_desc = "Testing shortcuts for development.",
		csr_grant_items_title = "Grant All Items",
		csr_grant_items_desc = "Gives your character one of every item currently in the mod "
			.. "(bypasses the selection window). Click again to add another stack of each.",
		csr_grant_coj_title = "Grant Cup of Joe",
		csr_grant_coj_desc = "Gives one Cup of Joe (the per-item-file test item) to isolate its "
			.. "effect. Click again for another stack.",
		csr_grant_pen_title = "Grant Tactical Pen",
		csr_grant_pen_desc = "Gives one Tactical Pen (+13%/stack damage to enemies within 7m). "
			.. "Click again for another stack.",
		csr_force_fwb_title = "Force: First World Bank",
		csr_force_fwb_desc = "Sets your next heist to First World Bank (red2) so you can test it. "
			.. "Requires an active run: click this, then open the Crime Spree contract -- it will be the only "
			.. "card. Pick a difficulty and start as usual.",
		csr_add_tokens_title = "Add 100 Tokens",
		csr_add_tokens_desc = "Credits 100 Gage Tokens to your account. For testing the shop.",
		csr_grant_wildcard_desc = "Gives this wildcard to your character. Wildcards are carry-1: "
			.. "granting one replaces any wildcard you already hold.",
		csr_grant_wc_ff_title = "Grant Wildcard: Familiar Friend",
		csr_grant_wc_ss_title = "Grant Wildcard: Side Satchel",
		csr_grant_wc_tu_title = "Grant Wildcard: Turron",
		csr_grant_wc_ho_title = "Grant Wildcard: Hippocratic Oath",
	})
end)

Hooks:Add("MenuManagerInitialize", "CSR_DebugCallbacks", function(menu_manager)
	MenuCallbackHandler.csr_grant_all_items = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.grant_all_items then
			mgr:grant_all_items()
		end
	end

	MenuCallbackHandler.csr_grant_cup_of_joe = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.add_item then
			mgr:add_item(mgr:local_peer_id(), "cup_of_joe")
		end
	end

	MenuCallbackHandler.csr_grant_aloe_leaf = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.add_item then
			mgr:add_item(mgr:local_peer_id(), "aloe_leaf")
		end
	end

	MenuCallbackHandler.csr_grant_tactical_pen = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.add_item then
			mgr:add_item(mgr:local_peer_id(), "tactical_pen")
		end
	end

	MenuCallbackHandler.csr_force_fwb = function(self, item)
		local mgr = managers.csr
		if mgr and mgr.debug_force_mission then
			mgr:debug_force_mission("red2")
		end
	end

	MenuCallbackHandler.csr_add_tokens = function(self, item)
		CSR_Shop.credit(CSR_Shop.local_peer_id(), 100)
	end

	for _, w in ipairs(CSR_WILDCARD_GRANTS) do
		MenuCallbackHandler[w.callback] = function(self, item)
			local mgr = managers.csr
			if mgr and mgr.add_item then
				mgr:add_item(mgr:local_peer_id(), w.type)
			end
		end
	end
end)

Hooks:Add("MenuManagerSetupCustomMenus", "CSR_DebugSetup", function(menu_manager, nodes)
	MenuHelper:NewMenu("csr_debug_menu")
end)

Hooks:Add("MenuManagerBuildCustomMenus", "CSR_DebugBuild", function(menu_manager, nodes)
	nodes.csr_debug_menu = MenuHelper:BuildMenu("csr_debug_menu", { back_callback = "csr_options_back" })
	MenuHelper:AddMenuItem(nodes.csr_options_menu, "csr_debug_menu", "csr_debug_menu_title", "csr_debug_menu_desc")
end)

Hooks:Add("MenuManagerPopulateCustomMenus", "CSR_DebugPopulate", function(menu_manager, nodes)
	MenuHelper:AddButton({
		id = "grant_all_items",
		title = "csr_grant_items_title",
		desc = "csr_grant_items_desc",
		callback = "csr_grant_all_items",
		menu_id = "csr_debug_menu",
		priority = 2,
	})

	MenuHelper:AddButton({
		id = "grant_cup_of_joe",
		title = "csr_grant_coj_title",
		desc = "csr_grant_coj_desc",
		callback = "csr_grant_cup_of_joe",
		menu_id = "csr_debug_menu",
		priority = 1,
	})

	MenuHelper:AddButton({
		id = "grant_aloe_leaf",
		title = "csr_grant_aloe_title",
		desc = "csr_grant_aloe_desc",
		callback = "csr_grant_aloe_leaf",
		menu_id = "csr_debug_menu",
		priority = 0,
	})

	MenuHelper:AddButton({
		id = "grant_tactical_pen",
		title = "csr_grant_pen_title",
		desc = "csr_grant_pen_desc",
		callback = "csr_grant_tactical_pen",
		menu_id = "csr_debug_menu",
		priority = -1,
	})

	MenuHelper:AddButton({
		id = "force_fwb",
		title = "csr_force_fwb_title",
		desc = "csr_force_fwb_desc",
		callback = "csr_force_fwb",
		menu_id = "csr_debug_menu",
		priority = 3,
	})

	MenuHelper:AddButton({
		id = "add_tokens",
		title = "csr_add_tokens_title",
		desc = "csr_add_tokens_desc",
		callback = "csr_add_tokens",
		menu_id = "csr_debug_menu",
		priority = 4,
	})

	for i, w in ipairs(CSR_WILDCARD_GRANTS) do
		MenuHelper:AddButton({
			id = "grant_" .. w.type,
			title = w.title,
			desc = "csr_grant_wildcard_desc",
			callback = w.callback,
			menu_id = "csr_debug_menu",
			priority = 4 + i,
		})
	end
end)
