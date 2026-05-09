-- Crime Spree Roguelike - Item Crash Handler
-- Auto-wraps all CSR_ hooks in pcall to prevent game crashes from item bugs.
-- On error: logs to file, shows in chat which item failed, disables after 3 errors.
-- Also provides CSR_SafeOverride() for wrapping direct function overrides.
--
-- Loaded as the FIRST pre_hook (lib/entry) so it patches Hooks before any items register.
-- Only wraps hooks whose ID matches a known CSR_ prefix — other mods are unaffected.

if _G.CSR_ItemCrashHandlerInstalled then
	return
end
_G.CSR_ItemCrashHandlerInstalled = true

_G.CSR_ItemErrors = {}
_G.CSR_DisabledItems = {}

local MAX_ERRORS = 3
local CHAT_COOLDOWN = 5 -- seconds between chat messages per item
local _last_chat = {}

-- Hook ID prefix -> human-readable item/mechanic name
local ITEM_NAMES = {
	-- Player items
	CSR_BonnieChip = "Bonnie's Lucky Chip",
	CSR_PinkSlip = "Pink Slip",
	CSR_OverkillRush = "Overkill Rush",
	CSR_ViklundVinyl = "Viklund Vinyl",
	CSR_TheEdge = "The Edge",
	CSR_DearestPossession = "Dearest Possession",
	CSR_DMT = "Dead Man's Trigger",
	CSR_PlushShark = "Plush Shark",
	CSR_Rebar = "Piece of Rebar",
	CSR_Equalizer = "Equalizer",
	CSR_JiroLastWish = "Jiro's Last Wish",
	CSR_CrookedBadge = "Crooked Badge",
	CSR_HalfAGlass = "Half-a-Glass",
	CSR_WolfsToolbox = "Wolf's Toolbox",
	-- Passive progression
	CSR_HealthRegen = "Passive Progression",
	CSR_InitHealthRegen = "Passive Progression",
	CSR_TrackDamage = "Passive Progression",
	-- Bot scaling
	CSR_BotWeaponMark = "Bot Damage",
	CSR_BotHPPassive = "Bot HP",
	CSR_BotFireReload = "Bot Fire Rate",
	-- Forced modifiers
	CSR_ShockingSurprise = "Shocking Surprise",
	CSR_PhalanxKnock = "Shock and Awe",
	CSR_RemoveDamageCap = "Damage Cap",
	-- Damage system
	CSR_PoisonGasDamage = "Poison Gas",
	CSR_ExplosiveDamage = "Explosive Damage",
	CSR_MeleeDamage = "Melee Damage",
	CSR_IncreaseEnemyHealth = "Enemy HP",
	CSR_RestoreHealthInit = "HP Scaling",
	CSR_Bullseye = "Bullseye",
	-- Mechanics
	CSR_CivilianKill = "Guilty Conscience",
	CSR_SnapshotCash = "Bonus Item Drop",
	CSR_BonusDrop = "Bonus Item Drop",
	CSR_DiamondBileStay = "Diamond Bile Stay",
	CSR_RefreshHUD = "HUD Refresh",
	CSR_UpdateArmorHP = "HUD Refresh",
	CSR_TimelineFix = "Timeline Fix",
	CSR_ApplyBuffs = "Buff Application",
	CSR_ReapplyHP = "HP Scaling",
	CSR_SuppressSuspended = "Assault Extender",
}

