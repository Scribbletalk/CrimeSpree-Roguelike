-- Dearest Possession (rare) — overheal at full HP becomes a temporary shield.
-- Shield cap = base MaxArmor * 0.5 * stacks; decays in 5s ticks at 8.33% (1 stack drains ~30s).
-- Drains BEFORE base armor on incoming damage; displays in vanilla's absorb HUD chunk.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local CAP_PCT = 0.5
local DECAY_RATE = 0.01666
local DRAIN_INTERVAL = 5.0

_G.CSR.register_item({
	type = "dearest_possession",
	rarity = "rare",
	name = "csr_logbook_dearest_possession_name",
	desc = "csr_item_dearest_possession_desc",
	full_desc = "csr_logbook_dearest_possession_effect",
	notes = "csr_logbook_dearest_possession_notes",
	icon = "csr_dearest_possession",
	icon_scale = 1.0,

	hooks = {
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_DEAREST_HOOKED then
				return
			end
			_G._CSR_DEAREST_HOOKED = true

			-- Detect: catch overheal at full HP and bank the excess.
			local orig_set_health = PlayerDamage.set_health
			function PlayerDamage:set_health(health)
				if self._csr_dp_in_set_health then
					return orig_set_health(self, health)
				end
				local mgr = managers.csr
				if mgr and mgr.is_run_active and mgr:is_run_active() then
					local stacks = mgr:owned("dearest_possession")
					if stacks > 0 then
						local eff_max_hp = self:_max_health() * (self._max_health_reduction or 1)
						-- get_real_health()/get_real_armor() return nil until _health/_armor are first set:
						-- the spawn-time _regenerated -> set_health runs BEFORE _health exists. Skip the
						-- overheal-banking on that first set (cur_hp nil) and let vanilla initialise health.
						local cur_hp = self:get_real_health()
						if cur_hp and eff_max_hp and health > eff_max_hp then
							-- Catch-up heal (not actually full HP yet) — normal heal.
							if cur_hp < eff_max_hp - 0.01 then
								return orig_set_health(self, health)
							end
							-- Base armor must be full first.
							local max_armor = self:_max_armor()
							if (self:get_real_armor() or 0) < max_armor - 0.01 then
								self._csr_dp_in_set_health = true
								orig_set_health(self, eff_max_hp)
								self._csr_dp_in_set_health = false
								return
							end
							-- Bank excess into shield (capped).
							local cap = max_armor * CAP_PCT * stacks
							local cur = self._csr_dp_armor or 0
							local new_bonus = math.min(cap, cur + (health - eff_max_hp))
							if new_bonus > cur then
								-- Reset the drain metronome on the 0 → N edge.
								if cur <= 0 then
									self._csr_dp_drain_timer = 0
								end
								self._csr_dp_armor = new_bonus
							end
							self._csr_dp_in_set_health = true
							orig_set_health(self, eff_max_hp)
							self._csr_dp_in_set_health = false
							return
						end
					end
				end
				return orig_set_health(self, health)
			end

			-- Absorb: shield drains before base armor (all damage variants funnel here).
			Hooks:PreHook(PlayerDamage, "_calc_armor_damage", "CSR_Dearest_Absorb", function(self, attack_data)
				local bonus = self._csr_dp_armor or 0
				if bonus <= 0 or not attack_data or not attack_data.damage or attack_data.damage <= 0 then
					return
				end
				local absorbed = math.min(attack_data.damage, bonus)
				self._csr_dp_armor = bonus - absorbed
				attack_data.damage = attack_data.damage - absorbed
			end)

			-- Decay + HUD push. Self-gated on _csr_dp_armor > 0.
			Hooks:PostHook(PlayerDamage, "update", "CSR_Dearest_Decay", function(self, unit, t, dt)
				local bonus = self._csr_dp_armor
				if not bonus or bonus <= 0 then
					-- Hand absorb chunk back to vanilla (Maniac / Hostage Taker).
					if
						self._csr_dp_last_absorb
						and self._csr_dp_last_absorb > 0
						and managers.hud
						and managers.hud.set_absorb_active
					then
						local base_absorb = (
							managers.player
							and managers.player.damage_absorption
							and managers.player:damage_absorption()
						) or 0
						managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, base_absorb)
						self._csr_dp_last_absorb = base_absorb
					end
					return
				end

				self._csr_dp_drain_timer = (self._csr_dp_drain_timer or 0) + dt
				if self._csr_dp_drain_timer >= DRAIN_INTERVAL then
					self._csr_dp_drain_timer = self._csr_dp_drain_timer - DRAIN_INTERVAL
					local decayed = self:_max_armor() * DECAY_RATE * DRAIN_INTERVAL
					self._csr_dp_armor = math.max(0, bonus - decayed)
				end

				if managers.hud and managers.hud.set_absorb_active then
					local base_absorb = (
						managers.player
						and managers.player.damage_absorption
						and managers.player:damage_absorption()
					) or 0
					local new_absorb = base_absorb + self._csr_dp_armor
					if self._csr_dp_last_absorb ~= new_absorb then
						managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, new_absorb)
						self._csr_dp_last_absorb = new_absorb
					end
				end
			end)

			-- Reset per spawn.
			Hooks:PostHook(PlayerDamage, "init", "CSR_Dearest_Init", function(self)
				self._csr_dp_armor = 0
				self._csr_dp_drain_timer = 0
				self._csr_dp_last_absorb = nil
			end)
		end,
	},
})
