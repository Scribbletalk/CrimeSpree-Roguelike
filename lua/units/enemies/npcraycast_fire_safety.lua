-- Verbatim mirror of NPCRaycastWeaponBase:_fire_raycast (npcraycastweaponbase.lua:345-408,
-- game 1.152.269) with four added alive() guards marked "CSR GUARD". A cop's weapon unit (or its
-- target) can be freed mid-call (LIES MWS / FSS area damage, or a generic mid-shoot teardown where
-- CopActionShoot:update fires one extra frame) -> dead userdata native AV. Sites: on_hit_player,
-- on_collision, build_suppression, and _spawn_trail_effect (self._obj_fire). Not LIES-specific.
-- PreHook can't fix this (target freed after entry); must own the body. NOT a CSR bug.
-- Re-diff against vanilla if the game updates this function. See pd2_mia_npcraycast_fire_native_av.md.

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

		-- CSR GUARD: alive(self._unit) added vs vanilla. Weapon unit can be freed mid-frame
		-- (cop disposed mid-action) between damage_player() and here -> native AV on :base().
		if player_hit and alive(self._unit) then
			self._unit:base():bullet_class():on_hit_player(col_ray or player_ray_data, self._unit, user_unit, damage)
		end
	end

	local char_hit = nil

	-- CSR GUARD: alive() added vs vanilla. on_collision derefs col_ray.unit:damage(),
	-- col_ray.body:extension() (2694, unguarded - vanilla guards same at vehicledrivingext:1865),
	-- and this frame derefs self._unit:base(); any can be freed mid-frame (ragdoll body-swap /
	-- cop disposed mid-action) -> native AV. Skip applies no damage to a dying entity (harmless).
	if not player_hit and col_ray and alive(col_ray.unit) and alive(col_ray.body) and alive(self._unit) then
		char_hit =
			self._unit:base():bullet_class():on_collision(col_ray, self._unit, user_unit, damage, self._fires_blanks)
	end

	-- CSR GUARD: alive(target_unit) replaces vanilla's bare `target_unit and` - on_collision
	-- above may free target_unit; dead userdata AVs on :character_damage().
	if
		not shoot_player
		and (not col_ray or col_ray.unit ~= target_unit)
		and alive(target_unit)
		and target_unit:character_damage()
		and target_unit:character_damage().build_suppression
	then
		target_unit:character_damage():build_suppression(tweak_data.weapon[self._name_id].suppression)
	end

	-- CSR GUARD: alive(self._unit) added vs vanilla. _spawn_trail_effect derefs self._obj_fire
	-- (a child object of self._unit, set at npcraycastweaponbase.lua:49) -> native AV if the weapon
	-- unit is disposed mid-action (cop removed while CopActionShoot:update fires one extra frame).
	-- No weapon unit = nothing to attach a trail to, so skipping is harmless.
	if alive(self._unit) and (not col_ray or col_ray.distance > 600 or result.guaranteed_miss) then
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
