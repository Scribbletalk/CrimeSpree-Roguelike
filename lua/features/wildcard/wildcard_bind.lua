-- In-game bind for the wildcard active, capturable from the CSR Preferences panel.
-- BLTKeybindsManager:update polls only Input:keyboard()/Input:mouse(), and vanilla's rebind screen
-- connects those same two devices, so a pad button can never reach either one -- CSR has to capture
-- the input itself. Both halves stick to calls vanilla actually makes:
--   pad      -- ControllerManager:_poll_reconnected_controller enumerates Input:num_controllers() and
--              reads a raw device with :pressed(<button index>), an integer, not a name.
--   keyboard -- MenuComponentManager:_setup_controller_input connects the keyboard to its FULLSCREEN
--              workspace and takes key events on that workspace's panel via key_press. The saferect
--              _ws never carries input in vanilla, and a capture hung on it receives nothing.
-- Mouse buttons are deliberately NOT capturable: the click that opens the capture window would
-- race with the click that closes it. Mouse binds stay available through the BLT keybinds menu.

if not RequiredScript then
	return
end

if _G.CSR_WILDCARD_BIND_LOADED then
	return
end
_G.CSR_WILDCARD_BIND_LOADED = true

local SETTING_KEY = "wildcard_bind"
local BLT_KEYBIND_ID = "csr_activate_wildcard"
-- Capture window; expiring keeps the previous binding.
local LISTEN_TIMEOUT = 5
-- The click that starts capture is itself an input event (on a pad, A replays a mouse click), so
-- ignore input briefly or the row would instantly bind whatever confirmed it.
local LISTEN_GUARD = 0.35
-- Input:controller() also hands out the keyboard and the mouse; everything else is a pad (PC builds
-- wrap xb1_controller and ps4_controller, create_virtual_pad names win32_game_controller).
-- "virtual" devices are the wrappers vanilla builds on top of the real ones, so a keyboard press
-- shows up on them too; capturing from one would bind a key as if it were a pad button.
local NON_PAD_TYPES = {
	win32_keyboard = true,
	win32_mouse = true,
	vr_controller = true,
	virtual = true,
}

-- Wrapper type whose glyph table names this device's buttons (LocalizationManager._input_translations).
local GLYPH_TYPES = {
	xb1_controller = "xb1",
	ps4_controller = "ps4",
}
local DEFAULT_GLYPH_TYPE = "xb1"

-- Vanilla maps all four d-pad directions onto one glyph, so the direction is spelled out next to it.
local DPAD_SUFFIX = {
	d_up = "D-PAD UP",
	d_down = "D-PAD DOWN",
	d_left = "D-PAD LEFT",
	d_right = "D-PAD RIGHT",
}

-- Not bindable: the menu buttons (Back/Start, Share/Options on a DualShock). PS names are listed
-- alongside the Xbox ones because a natively wrapped DualShock reports its own.
local BLOCKED_PAD_BUTTONS = {
	back = true,
	select = true,
	start = true,
}
-- Used only when a device refuses num_buttons(); pads sit far below this.
local PROBE_BUTTONS = 32

-- Pad buttons come back as an Idstring from button_name(), which cannot be turned back into text on
-- its own. These are the input names vanilla uses for a pad (LocalizationManager builds its button
-- macros from the same list); an unresolved button still binds, it just displays as its index.
local KNOWN_BUTTONS = {
	"a",
	"b",
	"x",
	"y",
	"back",
	"start",
	"select",
	"left",
	"right",
	"left_shoulder",
	"right_shoulder",
	"left_trigger",
	"right_trigger",
	"left_thumb",
	"right_thumb",
	"d_up",
	"d_down",
	"d_left",
	"d_right",
	"cross",
	"circle",
	"square",
	"triangle",
	"l1_trigger",
	"r1_trigger",
	"l2_trigger",
	"r2_trigger",
}

local function dbg(msg)
	local mgr = managers and managers.csr
	if mgr and mgr.debug_enabled and mgr:debug_enabled() then
		mgr:debug_log("[WildcardBind] " .. tostring(msg))
	end
end

-- Idstrings are rebuilt every frame otherwise; cache them like ControllerWrapper does.
local id_cache = {}

local function ids_for(name)
	local ids = id_cache[name]
	if not ids then
		ids = Idstring(name)
		id_cache[name] = ids
	end
	return ids
