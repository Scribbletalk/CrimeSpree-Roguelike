-- Crime Spree Roguelike - Less Concealment Modifier
-- Reduces concealment by +3 each tier (max 72 total = 24 tiers)

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

CSR_log("[CSR LessConcealment] File loading")

-- Create our class, inheriting from the vanilla one
-- Description and Total are handled in localization.lua
ModifierCSRLessConcealment = ModifierCSRLessConcealment or class(ModifierLessConcealment)
ModifierCSRLessConcealment.desc_id = "menu_cs_modifier_less_concealment"

CSR_log("[CSR LessConcealment] ModifierCSRLessConcealment created")
