-- Crime Spree Roguelike - Localization loader
-- U1: ALL static strings (items, logbook names/effects/notes, modifiers, UI labels,
-- vanilla overrides) live in loc/english.json, loaded here. Everything the
-- pre-refactor monolith generated at runtime -- item-copy keys (CSR_ITEM_REGISTRY),
-- balance-number interpolation (CSR_ItemConstants), forced-modifier full-ids,
-- next-modifier glyph labels, per-UI "Total" appends (CSR_FilterForUI) -- is dead in
-- U1 (those globals are never assigned, and the vanilla CS modifier UI CSR borrows
-- reads its own unpopulated manager) and has been removed. The only remaining
-- dynamic bits are the two text() tweaks below.

if not RequiredScript then
	return
end

Hooks:Add("LocalizationManagerPostInit", "CSR_Localization", function(loc)
	loc:load_localization_file(ModPath .. "loc/english.json")
end)

-- Hook text() for two runtime tweaks the static JSON can't express.
local original_text = LocalizationManager.text
function LocalizationManager:text(string_id, macros)
	local result = original_text(self, string_id, macros)
	if type(result) ~= "string" then
		return result
	end

	-- Rename vanilla "STARTING LEVEL" -> "STARTING DIFFICULTY" wherever it appears.
	if string.find(result, "STARTING LEVEL") then
		result = string.gsub(result, "STARTING LEVEL:?", "STARTING DIFFICULTY:")
	end

	-- Bullseye (Headshot Armor Regen, vanilla key menu_prison_wife_beta_desc):
	-- append a CSR rank-scaling note.
	if string_id == "menu_prison_wife_beta_desc" then
		result = result .. "\n\nIn ##Crime Spree Roguelike##, armor regen scales with rank."
	end

	return result
end

csr_log("[CSR LOC] localization.lua loaded")
