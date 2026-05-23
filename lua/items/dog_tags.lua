-- Dog Tags (common) -- +10% max health per copy owned.
--
-- Per-item-file model (see cup_of_joe.lua for the full pattern notes). Text
-- fields are localization keys; loc/<lang>.json holds the strings.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

_G.CSR.register_item({
	type = "dog_tags",
	rarity = "common",
	name = "logbook_dog_tags_name",
	desc = "item_dog_tags_desc",
	full_desc = "logbook_dog_tags_effect",
	notes = "logbook_dog_tags_notes",
	icon = "dog_tags",

	hooks = {
		-- +10% to PlayerManager:health_skill_multiplier per copy owned. Return-value
		-- method -> raw chain wrap (CSR convention); _G guard stops a double-wrap.
		-- Mirrors the 6.2 constant dog_tags_hp_bonus (0.10).
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
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return v
				end
				return v + 0.10 * mgr:owned("dog_tags")
			end
		end,
	},
})
