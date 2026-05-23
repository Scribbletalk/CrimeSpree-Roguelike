-- Pink Slip (uncommon) -- killing an enemy restores health.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Local-player-scoped (each peer heals its own player on its own kills), so
-- MP-symmetric.
--
-- Kill detection: PostHook on CopDamage's four damage_* paths, gated on
-- cop._dead + a once-per-corpse flag (cop._csr_pinkslip_kill) + the attacker
-- being the local player. The flag rides on the CopDamage instance and is GC'd
-- with the unit, so no global table or death-cleanup is needed.
--
-- Heal per kill = max_hp*base_pct + (base_flat + (stacks-1)*extra_flat) display
-- HP, the flat part /display-scale to internal units. Values mirror the 6.2
-- register line (base_pct 0.01 / base_flat 4 / extra_flat 6).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local BASE_PCT = 0.01
local BASE_FLAT = 4
local EXTRA_FLAT = 6

local function apply_kill_heal(mgr, stacks)
	local pu = managers.player and managers.player:player_unit()
	if not pu or not alive(pu) then
		return
	end
	local dmg = pu:character_damage()
	if not dmg or not dmg._max_health then
		return
	end
	local scale = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local max_hp = dmg:_max_health()
	local heal = max_hp * BASE_PCT + (BASE_FLAT + (stacks - 1) * EXTRA_FLAT) / scale
	if heal > 0 then
		dmg:set_health(dmg:get_real_health() + heal)
		if mgr:debug_enabled() then
			mgr:debug_log(string.format("pink_slip heal +%.2f (internal) on kill", heal))
		end
	end
end

local function on_enemy_damage(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return
	end
	if not cop._dead or cop._csr_pinkslip_kill then
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
	cop._csr_pinkslip_kill = true
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

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_PINK_SLIP_HOOKED then
				return
			end
			_G._CSR_PINK_SLIP_HOOKED = true
			Hooks:PostHook(CopDamage, "damage_bullet", "CSR_PinkSlip_Bullet", on_enemy_damage)
			if CopDamage.damage_melee then
				Hooks:PostHook(CopDamage, "damage_melee", "CSR_PinkSlip_Melee", on_enemy_damage)
			end
			if CopDamage.damage_explosion then
				Hooks:PostHook(CopDamage, "damage_explosion", "CSR_PinkSlip_Explosion", on_enemy_damage)
			end
			if CopDamage.damage_dot then
				Hooks:PostHook(CopDamage, "damage_dot", "CSR_PinkSlip_Dot", on_enemy_damage)
			end
		end,
	},
})
