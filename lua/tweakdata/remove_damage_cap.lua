-- Crime Spree Roguelike - Remove Damage Cap (TweakData approach)
-- Remove damage caps directly from tweak_data for all enemies

if not RequiredScript then
	return
end



-- Hook on CharacterTweakData:init - called when tweak_data is loaded
Hooks:PostHook(CharacterTweakData, "init", "CSR_RemoveAllDamageCaps", function(self)

	local removed_count = 0
	local enemy_list = {}

	-- Iterate over all enemies in tweak_data.character
	for enemy_name, enemy_data in pairs(self) do
		-- Guard: must be a table with enemy data, not a function
		if type(enemy_data) == "table" and type(enemy_name) == "string" then
			local caps_removed = {}

			-- Remove bullet damage cap
			if enemy_data.DAMAGE_CLAMP_BULLET then
				table.insert(caps_removed, "BULLET:" .. tostring(enemy_data.DAMAGE_CLAMP_BULLET))
				enemy_data.DAMAGE_CLAMP_BULLET = nil
			end

			-- Remove explosion damage cap
			if enemy_data.DAMAGE_CLAMP_EXPLOSION then
				table.insert(caps_removed, "EXPLOSION:" .. tostring(enemy_data.DAMAGE_CLAMP_EXPLOSION))
				enemy_data.DAMAGE_CLAMP_EXPLOSION = nil
			end

			-- Remove melee damage cap
			if enemy_data.DAMAGE_CLAMP_MELEE then
				table.insert(caps_removed, "MELEE:" .. tostring(enemy_data.DAMAGE_CLAMP_MELEE))
				enemy_data.DAMAGE_CLAMP_MELEE = nil
			end

			-- Remove fire damage cap
			if enemy_data.DAMAGE_CLAMP_FIRE then
				table.insert(caps_removed, "FIRE:" .. tostring(enemy_data.DAMAGE_CLAMP_FIRE))
				enemy_data.DAMAGE_CLAMP_FIRE = nil
			end

			-- Remove shock damage cap
			if enemy_data.DAMAGE_CLAMP_SHOCK then
				table.insert(caps_removed, "SHOCK:" .. tostring(enemy_data.DAMAGE_CLAMP_SHOCK))
				enemy_data.DAMAGE_CLAMP_SHOCK = nil
			end

			-- Remove DOT damage cap
			if enemy_data.DAMAGE_CLAMP_DOT then
				table.insert(caps_removed, "DOT:" .. tostring(enemy_data.DAMAGE_CLAMP_DOT))
				enemy_data.DAMAGE_CLAMP_DOT = nil
			end

			-- Remove headshot damage reduction
			if enemy_data.headshot_dmg_mul and enemy_data.headshot_dmg_mul < 1 then
				table.insert(caps_removed, "HEADSHOT_MUL:" .. tostring(enemy_data.headshot_dmg_mul))
				enemy_data.headshot_dmg_mul = 1
			end

			if #caps_removed > 0 then
				removed_count = removed_count + 1
				table.insert(enemy_list, enemy_name)
			end
		end
	end

end)

