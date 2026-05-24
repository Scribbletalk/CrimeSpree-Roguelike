-- Guilty Conscience (loud modifier) -- killing civilians permanently lowers your
-- max health for the mission.
--
-- ModifierCivilianGuilt is a CSR-CUSTOM class NOT present in the engine (the
-- pre-refactor mod defined it; not ported to U1 yet). apply_combat_modifiers
-- nil-guards _G[class] and skips the effect, so this passport is display-only
-- for now -- it still shows in the Modifiers panel. Port the class to wire it.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "civilian_guilt",
	category = "loud",
	loc = "menu_cs_modifier_civilian_guilt",
	icon = "csr_guilty_conscience",
	class = "ModifierCivilianGuilt",
	data = {},
})
