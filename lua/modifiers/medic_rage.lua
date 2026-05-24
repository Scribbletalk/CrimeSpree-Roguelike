-- Overdose (loud modifier) -- a Medic gains +20% base damage per cop that dies
-- within its healing range (stacks indefinitely).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "medic_rage",
	category = "loud",
	loc = "menu_cs_modifier_medic_rage",
	icon = "crime_spree_medic_rage",
	class = "ModifierMedicRage",
	data = { damage = { 20, "add" } },
})
