-- Crime Spree Roguelike - Less Concealment Modifier
-- Reduces concealment by +3 each tier (max 72 total = 24 tiers)

if not RequiredScript then
	return
end

log("[CSR LessConcealment] File loading")

-- Create our class, inheriting from the vanilla one
-- Description and Total are handled in localization.lua
ModifierCSRLessConcealment = ModifierCSRLessConcealment or class(ModifierLessConcealment)
ModifierCSRLessConcealment.desc_id = "menu_cs_modifier_less_concealment"

log("[CSR LessConcealment] ModifierCSRLessConcealment created")