-- Match hook_id against known prefixes, return item name or nil
local function get_item_name(hook_id)
	if type(hook_id) ~= "string" then
		return nil
	end
	for prefix, name in pairs(ITEM_NAMES) do
		if hook_id:sub(1, #prefix) == prefix then
			return name
		end
	end
	return nil
end

-- Report an item error: log + chat message + disable after threshold
local function report_error(item_name, hook_id, err)
	local err_str = tostring(err)
	_G.CSR_ItemErrors[item_name] = (_G.CSR_ItemErrors[item_name] or 0) + 1
	local count = _G.CSR_ItemErrors[item_name]

	log("[CSR][ItemCrash] " .. item_name .. " (" .. tostring(hook_id) .. "): " .. err_str)

	if count >= MAX_ERRORS then
		_G.CSR_DisabledItems[item_name] = true
		log("[CSR][ItemCrash] " .. item_name .. " DISABLED after " .. count .. " errors")
	end

	-- Rate-limit chat messages to avoid spam
	local now = os.clock()
	if _last_chat[item_name] and (now - _last_chat[item_name]) < CHAT_COOLDOWN then
		return
	end
	_last_chat[item_name] = now

	-- Show in chat (delayed to ensure chat manager is available)
	local safe_name = item_name:gsub("%s", "")
	DelayedCalls:Add("CSR_ItemErr_" .. safe_name .. "_" .. count, 0.1, function()
		if managers and managers.chat then
			local msg = item_name .. ": " .. err_str
			if _G.CSR_DisabledItems[item_name] then
				msg = msg .. " [DISABLED]"
			end
			local color = tweak_data and tweak_data.system_chat_color or Color(1, 0.3, 0.3)
			managers.chat:_receive_message(1, "[CSR]", msg, color)
		end
	end)
end

-- =========================================================
-- PATCH Hooks:PostHook — auto-wrap CSR_ callbacks in pcall
-- =========================================================
local _orig_PostHook = Hooks.PostHook

function Hooks:PostHook(class, func_name, hook_id, callback)
	local item_name = get_item_name(hook_id)
	if item_name then
		local orig_cb = callback
		callback = function(self, ...)
			if _G.CSR_DisabledItems[item_name] then
				return
			end
			local ok, err = pcall(orig_cb, self, ...)
			if not ok then
				report_error(item_name, hook_id, err)
			end
		end
	end
	return _orig_PostHook(self, class, func_name, hook_id, callback)
end

-- =========================================================
-- PATCH Hooks:PreHook — preserves return value for blocking
-- hooks (e.g. The Edge / Plush Shark returning false)
-- =========================================================
local _orig_PreHook = Hooks.PreHook

function Hooks:PreHook(class, func_name, hook_id, callback)
	local item_name = get_item_name(hook_id)
	if item_name then
		local orig_cb = callback
		callback = function(self, ...)
			if _G.CSR_DisabledItems[item_name] then
				return
			end
			local ok, result = pcall(orig_cb, self, ...)
			if not ok then
				report_error(item_name, hook_id, result)
				return -- don't interfere with vanilla on error
			end
			return result
		end
	end
	return _orig_PreHook(self, class, func_name, hook_id, callback)
end

-- =========================================================
-- PATCH Hooks:Add — for event hooks (NetworkReceivedData etc.)
-- Callback signature is (sender, id, data), NOT (self, ...)
-- =========================================================
local _orig_Add = Hooks.Add

function Hooks:Add(key, hook_id, callback)
	local item_name = type(hook_id) == "string" and get_item_name(hook_id) or nil
	if item_name then
		local orig_cb = callback
		callback = function(...)
			if _G.CSR_DisabledItems[item_name] then
				return
			end
			local ok, err = pcall(orig_cb, ...)
			if not ok then
				report_error(item_name, hook_id, err)
			end
		end
	end
	return _orig_Add(self, key, hook_id, callback)
end

-- =========================================================
-- CSR_SafeOverride: wrap direct function overrides in pcall
-- Falls back to original function on error.
-- Usage:
--   local orig = Class.method
--   CSR_SafeOverride(Class, "method", "Item Name", orig, function(self, ...)
--       ... new logic that may call orig internally ...
--   end)
-- =========================================================
function _G.CSR_SafeOverride(class, method, item_name, original_fn, new_fn)
	class[method] = function(self, ...)
		if _G.CSR_DisabledItems[item_name] then
			return original_fn(self, ...)
		end
		local results = { pcall(new_fn, self, ...) }
		if results[1] then
			return select(2, unpack(results))
		else
			report_error(item_name, method, results[2])
			return original_fn(self, ...)
		end
	end
end

local _prefix_count = 0
for _ in pairs(ITEM_NAMES) do
	_prefix_count = _prefix_count + 1
end
log("[CSR] Item crash handler installed — " .. _prefix_count .. " item prefixes registered")
