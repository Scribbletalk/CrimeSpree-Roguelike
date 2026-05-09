-- Crime Spree Roguelike - Bag Secured Counter
-- Counts bags secured during a mission for rank bonus calculation.
-- Vanilla bag presentation (cash popup) is preserved as-is.

if not RequiredScript then
	return
end

-- Count bags secured during THIS mission (reliable on both host and client).
-- sync_secure_loot fires for every bag on all peers, so the count is always correct.
Hooks:PostHook(LootManager, "sync_secure_loot", "CSR_CountSecuredBag", function(self, carry_id)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	-- Skip small loot (loose cash, jewelry, etc.)
	if tweak_data.carry.small_loot[carry_id] then
		return
	end
	_G.CSR_MissionBagCount = (_G.CSR_MissionBagCount or 0) + 1
end)
