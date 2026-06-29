-- Glass Pistol (contraband) — glass cannon: huge damage, fraction of survivability.
-- Linear per stack: damage ×(2*stacks), health & armor ÷(2*stacks).
-- 1 pistol = ×2 / ÷2, 2 = ×4 / ÷4, 3 = ×6 / ÷6.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local DMG_MUL_PER_STACK = 2 -- linear damage factor per stack
local DIV_PER_STACK = 2 -- linear health/armor divisor per stack

local function run_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

-- Host-side AoE (explosion/fire/DOT) is simulated for the whole crew, so is_local_player can't
-- tell whose hit it is. Resolve the attacker's peer and read THAT peer's synced glass-pistol stacks
-- (item_count works for remote peers via _remote_peer_items). SP / no session: attacker is local.
local function attacker_stacks(mgr, attacker_unit)
	if not (attacker_unit and alive(attacker_unit)) then
		return 0
	end
	local sess = managers.network and managers.network:session()
	if not sess then
		return mgr:owned("glass_pistol")
	end
	local peer = sess:peer_by_unit(attacker_unit)
	if not peer then
		return 0
	end
	return mgr:item_count(peer:id(), "glass_pistol")
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

	-- $dmg_mul / $div_mul fill csr_logbook_glass_pistol_effect.
	loc_macros = {
		dmg_mul = DMG_MUL_PER_STACK,
		div_mul = DIV_PER_STACK,
	},

	-- Heister panel: glass cannon -- huge weapon damage, a fraction of the armor.
	-- Health is on-path (health_skill_multiplier) so the panel folds it automatically; only the
	-- off-path stats (armor + every weapon-damage class) are declared here.
	stat_preview = function(count)
		local mul = DMG_MUL_PER_STACK * count
		return {
			armor = 1 / (DIV_PER_STACK * count),
			damage_ranged = mul,
			damage_melee = mul,
			damage_throwable = mul,
		}
	end,

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
					damage = damage * (DMG_MUL_PER_STACK * stacks)
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
					local mul = DMG_MUL_PER_STACK * stacks
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
					v = v / (DIV_PER_STACK * stacks)
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
					v = v / (DIV_PER_STACK * stacks)
				end
				return v
			end
		end,

		-- Bows / crossbows + AoE. Arrows resolve to CopDamage:damage_bullet, bypassing the ranged
		-- _get_current_damage hook above; explosions/fire/DOT run host-side for the whole crew.
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_GLASS_PISTOL_COPDAMAGE_HOOKED then
				return
			end
			_G._CSR_GLASS_PISTOL_COPDAMAGE_HOOKED = true

			-- Bows / crossbows: attacker-side, gated on local player + a bow/crossbow weapon so guns
			-- (already scaled at _get_current_damage) aren't double-counted.
			Hooks:PreHook(CopDamage, "damage_bullet", "CSR_GlassPistol_Bow", function(_, attack_data)
				if not attack_data or type(attack_data.damage) ~= "number" or attack_data.damage <= 0 then
					return
				end
				local au = attack_data.attacker_unit
				if not (au and alive(au) and au:base() and au:base().is_local_player == true) then
					return
				end
				local wu = attack_data.weapon_unit
				if
					not (
						wu
						and alive(wu)
						and wu:base()
						and wu:base().is_category
						and wu:base():is_category("bow", "crossbow")
					)
				then
					return
				end
				local mgr = run_mgr()
				if not mgr then
					return
				end
				local stacks = mgr:owned("glass_pistol")
				if stacks > 0 then
					attack_data.damage = attack_data.damage * (DMG_MUL_PER_STACK * stacks)
				end
			end)

			-- Explosion / fire / DOT: host-only (a client would double-scale); attacker's own stacks.
			local function scale_aoe(_, attack_data)
				if not Network:is_server() then
					return
				end
				if not attack_data or type(attack_data.damage) ~= "number" or attack_data.damage <= 0 then
					return
				end
				local mgr = run_mgr()
				if not mgr then
					return
				end
				local stacks = attacker_stacks(mgr, attack_data.attacker_unit)
				if stacks > 0 then
					attack_data.damage = attack_data.damage * (DMG_MUL_PER_STACK * stacks)
				end
			end
			Hooks:PreHook(CopDamage, "damage_explosion", "CSR_GlassPistol_Explosion", scale_aoe)
			Hooks:PreHook(CopDamage, "damage_fire", "CSR_GlassPistol_Fire", scale_aoe)
			Hooks:PreHook(CopDamage, "damage_dot", "CSR_GlassPistol_Dot", scale_aoe)
		end,

		-- Sentry turrets fire via the sentry unit, not the player, so they bypass the bullet hook.
		-- Scale the sentry's own per-shot damage, gated on its owner being the local player
		-- (mirror of evidence_rounds.lua).
		["lib/units/weapons/sentrygunweapon"] = function()
			if _G._CSR_GLASS_PISTOL_SENTRY_HOOKED then
				return
			end
			_G._CSR_GLASS_PISTOL_SENTRY_HOOKED = true
			local orig = SentryGunWeapon._apply_dmg_mul
			if not orig then
				return
			end
			function SentryGunWeapon:_apply_dmg_mul(damage, col_ray, from_pos)
				local result = orig(self, damage, col_ray, from_pos)
				if type(result) ~= "number" then
					return result
				end
				local owner = self._owner
				if not (owner and alive(owner) and owner:base() and owner:base().is_local_player == true) then
					return result
				end
				local mgr = run_mgr()
				if not mgr then
					return result
				end
				local stacks = mgr:owned("glass_pistol")
				if stacks > 0 then
					result = result * (DMG_MUL_PER_STACK * stacks)
				end
				return result
			end
		end,
	},
})
