-- Instant Win for DEBUG mode
-- Press F8 to instantly complete the mission

if not RequiredScript then
    return
end

-- Only run in DEBUG mode
if not CSR_DEBUG_MODE then
    return
end

print("[CSR Instant Win] DEBUG mode enabled - F8 to complete mission")

-- Keyboard listener
Hooks:Add("GameSetupUpdate", "CSR_InstantWin", function(t, dt)
    if not Input or not Input:keyboard() then
        return
    end

    -- F8: Instant mission complete
    if Input:keyboard():pressed(Idstring("f8")) then
        print("[CSR Instant Win] =========================================")
        print("[CSR Instant Win] F8 pressed - attempting mission completion")
        print("[CSR Instant Win] =========================================")

        -- Check if in game
        if not game_state_machine then
            print("[CSR Instant Win] ERROR: game_state_machine not found")
            return
        end

        -- Method 1: Try to teleport to escape zone (most reliable for heists with escape)
        local teleported = false
        if managers.groupai and managers.groupai:state() then
            local state = managers.groupai:state()
            print("[CSR Instant Win] Checking escape zones...")

            if state._escape_zones then
                for id, zone in pairs(state._escape_zones) do
                    if zone and zone.pos then
                        local player = managers.player:player_unit()
                        if player and alive(player) then
                            player:set_position(zone.pos)
                            print("[CSR Instant Win] ✓ TELEPORTED to escape zone: " .. tostring(id))
                            teleported = true

                            if managers.hud then
                                managers.hud:show_hint({
                                    text = "F8: Teleported to escape",
                                    time = 3
                                })
                            end
                            return
                        end
                    end
                end
            end

            if not teleported then
                print("[CSR Instant Win] No escape zones found or player not alive")
            end
        end

        -- Method 2: Force victory screen (works for most missions)
        print("[CSR Instant Win] Attempting to force victory screen...")
        local success, err = pcall(function()
            -- Try multiple methods
            if game_state_machine.change_state_by_name then
                game_state_machine:change_state_by_name("victoryscreen", {num_winners = 4})
                print("[CSR Instant Win] ✓ FORCED victoryscreen state")
            elseif managers.game_play_central and managers.game_play_central.end_heist then
                managers.game_play_central:end_heist()
                print("[CSR Instant Win] ✓ Called end_heist")
            end
        end)

        if success then
            print("[CSR Instant Win] ✓ SUCCESS - Mission completion triggered")
            if managers.hud then
                managers.hud:show_hint({
                    text = "F8: Mission force-completed",
                    time = 3
                })
            end
        else
            print("[CSR Instant Win] ERROR: " .. tostring(err))
            if managers.hud then
                managers.hud:show_hint({
                    text = "F8: Failed - check console",
                    time = 5
                })
            end
        end
    end
end)

print("[CSR Instant Win] Press F8 during mission to complete instantly")
