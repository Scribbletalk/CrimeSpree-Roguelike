-- Crime Spree Roguelike - Bot HP passive progression
-- Hooks TeamAIDamage:init to scale bot max HP with CS rank.
-- Bots get +0.04% HP per CS level.

if not RequiredScript then
	return
end

local C = _G.CSR_ItemConstants or {}
local BOT_HP_PER_LEVEL = C.bot_hp_per_level or 0.0004 -- +0.04% per CS level

Hooks:PostHook(TeamAIDamage, "init", "CSR_BotHPPassive", function(self, unit)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end

	local spree_level = (_G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and _G.CSR_MP_HostRank)
		or managers.crime_spree:spree_level()
		or 0
	if spree_level <= 0 then
		return
	end

	local mult = 1 + BOT_HP_PER_LEVEL * spree_level

	self._HEALTH_INIT = math.ceil(self._HEALTH_INIT * mult)
	self._HEALTH_BLEEDOUT_INIT = math.ceil(self._HEALTH_BLEEDOUT_INIT * mult)
	self._HEALTH_TOTAL = self._HEALTH_INIT + self._HEALTH_BLEEDOUT_INIT
	self._HEALTH_TOTAL_PERCENT = self._HEALTH_TOTAL / 100
	self._health = self._HEALTH_INIT
end)
