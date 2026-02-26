-- Crime Spree Roguelike - Automatically close popup with 0 modifiers

if not RequiredScript then
	return
end

-- Hook on init - if no modifiers present, auto-close the popup
Hooks:PostHook(CrimeSpreeForcedModifiersMenuComponent, "init", "CSR_AutoCloseEmptyPopup", function(self)
	-- Check how many modifiers are in the list
	local modifiers = self._modifiers or {}
	
	if #modifiers == 0 then
		log("[CSR] CrimeSpreeForcedModifiersMenuComponent: 0 modifiers, auto-closing")
		-- Close via timer (to let init finish first)
		DelayedCalls:Add("csr_close_empty_forced_popup", 0.1, function()
			if self.close then
				self:close()
			end
		end)
	end
end)

log("[CSR] Auto-close empty forced modifiers popup hook loaded!")
