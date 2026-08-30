-- Overdose (loud modifier) -- a Medic gains +N% base damage per cop that dies
-- within its healing range (stacks indefinitely).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local DAMAGE_PER_KILL = 20

_G.CSR.register_modifier({
	id = "medic_rage",
	category = "loud",
	loc = "csr_modifier_medic_rage",
	loc_macros = { pct = DAMAGE_PER_KILL },
	icon = "crime_spree_medic_rage",
	class = "ModifierMedicRage",
	data = { damage = { DAMAGE_PER_KILL, "add" } },
})