end

-- Device button values may come back as a string or an Idstring depending on the device; compare
-- both ways so nothing here depends on which.
local function same_button(device_value, ids)
	if device_value == ids then
		return true
	end
	if type(device_value) == "string" then
		return Idstring(device_value) == ids
	end
	return false
end

-- Vanilla gamepad connection map, or nil while the player is on keyboard/mouse (then the map holds
-- key names and comparing button names against it would be meaningless).
local function vanilla_gamepad_map()
	local cm = managers and managers.controller
	if not (cm and cm.get_default_wrapper_type and cm.get_settings) then
		return nil
	end
	local wrapper = cm:get_default_wrapper_type()
	if not wrapper or wrapper == "pc" or wrapper == "steam" or wrapper == "vr" then
		return nil
	end
	local ok, map = pcall(function()
		return cm:get_settings(wrapper):get_connection_map()
	end)
	return ok and map or nil
end

local function connection_input_names(connection)
	if not connection or not connection.get_input_name_list then
		return {}
	end
	local ok, list = pcall(connection.get_input_name_list, connection)
	return (ok and list) or {}
end

-- ============================================================
-- Pads
-- ============================================================

-- Rebuilt on demand: one entry per connected pad, with the button count to scan.
local pads = nil
local pads_failed = false

local function pad_list()
	if pads then
		return pads
	end
	if pads_failed then
		return {}
	end
	local found = {}
	local ok, err = pcall(function()
		local count = Input:num_controllers()
		dbg("scanning " .. tostring(count) .. " input device(s)")
		for i = 0, count - 1 do
			local device = Input:controller(i)
			local device_type = device and device:type()
			local connected = device and device:connected()
			if device and device_type and not NON_PAD_TYPES[device_type] and connected then
				local buttons = PROBE_BUTTONS
				local ok_count, reported = pcall(function()
					return device:num_buttons()
				end)
				if ok_count and type(reported) == "number" and reported > 0 then
					buttons = reported
				end
				table.insert(found, {
					device = device,
					buttons = buttons,
					glyph_type = GLYPH_TYPES[device_type] or DEFAULT_GLYPH_TYPE,
				})
				dbg("pad at " .. tostring(i) .. " type=" .. tostring(device_type) .. " buttons=" .. tostring(buttons))
			else
				dbg("skipped " .. i .. " " .. tostring(device_type) .. " conn=" .. tostring(connected))
			end
		end
	end)
	if not ok then
		pads_failed = true
		log("[CSR] wildcard pad bind disabled, device list unavailable: " .. tostring(err))
		return {}
	end
	pads = found
	return pads
end

-- :pressed(index) is the raw-device read ControllerManager:_poll_reconnected_controller makes. It is
-- pcall'd until it answers once -- the trigger path runs every frame and must not allocate.
local pressed_verified = false

local function device_pressed(device, index)
	if pressed_verified then
		return device:pressed(index) == true
	end
	local ok, res = pcall(function()
		return device:pressed(index)
	end)
	if not ok then
		dbg("pressed(" .. tostring(index) .. ") failed: " .. tostring(res))
		return false
	end
	pressed_verified = true
	return res == true
end

-- Plain-text name of button `index` on `device`, or nil when nothing resolves it.
local function button_text(device, index)
	local ok, value = pcall(function()
		return device:button_name(index)
	end)
	if not ok or value == nil then
		return nil
	end
	if type(value) == "string" then
		return value
	end
	local ok_str, text = pcall(function()
		return device:button_name_str(value)
	end)
	if ok_str and type(text) == "string" and text ~= "" then
		return text
	end
	for _, name in ipairs(KNOWN_BUTTONS) do
		if Idstring(name) == value then
			return name
		end
	end
	local map = vanilla_gamepad_map()
	if map then
		for _, connection in pairs(map) do
			for _, input_name in ipairs(connection_input_names(connection)) do
				if type(input_name) == "string" and Idstring(input_name) == value then
					return input_name
				end
			end
		end
	end
	return nil
end

CSR_WildcardBind = CSR_WildcardBind or {}
CSR_WildcardBind.SETTING_KEY = SETTING_KEY

