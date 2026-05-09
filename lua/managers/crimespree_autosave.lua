-- Crime Spree Roguelike - Auto-save modifiers to seed file
-- Saves the current modifier list whenever the player picks a new modifier

if not RequiredScript then
	return
end

-- Transfer player items from _global.modifiers to CSR_PlayerItems.
-- Vanilla select_modifier() places items into _global.modifiers, but the per-player
-- system stores them in CSR_PlayerItems. This must fire BEFORE the autosave hook below.
Hooks:PostHook(CrimeSpreeManager, "select_modifier", "CSR_TransferPlayerItem", function(self, modifier_id)
	if not modifier_id or type(modifier_id) ~= "string" then
		return
	end
	if string.find(modifier_id, "player_", 1, true) ~= 1 then
		return
	end

	-- Extract id_prefix: "player_health_boost_3" -> "player_health_boost_"
	local prefix = modifier_id:match("^(.+_)%d+$")
	if not prefix then
		return
	end

	local level = self:spree_level() or 0
	local items_before = CSR_GetLocalItems and #CSR_GetLocalItems() or -1
	if CSR_AddItem then
		CSR_AddItem(prefix, level)
	end
	local items_after = CSR_GetLocalItems and #CSR_GetLocalItems() or -1
	log(
		"[CSR TransferPlayerItem] modifier_id="
			.. tostring(modifier_id)
			.. " prefix="
			.. tostring(prefix)
			.. " items: "
			.. tostring(items_before)
			.. " -> "
			.. tostring(items_after)
	)

	-- Remove the item from _global.modifiers (vanilla already added it there)
	if self._global and self._global.modifiers then
		local clean = {}
		for _, mod in ipairs(self._global.modifiers) do
			if mod.id ~= modifier_id then
				table.insert(clean, mod)
			end
		end
		self._global.modifiers = clean
	end

	-- Clear the cached offer so a new set of items is generated for the next pick
	_G.CSR_CachedModifierOffer = nil
end)

-- Hook on select_modifier — fires when the player confirms an item choice in the popup
Hooks:PostHook(CrimeSpreeManager, "select_modifier", "CSR_AutoSaveModifiers", function(self, modifier_id)
	-- Only save while Crime Spree is active
	if not self:is_active() then
		return
	end

	-- Check if we have either forced mods OR player items to save
	local has_forced = self._global.modifiers and #self._global.modifiers > 0
	local has_items = _G.CSR_PlayerItems and CSR_GetLocalItems and #CSR_GetLocalItems() > 0
	if not has_forced and not has_items then
		return
	end

	local current_seed = _G.CSR_CurrentSeed
	local current_difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"

	if not current_seed then
		return
	end

	-- Write to the seed file (CSR_SaveSeed reads player items from CSR_PlayerItems now)
	local save_items_count = CSR_GetLocalItems and #CSR_GetLocalItems() or -1
	log(
		"[CSR AutoSaveModifiers] modifier_id="
			.. tostring(modifier_id)
			.. " forced_mods="
			.. tostring(self._global.modifiers and #self._global.modifiers or 0)
			.. " player_items="
			.. tostring(save_items_count)
	)
	if CSR_SaveSeed then
		CSR_SaveSeed(current_seed, current_difficulty, self._global.modifiers)

		-- Update the in-memory cache with forced mods (non-player_ entries)
		_G.CSR_SavedModifiers = {}
		for _, mod in ipairs(self._global.modifiers or {}) do
			table.insert(_G.CSR_SavedModifiers, { id = mod.id, level = mod.level })
		end
		-- Also include player items in CSR_SavedModifiers for backward compat
		local local_items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		for _, item in ipairs(local_items) do
			table.insert(_G.CSR_SavedModifiers, { id = item.id, level = item.level })
		end
	end

	-- MP clients: CSR_SaveSeed skips clients, so persist items to session file instead.
	-- Save under BOTH run_seed and CSR_CurrentSeed so reload recovery finds it.
	if _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and CSR_SaveSession then
		local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
		local td = _G.CSR_MP_TotalDrops or 0
		local rs = _G.CSR_MP_RunSeed
		if rs then
			CSR_SaveSession(rs, nil, items, td)
		end
		if _G.CSR_CurrentSeed and tostring(_G.CSR_CurrentSeed) ~= tostring(rs) then
			CSR_SaveSession(_G.CSR_CurrentSeed, nil, items, td)
		end
	end
end)
