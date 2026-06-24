-- Item crash handler: pcall-wraps every item/modifier hook so a bug shows as
-- a chat message + disable instead of a session crash. See csr_extension_api_deep_dive.md.
-- Loaded before extension_api (lib/entry); re-runs on lib/setups/setup to reset per-heist.

if not Hooks then
	return
end

-- Reassigning these tables here clears them each heist (wrappers read by global name).
_G.CSR_ItemErrors = {}
_G.CSR_DisabledItems = {}

-- Patch Hooks only once; helpers also defined here.
if _G.CSR_ItemCrashHandlerInstalled then
	return
end
_G.CSR_ItemCrashHandlerInstalled = true

local MAX_ERRORS = 3
local CHAT_COOLDOWN = 5 -- seconds between chat messages per item
local _last_chat = {}

-- Lazily resolved from registry on first error; falls back to owner id.
local _name_cache = {}

local function find_def(owner)
	local C = _G.CSR
	if not C then
		return nil
	end
	for _, def in ipairs(C._registrations or {}) do
		if def.type == owner then
			return def
		end
	end
	for _, def in ipairs(C._modifier_registrations or {}) do
		if def.id == owner then
			return def
		end
	end
	return nil
end

local function resolve_name(owner)
	if _name_cache[owner] then
		return _name_cache[owner]
	end
	local name = tostring(owner)
	local def = find_def(owner)
	local key = def and (def.name or def.loc)
	if key and managers and managers.localization then
		local ok, txt = pcall(function()
			return managers.localization:text(key)
		end)
		-- :text() returns "ERROR:..." for unknown keys - skip those.
		if ok and type(txt) == "string" and txt ~= "" and txt:sub(1, 5) ~= "ERROR" then
			name = txt
		end
	end
	_name_cache[owner] = name
	return name
end

-- Log + rate-limited chat + disable after MAX_ERRORS.
local function report_error(owner, where, err)
	local err_str = tostring(err)
	local item_name = resolve_name(owner)

	_G.CSR_ItemErrors[owner] = (_G.CSR_ItemErrors[owner] or 0) + 1
	local count = _G.CSR_ItemErrors[owner]

	log("[CSR][ItemCrash] " .. item_name .. " (" .. tostring(where) .. "): " .. err_str)

	if count >= MAX_ERRORS then
		_G.CSR_DisabledItems[owner] = true
		log("[CSR][ItemCrash] " .. item_name .. " DISABLED after " .. count .. " errors")
	end

	local now = os.clock()
	if _last_chat[owner] and (now - _last_chat[owner]) < CHAT_COOLDOWN then
		return
	end
	_last_chat[owner] = now

	-- Delay so the chat manager is ready.
	DelayedCalls:Add("CSR_ItemErr_" .. tostring(owner) .. "_" .. count, 0.1, function()
		if managers and managers.chat then
			local msg = item_name .. ": " .. err_str
			if _G.CSR_DisabledItems[owner] then
				msg = msg .. " [DISABLED]"
			end
			local color = (tweak_data and tweak_data.system_chat_color) or Color(1, 0.3, 0.3)
			managers.chat:_receive_message(1, "[CSR]", msg, color)
		end
	end)
end

_G.CSR_ReportItemError = report_error

-- Set by extension_api:_install_hook for the duration of an installer fn.
local function current_owner()
	return _G.CSR and _G.CSR._installing_owner or nil
end

-- =========================================================
-- PATCH Hooks:PostHook / PreHook / Add
-- =========================================================
local _orig_PostHook = Hooks.PostHook
function Hooks:PostHook(class, func_name, hook_id, callback)
	local owner = current_owner()
	if owner then
		local orig_cb = callback
		callback = function(s, ...)
			if _G.CSR_DisabledItems[owner] then
				return
			end
			local ok, err = pcall(orig_cb, s, ...)
			if not ok then
				report_error(owner, hook_id, err)
			end
		end
	end
	return _orig_PostHook(self, class, func_name, hook_id, callback)
end

-- PreHook preserves the return value so blocking hooks (e.g. returning false to cancel vanilla) still work.
local _orig_PreHook = Hooks.PreHook
function Hooks:PreHook(class, func_name, hook_id, callback)
	local owner = current_owner()
	if owner then
		local orig_cb = callback
		callback = function(s, ...)
			if _G.CSR_DisabledItems[owner] then
				return
			end
			local ok, result = pcall(orig_cb, s, ...)
			if not ok then
				report_error(owner, hook_id, result)
				return -- don't interfere with vanilla on error
			end
			return result
		end
	end
	return _orig_PreHook(self, class, func_name, hook_id, callback)
end

-- Event hooks: callback is (...) not (self, ...).
local _orig_Add = Hooks.Add
function Hooks:Add(key, hook_id, callback)
	local owner = current_owner()
	if owner then
		local orig_cb = callback
		callback = function(...)
			if _G.CSR_DisabledItems[owner] then
				return
			end
			local ok, err = pcall(orig_cb, ...)
			if not ok then
				report_error(owner, hook_id, err)
			end
		end
	end
	return _orig_Add(self, key, hook_id, callback)
end

-- =========================================================
-- CSR_SafeOverride: opt-in guard for raw overrides where Hooks:PostHook can't be used.
-- Falls back to original on error.
-- =========================================================
function _G.CSR_SafeOverride(class, method, owner, original_fn, new_fn)
	class[method] = function(self, ...)
		if _G.CSR_DisabledItems[owner] then
			return original_fn(self, ...)
		end
		local results = { pcall(new_fn, self, ...) }
		if results[1] then
			return select(2, unpack(results))
		end
		report_error(owner, method, results[2])
		return original_fn(self, ...)
	end
end

csr_log("[CSR] Item crash handler installed")