-- Stored as { kind = "keyboard", name = "g" } or { kind = "gamepad", index = 3, name = "a" }: the pad
-- is polled by button index, the name is for display.
function CSR_WildcardBind.binding()
	local mgr = managers and managers.csr
	local value = mgr and mgr.setting and mgr:setting(SETTING_KEY)
	if type(value) == "table" and (value.name or value.index) then
		-- A bind saved before a button became reserved reads as unbound rather than firing.
		if value.kind == "gamepad" and value.name and BLOCKED_PAD_BUTTONS[value.name] then
			return nil
		end
		return value
	end
	return nil
end

-- Pad buttons draw as the private-use glyphs vanilla builds in LocalizationManager:_setup_macros
-- (utf8.char(57344+), carried by the same pd2 fonts this row uses). key_to_btn_text falls back to
-- "[name]" for an input its table doesn't know; that is worse than our own spelled-out name.
local function pad_glyph(bind)
	local loc = managers and managers.localization
	if not (loc and loc.key_to_btn_text) then
		return nil
	end
	local ok, text = pcall(function()
		return loc:key_to_btn_text(bind.name, false, bind.pad or DEFAULT_GLYPH_TYPE)
	end)
	if not ok or type(text) ~= "string" or text == "" or text:sub(1, 1) == "[" then
		return nil
	end
	return text
end

-- Display label: a button glyph for a pad, the input name in caps otherwise, or a numbered fallback.
function CSR_WildcardBind.label(bind)
	if not bind then
		return nil
	end
	if bind.kind == "gamepad" and bind.name then
		local glyph = pad_glyph(bind)
		if glyph then
			local suffix = DPAD_SUFFIX[bind.name]
			return suffix and (glyph .. " " .. suffix) or glyph
		end
	end
	if bind.name then
		return utf8.to_upper((bind.name:gsub("_", " ")))
	end
	if bind.index then
		return "BUTTON " .. tostring(bind.index)
	end
	return nil
end

-- Split for the bind row: the pad glyph, which the row draws on its own so it can be sized up, and
-- the plain text beside it (a d-pad direction, or the whole label when there is no glyph).
function CSR_WildcardBind.display(bind)
	if bind and bind.kind == "gamepad" and bind.name then
		local glyph = pad_glyph(bind)
		if glyph then
			return glyph, DPAD_SUFFIX[bind.name]
		end
	end
	return nil, CSR_WildcardBind.label(bind)
end

-- ============================================================
-- Capture
-- ============================================================

local listen = nil

function CSR_WildcardBind.listening()
	return listen ~= nil
end

-- Keyboard capture borrows MenuComponentManager's fullscreen workspace, the one vanilla itself
-- connects the keyboard to. MCM parks key_press_controller_support on that panel while a pad is
-- connected, so the callback is put back on the way out instead of being left cleared.
local keyboard_hooked = false

local function keyboard_capture_start()
	local mcm = managers and managers.menu_component
	local ws = mcm and mcm._fullscreen_ws
	if not ws then
		dbg("no fullscreen workspace, keyboard capture unavailable")
		return
	end
	local ok, err = pcall(function()
		ws:connect_keyboard(Input:keyboard())
		ws:panel():key_press(function(_, key)
			if listen then
				listen.key = key
			end
		end)
	end)
	if ok then
		keyboard_hooked = true
		dbg("keyboard capture armed")
	else
		dbg("keyboard capture failed: " .. tostring(err))
	end
end

local function keyboard_capture_stop()
	if not keyboard_hooked then
		return
	end
	keyboard_hooked = false
	local mcm = managers and managers.menu_component
	local ws = mcm and mcm._fullscreen_ws
	if not ws then
		return
	end
	pcall(function()
		if alive(ws:panel()) then
			if mcm._controller_connected and IS_PC then
				ws:panel():key_press(callback(mcm, mcm, "key_press_controller_support"))
			else
				ws:panel():key_press(nil)
			end
		end
		-- Only hand the keyboard back when MCM was not the one holding it.
		if not (mcm._controller_connected and IS_PC) then
			ws:disconnect_keyboard()
		end
	end)
end

-- callback(bind_or_nil): fires once, with nil when the window expired or was cancelled.
function CSR_WildcardBind.begin_listen(callback_fn)
	listen = { elapsed = 0, callback = callback_fn, key = nil }
	-- Rescan so a pad connected since the last capture is included.
	pads = nil
	pad_list()
	keyboard_capture_start()
	dbg("listening for an input")
end

