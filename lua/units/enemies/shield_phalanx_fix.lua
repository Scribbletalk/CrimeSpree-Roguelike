-- Shield Phalanx Fix
-- Fixes two bugs with the Phalanx Formation (csr_shield_phalanx) crime spree modifier.
--
-- How vanilla ShieldPhalanx works:
--   ModifierShieldPhalanx:init replaces tweak_data.group_ai.unit_categories.CS_shield
--   and FBI_shield with a deep_clone of Phalanx_minion (is_captain = nil).
--   Since the clone has special_type = "shield" and is_captain = nil, the vanilla
--   spawn cap in _spawn_in_group should apply (Normal=2, Hard+=4).
--
-- Spawn cap fix:
--   In practice the vanilla cap may fail because _special_units["shield"] is not
--   populated for phalanx_minion units. The actual fix is in shock_and_awe_phalanx.lua:
--   it overrides _get_special_unit_type_count to use the reliable CSR tracking counter.
--
-- Crash fix (playerstandard): _get_unit_intimidation_action crashes with pairs(nil)
--   for phalanx_minion because vanilla intimidation data has no entry for this unit type.

if not RequiredScript then return end


-- ============================================================
-- PlayerStandard — guard intimidation lookup against nil crash
-- ============================================================
if RequiredScript == "lib/units/beings/player/states/playerstandard" then

	if PlayerStandard and PlayerStandard._get_unit_intimidation_action then
		local orig_get_intimidation = PlayerStandard._get_unit_intimidation_action
		function PlayerStandard:_get_unit_intimidation_action(unit, ...)
			-- phalanx_minion has no intimidation data — skip lookup to avoid pairs(nil) crash
			-- unit can be a boolean value in some call paths, so check type first
			if type(unit) == "userdata" and unit:base() and unit:base()._tweak_table == "phalanx_minion" then
				return nil
			end
			return orig_get_intimidation(self, unit, ...)
		end
	end

end
