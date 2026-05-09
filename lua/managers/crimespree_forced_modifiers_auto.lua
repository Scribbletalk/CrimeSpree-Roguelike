-- Crime Spree Roguelike - Auto-apply Forced Modifiers
-- Automatically applies forced modifiers after mission when thresholds reached (20, 40, 60...)

if not RequiredScript then
	return
end

-- Recovery: fill in any forced modifiers that were missed (e.g. after crash/desync)
Hooks:PostHook(CrimeSpreeManager, "_setup", "CSR_RecoverMissingForcedMods", function(self)
	if not self._global then
		return
	end

	local current_level = self._global.spree_level or 0
	if current_level <= 0 then
		return
	end

	local forced_mods = tweak_data.crime_spree
			and tweak_data.crime_spree.repeating_modifiers
			and tweak_data.crime_spree.repeating_modifiers.forced
		or {}

	local existing_ids = {}
	for _, mod in ipairs(self._global.modifiers or {}) do
		if mod.id then
			existing_ids[mod.id] = true
		end
	end

	local recovered = {}
	for _, mod in ipairs(forced_mods) do
		if mod.id and mod.level and mod.level <= current_level and not existing_ids[mod.id] then
			table.insert(self._global.modifiers, { id = mod.id, level = mod.level })
			table.insert(recovered, mod.id)
		end
	end

	if #recovered > 0 then
		log("[CSR] Recovered " .. #recovered .. " missing forced modifiers: " .. table.concat(recovered, ", "))
		if CSR_SaveSeed and _G.CSR_CurrentSeed then
			local difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"
			CSR_SaveSeed(_G.CSR_CurrentSeed, difficulty, self._global.modifiers)
		end
	end
end)

-- PostHook: Apply forced modifiers AFTER bags/kills bonus
Hooks:PostHook(CrimeSpreeManager, "on_mission_completed", "CSR_AutoApplyForcedMods", function(self, mission_id)
	if not self:is_active() or self:has_failed() then
		return
	end

	-- Clients receive forced mods from the host via broadcast_forced_mods/apply_forced_mods.
	-- Running this on the client would calculate mods based on the client's own rank, not the host's.
	if _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() then
		return
	end

	-- Get old and new level
	local old_level = self._csr_old_level or 0
	local new_level = self._global.spree_level or 0

	if new_level <= old_level then
		return
	end

	-- v2.50: Debug logging

	-- Get list of forced modifiers
	local forced_mods = tweak_data.crime_spree.repeating_modifiers and tweak_data.crime_spree.repeating_modifiers.forced
		or {}

	-- v2.50: Debug logging

	-- Find modifiers between old and new level
	local mods_to_add = {}
	for _, mod in ipairs(forced_mods) do
		if mod.id and mod.level and mod.level > old_level and mod.level <= new_level then
			-- Check that modifier does not exist yet (duplicate protection)
			local already_exists = false
			for _, existing in ipairs(self._global.modifiers or {}) do
				if existing.id == mod.id then
					already_exists = true
					break
				end
			end

			if not already_exists then
				table.insert(mods_to_add, {
					id = mod.id,
					level = mod.level,
				})
			else
			end
		end
	end

	-- Signal that a popup is about to appear (so rank animation can wait)
	_G.CSR_ForcedModsPending = #mods_to_add > 0

	-- Add modifiers
	if #mods_to_add > 0 then
		for _, mod in ipairs(mods_to_add) do
			table.insert(self._global.modifiers, mod)
		end

		-- Update CSR_LastShownForcedLevel to max level
		local max_forced_level = 0
		for _, mod in ipairs(mods_to_add) do
			if mod.level > max_forced_level then
				max_forced_level = mod.level
			end
		end

		if max_forced_level > 0 then
			local old_last_shown = _G.CSR_LastShownForcedLevel or 0
			_G.CSR_LastShownForcedLevel = math.max(old_last_shown, max_forced_level)
		end

		-- AUTOSAVE: Save modifiers to seed file
		if CSR_SaveSeed and _G.CSR_CurrentSeed then
			local current_difficulty = self._global.selected_difficulty or _G.CSR_CurrentDifficulty or "normal"
			CSR_SaveSeed(_G.CSR_CurrentSeed, current_difficulty, self._global.modifiers)
		end

		-- Refresh the CS details panel so forced mods appear in the modifiers list immediately.
		DelayedCalls:Add("CSR_RefreshDetailsAfterAutoMods", 0.5, function()
			if managers.menu_component then
				pcall(function()
					managers.menu_component:refresh_crime_spree_details_gui()
				end)
			end
		end)

		-- Broadcast to clients in multiplayer
		if _G.CSR_MP and CSR_MP.broadcast_forced_mods then
			CSR_MP.broadcast_forced_mods(mods_to_add)
		end

		-- SHOW NOTIFICATION (v2.49: direct call, no double delay)
		DelayedCalls:Add("CSR_ShowForcedModsNotification", 0.5, function()
			if _G.CSR_ShowForcedModsPopup then
				_G.CSR_ShowForcedModsPopup(mods_to_add)
			else
			end
		end)
	else
	end
end)
