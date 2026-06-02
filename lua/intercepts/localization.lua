-- Localization loader.

if not RequiredScript then
	return
end

Hooks:Add("LocalizationManagerPostInit", "CSR_Localization", function(loc)
	loc:load_localization_file(ModPath .. "loc/english.json")
end)

csr_log("[CSR LOC] localization.lua loaded")
