-- Viklund's Vinyl (rare) -- a hit has a chance to chain damage to nearby enemies.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/viklundvinyl.lua). On a local-player hit that dealt
-- real damage, PROC_CHANCE (fixed, doesn't scale) to chain: find the CHAIN_COUNT
-- nearest living enemies within radius (radius grows per stack) and deal
-- chain_dmg_pct of the original damage to each (specials take an extra cut). The
-- chain damage is routed through vanilla CopDamage:damage_bullet with the local
-- player as attacker, so it goes over the vanilla net like a normal bullet
-- (MP-safe, same pattern as Bonnie/Rebar) -- never :die() directly.
--
-- The fake col_ray MUST carry a REAL Body (unit:body(0)); vanilla damage_bullet
-- calls native body:name()/position()/key() and a plain Lua table crashes.
--
-- Deferred: the 6.2 electric "taser_hittarget" spark on chained enemies (and its
-- per-frame effect-queue/flush). That's a known vanilla particle but it isn't in
-- the extracted-asset set I can verify, so it's left out for now (polish, like
-- half_a_glass's contour). The chain damage works without it.
--
-- Values mirror the 6.2 constants except chain damage, rebalanced down to 0.20
-- (was 0.25) for U1 (proc 0.80 / chain 0.20 / count 2 / radius 500cm +200/stack /
-- special cut 0.25). Keep the localization fallback in sync (logbook display).

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

-- File-locals (the item file is dofile'd once, so these are shared by the hook
-- closures): anti-recursion guard + the just-directly-hit set (excluded from
-- chains so multi-hit melee can't chain back into its own targets).
local chaining = false
local direct_hits = {}
local direct_expiry = 0

-- Specials (armored / high-resist) take a reduced cut of the chain damage.
-- Bulldozers use the "tank" tweak_table prefix.
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

-- A col_ray carrying a REAL body from the unit (native methods are called on it).
-- Position is COPIED (m_pos returns a reference into engine memory that dangles if
-- the unit dies mid-chain).
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

local function pos_dist_sq(a, b)
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz
end

local function run_chain(original_damage, attacker_unit, weapon_unit, initial_target, stacks)
	-- Vanilla damage_bullet dereferences weapon_unit:base() unguarded; validate or
	-- fall back to the attacker's equipped weapon, else bail.
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

	-- damage_bullet feeds attack_data.origin to a C++ distance call; nil crashes.
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

	local candidates = {}
	for _, unit in ipairs(World:find_units_quick("sphere", src_pos, radius, managers.slot:get_mask("enemies"))) do
		if alive(unit) and unit ~= initial_target and not direct_hits[unit] then
			local cd = unit:character_damage()
			if cd and not cd:dead() and unit:movement() then
				table.insert(candidates, { unit = unit, dist = pos_dist_sq(src_pos, unit:movement():m_pos()) })
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)

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
		end
	end
end

local function on_damage(self, attack_data)
	if chaining then
		return
	end
	local mgr = managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
		return
	end
	-- Vanilla damage_*'s early-returns (corpse / invulnerable / friendly fire /
	-- immune) leave attack_data.result nil => no real damage => no chain.
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
	-- No chaining in stealth: it would alert undetected enemies.
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
