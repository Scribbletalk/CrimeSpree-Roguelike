-- Crime Spree Roguelike - Logbook Item Tracker
-- Tracks item acquisition for Logbook unlock.
--
-- NOTE: mark_seen is NOT called here (from activate_modifier) because that
-- creates a race condition: items would be marked seen BEFORE CSR_GenerateNewSeed()
-- calls unlock_seen() — causing them to unlock in the same session they were picked up.
-- Instead, mark_seen is called only from playermanager.lua:spawned_player,
-- which fires AFTER the new seed has been generated.

if not RequiredScript then
	return
end

log("[CSR Logbook] Item tracker loaded (mark_seen handled by spawned_player)")
