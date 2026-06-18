-- Crime Spree Roguelike - guard vanilla NPC fire against a freed aim-target (LIES MWS / FSS compat).
-- Aggressive enemy-AI mods (LIES MWS, Full Speed Swarm) drive cops to fire at a unit that gets
-- freed within the same frame. Vanilla NPCRaycastWeaponBase:_fire_raycast already guards target_unit
-- with alive() in _check_smoke_shot (npcraycastweaponbase.lua:348) but NOT in the build_suppression
-- branch (line 379-380: target_unit:character_damage()), so a freed target_unit there dereferences
-- dead userdata -> native access violation (uncatchable by pcall/crashfixes; they wrap copactionshoot
-- above this frame). We drop a dead target_unit to nil before vanilla runs; vanilla's own nil-guards
-- then skip the deref. No change for live targets (alive() is true) -> mirrors vanilla's own pattern.
--
-- Raw override (not PreHook): a Diesel PreHook can't mutate the args passed to the original.

if not RequiredScript or not NPCRaycastWeaponBase then
	return
end

if _G._CSR_NPC_FIRE_GUARD_HOOKED then
	return
end
_G._CSR_NPC_FIRE_GUARD_HOOKED = true

local orig_fire_raycast = NPCRaycastWeaponBase._fire_raycast
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
	if target_unit and not alive(target_unit) then
		target_unit = nil
	end
	return orig_fire_raycast(
		self,
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
end
