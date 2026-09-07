-- Tactical Pen (common): +damage to enemies near you, shown by a ground ring.
-- Target-side scaling on CopDamage, gated by local-player attacker + victim in RADIUS.
-- No networking - damage routes through vanilla. See csr_damage_amplification_pattern.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local RADIUS = 500 -- 5m (PD2 units: 1m = 100)
local BONUS = 0.13 -- +13% damage per stack (additive / linear)

-- Ring visual: flat white circle on the ground, built from line segments (Draw:pen ignores alpha).
local RING_ALPHA = 0.1 -- opacity_add blend
local RING_COLOR = { 1, 1, 1 } -- white
local RING_SEGMENTS = 64 -- circle smoothness
local RING_WIDTH = 2 -- line thickness
local RING_Z = 4 -- lift off the floor to avoid z-fighting

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

local function player_pos()
	local pu = managers.player and managers.player:player_unit()
	if not (alive(pu) and pu:movement()) then
		return nil
	end
	return pu:movement():m_pos()
end

-- Target-side amplifier: only my hits (is_local_player), only victims within RADIUS of me.
local function apply_tactical_pen(self, attack_data)
	if not attack_data or not attack_data.damage or attack_data.damage <= 0 then
		return
	end
	local au = attack_data.attacker_unit
	if not au or not alive(au) or not au:base() or au:base().is_local_player ~= true then
		return
	end
	local mgr = csr_mgr()
	if not mgr then
		return
	end
	local stacks = mgr:owned("tactical_pen")
	if stacks <= 0 then
		return
	end
	local victim = self._unit
	local center = player_pos()
	if not (center and alive(victim)) then
		return
	end
	if mvector3.distance(victim:position(), center) > RADIUS then
		return
	end
	attack_data.damage = attack_data.damage * (1 + BONUS * stacks)
end

-- Owner-local radius ring at the player's feet (math.cos/sin take DEGREES in Diesel).
local function draw_ring()
	local mgr = csr_mgr()
	if not mgr or (mgr:owned("tactical_pen") or 0) <= 0 then
		return
	end
	local center = player_pos()
	if not center then
		return
	end
	local brush = Draw:brush(Color(RING_ALPHA, RING_COLOR[1], RING_COLOR[2], RING_COLOR[3]))
	brush:set_blend_mode("opacity_add")
	local step = 360 / RING_SEGMENTS
	local prev
	for i = 0, RING_SEGMENTS do
		local a = i * step
		local p = center + Vector3(math.cos(a) * RADIUS, math.sin(a) * RADIUS, RING_Z)
		if prev then
			brush:line(prev, p, RING_WIDTH)
		end
		prev = p
	end
end

_G.CSR.register_item({
	type = "tactical_pen",
	rarity = "common",
	name = "csr_logbook_tactical_pen_name",
	desc = "csr_item_tactical_pen_desc",
	full_desc = "csr_logbook_tactical_pen_effect",
	notes = "csr_logbook_tactical_pen_notes",
	icon = "csr_tactical_pen",
	icon_scale = 0.85,

	-- $radius / $pct fill csr_logbook_tactical_pen_effect.
	loc_macros = {
		radius = string.format("%g", RADIUS / 100),
		pct = string.format("%g", BONUS * 100),
	},

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_TACTICAL_PEN_HOOKED then
				return
			end
			_G._CSR_TACTICAL_PEN_HOOKED = true
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_TacticalPen_Bullet", apply_tactical_pen)
			if CopDamage.damage_melee then
				Hooks:PreHook(CopDamage, "damage_melee", "CSR_TacticalPen_Melee", apply_tactical_pen)
			end
			if CopDamage.damage_dot then
				Hooks:PreHook(CopDamage, "damage_dot", "CSR_TacticalPen_Dot", apply_tactical_pen)
			end
			if CopDamage.damage_explosion then
				Hooks:PreHook(CopDamage, "damage_explosion", "CSR_TacticalPen_Explosion", apply_tactical_pen)
			end
		end,

		["lib/managers/playermanager"] = function()
			if _G._CSR_TACTICAL_PEN_RING_HOOKED then
				return
			end
			_G._CSR_TACTICAL_PEN_RING_HOOKED = true
			Hooks:Add("GameSetupUpdate", "CSR_TacticalPen_RingDraw", function()
				pcall(draw_ring)
			end)
		end,
	},
})
