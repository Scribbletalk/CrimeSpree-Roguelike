-- Crime Spree Roguelike - Selection Wait
-- Blocks the host's "Start the heist" button while clients are selecting items.
-- Shows a countdown timer next to the button.

if not RequiredScript then
	return
end

local required = RequiredScript:lower()

-- === BLOCK CALLBACK (hooked on menumanager) ===
if required == "lib/managers/menumanager" then
	if MenuCallbackHandler then
		Hooks:PreHook(
			MenuCallbackHandler,
			"accept_crime_spree_contract",
			"CSR_BlockStartDuringSelection",
			function(self, item, node)
				if not _G.CSR_HostSelectionDeadline then
					return
				end

				local remaining = _G.CSR_HostSelectionDeadline - os.clock()
				if remaining > 0 then
					-- Block the callback by making it a no-op:
					-- set the item as disabled so vanilla skips it
					if item and item.set_enabled then
						item:set_enabled(false)
					end
				end
			end
		)
	end

	-- Countdown overlay removed — ready system handles blocking start
end
