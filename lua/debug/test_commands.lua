-- Crime Spree Roguelike - Test Commands
-- Hotkeys for quick testing

if not RequiredScript then
    return
end

local function show_hint(text, duration)
    duration = duration or 3
    if managers.hud then
        managers.hud:show_hint({text = text, time = duration})
    end
end

local function print_cs_state()
    if not managers.crime_spree then
        print("[CSR Test] Crime Spree manager not available")
        return
    end

    local level = managers.crime_spree:spree_level() or 0
    local active = managers.crime_spree:is_active()
    print("[CSR Test] ==================")
    print("[CSR Test] Crime Spree Level: " .. level)
    print("[CSR Test] Active: " .. tostring(active))

    local mods = managers.crime_spree:active_modifiers() or {}
    print("[CSR Test] Active Modifiers: " .. #mods)
    for i, mod in ipairs(mods) do
        if i <= 10 then  -- Show first 10
            print("[CSR Test]   - " .. mod.id .. " (level " .. mod.level .. ")")
        end
    end
    if #mods > 10 then
        print("[CSR Test]   ... and " .. (#mods - 10) .. " more")
    end
    print("[CSR Test] ==================")
end

-- Keyboard listener
Hooks:Add("GameSetupUpdate", "CSR_TestCommandsUpdate", function(t, dt)
    if not Input or not Input:keyboard() then
        return
    end

    -- F9: Enable Crime Spree + Set Level 100
    if Input:keyboard():pressed(Idstring("f9")) then
        print("[CSR Test] F9: Enabling Crime Spree at level 100...")
        print("[CSR Test] DEBUG: managers.crime_spree = " .. tostring(managers.crime_spree))

        if managers.crime_spree and managers.crime_spree.enable_crime_spree then
            -- Enable Crime Spree (safe call with pcall)
            print("[CSR Test] DEBUG: Calling enable_crime_spree()...")
            local success, err = pcall(function()
                managers.crime_spree:enable_crime_spree()
            end)

            if not success then
                print("[CSR Test] ❌ ERROR enabling CS: " .. tostring(err))
                print("[CSR Test] This may be due to hook conflicts in seed_manager.lua")
                show_hint("Error: check console", 5)
                return
            end
            print("[CSR Test] ✓ enable_crime_spree() successful")

            -- Set starting level (safe call)
            success, err = pcall(function()
                managers.crime_spree:set_starting_level(100)
            end)

            if not success then
                print("[CSR Test] ERROR setting level: " .. tostring(err))
                show_hint("Error: " .. tostring(err), 5)
                return
            end

            show_hint("Crime Spree ENABLED: Level 100", 3)
            print_cs_state()
        else
            print("[CSR Test] ERROR: Crime Spree manager not available or enable_crime_spree method missing")
            show_hint("Crime Spree manager not ready", 3)
        end
    end

    -- F10: Add test modifiers (items)
    if Input:keyboard():pressed(Idstring("f10")) then
        print("[CSR Test] F10: Adding test modifiers...")

        if managers.crime_spree and managers.crime_spree._global then
            local test_mods = {
                {id = "player_plush_shark_1", level = 100},
                {id = "player_damage_boost_1", level = 100},
                {id = "player_health_boost_1", level = 100},
                {id = "player_wolfs_toolbox_1", level = 100},
                {id = "player_bonnie_chip_1", level = 100}
            }

            -- Add directly to modifiers table
            if not managers.crime_spree._global.modifiers then
                managers.crime_spree._global.modifiers = {}
            end

            for _, mod in ipairs(test_mods) do
                table.insert(managers.crime_spree._global.modifiers, mod)
            end

            show_hint("Added 5 test items", 3)
            print("[CSR Test] Added modifiers:")
            for _, mod in ipairs(test_mods) do
                print("[CSR Test]   + " .. mod.id)
            end
            print_cs_state()
        else
            print("[CSR Test] ERROR: Crime Spree manager not available")
        end
    end

    -- F11: Print current state
    if Input:keyboard():pressed(Idstring("f11")) then
        print("[CSR Test] F11: Printing Crime Spree state...")
        print_cs_state()
        show_hint("Check console for CS state", 2)
    end

    -- F12: Reset Crime Spree (clear modifiers)
    if Input:keyboard():pressed(Idstring("f12")) then
        print("[CSR Test] F12: Resetting Crime Spree...")

        if managers.crime_spree and managers.crime_spree._global then
            managers.crime_spree._global.modifiers = {}
            managers.crime_spree._global.spree_level = 0
            managers.crime_spree._global.is_active = false

            show_hint("Crime Spree RESET", 3)
            print("[CSR Test] Crime Spree reset complete")
            print_cs_state()
        else
            print("[CSR Test] ERROR: Crime Spree manager not available")
        end
    end
end)

print("[CSR Test Commands] Loaded!")
print("[CSR Test Commands] Hotkeys:")
print("  F9  - Enable Crime Spree + Set Level 100")
print("  F10 - Add 5 test items")
print("  F11 - Print current state")
print("  F12 - Reset Crime Spree")
