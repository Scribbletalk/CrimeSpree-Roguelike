-- Per-rank player passives: HP / armor / weapon damage scale with CS rank.
-- Hooked on 8 engine scripts (see mod.txt) so this file loads 8 times — _G flags
-- make each install run exactly once.

if not RequiredScript then
	return
end

local HP_PER_RANK = 0.025
local ARMOR_PER_RANK = 0.025
-- Shared with perk_deck_scaling.lua: perk-deck armor/health regen scales by the same per-rank factors.
_G.CSR_ARMOR_PER_RANK = ARMOR_PER_RANK
_G.CSR_HP_PER_RANK = HP_PER_RANK
local DMG_PER_RANK = 0.01
local BOT_HP_PER_RANK = 0.01
local BOT_DMG_PER_RANK = 0.10

-- Rank we're playing at. host_rank() so clients scale off the host's synced rank.
-- Gated on in_csr_heist() (not is_run_active) so HP/armor/damage never leak into vanilla
-- heists: returns 0 outside a CSR heist, making every wrap below a no-op there.
local function run_rank()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return 0
	end
	return (mgr.host_rank and mgr:host_rank()) or 0
end

-- Debug-only trace (silent unless _G.CSR_DEBUG).
local function dbg_mult(stat, value)
	local mgr = managers and managers.csr
	if mgr and mgr._debug_stat then
		mgr:_debug_stat("rank_passive", stat, value)
	end
end

local function is_bot_unit(unit)
	if not alive(unit) then
		return false
	end
	local crim = managers.criminals
	if not crim or not crim.has_character_by_unit then
		return false
	end
	if not crim:has_character_by_unit(unit) then
		return false
	end
	local data = crim:character_data_by_unit(unit)
	return data ~= nil and data.ai == true
end

-- HP: same field Dog Tags touches.
if PlayerManager and not _G._CSR_RankPassive_HP then
	_G._CSR_RankPassive_HP = true
	local orig = PlayerManager.health_skill_multiplier
	if orig then
		function PlayerManager:health_skill_multiplier()
			local r = run_rank()
			dbg_mult("max_health_add", HP_PER_RANK * r)
			return orig(self) + HP_PER_RANK * r
		end
	end
end

-- Armor: composes with Glass Pistol / Dozer Guide (all multiplicative).
if PlayerDamage and not _G._CSR_RankPassive_Armor then
	_G._CSR_RankPassive_Armor = true
	local orig = PlayerDamage._max_armor
	if orig then
		function PlayerDamage:_max_armor()
			local r = run_rank()
			dbg_mult("max_armor_mult", 1 + ARMOR_PER_RANK * r)
			return orig(self) * (1 + ARMOR_PER_RANK * r)
		end
	end
end

-- Ranged damage. Bots skip — they go through the NewRaycastWeaponBase path below.
if RaycastWeaponBase and not _G._CSR_RankPassive_Dmg then
	_G._CSR_RankPassive_Dmg = true
	local orig = RaycastWeaponBase._get_current_damage
	if orig then
		function RaycastWeaponBase:_get_current_damage(...)
			local dmg = orig(self, ...)
			if type(dmg) == "number" then
				local user = self._setup and self._setup.user_unit
				if user and is_bot_unit(user) then
					return dmg
				end
				local r = run_rank()
				dbg_mult("ranged_dmg_mult", 1 + DMG_PER_RANK * r)
				return dmg * (1 + DMG_PER_RANK * r)
			end
			return dmg
		end
	end
end

-- Melee. Returns (dmg, dmg_effect) — scale both.
if BlackMarketManager and not _G._CSR_RankPassive_Melee then
	_G._CSR_RankPassive_Melee = true
	local orig = BlackMarketManager.equipped_melee_weapon_damage_info
	if orig then
		function BlackMarketManager:equipped_melee_weapon_damage_info(...)
			local dmg, dmg_effect = orig(self, ...)
			local rank = run_rank()
			if rank > 0 then
				local mul = 1 + DMG_PER_RANK * rank
				dbg_mult("melee_dmg_mult", mul)
				if type(dmg) == "number" then
					dmg = dmg * mul
				end
				if type(dmg_effect) == "number" then
					dmg_effect = dmg_effect * mul
				end
			end
			return dmg, dmg_effect
		end
	end