function CSR_WildcardBind.cancel_listen()
	local entry = listen
	listen = nil
	keyboard_capture_stop()
	if entry and entry.callback then
		entry.callback(nil)
	end
end

local ESC = Idstring("esc")

-- The key the workspace reported this frame, as a bind table, or "cancel" for esc.
local function captured_key()
	local key = listen and listen.key
	if not key then
		return nil
	end
	listen.key = nil
	if same_button(key, ESC) then
		return "cancel"
	end
	local ok, name = pcall(function()
		return Input:keyboard():button_name_str(key)
	end)
	if not ok or type(name) ~= "string" or name == "" then
		dbg("key with no resolvable name ignored")
		return nil
	end
	return { kind = "keyboard", name = name }
end

-- First pad button held this frame, as a bind table.
local function captured_button()
	for _, pad in ipairs(pad_list()) do
		for index = 0, pad.buttons - 1 do
			if device_pressed(pad.device, index) then
				local name = button_text(pad.device, index)
				if name and BLOCKED_PAD_BUTTONS[name] then
					dbg("reserved button ignored: " .. name)
				else
					return {
						kind = "gamepad",
						index = index,
						name = name,
						pad = pad.glyph_type,
					}
				end
			end
		end
	end
	return nil
end

local function update_listen(_, dt)
	if not listen then
		return
	end
	listen.elapsed = listen.elapsed + (dt or 0)
	if listen.elapsed < LISTEN_GUARD then
		listen.key = nil
		return
	end
	if listen.elapsed > LISTEN_TIMEOUT then
		dbg("capture window expired")
		CSR_WildcardBind.cancel_listen()
		return
	end

	local bind = captured_key() or captured_button()
	if not bind then
		return
	end
	if bind == "cancel" then
		dbg("capture cancelled with esc")
		CSR_WildcardBind.cancel_listen()
		return
	end

	local entry = listen
	listen = nil
	keyboard_capture_stop()
	local mgr = managers and managers.csr
	if mgr and mgr.set_setting then
		mgr:set_setting(SETTING_KEY, bind)
	end
	dbg("bound to " .. tostring(bind.kind) .. " " .. tostring(bind.name or bind.index))
	if entry.callback then
		entry.callback(bind)
	end
end

-- ============================================================
-- In-heist trigger
-- ============================================================

-- :pressed() is already an edge on both device kinds, so no held-state bookkeeping is needed.
local function bind_pressed(bind)
	if bind.kind == "keyboard" then
		if not bind.name then
			return false
		end
		return Input:keyboard():pressed(ids_for(bind.name)) == true
	end
	if not bind.index then
		return false
	end
	for _, pad in ipairs(pad_list()) do
		if bind.index < pad.buttons and device_pressed(pad.device, bind.index) then
			return true
		end
	end
	return false
end

-- The BLT keybind polls keyboard and mouse on its own; when it holds the same key, let it fire so
-- one press does not reach the dispatcher twice.
local function blt_covers(bind)
	if bind.kind ~= "keyboard" or not bind.name then
		return false
	end
	local keybinds = _G.BLT and BLT.Keybinds
	local keybind = keybinds and keybinds.get_keybind and keybinds:get_keybind(BLT_KEYBIND_ID)
	local key = keybind and keybind.Key and keybind:Key()
	return type(key) == "string" and key == bind.name
end

if Hooks then
	Hooks:Add("GameSetupUpdate", "CSR_WildcardBind_Update", function(t, dt)
		update_listen(t, dt)
		if listen or not _G.CSR_TriggerWildcard then
			return
		end
		-- A menu (pause, and its Preferences panel) owns input while open; so does chat.
		if managers.menu and managers.menu:active_menu() then
			return
		end
		if managers.hud and managers.hud.chat_focus and managers.hud:chat_focus() then
			return
		end
		local bind = CSR_WildcardBind.binding()
		if bind and not blt_covers(bind) and bind_pressed(bind) then
			CSR_TriggerWildcard()
		end
	end)

	-- Capture only: these states never fire the active (menu, or in-heist while paused in SP).
	Hooks:Add("MenuUpdate", "CSR_WildcardBind_MenuUpdate", function(t, dt)
		update_listen(t, dt)
	end)
	Hooks:Add("GameSetupPausedUpdate", "CSR_WildcardBind_PausedUpdate", function(t, dt)
		update_listen(t, dt)
	end)
end
