-- Dead Man's Trigger (contraband) -- go down and take the room with you.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/deadmanstrigger.lua). PostHook on PlayerDamage:
-- _check_bleed_out: the moment the LOCAL player's real health hits 0 (a genuine
-- down -- a guardian save leaves HP > 0), detonate an explosion centered on them.
--   * radius  = BASE_RADIUS + (stacks-1)*RADIUS_PER_STACK            (cm)
--   * damage  = BASE_DAMAGE + (stacks-1)*DAMAGE_PER_STACK + rank*LEVEL_DAMAGE
--   * enemies take `damage` with linear distance falloff, walls block (LOS ray)
--   * allies (players + bots) take ALLY_MULT of that, same falloff + LOS
-- Damage is internal units fed to damage_bullet (BASE_DAMAGE 2400 = 480 display);
-- rank scaling reads managers.csr:rank() (the U1 run rank).
--
-- Disabled in stealth (the blast + sound would instantly blow whisper mode). A 1s
-- file-local cooldown guards against _check_bleed_out re-entrancy on a single down.
--
-- The fake col_ray carries the victim's real Body (unit:body(0)); vanilla
-- damage_bullet calls native body methods and a plain Lua table crashes (same
-- pattern as Viklund's Vinyl). Position is COPIED (m_pos returns engine memory).
--
-- DEFERRED: the 6.2 HUD cooldown-timer events (VHUDPlus/WFHud/PocoHud) -- those
-- shims aren't ported yet. The explosion itself is the mechanic and works without.
--
-- Values mirror the 6.2 constants (dmt_base_radius 300 / dmt_radius_per_stack 200
-- / dmt_base_damage 2400 / dmt_damage_per_stack 1200 / dmt_level_damage 10 /
-- dmt_ally_mult 0.20). Keep the localization fallback in sync (logbook display).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BASE_RADIUS = 300
local RADIUS_PER_STACK = 200
local BASE_DAMAGE = 2400
local DAMAGE_PER_STACK = 1200
local LEVEL_DAMAGE = 10
local ALLY_MULT = 0.20
local COOLDOWN = 1.0

-- File-local re-entry guard (the file is dofile'd once; shared by the closure).
local last_trigger = 0

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

local function dist(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- True when nothing blocks the path. On any failure default to "visible" (no block).
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

local function detonate(self)
	local player_unit = managers.player and managers.player:player_unit()
	if not player_unit or self._unit ~= player_unit then
		return
	end
	-- Only a real down (HP at 0). A guardian save (Plush Shark) leaves HP > 0.
	if not self.get_real_health or self:get_real_health() > 0 then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
		return
	end
	local stacks = mgr:owned("dead_mans_trigger")
	if stacks <= 0 then
		return
	end
	-- No detonation in stealth: blast + sound would break whisper mode.
	if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
		return
	end

	local now = Application:time()
	if now - last_trigger < COOLDOWN then
		return
	end
	last_trigger = now

	local move = player_unit:movement()
	if not move then
		return
	end
	local player_pos = move:m_pos()
	local rank = (mgr.rank and mgr:rank()) or 0
	local radius = BASE_RADIUS + (stacks - 1) * RADIUS_PER_STACK
	local max_damage = BASE_DAMAGE + (stacks - 1) * DAMAGE_PER_STACK + rank * LEVEL_DAMAGE
	local ally_max = max_damage * ALLY_MULT

	-- Blast effect + sound.
	pcall(function()
		managers.explosion:play_sound_and_effects(player_pos, math.UP, radius, {
			sound_event = "grenade_explode",
			effect = "effects/payday2/particles/explosions/grenade_explosion",
		})
	end)

	-- damage_bullet dereferences weapon_unit:base() and uses attack_data.origin;
	-- supply the equipped weapon + a valid origin or it can native-crash.
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
	local from_pos = player_pos + Vector3(0, 0, 80) -- chest height for LOS rays

	-- Enemies: full damage, linear falloff, walls block.
	for _, unit in ipairs(World:find_units_quick("sphere", player_pos, radius, managers.slot:get_mask("enemies"))) do
		if alive(unit) and unit:movement() then
			local cdmg = unit:character_damage()
			if cdmg and not cdmg:dead() then
				local to_pos = unit:movement():m_pos() + Vector3(0, 0, 80)
				if has_los(geometry_mask, from_pos, to_pos) then
					local falloff = math.max(0, 1 - dist(player_pos, unit:movement():m_pos()) / radius)
					local dmg = max_damage * falloff
					local col_ray = make_fake_col_ray(unit)
					if dmg > 0 and col_ray.body then
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

	-- Allies (players + bots): ALLY_MULT of the damage, same falloff + LOS. No
	-- attacker_unit -> vanilla's friendly-fire gate skips, so it always lands.
	for _, unit in ipairs(World:find_units_quick("sphere", player_pos, radius, managers.slot:get_mask("all_criminals"))) do
		if alive(unit) and unit ~= player_unit and unit:movement() then
			local cdmg = unit:character_damage()
			if cdmg and not cdmg:dead() then
				local to_pos = unit:movement():m_pos() + Vector3(0, 0, 80)
				if has_los(geometry_mask, from_pos, to_pos) then
					local falloff = math.max(0, 1 - dist(player_pos, unit:movement():m_pos()) / radius)
					local dmg = ally_max * falloff
					if dmg > 0 then
						local ok = pcall(function()
							cdmg:damage_explosion({
								damage = dmg,
								pos = player_pos,
								attacker_unit = nil,
								range = radius,
							})
						end)
						-- Fallback for character_damage classes without damage_explosion.
						if not ok and cdmg.get_real_health and cdmg.set_health then
							pcall(function()
								cdmg:set_health(cdmg:get_real_health() - dmg)
							end)
						end
					end
				end
			end
		end
	end
end

_G.CSR.register_item({
	type = "dead_mans_trigger",
	rarity = "contraband",
	name = "csr_logbook_dead_mans_trigger_name",
	desc = "csr_item_dead_mans_trigger_desc",
	full_desc = "csr_logbook_dead_mans_trigger_effect",
	notes = "csr_logbook_dead_mans_trigger_notes",
	icon = "csr_dead_mans_trigger",

	hooks = {
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_DEAD_MANS_TRIGGER_HOOKED then
				return
			end
			_G._CSR_DEAD_MANS_TRIGGER_HOOKED = true
			Hooks:PostHook(PlayerDamage, "_check_bleed_out", "CSR_DeadMansTrigger_Explode", detonate)
		end,
	},
})
