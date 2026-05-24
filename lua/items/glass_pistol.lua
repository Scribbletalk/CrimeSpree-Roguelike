-- Glass Pistol (contraband) -- the classic glass-cannon trade: huge damage, but
-- a fraction of the survivability.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/glasscannon.lua was a thin passport stub; the real
-- mechanic lived spread across playermanager/raycastweapon/player_passives).
--
-- Four independent chain-wraps, all MULTIPLICATIVE (per stack):
--   * ranged damage  x DMG_PER_STACK^stacks  (RaycastWeaponBase:_get_current_damage)
--   * melee  damage  x DMG_PER_STACK^stacks  (BlackMarketManager:equipped_melee_weapon_damage_info)
--   * max health     x (1/DIV_PER_STACK)^stacks (PlayerManager:health_skill_multiplier)
--   * max armor      x (1/DIV_PER_STACK)^stacks (PlayerDamage:_max_armor)
--
-- 6.2's _max_armor anti-recursion guard is gone: it only mattered for the old
-- centralized stat-sync loop (set_armor -> _max_armor re-entry). The per-item
-- chain-wrap calls the captured orig (-> vanilla _raw_max_armor) directly, so
-- there is no self-recursion. Vanilla recomputes the reduced max on spawn.
--
-- Rule #13 ("applied last") no longer applies: in the per-item model every stat
-- item is its own wrap and stacks multiplicatively by nature; there is no single
-- additive accumulator to be the last term of.
--
-- Values mirror the 6.2 constants (glass_pistol_dmg_per_stack 1.75 /
-- glass_pistol_div_per_stack 2). Keep the localization fallback in sync (logbook).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local DMG_PER_STACK = 1.75
local DIV_PER_STACK = 2

-- managers.csr only while a run is active, else nil (shared bail helper).
local function run_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.is_run_active and mgr:is_run_active() then
		return mgr
	end
	return nil
end

_G.CSR.register_item({
	type = "glass_pistol",
	rarity = "contraband",
	name = "csr_logbook_glass_pistol_name",
	desc = "csr_item_glass_pistol_desc",
	full_desc = "csr_logbook_glass_pistol_effect",
	notes = "csr_logbook_glass_pistol_notes",
	icon = "csr_glass_pistol",

	hooks = {
		-- Ranged: multiply RaycastWeaponBase:_get_current_damage by DMG_PER_STACK^stacks.
		["lib/units/weapons/raycastweaponbase"] = function()
			if _G._CSR_GLASS_PISTOL_RANGED_HOOKED then
				return
			end
			_G._CSR_GLASS_PISTOL_RANGED_HOOKED = true
			local orig = RaycastWeaponBase._get_current_damage
			if not orig then
				return
			end
			function RaycastWeaponBase:_get_current_damage(...)
				local damage = orig(self, ...)
				if type(damage) ~= "number" then
					return damage
				end
				local mgr = run_mgr()
				if not mgr then
					return damage
				end
				local stacks = mgr:owned("glass_pistol")
				if stacks > 0 then
					damage = damage * (DMG_PER_STACK ^ stacks)
				end
				return damage
			end
		end,

		-- Melee: multiply BlackMarketManager:equipped_melee_weapon_damage_info by the
		-- same factor (dmg + dmg_effect). Only the local player calls this; networks
		-- via attack_data like every other melee item (Evidence Rounds, Jiro).
		["lib/managers/blackmarketmanager"] = function()
			if _G._CSR_GLASS_PISTOL_MELEE_HOOKED then
				return
			end
			_G._CSR_GLASS_PISTOL_MELEE_HOOKED = true
			local orig = BlackMarketManager.equipped_melee_weapon_damage_info
			if not orig then
				return
			end
			function BlackMarketManager:equipped_melee_weapon_damage_info(lerp_value)
				local dmg, dmg_effect = orig(self, lerp_value)
				local mgr = run_mgr()
				if not mgr then
					return dmg, dmg_effect
				end
				local stacks = mgr:owned("glass_pistol")
				if stacks > 0 and type(dmg) == "number" then
					local mul = DMG_PER_STACK ^ stacks
					dmg = dmg * mul
					if type(dmg_effect) == "number" then
						dmg_effect = dmg_effect * mul
					end
				end
				return dmg, dmg_effect
			end
		end,

		-- Max health: multiply PlayerManager:health_skill_multiplier by (1/DIV)^stacks.
		["lib/managers/playermanager"] = function()
			if _G._CSR_GLASS_PISTOL_HP_HOOKED then
				return
			end
			_G._CSR_GLASS_PISTOL_HP_HOOKED = true
			local orig = PlayerManager.health_skill_multiplier
			if not orig then
				return
			end
			function PlayerManager:health_skill_multiplier()
				local v = orig(self)
				local mgr = run_mgr()
				if not mgr or type(v) ~= "number" then
					return v
				end
				local stacks = mgr:owned("glass_pistol")
				if stacks > 0 then
					v = v * ((1 / DIV_PER_STACK) ^ stacks)
				end
				return v
			end
		end,

		-- Max armor: multiply PlayerDamage:_max_armor by (1/DIV)^stacks.
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_GLASS_PISTOL_ARMOR_HOOKED then
				return
			end
			_G._CSR_GLASS_PISTOL_ARMOR_HOOKED = true
			local orig = PlayerDamage._max_armor
			if not orig then
				return
			end
			function PlayerDamage:_max_armor()
				local v = orig(self)
				local mgr = run_mgr()
				if not mgr or type(v) ~= "number" or v <= 0 then
					return v
				end
				local stacks = mgr:owned("glass_pistol")
				if stacks > 0 then
					v = v * ((1 / DIV_PER_STACK) ^ stacks)
				end
				return v
			end
		end,
	},
})
