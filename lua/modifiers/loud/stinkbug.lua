-- Stinkbug (loud modifier) -- killed Cloakers leave behind a toxic cloud.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

-- Cloud damage = this fraction of the LOCAL player's max health per tick (1s).
-- TearGasGrenade is spawned ONLY by ModifierCloakerTearGas, so overriding its
-- update is exclusive to Stinkbug. data.damage below is now just the placeholder
-- the vanilla OnEnemyDied needs (value("damage")*0.1); the wrapper supersedes it.
local STINKBUG_HEALTH_PCT = 0.10

_G.CSR.register_modifier({
	id = "cloaker_tear_gas",
	category = "loud",
	loc = "menu_cs_modifier_cloaker_tear_gas",
	icon = "crime_spree_cloaker_tear_gas",
	class = "ModifierCloakerTearGas",
	data = { diameter = { 4, "none" }, damage = { 30, "none" }, duration = { 10, "none" } },

	hooks = {
		-- Each client runs update vs its OWN player_unit, so % scales per-player -> MP-safe.
		["lib/units/weapons/grenades/teargasgrenade"] = function()
			if not TearGasGrenade then
				return
			end
			local orig_update = TearGasGrenade.update
			function TearGasGrenade:update(unit, t, dt)
				if self._damage_t and self._damage_t < t then
					local player = managers.player:player_unit()
					local cdmg = player and player:character_damage()
					if cdmg and cdmg._max_health then
						local saved = self.damage
						self.damage = cdmg:_max_health() * STINKBUG_HEALTH_PCT
						orig_update(self, unit, t, dt)
						self.damage = saved
						return
					end
				end
				return orig_update(self, unit, t, dt)
			end
		end,
	},
})
