-- Crime Spree Roguelike - Remove Damage Cap (TweakData approach)
-- Remove damage caps directly from tweak_data for all enemies.
-- Originals are saved to __CSR_ORIG_* keys so damage_cap_override.lua can
-- temporarily restore them on hits against converts (Jokers), preserving
-- Partners in Crime balance.

if not RequiredScript then
	return
end

-- Hook on CharacterTweakData:init - called when tweak_data is loaded
Hooks:PostHook(CharacterTweakData, "init", "CSR_RemoveAllDamageCaps", function(self)
	-- Guard: only remove damage caps during active Crime Spree
	local cs = Global.crime_spree
	if not cs or not cs.in_progress then
		return
	end

	for enemy_name, enemy_data in pairs(self) do
		-- Only touch genuine enemy entries. CharacterTweakData has non-enemy
		-- sibling tables (weap_ids, weap_unit_names, _unit_prefixes, _enemy_list,
		-- civilian, escort, ...) and stamping __CSR_* keys into them corrupts
		-- data that other mods iterate with pairs() — e.g. HopLib's
		-- NameProvider:init walks tweak_data.character.weap_ids expecting only
		-- string values and crashes on a boolean (crash_report_2026_04_21_16_40).
		-- HEALTH_INIT is present on every enemy entry and absent from config
		-- tables, so it's a reliable discriminator.
		if
			type(enemy_data) == "table"
			and type(enemy_name) == "string"
			and type(enemy_data.HEALTH_INIT) == "number"
		then
			-- Backup originals BEFORE wiping. Converts read these via the
			-- per-hit restore path in damage_cap_override.lua so vanilla
			-- Jokers balance still applies to them even though non-converts
			-- get uncapped damage.
			enemy_data.__CSR_ORIG_DAMAGE_CLAMP_BULLET = enemy_data.DAMAGE_CLAMP_BULLET
			enemy_data.__CSR_ORIG_DAMAGE_CLAMP_EXPLOSION = enemy_data.DAMAGE_CLAMP_EXPLOSION
			enemy_data.__CSR_ORIG_DAMAGE_CLAMP_MELEE = enemy_data.DAMAGE_CLAMP_MELEE
			enemy_data.__CSR_ORIG_DAMAGE_CLAMP_FIRE = enemy_data.DAMAGE_CLAMP_FIRE
			enemy_data.__CSR_ORIG_DAMAGE_CLAMP_SHOCK = enemy_data.DAMAGE_CLAMP_SHOCK
			enemy_data.__CSR_ORIG_DAMAGE_CLAMP_DOT = enemy_data.DAMAGE_CLAMP_DOT
			enemy_data.__CSR_ORIG_HEADSHOT_DMG_MUL = enemy_data.headshot_dmg_mul
			enemy_data.__CSR_CAPS_SAVED = true

			enemy_data.DAMAGE_CLAMP_BULLET = nil
			enemy_data.DAMAGE_CLAMP_EXPLOSION = nil
			enemy_data.DAMAGE_CLAMP_MELEE = nil
			enemy_data.DAMAGE_CLAMP_FIRE = nil
			enemy_data.DAMAGE_CLAMP_SHOCK = nil
			enemy_data.DAMAGE_CLAMP_DOT = nil
			if enemy_data.headshot_dmg_mul and enemy_data.headshot_dmg_mul < 1 then
				enemy_data.headshot_dmg_mul = 1
			end
		end
	end
end)
