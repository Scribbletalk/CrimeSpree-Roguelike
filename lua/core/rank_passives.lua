-- Passive per-rank player progression: +1% Max Health, +1% Max Armor and +1% damage
-- (all sources) per Crime Spree rank (additive in rank, user balance 2026-05-24 --
-- ports the pre-refactor +0.2% HP / +0.2% armor / +0.04% damage, scaled up and rounded
-- to a flat 1% "to everything" for now). NOT an item: it scales continuously with the
-- run rank, mirroring the per-rank ENEMY scaling in game_manager.lua apply_modifiers.
--
-- Applied LOCALLY on each peer (these are the player's own stat methods); rank comes
-- from host_rank() so every peer scales off the same synced run rank. Each wrap is a
-- raw chain-wrap (the CSR convention for return-value hooks -- see the item files),
-- guarded by a _G flag: this file is hooked on SIX engine scripts (mod.txt), so it
-- loads six times with independent file-locals -- the flags make each install happen
-- exactly once, when its class first appears (order-independent). Outside a run
-- run_rank() returns 0, so every wrap is a no-op (no leak into vanilla sessions -- the
-- same is_run_active() gate the items use).

if not RequiredScript then
	return
end

local PER_RANK = 0.01 -- +1% per rank, to HP / armor / all damage (players)
local BOT_HP_PER_RANK = 0.01 -- +1% per rank to bot max HP
local BOT_DMG_PER_RANK = 0.05 -- +5% per rank to bot weapon damage

-- Current run rank for the local view (0 outside a run). host_rank so a client scales
-- off the host's synced rank, exactly like the enemy scaling + active_modifiers.
local function run_rank()
	local mgr = managers and managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
		return 0
	end
	return (mgr.host_rank and mgr:host_rank()) or 0
end

-- Debug-only scaling trace. Routes through managers.csr:_debug_stat, which logs ONLY
-- when the value changes (so the per-shot / per-hit wraps never flood) and is silent
-- unless debug_mode is on. No-op until managers.csr exists. Lets you confirm each path
-- fires and see the exact factor it applied (e.g. "rank_passive 'ranged_dmg_mult' bonus
-- -> 1.0500" at rank 5).
local function dbg_mult(stat, value)
	local mgr = managers and managers.csr
	if mgr and mgr._debug_stat then
		mgr:_debug_stat("rank_passive", stat, value)
	end
end

-- Returns true if `unit` is an AI bot teammate (not a human player).
-- Used to route bots to their own scaling path and skip the player weapon wrap.
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

-- +1%/rank to the health skill multiplier (the field Dog Tags also adds to; the Heister
-- panel reads this, so its Max Health already reflects this passive).
if PlayerManager and not _G._CSR_RankPassive_HP then
	_G._CSR_RankPassive_HP = true
	local orig = PlayerManager.health_skill_multiplier
	if orig then
		function PlayerManager:health_skill_multiplier()
			local r = run_rank()
			dbg_mult("max_health_add", PER_RANK * r)
			return orig(self) + PER_RANK * r
		end
	end
end

-- +1%/rank to max armor (multiplies the base, like Dozer Guide). Composes with the other
-- _max_armor chain-wraps (Glass Pistol / Dozer Guide) -- multiplicative, so order between
-- them doesn't matter.
if PlayerDamage and not _G._CSR_RankPassive_Armor then
	_G._CSR_RankPassive_Armor = true
	local orig = PlayerDamage._max_armor
	if orig then
		function PlayerDamage:_max_armor()
			local r = run_rank()
			dbg_mult("max_armor_mult", 1 + PER_RANK * r)
			return orig(self) * (1 + PER_RANK * r)
		end
	end
end

-- +1%/rank to ranged weapon damage (RaycastWeaponBase:_get_current_damage -- the gun
-- point the pre-refactor "all damage" buff used). Bots are excluded here: they get their
-- own separate scaling in the NewRaycastWeaponBase._fire_raycast wrap below.
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
				dbg_mult("ranged_dmg_mult", 1 + PER_RANK * r)
				return dmg * (1 + PER_RANK * r)
			end
			return dmg
		end
	end
end

-- +1%/rank to melee damage. equipped_melee_weapon_damage_info runs per swing
-- (PlayerStandard:_do_melee_damage); its result flows through attack_data.damage to
-- CopDamage:damage_melee and networks to the host the standard way, so scaling here is
-- MP-correct (each peer scales its own swing). Returns (dmg, dmg_effect) -- scale both.
-- (Explosions / fire / DOT / sentry are scaled in the blocks below.)
if BlackMarketManager and not _G._CSR_RankPassive_Melee then
	_G._CSR_RankPassive_Melee = true
	local orig = BlackMarketManager.equipped_melee_weapon_damage_info
	if orig then
		function BlackMarketManager:equipped_melee_weapon_damage_info(...)
			local dmg, dmg_effect = orig(self, ...)
			local rank = run_rank()
			if rank > 0 then
				local mul = 1 + PER_RANK * rank
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

-- Host-authoritative damage types: explosions / fire / DOT are computed by the HOST for
-- the whole crew, so they're scaled there -- one PreHook each on CopDamage, HOST-ONLY,
-- multiplying attack_data.damage (the input every damage_* variant reads first) by the
-- run-rank mult. Covers grenades / RPG / GL40 / trip mines (explosion), molotov /
-- incendiary / Dragon's Breath (fire) and poison / fire-DOT ticks (dot). Host-only so a
-- client never double-scales; the bigger enemy health loss syncs to everyone. (Guns +
-- melee are scaled per-machine at their own source above, so they're NOT in here.)
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
			local mul = 1 + PER_RANK * r
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

-- Sentry turret damage (a deployable -- uses SentryGunWeapon, not the player's
-- RaycastWeapon, so it's a separate point). Scale self._damage around _fire_raycast
-- (both the enemy-hit and player-hit branches read it via _apply_dmg_mul), saving and
-- restoring so the base value isn't permanently inflated. Sentry AI fires host-side, so
-- this scales once per shot.
if SentryGunWeapon and not _G._CSR_RankPassive_Sentry then
	_G._CSR_RankPassive_Sentry = true
	local orig = SentryGunWeapon._fire_raycast
	if orig then
		function SentryGunWeapon:_fire_raycast(...)
			local r = run_rank()
			if r > 0 and type(self._damage) == "number" then
				local mul = 1 + PER_RANK * r
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

-- +1%/rank to bot max HP. PostHook on TeamAIDamage:init -- the fields are already set by
-- the time the hook fires, so we multiply them in-place. All five HP fields must be
-- scaled together or the bleedout / percentage math diverges.
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

-- +5%/rank to bot weapon damage. Wrapped at NewRaycastWeaponBase._fire_raycast so bots
-- get their own multiplier independent of the player _get_current_damage path. Host-only:
-- bot AI fires server-side (clients use HuskTeamAIDamage which doesn't fire directly).
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

csr_log("[CSR] rank_passives.lua loaded (per-rank player HP/armor/damage passive)")
