-- Career combat tally: counts the LOCAL player's kills, damage dealt, and damage taken during
-- CSR heists. Each hit only bumps a runtime tally in managers.csr; mission_lifecycle.lua flushes
-- it into _meta.stats once per heist (no per-bullet disk writes). Loaded on 3 engine scripts
-- (see mod.txt) so this file runs 3 times; _G flags make each install run exactly once. Every
-- hook gates on in_csr_heist() so nothing leaks into vanilla heists.

if not RequiredScript then
	return
end

local function in_csr_heist()
	local mgr = managers and managers.csr
	return mgr and mgr.in_csr_heist and mgr:in_csr_heist()
end

local function tally(key, amount)
	local mgr = managers and managers.csr
	if mgr and mgr.tally_combat then
		mgr:tally_combat(key, amount)
	end
end

local function tally_max(key, amount)
	local mgr = managers and managers.csr
	if mgr and mgr.tally_combat_max then
		mgr:tally_combat_max(key, amount)
	end
end

-- Damage dealt: on_damage_dealt fires only when the local player is the attacker (copdamage.lua
-- and civiliandamage.lua gate the call on attacker_unit == player_unit). damage_info.damage is
-- the amount applied this hit.
if PlayerManager and not _G._CSR_CombatStat_Dealt then
	_G._CSR_CombatStat_Dealt = true
	Hooks:PostHook(PlayerManager, "on_damage_dealt", "CSR_CombatStat_Dealt", function(_, unit, damage_info)
		if damage_info and in_csr_heist() then
			tally("damage_dealt", damage_info.damage or 0)
			tally_max("max_hit", damage_info.damage or 0) -- biggest single hit (career record)
		end
	end)
end

-- Damage taken: armor absorbed + health lost are disjoint, summing to the real damage taken.
-- Both _calc functions return health_subtracted; raw-wrap to read the return (PostHook can't).
if PlayerDamage and not _G._CSR_CombatStat_Taken then
	_G._CSR_CombatStat_Taken = true

	local orig_armor = PlayerDamage._calc_armor_damage
	function PlayerDamage:_calc_armor_damage(attack_data)
		local health_subtracted = orig_armor(self, attack_data)
		if in_csr_heist() then
			tally("damage_taken", health_subtracted or 0)
		end
		return health_subtracted
	end

	local orig_health = PlayerDamage._calc_health_damage
	function PlayerDamage:_calc_health_damage(attack_data)
		local health_subtracted = orig_health(self, attack_data)
		if in_csr_heist() then
			tally("damage_taken", health_subtracted or 0)
		end
		return health_subtracted
	end
end

-- A "special" is any enemy with a priority_shout (the special-callout voice line): taser, cloaker,
-- bulldozer/medic/sniper/shield/phalanx. Regular cops/heavies carry only silent_priority_shout.
local function is_special_char(name)
	local cdata = name and tweak_data and tweak_data.character and tweak_data.character[name]
	return (cdata and cdata.priority_shout ~= nil) or false
end

-- Kills: StatisticsManager:killed is the local player's per-kill recorder (drives the end-screen
-- kill count); one call == one kill by this player. data.name is the character tweak_table key.
if StatisticsManager and not _G._CSR_CombatStat_Kills then
	_G._CSR_CombatStat_Kills = true
	Hooks:PostHook(StatisticsManager, "killed", "CSR_CombatStat_Kills", function(_, data)
		if in_csr_heist() then
			tally("kills", 1)
			if data and is_special_char(data.name) then
				tally("specials_killed", 1)
			end
		end
	end)
end

csr_log("[CSR] combat_stats.lua loaded")
