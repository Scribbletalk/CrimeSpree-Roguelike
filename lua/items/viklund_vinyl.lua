-- Viklund's Vinyl (rare) — chance to chain damage to nearby enemies on hit.
-- Chain damage routes through new damage_bullet calls; see csr_damage_amplification_pattern.md.
-- The electric spark uses World:effect_manager() which doesn't replicate — only the
-- owner sees particles. Chain DAMAGE still syncs via vanilla networking.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local PROC_CHANCE = 0.80
local CHAIN_DMG_PCT = 0.20
local CHAIN_SPEC_MULT = 0.25
local CHAIN_COUNT = 2
local RADIUS_BASE = 500
local RADIUS_STEP = 200
local DIRECT_HIT_WINDOW = 0.15

local ELECTRIC_EFFECT_IDS = Idstring("effects/payday2/particles/character/taser_hittarget")
local ELECTRIC_SPINE_IDS = Idstring("Spine1")
local ELECTRIC_EFFECT_DURATION = 0.6
local MAX_CONCURRENT_FX = 16

-- File-locals shared by all hook closures.
local chaining = false
local direct_hits = {}
local direct_expiry = 0
local active_fx = 0
local fx_counter = 0

-- Reused across procs to avoid per-proc allocations in the per-hit path.
-- run_chain is never re-entrant (the `chaining` guard bails on_damage), so a single
-- pooled candidates array + a hoisted comparator are safe.
local candidates = {}
local function cmp_dist(a, b)
	return a.dist < b.dist
end
-- col_ray ray direction is read-only; share one constant like math.UP is shared for normal.
local RAY_DOWN = Vector3(0, 0, -1)

local SPECIAL_SUBSTRINGS = { "taser", "cloaker", "tank", "captain", "sniper", "shield", "marshal" }

local function is_special_enemy(unit)
	local base = unit and unit:base()
	local td = base and base._tweak_table
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

-- col_ray MUST carry a real Body (native methods called on it). Position is COPIED
-- because m_pos() returns engine memory that dangles if the unit dies mid-chain.
local function make_fake_col_ray(unit)
	local pos = Vector3(0, 0, 0)
	if unit:movement() and unit:movement().m_pos then
		mvector3.set(pos, unit:movement():m_pos())
	elseif unit:position() then
		mvector3.set(pos, unit:position())
	end
	return {
		ray = RAY_DOWN,
		position = pos,
		normal = math.UP,
		unit = unit,
		distance = 0,
		body = unit:body(0),
	}
end

