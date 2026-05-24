-- Shocking Surprise (loud modifier) -- Tasers release an electric burst on death,
-- slowing nearby players and blocking sprint briefly.
--
-- ModifierShockingSurprise is a CSR-CUSTOM class NOT present in the engine (see
-- civilian_guilt.lua): display-only until the class is ported. apply_combat_
-- modifiers nil-guards _G[class] and skips the effect.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "shocking_surprise",
	category = "loud",
	loc = "menu_cs_modifier_shocking_surprise",
	icon = "csr_shocking_surprise",
	class = "ModifierShockingSurprise",
	data = {},
})
