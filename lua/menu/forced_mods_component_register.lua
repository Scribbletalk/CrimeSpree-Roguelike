-- Crime Spree Roguelike - Register Forced Mods Notification Helper
-- v2.49: Simplified - no MenuHelper, just global helper function

log("[CSR Notification] Registering helper function...")

-- Helper function for showing popup (called from crimespree_forced_modifiers_auto.lua)
_G.CSR_ShowForcedModsPopup = function(modifiers)
	log("[CSR Notification] ShowForcedModsPopup called with " .. #modifiers .. " modifiers")

	-- Close old popup if exists
	if _G.CSR_ForcedModsNotificationInstance then
		_G.CSR_ForcedModsNotificationInstance:close()
		_G.CSR_ForcedModsNotificationInstance = nil
	end

	-- Delay to let old popup fade out
	DelayedCalls:Add("CSR_CreatePopup", 0.3, function()
		if CSRForcedModsNotification then
			_G.CSR_ForcedModsNotificationInstance = CSRForcedModsNotification:new(modifiers)
			log("[CSR Notification] Popup created successfully")
		else
			log("[CSR Notification] ERROR: CSRForcedModsNotification class not found!")
		end
	end)
end

log("[CSR Notification] Helper function registered!")
