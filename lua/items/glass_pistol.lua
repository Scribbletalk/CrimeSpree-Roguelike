-- Glass Pistol (contraband) — glass cannon: huge damage, fraction of survivability.
-- All four wraps multiply per stack (DMG_PER_STACK^stacks, (1/DIV)^stacks).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local DMG_PER_STACK = 1.75
local DIV_PER_STACK = 2

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
	icon_scale = 1.0,

	hooks = {
		-- Ranged damage.
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

		-- Melee damage.
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

		-- Max health.
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

		-- Max armor.
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