local function pos_dist_sq(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz
end

-- Local-only cosmetic spark on chained enemies; looping particle needs fade_kill.
local function spawn_electric_effect(unit)
	if active_fx >= MAX_CONCURRENT_FX or not alive(unit) or not unit:movement() then
		return
	end
	pcall(function()
		local spine = unit:get_object(ELECTRIC_SPINE_IDS)
		if not spine then
			return
		end
		local fx = World:effect_manager():spawn({ effect = ELECTRIC_EFFECT_IDS, parent = spine })
		if not fx then
			return
		end
		active_fx = active_fx + 1
		fx_counter = fx_counter + 1
		DelayedCalls:Add("CSR_ViklundVinyl_FX_" .. fx_counter, ELECTRIC_EFFECT_DURATION, function()
			active_fx = active_fx - 1
			pcall(function()
				World:effect_manager():fade_kill(fx)
			end)
		end)
	end)
end

local function run_chain(original_damage, attacker_unit, weapon_unit, initial_target, stacks)
	-- Validate weapon_unit; vanilla damage_bullet dereferences weapon_unit:base().
	local weapon_ok = false
	if weapon_unit then
		pcall(function()
			weapon_ok = alive(weapon_unit) and weapon_unit:base() ~= nil
		end)
	end
	if not weapon_ok and alive(attacker_unit) then
		pcall(function()
			weapon_unit = attacker_unit:inventory():equipped_unit()
		end)
	end
	if not weapon_unit then
		return
	end

	-- attack_data.origin feeds a C++ distance call; nil crashes.
	local attacker_pos = Vector3(0, 0, 0)
	if alive(attacker_unit) then
		pcall(function()
			mvector3.set(attacker_pos, attacker_unit:position())
		end)
	end

	if not alive(initial_target) or not initial_target:movement() then
		return
	end
	local src_pos = initial_target:movement():m_pos()
	local radius = RADIUS_BASE + (stacks - 1) * RADIUS_STEP
	local chain_dmg = original_damage * CHAIN_DMG_PCT

	local n = 0
	for _, unit in ipairs(World:find_units_quick("sphere", src_pos, radius, managers.slot:get_mask("enemies"))) do
		if alive(unit) and unit ~= initial_target and not direct_hits[unit] then
			local cd = unit:character_damage()
			if cd and not cd:dead() and unit:movement() then
				n = n + 1
				local slot = candidates[n]
				if not slot then
					slot = {}
					candidates[n] = slot
				end
				slot.unit = unit
				slot.dist = pos_dist_sq(src_pos, unit:movement():m_pos())
			end
		end
	end
	-- Drop pooled slots beyond this proc's count so table.sort only ranks [1..n].
	for i = #candidates, n + 1, -1 do
		candidates[i] = nil
	end
	table.sort(candidates, cmp_dist)

	for i = 1, math.min(CHAIN_COUNT, #candidates) do
		local unit = candidates[i].unit
		if alive(unit) and unit:character_damage() and not unit:character_damage():dead() and unit:movement() then
			local dmg = is_special_enemy(unit) and (chain_dmg * CHAIN_SPEC_MULT) or chain_dmg
			pcall(function()
				local col_ray = make_fake_col_ray(unit)
				if not col_ray.body then
					return
				end
				unit:character_damage():damage_bullet({
					damage = dmg,
					attacker_unit = attacker_unit,
					weapon_unit = weapon_unit,
					variant = "bullet",
					col_ray = col_ray,
					origin = attacker_pos,
				})
			end)
			if alive(unit) then
				spawn_electric_effect(unit)
			end
		end
	end
end

local function on_damage(self, attack_data)
	if chaining then
		return
	end
	local mgr = managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end
	-- result == nil → vanilla's early-returns rejected the hit; no real damage = no chain.
	if not attack_data or not attack_data.result or not attack_data.damage or attack_data.damage <= 0 then
		return
	end
	local au = attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	if mgr:owned("viklund_vinyl") <= 0 then
		return
	end
	-- No chaining in stealth: it would alert.
	if managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode() then
		return
	end

	-- Lazily drop the stale direct-hit set (covers the multi-hit melee window).
	local now = Application:time()
	if now > direct_expiry then
		direct_hits = {}
	end

	if math.random() > PROC_CHANCE then
		return
	end

	direct_hits[self._unit] = true
	direct_expiry = now + DIRECT_HIT_WINDOW

	chaining = true
	pcall(run_chain, attack_data.damage, au, attack_data.weapon_unit, self._unit, mgr:owned("viklund_vinyl"))
	chaining = false
end

_G.CSR.register_item({
	type = "viklund_vinyl",
	rarity = "rare",
	name = "csr_logbook_viklund_vinyl_name",
	desc = "csr_item_viklund_vinyl_desc",
	full_desc = "csr_logbook_viklund_vinyl_effect",
	notes = "csr_logbook_viklund_vinyl_notes",
	icon = "csr_viklund_vinyl",
	icon_scale = 1.0,
	loc_macros = {
		proc_chance_pct = string.format("%g", PROC_CHANCE * 100),
		chain_count = CHAIN_COUNT,
		chain_dmg_pct = string.format("%g", CHAIN_DMG_PCT * 100),
		radius = string.format("%g", RADIUS_BASE / 100),
		radius_step = string.format("%g", RADIUS_STEP / 100),
	},

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_VIKLUND_HOOKED then
				return
			end
			_G._CSR_VIKLUND_HOOKED = true
			Hooks:PostHook(CopDamage, "damage_bullet", "CSR_ViklundVinyl_Bullet", on_damage)
			if CopDamage.damage_melee then
				Hooks:PostHook(CopDamage, "damage_melee", "CSR_ViklundVinyl_Melee", on_damage)
			end
		end,
	},
})
