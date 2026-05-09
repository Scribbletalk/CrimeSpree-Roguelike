-- Crime Spree Roguelike - Bot fire rate + reload speed passive progression
-- PostHooks CharacterTweakData:init to scale team AI weapon presets with CS rank.
-- Fire rate: reduces FALLOFF.recoil values (lower = faster shooting)
-- Reload speed: increases RELOAD_SPEED (higher = faster reload animation)
-- Both capped at bot_fire_reload_max_bonus (default 50%).

if not RequiredScript then
	return
end

Hooks:PostHook(CharacterTweakData, "init", "CSR_BotFireReload", function(self)
	-- CS state is already in Global when tweakdata loads (persisted between sessions)
	local cs = Global.crime_spree
	if not cs or not cs.in_progress then
		return
	end

	local spree_level = cs.spree_level or 0
	if spree_level <= 0 then
		return
	end

	local C = _G.CSR_ItemConstants or {}
	local fire_per_level = C.bot_fire_rate_per_level or 0.005
	local reload_per_level = C.bot_reload_per_level or 0.005
	local max_bonus = C.bot_fire_reload_max_bonus or 0.50

	local fire_bonus = math.min(fire_per_level * spree_level, max_bonus)
	local reload_bonus = math.min(reload_per_level * spree_level, max_bonus)

	-- Lower recoil = faster shooting, higher RELOAD_SPEED = faster reload
	local recoil_mult = 1 - fire_bonus
	local reload_mult = 1 + reload_bonus

	local gm = self.presets and self.presets.weapon and self.presets.weapon.gang_member
	if not gm then
		return
	end

	-- Track visited tables to avoid double-applying on shared references
	-- (e.g. is_smg = is_rifle means both point to the same table)
	local visited = {}

	for _, weapon_data in pairs(gm) do
		if type(weapon_data) == "table" and not visited[weapon_data] then
			visited[weapon_data] = true

			if weapon_data.RELOAD_SPEED then
				weapon_data.RELOAD_SPEED = weapon_data.RELOAD_SPEED * reload_mult
			end

			if weapon_data.FALLOFF then
				for _, falloff in ipairs(weapon_data.FALLOFF) do
					if falloff.recoil then
						falloff.recoil[1] = falloff.recoil[1] * recoil_mult
						falloff.recoil[2] = falloff.recoil[2] * recoil_mult
					end
				end
			end
		end
	end
end)
