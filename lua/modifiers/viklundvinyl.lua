-- VIKLUND'S VINYL - Chain Damage
-- 80% chance on hit (fixed, does not scale with stacks).
-- Chains 20% damage to 2 nearest enemies within radius.
-- Base radius: 500cm (5m), +200cm (+2m) per additional stack.

if not RequiredScript then
	return
end

local required = string.lower(RequiredScript)

ModifierViklundVinyl = ModifierViklundVinyl or class(CSRBaseModifier)
ModifierViklundVinyl.desc_id = "csr_viklund_vinyl_desc"

-- Read constants from _G.CSR_ItemConstants per call so debug-menu retuning
-- takes effect without a game restart and so values are correct even if this
-- file loads before base_modifier.lua sets the table.
local function CC()
	return _G.CSR_ItemConstants or {}
end

-- Special enemies that normally have armor/high resistance.
-- Bulldozers use "tank" as their tweak_table prefix (e.g. "tank", "tank_skull", "tank_medic").
local SPECIAL_SUBSTRINGS = { "taser", "cloaker", "tank", "captain", "sniper", "shield", "marshal" }

local function is_special_enemy(unit)
	if not unit or not unit:base() then
		return false
	end
	local td = unit:base()._tweak_table
	if type(td) ~= "string" then
		return false
	end
	for _, s in ipairs(SPECIAL_SUBSTRINGS) do
		if td:find(s) then
			return true
		end
	end
	return false
end

-- Build a col_ray that uses a REAL Body object from the target unit.
-- Vanilla copdamage calls body:position(), body:rotation(), body:name(), body:key()
-- which are all native C++ methods — a fake Lua table crashes with access violation.
local function make_fake_col_ray(unit)
	-- MUST copy position — m_pos() returns a reference to internal engine memory.
	-- If the unit dies mid-chain, that reference becomes a dangling pointer → access violation.
	local pos = Vector3(0, 0, 0)
	if unit:movement() and unit:movement().m_pos then
		mvector3.set(pos, unit:movement():m_pos())
	elseif unit:position() then
		mvector3.set(pos, unit:position())
	end
	-- Use the unit's first body (root body) — always valid on alive units.
	-- This satisfies vanilla + any mod (BeardLib etc.) that calls native Body methods.
	local body = unit:body(0)
	return {
		ray = Vector3(0, 0, -1),
		position = pos,
		normal = math_up,
		unit = unit,
		distance = 0,
		body = body,
	}
end

local ELECTRIC_EFFECT_DURATION = 0.6 -- seconds before effect is killed
-- Hard cap: sustained fire (LMG + 80% proc + 2 chains) can otherwise spawn
-- dozens of particles per second, each of which costs a World:effect_manager
-- spawn + a later fade_kill. Skip new spawns once the queue is saturated —
-- the player already sees plenty of shock fx.
local MAX_EFFECT_QUEUE = 16

-- Pending effects: {fx, kill_at}. Processed in on_damage (combat = frequent) and
-- on the death of the target unit via clbk_death hook.
_G.CSR_VinylEffectQueue = _G.CSR_VinylEffectQueue or {}
-- Directly hit units: excluded from all chains until 0.15s has passed.
-- Prevents multi-hit melee from chaining back into its own targets.
_G.CSR_VinylDirectHits = _G.CSR_VinylDirectHits or {}
_G.CSR_VinylDirectExpiry = _G.CSR_VinylDirectExpiry or 0

local function flush_vinyl_effects()
	local now = Application:time()
	-- Clear direct-hit list after 0.15s (covers multi-hit melee window)
	if now > _G.CSR_VinylDirectExpiry then
		_G.CSR_VinylDirectHits = {}
	end
	if #_G.CSR_VinylEffectQueue == 0 then
		return
	end
	local i = 1
	while i <= #_G.CSR_VinylEffectQueue do
		local entry = _G.CSR_VinylEffectQueue[i]
		if now >= entry.kill_at then
			pcall(function()
				World:effect_manager():fade_kill(entry.fx)
			end)
			table.remove(_G.CSR_VinylEffectQueue, i)
		else
			i = i + 1
		end
	end
end

local function spawn_electric_effect(unit)
	if not alive(unit) or not unit:movement() then
		return
	end
	if #_G.CSR_VinylEffectQueue >= MAX_EFFECT_QUEUE then
		return
	end
	pcall(function()
		local spine = unit:get_object(Idstring("Spine1"))
		if not spine then
			return
		end
		local effect = World:effect_manager():spawn({
			effect = Idstring("effects/payday2/particles/character/taser_hittarget"),
			parent = spine,
		})
		if effect then
			table.insert(_G.CSR_VinylEffectQueue, {
				fx = effect,
				kill_at = Application:time() + ELECTRIC_EFFECT_DURATION,
			})
		end
	end)
end

-- Squared distance between two Vector3 positions
local function pos_dist_sq(p1, p2)
	local dx = p1.x - p2.x
	local dy = p1.y - p2.y
	local dz = p1.z - p2.z
	return dx * dx + dy * dy + dz * dz
end

-- Anti-recursion guard: chain damage calls damage_bullet again, this prevents looping
_G.CSR_ViklundChaining = false

