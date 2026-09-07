-- Familiar Friend (wildcard) - "Spike Nova": 360 AoE on key press; csr_ff_arrow projectiles fly to each hit enemy.
-- 1000 display dmg @rank0 (+5%/rank); display HP -> internal x5 (dead_mans_trigger convention).
-- MP: damage via damage_bullet (vanilla-authoritative); cross-peer arrow cosmetic deferred.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local RADIUS = 600 -- 6m AoE
local BASE_DISPLAY_DAMAGE = 1000 -- display HP at rank 0
local DISPLAY_SCALE = 5 -- display → internal units for damage_bullet
local LEVEL_PCT = 0.05 -- +5% damage per CS rank (matches enemy HP +5%/rank)
local COOLDOWN = 60
local CHARGE_DELAY = 0.6 -- wind-up before the nova fires (matches charge SFX)

local SPIKE_ORIGIN_Z = 80 -- chest height above player feet (caster anchor)
local SPIKE_TARGET_Z = 80 -- enemy chest height (aim point)
local SPIKE_PROJECTILE_ENTRY = "csr_ff_arrow"

-- Per-heist cooldown timestamp; reset in spawned_player.
local cooldown_end = 0

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

local function in_whisper_mode()
	return managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode()
end

local function dist(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function has_los(geometry_mask, from_pos, to_pos)
	if not geometry_mask then
		return true
	end
	local blocked = false
	pcall(function()
		blocked = World:raycast("ray", from_pos, to_pos, "slot_mask", geometry_mask) ~= nil
	end)
	return not blocked
end

-- col_ray needs a real Body (native methods called on it); position COPIED from movement.
local function make_fake_col_ray(unit)
	local pos = Vector3(0, 0, 0)
	if unit:movement() and unit:movement().m_pos then
		mvector3.set(pos, unit:movement():m_pos())
	elseif unit:position() then
		mvector3.set(pos, unit:position())
	end
	return {
		ray = Vector3(0, 0, -1),
		position = pos,
		normal = math.UP,
		unit = unit,
		distance = 0,
		body = unit:body(0),
	}
end

-- Fire one csr_ff_arrow locally (client-authoritative projectile).
local function fire_arrow_at(spawn_pos, target_pos)
	if not ProjectileBase or not ProjectileBase.throw_projectile then
		return
	end
	if not (managers and managers.network and managers.network:session()) then
		return
	end
	local local_peer = managers.network:session():local_peer()
	if not local_peer then
		return
	end
	local dx, dy, dz = target_pos.x - spawn_pos.x, target_pos.y - spawn_pos.y, target_pos.z - spawn_pos.z
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1 then
		return
	end
	local dir = Vector3(dx / len, dy / len, dz / len)
	pcall(function()
		ProjectileBase.throw_projectile(SPIKE_PROJECTILE_ENTRY, spawn_pos, dir, local_peer:id())
	end)
end

local function spawn_spikes_to_targets(caster_chest_pos, targets)
	for _, target_pos in ipairs(targets) do
		fire_arrow_at(caster_chest_pos, target_pos)
	end
end

-- Apply nova damage after wind-up; re-validates state (player may have died / cuffed during delay).
local function fire_spike_nova(player_unit, stacks)
	if not alive(player_unit) then
		return
	end
	if in_whisper_mode() then
		return
	end
	local cdmg_self = player_unit:character_damage()
	if cdmg_self then
		if cdmg_self.dead and cdmg_self:dead() then
			return
		end
		if cdmg_self.bleed_out and cdmg_self:bleed_out() then
			return
		end
		if cdmg_self.arrested and cdmg_self:arrested() then
			return
		end
	end

	local move = player_unit:movement()
	if not move then
		return
	end
	local player_pos = move:m_pos()

	local mgr = managers and managers.csr
	local rank = (mgr and mgr.rank and mgr:rank()) or 0
	local max_damage = BASE_DISPLAY_DAMAGE * DISPLAY_SCALE * (1 + rank * LEVEL_PCT)

	-- Attack SFX at chest height; fresh source, no collision with the gup_charge that played CHARGE_DELAY earlier.
	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("gup_attack", { position = player_pos + Vector3(0, 0, SPIKE_ORIGIN_Z) })
	end

	local weapon_unit = nil
	pcall(function()
		weapon_unit = player_unit:inventory():equipped_unit()
	end)
	local origin = Vector3(0, 0, 0)
	mvector3.set(origin, player_pos)

	local geometry_mask = nil
	pcall(function()
		geometry_mask = managers.slot:get_mask("world_geometry")
	end)
	local from_pos = player_pos + Vector3(0, 0, SPIKE_ORIGIN_Z)

	local enemy_mask = managers.slot:get_mask("enemies")
	local enemies = World:find_units_quick("sphere", player_pos, RADIUS, enemy_mask)

	-- Capture target positions before damage_bullet (dead units' movement() may stale after kill anim).
	local spike_targets = {}

	for _, unit in ipairs(enemies) do
		if alive(unit) and unit:movement() then
			local cdmg = unit:character_damage()
			if cdmg and not cdmg:dead() then
				local to_pos = unit:movement():m_pos() + Vector3(0, 0, SPIKE_TARGET_Z)
				if has_los(geometry_mask, from_pos, to_pos) then
					local falloff = math.max(0, 1 - dist(player_pos, unit:movement():m_pos()) / RADIUS)
					local dmg = max_damage * falloff
					local col_ray = make_fake_col_ray(unit)
					if dmg > 0 and col_ray.body then
						table.insert(spike_targets, Vector3(to_pos.x, to_pos.y, to_pos.z))
						pcall(function()
							cdmg:damage_bullet({
								damage = dmg,
								attacker_unit = player_unit,
								weapon_unit = weapon_unit,
								variant = "bullet",
								col_ray = col_ray,
								origin = origin,
							})
						end)
					end
				end
			end
		end
	end

	spawn_spikes_to_targets(from_pos, spike_targets)
end

-- Cooldown-ready chime. Suppressed if the player left the heist or no longer owns it.
local function play_cooldown_ready()
	local mgr = csr_mgr()
	if not mgr then
		return
	end
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		if state == "victoryscreen" or state == "gameoverscreen" then
			return
		end
	end
	if mgr:owned("familiar_friend") <= 0 then
		return
	end
	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("gup_cooldown")
	end
end

-- Wildcard dispatcher entry point; player_unit is the local player (pre-validated).
local function activate_spike_nova(player_unit)
	local mgr = csr_mgr()
	if not mgr then
		return
	end
	local stacks = mgr:owned("familiar_friend")
	if stacks <= 0 then
		return
	end
	-- Stealth gate: detonating during whisper would instantly break it.
	if in_whisper_mode() then
		return
	end
	-- Cooldown gate.
	local now = TimerManager:game():time()
	if now < (cooldown_end or 0) then
		return
	end
	if not player_unit:movement() then
		return
	end

	cooldown_end = now + COOLDOWN
	if _G.CSR_SetWildcardCooldown then
		_G.CSR_SetWildcardCooldown("familiar_friend", cooldown_end, COOLDOWN)
	end

	-- Charge SFX immediately on press as the wind-up.
	if _G.CSR and _G.CSR.play_sound then
		local move = player_unit:movement()
		local sfx_pos = move and (move:m_pos() + Vector3(0, 0, SPIKE_ORIGIN_Z)) or nil
		if sfx_pos then
			_G.CSR.play_sound("gup_charge", { position = sfx_pos })
		else
			_G.CSR.play_sound("gup_charge", { unit = player_unit })
		end
	end

	DelayedCalls:Add("CSR_FamiliarFriend_Fire", CHARGE_DELAY, function()
		fire_spike_nova(player_unit, stacks)
	end)
	DelayedCalls:Add("CSR_FamiliarFriend_CooldownReady", COOLDOWN, play_cooldown_ready)
end

_G.CSR.register_item({
	type = "familiar_friend",
	rarity = "wildcard",
	name = "csr_logbook_familiar_friend_name",
	desc = "csr_item_familiar_friend_desc",
	full_desc = "csr_logbook_familiar_friend_effect",
	notes = "csr_logbook_familiar_friend_notes",
	icon = "csr_familiar_friend",
	icon_scale = 1.0,

	-- $aura_radius / $base_dmg / $cooldown fill csr_logbook_familiar_friend_effect.
	loc_macros = {
		aura_radius = string.format("%g", RADIUS / 100),
		base_dmg = BASE_DISPLAY_DAMAGE,
		cooldown = string.format("%g", COOLDOWN),
	},

	hooks = {
		["lib/managers/playermanager"] = function()
			if _G._CSR_FAMILIAR_FRIEND_HOOKED then
				return
			end
			_G._CSR_FAMILIAR_FRIEND_HOOKED = true

			-- Reset cooldown on spawn (per-heist).
			Hooks:PostHook(PlayerManager, "spawned_player", "CSR_FamiliarFriendInit", function()
				cooldown_end = 0
				if _G.CSR_SetWildcardCooldown then
					_G.CSR_SetWildcardCooldown("familiar_friend", 0, COOLDOWN)
				end
			end)

			-- Register with the wildcard dispatcher (idempotent — keyed by type).
			if _G.CSR_RegisterWildcardActive then
				_G.CSR_RegisterWildcardActive("familiar_friend", activate_spike_nova)
			end
		end,
	},
})
