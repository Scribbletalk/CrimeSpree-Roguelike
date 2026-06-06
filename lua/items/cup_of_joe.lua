-- Cup of Joe (common) — +10% max stamina per copy owned.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

-- Tuning -- single source: feeds both the stamina hook and the $-macros in the localized effect text.
local STAMINA_PER = 0.10

_G.CSR.register_item({
	type = "cup_of_joe",
	rarity = "common",
	name = "csr_logbook_cup_of_joe_name",
	desc = "csr_item_cup_of_joe_desc",
	full_desc = "csr_logbook_cup_of_joe_effect",
	notes = "csr_logbook_cup_of_joe_notes",
	icon = "csr_cup_of_joe",
	icon_scale = 1.0,

	-- $stamina_pct fills csr_logbook_cup_of_joe_effect.
	loc_macros = { stamina_pct = string.format("%g", STAMINA_PER * 100) },

	hooks = {
		["lib/managers/playermanager"] = function()
			if _G._CSR_CUP_OF_JOE_HOOKED then
				return
			end
			_G._CSR_CUP_OF_JOE_HOOKED = true
			local orig = PlayerManager.stamina_multiplier
			function PlayerManager:stamina_multiplier()
				local v = orig(self)
				local mgr = managers.csr
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
					return v
				end
				return v + STAMINA_PER * mgr:owned("cup_of_joe")
			end
		end,
	},
})
