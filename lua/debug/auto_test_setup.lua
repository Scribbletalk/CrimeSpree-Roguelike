-- Auto Test Setup for DEBUG mode
-- Automatically adds test items and sets level 100 when creating Crime Spree lobby

if not RequiredScript then
	return
end

-- Only run in DEBUG mode
if not CSR_DEBUG_MODE then
	print("[CSR Auto Test] DEBUG mode disabled, auto setup inactive")
	return
end

print("[CSR Auto Test] DEBUG mode enabled - auto setup active")

-- Hook when Crime Spree setup is complete (after lobby creation)
Hooks:PostHook(CrimeSpreeManager, "_setup", "CSR_AutoTestSetup", function(self)
	print("[CSR Auto Test] _setup hook triggered!")
	print("[CSR Auto Test] self._global exists: " .. tostring(self._global ~= nil))

	if self._global then
		print("[CSR Auto Test] is_active: " .. tostring(self._global.is_active))
		print("[CSR Auto Test] spree_level: " .. tostring(self._global.spree_level or "nil"))
	end

	-- DON'T check is_active - it might not be set yet!
	if not self._global then
		print("[CSR Auto Test] No _global, skipping")
		return
	end

	-- Check if already has items (don't add duplicates)
	local has_test_items = false
	local local_items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
	local current_item_count = #local_items

	if current_item_count > 0 then
		has_test_items = true
		print("[CSR Auto Test] Found " .. current_item_count .. " existing player items")
	end

	print("[CSR Auto Test] Has test items already: " .. tostring(has_test_items))

	if has_test_items then
		print("[CSR Auto Test] Test items already present, skipping auto-add")
		return
	end

	-- Add test items via per-player item store
	local test_prefixes = {
		"player_overkill_rush_",
		"player_pink_slip_",
		"player_viklund_vinyl_",
		"player_equalizer_",
		"player_crooked_badge_",
		"player_dead_mans_trigger_",
		"player_half_a_glass_",
		"player_the_edge_",
		"player_cup_of_joe_",
		"player_lockes_beret_",
		"player_familiar_friend_",
		"player_side_satchel_",
		"player_carrot_stick_",
	}

	print("[CSR Auto Test] Adding " .. #test_prefixes .. " test items...")
	if CSR_AddItem then
		for i, prefix in ipairs(test_prefixes) do
			local new_id = CSR_AddItem(prefix, 100)
			print("[CSR Auto Test]   [" .. i .. "] Added: " .. tostring(new_id))
		end
	end

	local new_items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
	print("[CSR Auto Test] Total player items now: " .. #new_items)
	print("[CSR Auto Test] Crime Spree Level: " .. (self._global.spree_level or 0))

	-- Save to seed file so items persist after restart
	if _G.CSR_SaveSeed then
		DelayedCalls:Add("CSR_AutoTestSave", 0.5, function()
			local current_seed = _G.CSR_CurrentSeed or os.time()
			local current_difficulty = _G.CSR_CurrentDifficulty
				or managers.crime_spree._global.selected_difficulty
				or "normal"
			local current_modifiers = managers.crime_spree._global.modifiers

			print("[CSR Auto Test] Saving seed file...")
			_G.CSR_SaveSeed(current_seed, current_difficulty, current_modifiers)
			print("[CSR Auto Test] Saved test items to seed file")
		end)
	else
		print("[CSR Auto Test] WARNING: CSR_SaveSeed not available!")
	end

	print("[CSR Auto Test] Ready for testing!")

	-- Force "new logbook items" indicator for testing the LOGBOOK "!" button
	pcall(function()
		if _G.CSR_Logbook then
			_G.CSR_Logbook._new_items = { dog_tags = true }
			print("[CSR Auto Test] Forced logbook 'has_new' state for button test")
		end
	end)

	-- Show on-screen notification
	if managers.hud then
		managers.hud:show_hint({
			text = "DEBUG: Added " .. #test_prefixes .. " test items",
			time = 5,
		})
	end
end)
