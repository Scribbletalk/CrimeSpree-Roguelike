-- Cup of Joe (common) — +10% max stamina per copy owned.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "cup_of_joe",
	rarity = "common",
	name = "csr_logbook_cup_of_joe_name",
	desc = "csr_item_cup_of_joe_desc",
	full_desc = "csr_logbook_cup_of_joe_effect",
	notes = "csr_logbook_cup_of_joe_notes",
	icon = "csr_cup_of_joe",
	icon_scale = 1.0,

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
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return v
				end
				return v + 0.10 * mgr:owned("cup_of_joe")
			end
		end,
	},
})
