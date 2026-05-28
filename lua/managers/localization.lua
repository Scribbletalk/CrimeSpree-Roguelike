-- Localization loader + two runtime tweaks the static JSON can't express.

if not RequiredScript then
	return
end

Hooks:Add("LocalizationManagerPostInit", "CSR_Localization", function(loc)
	loc:load_localization_file(ModPath .. "loc/english.json")
end)

local original_text = LocalizationManager.text
function LocalizationManager:text(string_id, macros)
	local result = original_text(self, string_id, macros)
	if type(result) ~= "string" then
		return result
	end

	if string.find(result, "STARTING LEVEL") then
		result = string.gsub(result, "STARTING LEVEL:?", "STARTING DIFFICULTY:")
	end

	-- Bullseye: append a CSR rank-scaling note to the vanilla description.
	if string_id == "menu_prison_wife_beta_desc" then
		result = result .. "\n\nIn ##Crime Spree Roguelike##, armor regen scales with rank."
	end

	return result
end

csr_log("[CSR LOC] localization.lua loaded")
