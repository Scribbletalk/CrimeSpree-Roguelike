-- Pink Slip (uncommon) — kills heal you.
-- Hook on CopDamage:die (one-shot per death, any cause) so a corpse-touching DOT
-- can't proc the heal — the old damage_* approach did.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BASE_PCT = 0.01

local function apply_kill_heal(mgr, stacks)
	if mgr:item_heal_blocked() then
		return
	end
	local pu = managers.player and managers.player:player_unit()
	if not pu or not alive(pu) then
		return
	end
	local dmg = pu:character_damage()
	if not dmg or not dmg._max_health then
		return
	end
	local max_hp = dmg:_max_health()
	-- Hyperbolic stacking: 1 stack = BASE_PCT, diminishing per stack, asymptote 100% max HP.
	local frac = (BASE_PCT * stacks) / (1 - BASE_PCT + BASE_PCT * stacks)
	local heal = max_hp * frac
	if heal > 0 then
		dmg:set_health(dmg:get_real_health() + heal)
		if mgr:debug_enabled() then
			mgr:debug_log(string.format("pink_slip heal +%.2f (internal) on kill", heal))
		end
	end
end

local function on_enemy_die(_cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	local stacks = mgr:owned("pink_slip")
	if stacks <= 0 then
		return
	end
	apply_kill_heal(mgr, stacks)
end

_G.CSR.register_item({
	type = "pink_slip",
	rarity = "uncommon",
	name = "csr_logbook_pink_slip_name",
	desc = "csr_item_pink_slip_desc",
	full_desc = "csr_logbook_pink_slip_effect",
	notes = "csr_logbook_pink_slip_notes",
	icon = "csr_pink_slip",
	icon_scale = 1.05,
	loc_macros = {
		base_pct = string.format("%g", BASE_PCT * 100),
	},

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_PINK_SLIP_HOOKED then
				return
			end
			_G._CSR_PINK_SLIP_HOOKED = true
			Hooks:PostHook(CopDamage, "die", "CSR_PinkSlip_Kill", on_enemy_die)
		end,

		-- MP guest: host-spawned enemies are husks whose die() OVERRIDES the parent, so the
		-- CopDamage:die PostHook never fires for the guest's own kills. Hook the husk too.
		["lib/units/enemies/cop/huskcopdamage"] = function()
			if _G._CSR_PINK_SLIP_HUSK_HOOKED then
				return
			end
			_G._CSR_PINK_SLIP_HUSK_HOOKED = true
			Hooks:PostHook(HuskCopDamage, "die", "CSR_PinkSlip_Kill_Husk", on_enemy_die)
		end,
	},
})
