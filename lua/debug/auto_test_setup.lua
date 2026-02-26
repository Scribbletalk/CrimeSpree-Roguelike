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
    local current_mod_count = 0
    if self._global.modifiers then
        current_mod_count = #self._global.modifiers
        for _, mod in ipairs(self._global.modifiers) do
            if mod.id and string.find(mod.id, "player_", 1, true) then
                has_test_items = true
                print("[CSR Auto Test] Found existing player item: " .. tostring(mod.id))
                break
            end
        end
    end

    print("[CSR Auto Test] Current modifiers count: " .. current_mod_count)
    print("[CSR Auto Test] Has test items already: " .. tostring(has_test_items))

    if has_test_items then
        print("[CSR Auto Test] Test items already present, skipping auto-add")
        return
    end

    -- Initialize modifiers table if needed
    if not self._global.modifiers then
        self._global.modifiers = {}
        print("[CSR Auto Test] Initialized modifiers table")
    end

    -- Add test items
    local test_items = {
        {id = "player_overkill_rush_1", level = 100},
        {id = "player_pink_slip_1", level = 100},
        {id = "player_viklund_vinyl_1", level = 100},
        {id = "player_equalizer_1", level = 100},
        {id = "player_crooked_badge_1", level = 100},
        {id = "player_dead_mans_trigger_1", level = 100},
    }

    print("[CSR Auto Test] Adding " .. #test_items .. " test items...")
    for i, item in ipairs(test_items) do
        table.insert(self._global.modifiers, item)
        print("[CSR Auto Test]   [" .. i .. "] Added: " .. item.id)
    end

    print("[CSR Auto Test] ✓ Added " .. #test_items .. " test items")
    print("[CSR Auto Test] ✓ Total modifiers now: " .. #self._global.modifiers)
    print("[CSR Auto Test] ✓ Crime Spree Level: " .. (self._global.spree_level or 0))

    -- Save to seed file so items persist after restart
    if _G.CSR_SaveSeed then
        DelayedCalls:Add("CSR_AutoTestSave", 0.5, function()
            -- Get current seed, difficulty, and modifiers from Crime Spree
            local current_seed = _G.CSR_CurrentSeed or os.time()
            local current_difficulty = _G.CSR_CurrentDifficulty or managers.crime_spree._global.selected_difficulty or "normal"
            local current_modifiers = managers.crime_spree._global.modifiers

            print("[CSR Auto Test] Saving: seed=" .. tostring(current_seed) .. ", difficulty=" .. tostring(current_difficulty) .. ", mods=" .. tostring(current_modifiers and #current_modifiers or 0))

            _G.CSR_SaveSeed(current_seed, current_difficulty, current_modifiers)
            print("[CSR Auto Test] ✓ Saved test items to seed file")
        end)
    else
        print("[CSR Auto Test] WARNING: CSR_SaveSeed not available!")
    end

    print("[CSR Auto Test] Ready for testing!")

    -- Show on-screen notification
    if managers.hud then
        managers.hud:show_hint({
            text = "DEBUG: Added " .. #test_items .. " test items",
            time = 5
        })
    end
end)
