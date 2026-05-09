-- Crime Spree Roguelike - Forced modifiers popup guards
-- Auto-close popup with 0 modifiers + nil guards for client crashes

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

-- Guard: mouse_moved crashes when UI objects are nil or their C++ panels are destroyed
-- (e.g. playing as client, forced state transition via F8/mission end)
if CrimeSpreeForcedModifiersMenuComponent.mouse_moved then
	local _orig_forced_mouse_moved = CrimeSpreeForcedModifiersMenuComponent.mouse_moved
	function CrimeSpreeForcedModifiersMenuComponent:mouse_moved(o, x, y)
		if not self._modifiers_scroll or not self._back_btn or not alive(self._panel) then
			return false, "arrow"
		end
		return _orig_forced_mouse_moved(self, o, x, y)
	end
end

if CrimeSpreeForcedModifiersMenuComponent.mouse_pressed then
	local _orig_forced_mouse_pressed = CrimeSpreeForcedModifiersMenuComponent.mouse_pressed
	function CrimeSpreeForcedModifiersMenuComponent:mouse_pressed(button, x, y)
		if not self._modifiers_scroll or not self._back_btn or not alive(self._panel) then
			return false
		end
		return _orig_forced_mouse_pressed(self, button, x, y)
	end
end

-- Guard mouse_clicked: inherited from MenuGuiComponentGeneric, accesses self._panel:child()
function CrimeSpreeForcedModifiersMenuComponent:mouse_clicked(o, button, x, y)
	if not alive(self._panel) then
		return false
	end
end

-- Guard close() against already-destroyed panels
local _orig_forced_close = CrimeSpreeForcedModifiersMenuComponent.close
function CrimeSpreeForcedModifiersMenuComponent:close()
	if not alive(self._panel) then
		return
	end
	return _orig_forced_close(self)
end

-- Hook on init - if no modifiers present, auto-close the popup
Hooks:PostHook(CrimeSpreeForcedModifiersMenuComponent, "init", "CSR_AutoCloseEmptyPopup", function(self)
	-- Check how many modifiers are in the list
	local modifiers = self._modifiers or {}

	if #modifiers == 0 then
		CSR_log("[CSR] CrimeSpreeForcedModifiersMenuComponent: 0 modifiers, auto-closing")
		-- Dismiss properly by popping the menu node (not just closing panels)
		-- self:close() only removes panels but leaves the node on the stack → softlock
		DelayedCalls:Add("csr_close_empty_forced_popup", 0.1, function()
			if managers.menu then
				managers.menu:back(true)
			end
		end)
	end
end)
