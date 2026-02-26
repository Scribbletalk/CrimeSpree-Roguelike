-- Crime Spree Roguelike - HP/DMG Scaling System
-- Enemies gain bonus HP (+0.4%) and DMG (+0.3%) per Crime Spree level
-- Instead of many small modifiers - one virtual modifier with combined totals

if not RequiredScript then
	return
end



-- Global function to get HP/DMG bonuses based on current level
-- Called from the UI filter and enemy hooks
function CSR_GetTotalHPDamageBonus()
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0, 0
	end

	local level = managers.crime_spree:spree_level() or 0

	local hp_bonus = level * 0.004    -- +0.4% HP per level
	local dmg_bonus = level * 0.003   -- +0.3% DMG per level

	return hp_bonus, dmg_bonus
end

