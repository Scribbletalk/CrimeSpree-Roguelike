-- Pink Slip (uncommon) -- killing an enemy restores health.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Local-player-scoped (each peer heals its own player on its own kills), so
-- MP-symmetric.
--
-- Kill detection: PostHook on CopDamage:die -- it fires exactly once per death,
-- from ANY cause (bullet/melee/fire/tase/...), carrying the killing blow's
-- attacker. Gated on that attacker being the local player. Using die (not the
-- four damage_* paths) is what makes this correct: damage_bullet early-returns
-- on a dead cop but its PostHook still runs, so the old approach healed when the
-- local player's later hit/DOT touched a corpse SOMEONE ELSE (a bot) killed.
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

local function on_enemy_die(_cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
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

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_PINK_SLIP_HOOKED then
				return
			end
			_G._CSR_PINK_SLIP_HOOKED = true
			Hooks:PostHook(CopDamage, "die", "CSR_PinkSlip_Kill", on_enemy_die)
		end,
	},
})
