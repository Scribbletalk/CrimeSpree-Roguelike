-- CUP OF JOE - +10% max stamina per stack, additive linear
-- Hook on PlayerManager:stamina_multiplier lives in lua/managers/playermanager.lua
-- alongside the Dog Tags health hook (managers cannot be reliably overridden from a
-- crimespreetweakdata-hooked file because PlayerManager loads later).

if not RequiredScript then
	return
end

ModifierCupOfJoe = ModifierCupOfJoe or class(CSRBaseModifier)
ModifierCupOfJoe.desc_id = "csr_cup_of_joe_desc"