end

-- Explosions / fire / DOT run host-side for the whole crew.
-- Host-only or a client would double-scale.
if CopDamage and not _G._CSR_RankDmg_CopDamage then
	_G._CSR_RankDmg_CopDamage = true
	local function csr_scale_attack_damage(_, attack_data, label)
		if not Network:is_server() then
			return
		end
		if not attack_data or type(attack_data.damage) ~= "number" then
			return
		end
		local r = run_rank()
		if r > 0 then
			local mul = 1 + DMG_PER_RANK * r
			dbg_mult(label, mul)
			attack_data.damage = attack_data.damage * mul
		end
	end
	Hooks:PreHook(CopDamage, "damage_explosion", "CSR_RankDmg_Explosion", function(s, ad)
		csr_scale_attack_damage(s, ad, "explosion_dmg_mult")
	end)
	Hooks:PreHook(CopDamage, "damage_fire", "CSR_RankDmg_Fire", function(s, ad)
		csr_scale_attack_damage(s, ad, "fire_dmg_mult")
	end)
	Hooks:PreHook(CopDamage, "damage_dot", "CSR_RankDmg_Dot", function(s, ad)
		csr_scale_attack_damage(s, ad, "dot_dmg_mult")
	end)
end

-- Sentry turret — save/restore self._damage so the base isn't permanently inflated.
if SentryGunWeapon and not _G._CSR_RankPassive_Sentry then
	_G._CSR_RankPassive_Sentry = true
	local orig = SentryGunWeapon._fire_raycast
	if orig then
		function SentryGunWeapon:_fire_raycast(...)
			local r = run_rank()
			if r > 0 and type(self._damage) == "number" then
				local mul = 1 + DMG_PER_RANK * r
				dbg_mult("sentry_dmg_mult", mul)
				local saved = self._damage
				self._damage = saved * mul
				local res = orig(self, ...)
				self._damage = saved
				return res
			end
			return orig(self, ...)
		end
	end
end

-- Bot HP. All five fields must move together or bleedout math breaks.
if TeamAIDamage and not _G._CSR_BotHP then
	_G._CSR_BotHP = true
	Hooks:PostHook(TeamAIDamage, "init", "CSR_BotHPPassive", function(self)
		local r = run_rank()
		if r > 0 then
			local mul = 1 + BOT_HP_PER_RANK * r
			dbg_mult("bot_max_hp_mult", mul)
			self._HEALTH_INIT = self._HEALTH_INIT * mul
			self._HEALTH_BLEEDOUT_INIT = self._HEALTH_BLEEDOUT_INIT * mul
			self._HEALTH_TOTAL = self._HEALTH_TOTAL * mul
			self._HEALTH_TOTAL_PERCENT = self._HEALTH_TOTAL_PERCENT * mul
			self._health = self._health * mul
		end
	end)
end

-- Bot weapon damage. Host-only — bot AI fires server-side.
if NewRaycastWeaponBase and not _G._CSR_BotDmg then
	_G._CSR_BotDmg = true
	local orig = NewRaycastWeaponBase._fire_raycast
	if orig then
		function NewRaycastWeaponBase:_fire_raycast(user_unit, from_pos, direction, dmg_mul, ...)
			if Network:is_server() and is_bot_unit(user_unit) then
				local r = run_rank()
				if r > 0 then
					local mul = 1 + BOT_DMG_PER_RANK * r
					dbg_mult("bot_dmg_mult", mul)
					dmg_mul = (dmg_mul or 1) * mul
				end
			end
			return orig(self, user_unit, from_pos, direction, dmg_mul, ...)
		end
	end
end

csr_log("[CSR] rank_passives.lua loaded")
