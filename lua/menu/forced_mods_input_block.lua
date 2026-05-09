-- Crime Spree Roguelike - Block input behind forced mods popup
-- When the popup is open, prevent all clicks from reaching menu components
-- and route mouse events to the popup itself

if not RequiredScript then
	return
end

local function _popup_active()
	local inst = _G.CSR_ForcedModsNotificationInstance
	return inst and alive(inst._panel)
end

-- Use Hooks:OverrideFunction so other mods (or future internal code) can stack
-- their own hooks on these methods without being clobbered by a raw replacement.
-- The previous implementation captured the original function in a closure once
-- and returned it directly, which left this file at the bottom of any future
-- hook chain in a load-order-dependent way.
local _orig_mouse_pressed = Hooks:GetFunction(MenuComponentManager, "mouse_pressed")
	or MenuComponentManager.mouse_pressed

Hooks:OverrideFunction(MenuComponentManager, "mouse_pressed", function(self, o, button, x, y)
	if _popup_active() then
		local inst = _G.CSR_ForcedModsNotificationInstance
		inst:mouse_pressed(button, x, y)
		return true
	end
	return _orig_mouse_pressed(self, o, button, x, y)
end)

local _orig_mouse_clicked = Hooks:GetFunction(MenuComponentManager, "mouse_clicked")
	or MenuComponentManager.mouse_clicked

Hooks:OverrideFunction(MenuComponentManager, "mouse_clicked", function(self, o, button, x, y)
	if _popup_active() then
		return true
	end
	if _orig_mouse_clicked then
		return _orig_mouse_clicked(self, o, button, x, y)
	end
end)

local _orig_mouse_moved = Hooks:GetFunction(MenuComponentManager, "mouse_moved") or MenuComponentManager.mouse_moved

Hooks:OverrideFunction(MenuComponentManager, "mouse_moved", function(self, o, x, y)
	local inst = _G.CSR_ForcedModsNotificationInstance
	if inst then
		if alive(inst._panel) then
			local used, cursor = inst:mouse_moved(x, y)
			if cursor then
				managers.mouse_pointer:set_pointer_image(cursor)
			end
			return used, cursor or "arrow"
		else
			_G.CSR_ForcedModsNotificationInstance = nil
		end
	end
	return _orig_mouse_moved(self, o, x, y)
end)
