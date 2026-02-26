-- DEAD MAN'S TRIGGER - Explosion on going down
-- Going down triggers an explosion damaging nearby enemies (full) and allies (20%).
-- Radius: 300 cm per stack.
-- Enemy damage: (480 + cs_level × 2) display HP per stack, linear falloff with distance.
-- At CS 0: 480 display (guaranteed, kills light SWAT). Scales with enemy HP growth.
-- Ally damage: 20% of enemy damage at the same distance.
-- Line of sight: walls block damage for both enemies and allies.

if not RequiredScript then
	return
end



ModifierDeadMansTrigger = ModifierDeadMansTrigger or class(CSRBaseModifier)
ModifierDeadMansTrigger.desc_id = "csr_dead_mans_trigger_desc"

local BASE_RADIUS        = 300   -- cm at 1 stack
local RADIUS_PER_STACK   = 200   -- cm per additional stack (= +2m)
local BASE_DAMAGE        = 2400  -- internal at 1 stack (= 480 display HP)
local DAMAGE_PER_STACK   = 1200  -- internal per additional stack (= 240 display HP)
local LEVEL_DAMAGE       = 10    -- internal per CS level, flat bonus (= 2 display HP)
local ALLY_MULT          = 0.20  -- allies take 20% of enemy damage

local DUMMY_BODY_NAME = Idstring("chain_dummy")

-- Fake col_ray required by CopDamage:damage_bullet to avoid nil-access crash.
-- Dummy body name is not in any armor table, so the armor lookup is skipped.
local function make_fake_col_ray(unit)
	return {
		ray      = Vector3(0, 0, -1),
		position = unit:movement():m_pos(),
		normal   = math_up,
		unit     = unit,
		distance = 0,
		body     = { name = function() return DUMMY_BODY_NAME end },
	}
end

local function pos_dist(p1, p2)
	local dx = p1.x - p2.x
	local dy = p1.y - p2.y
	local dz = p1.z - p2.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Returns true if there is no geometry blocking the path from from_pos to to_pos.
-- On any error (slot mask unavailable, World:raycast not found) defaults to true (no block).
local function has_line_of_sight(geometry_mask, from_pos, to_pos)
	if not geometry_mask then return true end
	local blocked = false
	pcall(function()
		blocked = World:raycast("ray", from_pos, to_pos, "slot_mask", geometry_mask) ~= nil
	end)
	return not blocked
end

-- Cooldown: prevent double-trigger within the same down event
_G.CSR_DMT_LastTrigger = _G.CSR_DMT_LastTrigger or 0

Hooks:PostHook(PlayerDamage, "_check_bleed_out", "CSR_DMT_Explode", function(self)
	-- Only trigger for the local player (remote players / bots may not have get_real_health)
	local local_player_unit = managers.player and managers.player:player_unit()
	if not local_player_unit then return end
	if self._unit ~= local_player_unit then return end
	-- Only trigger when the player actually goes down (health still > 0 means Plush Shark saved them)
	if not self.get_real_health then return end
	if self:get_real_health() > 0 then return end
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.dead_mans_trigger then return end

	-- 1-second cooldown guard against re-entrant calls
	local now = Application:time()
	if now - _G.CSR_DMT_LastTrigger < 1.0 then
		return
	end
	_G.CSR_DMT_LastTrigger = now

	local stacks    = CSR_ActiveBuffs.dead_mans_trigger
	local cs_level  = (managers.crime_spree and managers.crime_spree:spree_level()) or 0
	local radius     = BASE_RADIUS + (stacks - 1) * RADIUS_PER_STACK
	local max_damage = BASE_DAMAGE + (stacks - 1) * DAMAGE_PER_STACK + cs_level * LEVEL_DAMAGE
	local ally_max   = max_damage * ALLY_MULT

	-- Get the downed player's position
	local player_unit = local_player_unit
	local move = player_unit:movement()
	if not move then return end
	local player_pos = move:m_pos()


	-- === Explosion effect + sound ===
	pcall(function()
		managers.explosion:play_sound_and_effects(player_pos, math_up, radius, {
			sound_event = "grenade_explode",
			effect      = "effects/payday2/particles/explosions/grenade_explosion",
		})
	end)

	-- Weapon unit fallback (melee-safe): use equipped weapon if available
	local weapon_unit = nil
	pcall(function()
		weapon_unit = player_unit:inventory():equipped_unit()
	end)

	-- LOS setup: geometry mask + chest-height origin for raycasts
	local geometry_mask = nil
	pcall(function() geometry_mask = managers.slot:get_mask("world_geometry") end)
	local player_check_pos = player_pos + Vector3(0, 0, 80)

	-- === Deal damage to enemies ===
	local enemy_mask = managers.slot:get_mask("enemies")
	local enemies = World:find_units_quick("sphere", player_pos, radius, enemy_mask)

	local hit_count = 0
	for _, unit in ipairs(enemies) do
		if alive(unit) and unit:movement() then
			local cdmg = unit:character_damage()
			if cdmg and not cdmg:dead() then
				local unit_pos = unit:movement():m_pos() + Vector3(0, 0, 80)
				if has_line_of_sight(geometry_mask, player_check_pos, unit_pos) then
					local dist    = pos_dist(player_pos, unit:movement():m_pos())
					local falloff = math.max(0, 1 - dist / radius)
					local dmg     = max_damage * falloff
					if dmg > 0 then
						pcall(function()
							cdmg:damage_bullet({
								damage        = dmg,
								attacker_unit = player_unit,
								weapon_unit   = weapon_unit,
								col_ray       = make_fake_col_ray(unit),
							})
						end)
						hit_count = hit_count + 1
					end
				end
			end
		end
	end

	-- === Deal damage to allies (human players + AI bots) ===
	local player_mask = managers.slot:get_mask("all_criminals")
	local players = World:find_units_quick("sphere", player_pos, radius, player_mask)

	local ally_hit = 0
	for _, unit in ipairs(players) do
		-- Skip the downed player themselves
		if alive(unit) and unit ~= player_unit then
			local pdmg = unit:character_damage()
			if pdmg and not pdmg:dead() then
				local unit_pos = unit:movement():m_pos() + Vector3(0, 0, 80)
				if has_line_of_sight(geometry_mask, player_check_pos, unit_pos) then
					local dist    = pos_dist(player_pos, unit:movement():m_pos())
					local falloff = math.max(0, 1 - dist / radius)
					local dmg     = ally_max * falloff
					if dmg > 0 then
						pcall(function()
							-- attacker_unit=nil → FF check "attacker_unit and ..." = false → skipped.
							-- range= satisfies the range-check inside damage_explosion.
							local ok = pcall(function()
								pdmg:damage_explosion({
									damage        = dmg,
									pos           = player_pos,
									attacker_unit = nil,
									range         = radius,
								})
							end)
							if not ok then
								-- Fallback for vanilla without damage_explosion on PlayerDamage
								if pdmg.get_real_health then
									local cur_hp = pdmg:get_real_health()
									if cur_hp then pdmg:set_health(cur_hp - dmg) end
								end
							end
						end)
						ally_hit = ally_hit + 1
					end
				end
			end
		end
	end
end)

