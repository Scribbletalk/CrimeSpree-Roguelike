-- Localization loader + mod language selection.
-- English is always loaded as the base layer, a translation is layered on top of it.

if not RequiredScript then
	return
end

-- SuperBLT repoints ModPath at every mod it loads, and apply() also runs long after boot
-- (Preferences row), so the path is captured here while it still points at CSR.
local MOD_PATH = ModPath

_G.CSR_Loc = _G.CSR_Loc or {}
local L = _G.CSR_Loc

-- Order = the order the Preferences row cycles through. `game` is the SystemInfo:language()
-- token "auto" matches against. Adding a language = one row here plus its loc/<name>.json.
L.LANGUAGES = {
	{ id = "auto", text_key = "csr_pref_language_auto" },
	{ id = "english", text_key = "csr_pref_language_english", file = "loc/english.json", game = "english" },
	{ id = "russian", text_key = "csr_pref_language_russian", file = "loc/russian.json", game = "russian" },
}
L.DEFAULT_ID = "english"
L.SETTING_KEY = "language"
L._listeners = L._listeners or {}

-- Called after every apply() with (effective_id, selected_id). For surfaces that build a widget
-- once and cannot rebuild it themselves, such as the Mod Options entry.
function L.add_listener(fn)
	table.insert(L._listeners, fn)
end

function L.by_id(id)
	for _, lang in ipairs(L.LANGUAGES) do
		if lang.id == id then
			return lang
		end
	end
	return nil
end

-- The stored choice, "auto" when unset or unknown. Runs during LocalizationManagerPostInit,
-- before managers.csr exists, so it falls back to the pre-init reader.
function L.selected_id()
	local mgr = managers and managers.csr
	local id = mgr and mgr.setting and mgr:setting(L.SETTING_KEY)
	if id == nil then
		local gm = rawget(_G, "CSRGameManager")
		if gm and gm.peek_setting then
			id = gm.peek_setting(L.SETTING_KEY)
		end
	end
	return L.by_id(id) and id or "auto"
end

-- Resolve "auto" against the game's own language; anything CSR has no file for falls to English.
function L.effective_id(selected)
	local id = selected or L.selected_id()
	if id ~= "auto" then
		return id
	end
	local key = SystemInfo and SystemInfo.language and SystemInfo:language():key()
	if key then
		for _, lang in ipairs(L.LANGUAGES) do
			if lang.game and Idstring(lang.game):key() == key then
				return lang.id
			end
		end
	end
	return L.DEFAULT_ID
end

-- English first: it is the complete key set, so a translation with gaps still resolves and
-- switching back restores every key. load_localization_file overwrites, so this doubles as
-- the live switch -- no restart needed.
function L.apply(loc)
	loc = loc or (managers and managers.localization)
	if not (loc and loc.load_localization_file) then
		return false
	end
	loc:load_localization_file(MOD_PATH .. "loc/english.json")
	local selected = L.selected_id()
	local id = L.effective_id(selected)
	local lang = L.by_id(id)
	if lang and lang.file and id ~= L.DEFAULT_ID then
		loc:load_localization_file(MOD_PATH .. lang.file)
	end

	-- Both language surfaces share this composed label: "LANGUAGE" plus the same word in the
	-- active language, which no single loc file can hold on its own. A file that omits the native
	-- word falls through to the English layer, so the two match and the suffix is dropped.
	local base = loc:text("csr_pref_language")
	local native = loc:text("csr_pref_language_native")
	loc:add_localized_strings({
		csr_pref_language_label = native ~= base and (base .. " (" .. native .. ")") or base,
	})

	for _, fn in ipairs(L._listeners) do
		fn(id, selected)
	end
	csr_log("[CSR LOC] language applied: " .. tostring(id) .. " (selected=" .. tostring(selected) .. ")")
	return true
end

Hooks:Add("LocalizationManagerPostInit", "CSR_Localization", function(loc)
	L.apply(loc)
end)

csr_log("[CSR LOC] localization.lua loaded")