local function run_chain(original_damage, attacker_unit, weapon_unit, initial_target, stacks)
	-- Vanilla damage_bullet calls weapon_unit:base() unguarded in several places
	-- (is_category, get_name_id, weapon_tweak_data etc.). Validate or fall back.
	local weapon_ok = false
	if weapon_unit then
		pcall(function()
			weapon_ok = alive(weapon_unit) and weapon_unit:base() ~= nil
		end)
	end
	if not weapon_ok and attacker_unit then
		pcall(function()
			weapon_unit = attacker_unit:inventory():equipped_unit()
		end)
	end
	-- If still no valid weapon, bail — vanilla damage_bullet will crash without it.
	if not weapon_unit then
		return
	end

	-- Vanilla damage_bullet uses attack_data.origin in mvector3.distance (C++ function)
	-- for marked-enemy damage bonus. Missing origin = nil passed to C++ = access violation.
	local attacker_pos = Vector3(0, 0, 0)
	if alive(attacker_unit) then
		pcall(function()
			mvector3.set(attacker_pos, attacker_unit:position())
		end)
	end

	local c = CC()
	local radius = (c.viklund_radius_base or 500) + (stacks - 1) * (c.viklund_radius_step or 200)
	local enemy_mask = managers.slot:get_mask("enemies")
	local chain_dmg = original_damage * (c.viklund_chain_dmg_pct or 0.25)

	if not alive(initial_target) or not initial_target:movement() then
		return
	end
	local src_pos = initial_target:movement():m_pos()

	-- Find nearby enemies within radius
	local nearby = World:find_units_quick("sphere", src_pos, radius, enemy_mask)
	local candidates = {}
	for _, unit in ipairs(nearby) do
		if alive(unit) and unit ~= initial_target and not _G.CSR_VinylDirectHits[unit] then
			local dmg = unit:character_damage()
			if dmg and not dmg:dead() and unit:movement() then
				local d = pos_dist_sq(src_pos, unit:movement():m_pos())
				table.insert(candidates, { unit = unit, dist = d })
			end
		end
	end

	-- Sort by distance, pick closest CHAIN_COUNT
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

	for i = 1, math.min(c.viklund_chain_count or 2, #candidates) do
		local unit = candidates[i].unit
		-- Re-check alive + dead RIGHT before damage — graze/other hooks may have
		-- killed this unit between the candidate collection and now
		if alive(unit) and unit:character_damage() and not unit:character_damage():dead() then
			local target_dmg = is_special_enemy(unit) and (chain_dmg * (c.viklund_chain_spec_mult or 0.25)) or chain_dmg
			-- Wrap each chain target in its own pcall — if one crashes, others still fire
			local was_dead_before = unit:character_damage():dead()
			local ok = pcall(function()
				if not alive(unit) then
					return
				end
				local cdmg = unit:character_damage()
				if not cdmg or cdmg:dead() then
					return
				end
				if not unit:movement() then
					return
				end
				local col_ray = make_fake_col_ray(unit)
				-- body:name() is called unguarded at the top of vanilla damage_bullet.
				-- If unit:body(0) returned nil, skip this target to avoid C++ crash.
				if not col_ray.body then
					return
				end
				cdmg:damage_bullet({
					damage = target_dmg,
					attacker_unit = attacker_unit,
					weapon_unit = weapon_unit,
					variant = "bullet",
					col_ray = col_ray,
					origin = attacker_pos,
				})
			end)
			-- Safety net: if pcall FAILED and damage_bullet crashed after die()
			-- but before _on_damage_received, the enemy is _dead but AI never
			-- stopped. Only fire on failure to avoid double _on_damage_received.
			if
				not ok
				and not was_dead_before
				and alive(unit)
				and unit:character_damage()
				and unit:character_damage()._dead
			then
				pcall(function()
					unit:character_damage():_on_damage_received({
						attacker_unit = attacker_unit,
						variant = "bullet",
						result = { type = "death", variant = "bullet" },
					})
				end)
			end
			if alive(unit) then
				spawn_electric_effect(unit)
			end
		end
	end
end

-- Process effect queue every frame via PlayerDamage:update.
-- Registered only when loaded from playerdamage context (update exists there).
if required == "lib/units/beings/player/playerdamage" then
	Hooks:PostHook(PlayerDamage, "update", "CSR_ViklundVinyl_EffectFlush", function(self, unit, t, dt)
		flush_vinyl_effects()
	end)
end

local function on_damage(self, attack_data)
	if _G.CSR_ViklundChaining then
		return
	end
	if not CSR_ActiveBuffs or not CSR_ActiveBuffs.viklund_vinyl then
		return
	end
	if not attack_data or not attack_data.damage or attack_data.damage <= 0 then
		return
	end
	-- Vanilla damage_bullet/damage_melee early-return on corpses (self._dead),
	-- invulnerable targets, friendly fire, and immune attackers WITHOUT setting
	-- attack_data.result. Nil result => no real damage dealt => no chain.
	if not attack_data.result then
		return
	end
	if not attack_data.attacker_unit then
		return
	end
	if not attack_data.attacker_unit:base() then
		return
	end
	if not attack_data.attacker_unit:base().is_local_player then
		return
	end

	-- Disabled in stealth: chain damage would alert undetected enemies and break stealth.
	if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
		return
	end

	-- 80% proc chance per hit (fixed, does not scale with stacks)
	if math.random() > (CC().viklund_proc_chance or 0.80) then
		return
	end

	local stacks = CSR_ActiveBuffs.viklund_vinyl

	-- Mark this unit as directly hit so it's excluded from chain candidates
	_G.CSR_VinylDirectHits[self._unit] = true
	_G.CSR_VinylDirectExpiry = Application:time() + 0.15

	_G.CSR_ViklundChaining = true
	pcall(run_chain, attack_data.damage, attack_data.attacker_unit, attack_data.weapon_unit, self._unit, stacks)
	_G.CSR_ViklundChaining = false
end

if required == "lib/units/enemies/cop/copdamage" then
	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_ViklundVinyl_Bullet", on_damage)
	Hooks:PostHook(CopDamage, "damage_melee", "CSR_ViklundVinyl_Melee", on_damage)
end
