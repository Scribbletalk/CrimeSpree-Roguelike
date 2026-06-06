-- Dog Tags (common) — +10% max health per copy owned.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local HEALTH_BONUS = 0.10

_G.CSR.register_item({
	type = "dog_tags",
	rarity = "common",
	name = "csr_logbook_dog_tags_name",
	desc = "csr_item_dog_tags_desc",
	full_desc = "csr_logbook_dog_tags_effect",
	notes = "csr_logbook_dog_tags_notes",
	icon = "csr_dog_tags",
	icon_scale = 1.0,
	loc_macros = { pct = string.format("%g", HEALTH_BONUS * 100) },

	hooks = {
		["lib/managers/playermanager"] = function()
			if _G._CSR_DOG_TAGS_HOOKED then
				return
			end
			_G._CSR_DOG_TAGS_HOOKED = true
			local orig = PlayerManager.health_skill_multiplier
			if not orig then
				return
			end
			function PlayerManager:health_skill_multiplier()
				local v = orig(self)
				local mgr = managers.csr
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
					return v
				end
				return v + HEALTH_BONUS * mgr:owned("dog_tags")
			end
		end,
	},
})
