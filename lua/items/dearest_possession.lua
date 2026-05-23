-- Dearest Possession (rare) -- healing received at full HP becomes a temporary shield.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/dearestpossession.lua). Four PlayerDamage hooks:
--   * set_health (raw chain-wrap -- Rule #1 return/value exception): when a heal
--     would push HP past the real max (and base armor is full), the excess is
--     capped off and banked into a temporary shield (self._csr_dp_armor) instead.
--   * _calc_armor_damage (PreHook): incoming damage drains the shield BEFORE the
--     white armor bar -- every damage variant funnels through here.
--   * update (PostHook): the shield decays in discrete 5s ticks and is pushed to
--     vanilla's absorb HUD chunk (guarded so set_absorb_active isn't 60Hz spam).
--   * init (PostHook): reset the shield on each player spawn (per-mission fresh).
--
-- Shield cap = base MaxArmor * cap_pct * stacks; per-tick decay = base MaxArmor *
-- decay_rate * 5s (8.33%/tick at the 6.2 constants -> 1-stack cap drains in ~30s).
-- "Full HP" = self:_max_health() * _max_health_reduction (vanilla's real cap; this
-- naturally accounts for Dog Tags' multiplier and any max-health reduction). 6.2's
-- captured-base-max globals (CSR_Original_*) aren't needed -- no ported item raises
-- MaxArmor, so current _max_armor() IS the base for the cap.
--
-- Deferred: the 6.2 HUDTeammate:_animate_update_absorb speed-up (faster chunk
-- catch-up). The shield still shows via the vanilla absorb chunk; it just animates
-- at vanilla's slower rate. Polish, like half_a_glass's package contour.
--
-- Values mirror the 6.2 constants (cap 0.5 / decay 0.01666 / interval 5).

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

	hooks = {
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_DEAREST_HOOKED then
				return
			end
			_G._CSR_DEAREST_HOOKED = true

			-- DETECTION: raw-wrap set_health to catch overheal at full HP and bank
			-- the excess as shield. orig = whatever set_health was at install time
			-- (so we chain other mods, not clobber them).
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
						if eff_max_hp and health > eff_max_hp then
							-- Catch-up heal (HP not actually full): normal heal, no shield.
							if self:get_real_health() < eff_max_hp - 0.01 then
								return orig_set_health(self, health)
							end
							-- Base armor must be full before banking shield (fix armor first).
							local max_armor = self:_max_armor()
							if self:get_real_armor() < max_armor - 0.01 then
								self._csr_dp_in_set_health = true
								orig_set_health(self, eff_max_hp)
								self._csr_dp_in_set_health = false
								return
							end
							-- Bank the excess into the shield (capped).
							local cap = max_armor * CAP_PCT * stacks
							local cur = self._csr_dp_armor or 0
							local new_bonus = math.min(cap, cur + (health - eff_max_hp))
							if new_bonus > cur then
								-- Reset the drain metronome on the 0 -> N edge so a small
								-- overheal gets a full tick of visibility before decay.
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

			-- ABSORPTION: shield drains before base armor (all damage variants
			-- funnel through _calc_armor_damage).
			Hooks:PreHook(PlayerDamage, "_calc_armor_damage", "CSR_Dearest_Absorb", function(self, attack_data)
				local bonus = self._csr_dp_armor or 0
				if bonus <= 0 or not attack_data or not attack_data.damage or attack_data.damage <= 0 then
					return
				end
				local absorbed = math.min(attack_data.damage, bonus)
				self._csr_dp_armor = bonus - absorbed
				attack_data.damage = attack_data.damage - absorbed
			end)

			-- DECAY + HUD: tick-based decay and push the amount to vanilla's absorb
			-- chunk. Self-gated on _csr_dp_armor > 0 (only set while owned/active).
			Hooks:PostHook(PlayerDamage, "update", "CSR_Dearest_Decay", function(self, unit, t, dt)
				local bonus = self._csr_dp_armor
				if not bonus or bonus <= 0 then
					-- Hand the absorb chunk back to vanilla (Maniac / Hostage Taker) once.
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

			-- Reset the shield on each player spawn.
			Hooks:PostHook(PlayerDamage, "init", "CSR_Dearest_Init", function(self)
				self._csr_dp_armor = 0
				self._csr_dp_drain_timer = 0
				self._csr_dp_last_absorb = nil
			end)
		end,
	},
})
