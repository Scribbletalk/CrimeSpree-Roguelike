-- Crime Spree Roguelike - guard vanilla NPC fire against a freed aim-target (LIES MWS / FSS compat).
-- Aggressive enemy-AI mods (LIES MWS, Full Speed Swarm) drive cops to fire so fast that the aim
-- target gets freed WITHIN a single _fire_raycast call: on_collision (vanilla line 376) can apply
-- area/explosion damage that destroys target_unit while col_ray.unit is a different unit, so the
-- build_suppression branch (vanilla line 379-380: target_unit:character_damage()) then dereferences
-- dead userdata -> native access violation. pcall/crashfixes cannot catch it (they wrap copactionshoot
-- ABOVE this frame). Vanilla guards target_unit with alive() in _check_smoke_shot (line 412) but the
-- build_suppression branch uses only a bare nil-check, which dead userdata passes.
--
-- An arg-sanitizing PreHook is INSUFFICIENT: it can only see target_unit at function ENTRY, before
-- on_collision frees it. The unsafe derefs are intra-function, so the only fix is to own the body and
-- re-validate at each deref site. This is a VERBATIM mirror of vanilla NPCRaycastWeaponBase:_fire_raycast
-- (npcraycastweaponbase.lua:345-408, game 1.152.269) with TWO added liveness guards (both search "CSR GUARD"):
--   1. on_collision call (vanilla line 375-376): gated on alive(col_ray.unit) - World:raycast can return
--      a unit freed this frame, and InstantBulletBase:on_collision derefs col_ray.unit:damage() unguarded.
--   2. build_suppression branch (vanilla line 379): alive(target_unit) instead of a bare `target_unit and`.
-- Re-diff against vanilla if the game ever updates this function. NOT a CSR bug (no CSR frame in the stack).

if not RequiredScript or not NPCRaycastWeaponBase then
	return
end

if _G._CSR_NPC_FIRE_GUARD_HOOKED then
	return
end
_G._CSR_NPC_FIRE_GUARD_HOOKED = true

local mvec_to = Vector3()
local mvec_spread = Vector3()

function NPCRaycastWeaponBase:_fire_raycast(
	user_unit,
	from_pos,
	direction,
	dmg_mul,
	shoot_player,
	spread_mul,
	autohit_mul,
	suppr_mul,
	target_unit
)
	local result = {}
	local miss, extra_spread = self:_check_smoke_shot(user_unit, target_unit)

	if miss then
		result.guaranteed_miss = miss

		mvector3.spread(direction, math.rand(unpack(extra_spread)))
	end

	mvector3.set(mvec_to, direction)
	mvector3.multiply(mvec_to, 20000)
	mvector3.add(mvec_to, from_pos)

	local damage = self._damage * (dmg_mul or 1)
	local bullet_slotmask = self._bullet_slotmask
	local col_ray =
		World:raycast("ray", from_pos, mvec_to, "slot_mask", bullet_slotmask, "ignore_unit", self._setup.ignore_units)
	local player_hit, player_ray_data = nil

	if shoot_player and self._hit_player then
		player_hit, player_ray_data = self:damage_player(col_ray, from_pos, direction, result)

		if player_hit then
			self._unit:base():bullet_class():on_hit_player(col_ray or player_ray_data, self._unit, user_unit, damage)
		end
	end

	local char_hit = nil

	-- CSR GUARD: alive(col_ray.unit) added vs vanilla. World:raycast can return a unit set_slot(0)'d
	-- this frame (AI mod churn); InstantBulletBase:on_collision derefs `col_ray.unit:damage()`
	-- (raycastweaponbase.lua:2693) with no liveness check -> AV on dead userdata. Skip the hit if gone.
	if not player_hit and col_ray and alive(col_ray.unit) then
		char_hit =
			self._unit:base():bullet_class():on_collision(col_ray, self._unit, user_unit, damage, self._fires_blanks)
	end

	-- CSR GUARD: alive(target_unit) replaces vanilla's bare `target_unit and` - on_collision above
	-- may have freed target_unit this frame, and dead userdata would AV on :character_damage().
	if
		not shoot_player
		and (not col_ray or col_ray.unit ~= target_unit)
		and alive(target_unit)
		and target_unit:character_damage()
		and target_unit:character_damage().build_suppression
	then
		target_unit:character_damage():build_suppression(tweak_data.weapon[self._name_id].suppression)
	end

	if not col_ray or col_ray.distance > 600 or result.guaranteed_miss then
		local num_rays = (tweak_data.weapon[self._name_id] or {}).rays or 1

		for i = 1, num_rays do
			mvector3.set(mvec_spread, direction)

			if i > 1 then
				mvector3.spread(mvec_spread, self:_get_spread(user_unit))
			end

			self:_spawn_trail_effect(mvec_spread, col_ray)
		end
	end

	result.hit_enemy = char_hit

	if self._alert_events then
		result.rays = {
			col_ray,
		}
	end

	self:_cleanup_smoke_shot()

	return result
end
