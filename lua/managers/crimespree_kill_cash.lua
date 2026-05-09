-- Crime Spree Roguelike - Kill Cash → Instant Cash
-- Adds accumulated kill cash (_G.CSR_MissionKillCash) to the Instant Cash total.
-- Direct override required because PostHook cannot modify return values.
-- get_real_total_small_loot_value is used by both TAB screen and MoneyManager payout.

if not RequiredScript then
	return
end

local original_get_real_total = LootManager.get_real_total_small_loot_value
_G.CSR_SafeOverride(
	LootManager,
	"get_real_total_small_loot_value",
	"Kill Cash",
	original_get_real_total,
	function(self, ...)
		local value = original_get_real_total(self, ...)
		local kill_cash = _G.CSR_MissionKillCash or 0

		if kill_cash ~= 0 and managers.crime_spree and managers.crime_spree:is_active() then
			value = value + kill_cash
		end

		return value
	end
)
