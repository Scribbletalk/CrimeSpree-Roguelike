-- Crime Spree Roguelike - Register Forced Mods Notification Helper
-- v2.49: Simplified - no MenuHelper, just global helper function

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("[CSR Notification] Registering helper function...")

-- Helper function for showing popup (called from crimespree_forced_modifiers_auto.lua)
_G.CSR_ShowForcedModsPopup = function(modifiers)
	CSR_log("[CSR Notification] ShowForcedModsPopup called with " .. #modifiers .. " modifiers")

	-- Close old popup if exists
	if _G.CSR_ForcedModsNotificationInstance then
		_G.CSR_ForcedModsNotificationInstance:close()
		_G.CSR_ForcedModsNotificationInstance = nil
	end

	-- Delay to let old popup fade out
	DelayedCalls:Add("CSR_CreatePopup", 0.3, function()
		-- Clear pending flag — popup is now being created (or failed)
		_G.CSR_ForcedModsPending = false

		if CSRForcedModsNotification then
			_G.CSR_ForcedModsNotificationInstance = CSRForcedModsNotification:new(modifiers)
			CSR_log("[CSR Notification] Popup created successfully")
		else
			log("[CSR Notification] ERROR: CSRForcedModsNotification class not found!")
		end
	end)
end

CSR_log("[CSR Notification] Helper function registered!")
