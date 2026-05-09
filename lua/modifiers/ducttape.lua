-- DUCT TAPE - Interaction speed boost item
-- +10% interaction speed per stack, additive with crew bonus "Quick".
-- Does NOT apply to reviving downed teammates or uncuffing.

if not RequiredScript then
	return
end

local required = string.lower(RequiredScript)

-- Track the tweak_data id of the interaction currently computing its timer,
-- so the crew_ability_upgrade_value override in playermanager.lua can skip
-- revive/free interactions.
_G.CSR_CurrentInteractionTweak = _G.CSR_CurrentInteractionTweak or nil

if required == "lib/units/interactions/interactionext" then
	Hooks:PreHook(BaseInteractionExt, "_get_timer", "CSR_DuctTape_TrackInteraction", function(self)
		_G.CSR_CurrentInteractionTweak = self.tweak_data
	end)
	Hooks:PostHook(BaseInteractionExt, "_get_timer", "CSR_DuctTape_ClearInteraction", function(self)
		_G.CSR_CurrentInteractionTweak = nil
	end)
elseif required == "lib/tweak_data/crimespreetweakdata" then
	ModifierDuctTape = ModifierDuctTape or class(CSRBaseModifier)
	ModifierDuctTape.desc_id = "menu_cs_modifier_duct_tape"
end
