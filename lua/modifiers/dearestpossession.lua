-- DEAREST POSSESSION - Overheal to temporary shield
-- When healed at full HP, excess healing converts to a temporary absorb shield.
-- Shield cap: 50% of base MaxArmor per stack.
-- Shield drains in discrete ticks (constant rate, independent of current value).
-- Damage CONSUMES the shield first; only the overflow hits base armor.
-- Visually: the absorb chunk on the armor radial shrinks while the white bar stays
-- full, until the shield is depleted.

if not RequiredScript then
	return
end

-- This file is hooked on TWO scripts (see mod.txt). Each load runs different code:
--   playerdamage -> PlayerDamage hooks (set_health override, _calc_armor_damage
--                   PreHook for shield-first absorption, update PostHook for decay).
--   hudteammate  -> override _animate_update_absorb to drain the shield chunk
--                   quickly instead of vanilla's ~1 unit/sec cap.
if RequiredScript == "lib/managers/hud/hudteammate" then
	-- Vanilla _animate_update_absorb uses lerp_speed = step_speed = 1, which caps
	-- the absorb-radial catch-up at ~1 unit/sec. Maniac/Hostage Taker absorb amounts
	-- rarely change so the cap doesn't hurt them, but Dearest Possession's shield
	-- drops every hit and decays every 5 s — at vanilla speeds the chunk visibly
	-- lags behind the actual shield value. Body is copied verbatim from
	-- pd2_source_code lib/managers/hud/hudteammate.lua line 2487, with the two
	-- speed locals bumped (10 / 1000 ≈ vanilla _update_armor_hud's bar lerp).
	if HUDTeammate and not HUDTeammate._csr_absorb_fast then
		HUDTeammate._csr_absorb_fast = true

		function HUDTeammate:_animate_update_absorb(
			o,
			radial_absorb_shield_name,
			radial_absorb_health_name,
			var_name,
			blink
		)
			repeat
				coroutine.yield()
			until alive(self._panel) and self[var_name] and self._armor_data and self._health_data

			local teammate_panel = self._panel:child("player")
			local radial_health_panel = self._radial_health_panel
			local radial_shield = radial_health_panel:child("radial_shield")
			local radial_health = radial_health_panel:child("radial_health")
			local radial_absorb_shield = radial_health_panel:child(radial_absorb_shield_name)
			local radial_absorb_health = radial_health_panel:child(radial_absorb_health_name)
			local radial_shield_rot = radial_shield:color().r
			local radial_health_rot = radial_health:color().r

			radial_absorb_shield:set_rotation((1 - radial_shield_rot) * 360)
			radial_absorb_health:set_rotation((1 - radial_health_rot) * 360)

			local current_absorb = 0
			local current_shield, current_health = nil
			-- CSR tuning: vanilla 1 / 1 was ~50 s for a 50-unit drop (way too slow),
			-- 100 / 10 felt instant, 40 / 8 still too fast. 10 / 3 lands at ~5 s for a
			-- 50-unit drop — slow enough to clearly read each hit eating into the
			-- shield. step_speed is the dominant knob (rate-limits the lerp result).
			local step_speed = 10
			local lerp_speed = 3
			local dt, update_absorb = nil
			local t = 0

			while alive(teammate_panel) do
				dt = coroutine.yield()

				if self[var_name] and self._armor_data and self._health_data then
					update_absorb = false
					current_shield = self._armor_data.current
					current_health = self._health_data.current

					if radial_shield:color().r ~= radial_shield_rot or radial_health:color().r ~= radial_health_rot then
						radial_shield_rot = radial_shield:color().r
						radial_health_rot = radial_health:color().r

						radial_absorb_shield:set_rotation((1 - radial_shield_rot) * 360)
						radial_absorb_health:set_rotation((1 - radial_health_rot) * 360)

						update_absorb = true
					end

					if current_absorb ~= self[var_name] then
						current_absorb = math.lerp(current_absorb, self[var_name], lerp_speed * dt)
						current_absorb = math.step(current_absorb, self[var_name], step_speed * dt)
						update_absorb = true
					end

					if blink then
						t = (t + dt * 0.5) % 1

						radial_absorb_shield:set_alpha(math.abs(math.sin(t * 180)) * 0.25 + 0.75)
						radial_absorb_health:set_alpha(math.abs(math.sin(t * 180)) * 0.25 + 0.75)
					end

					if update_absorb and current_absorb > 0 then
						local shield_ratio = current_shield == 0 and 0 or math.min(current_absorb / current_shield, 1)
						local health_ratio = current_health == 0 and 0
							or math.min((current_absorb - shield_ratio * current_shield) / current_health, 1)
						local shield = math.clamp(shield_ratio * radial_shield_rot, 0, 1)
						local health = math.clamp(health_ratio * radial_health_rot, 0, 1)

						radial_absorb_shield:set_color(Color(1, shield, 1, 1))
						radial_absorb_health:set_color(Color(1, health, 1, 1))
						radial_absorb_shield:set_visible(shield > 0)
						radial_absorb_health:set_visible(health > 0)
					end
				end
			end
		end
	end
	return
end

ModifierDearestPossession = ModifierDearestPossession or class(CSRBaseModifier)
ModifierDearestPossession.desc_id = "csr_dearest_possession_desc"

-- DECAY_RATE / cap are read from _G.CSR_ItemConstants in the hot path so debug-menu
-- retuning takes effect without a game restart.

-- == DETECTION: Override set_health to intercept ALL heal sources ==
-- set_health receives the raw (uncapped) value, cap happens inside vanilla.
-- If the intended new HP exceeds base max HP → overheal → convert excess to shield.
local original_set_health = PlayerDamage.set_health

_G.CSR_SafeOverride(PlayerDamage, "set_health", "Dearest Possession", original_set_health, function(self, health)
	if self._csr_dp_in_set_health then
		return original_set_health(self, health)
	end

	if CSR_ActiveBuffs and CSR_ActiveBuffs.dearest_possession then
		local base_fn = _G.CSR_Original_MaxHealth
		local base_max_hp = base_fn and (base_fn(self) * (self._max_health_reduction or 1))

		if base_max_hp and health > base_max_hp then
			-- Catch-up heal (HP wasn't full): route as normal heal, no shield gain.
			local current_hp = self:get_real_health()
			if current_hp < base_max_hp - 0.01 then
				original_set_health(self, health)
				return
			end

			-- Base armor must be FULL before granting shield.
			-- (Without this, shield could refill while base armor is broken — bypassing
			-- the "fix your armor first" pacing.)
			local base_max_armor = self:_max_armor()
			local current_armor = self:get_real_armor()
			if current_armor < base_max_armor - 0.01 then
				self._csr_dp_in_set_health = true
				original_set_health(self, base_max_hp)
				self._csr_dp_in_set_health = false
				return
			end

			local stacks = CSR_ActiveBuffs.dearest_possession
			local base_armor_for_cap = _G.CSR_Original_MaxArmor and _G.CSR_Original_MaxArmor(self) or base_max_armor
			local cap_pct = (_G.CSR_ItemConstants and _G.CSR_ItemConstants.dearest_armor_cap) or 0.5
			local shield_cap = base_armor_for_cap * cap_pct * stacks

			local current_bonus = self._csr_dp_armor or 0
			local excess = health - base_max_hp
			local new_bonus = math.min(shield_cap, current_bonus + excess)

			if new_bonus > current_bonus then
				-- Reset drain metronome on the 0 -> N activation edge so small
				-- per-kill overheals (Pink Slip) get one full tick of visibility
				-- before any reduction lands. Subsequent gains while shields are
				-- still up keep the existing countdown.
				if current_bonus <= 0 then
					self._csr_dp_drain_timer = 0
				end
				self._csr_dp_armor = new_bonus
			end

			-- Cap the heal at base max HP — overheal absorbed into shield.
			self._csr_dp_in_set_health = true
			original_set_health(self, base_max_hp)
			self._csr_dp_in_set_health = false
			return
		end
	end

	original_set_health(self, health)
end)

-- == DAMAGE ABSORPTION: shield drains BEFORE base armor ==
-- Every damage variant (bullet/melee/explosion/fire-hit) funnels through
-- _calc_armor_damage. Subtracting from _csr_dp_armor here, before vanilla calls
-- change_armor(-attack_data.damage), means the white armor bar stays untouched
-- until the shield is fully consumed.
Hooks:PreHook(PlayerDamage, "_calc_armor_damage", "CSR_DearestPossession_Absorb", function(self, attack_data)
	local dp_bonus = self._csr_dp_armor or 0
	if dp_bonus <= 0 or not attack_data or not attack_data.damage or attack_data.damage <= 0 then
		return
	end

	local incoming = attack_data.damage
	local absorbed = math.min(incoming, dp_bonus)
	self._csr_dp_armor = dp_bonus - absorbed
	attack_data.damage = incoming - absorbed
end)

-- == DECAY + HUD SHIELD VISUAL ==
-- PostHook on update handles shield decay (tick-based) and pushes the absorb
-- chunk amount to vanilla's pulsing-shield visual.
Hooks:PostHook(PlayerDamage, "update", "CSR_DearestPossession_Decay", function(self, unit, t, dt)
	local bonus = self._csr_dp_armor
	if not bonus or bonus <= 0 then
		-- Shield gone or never granted: clear the absorb override so vanilla
		-- (and other absorb sources like Maniac/Hostage Taker) own the chunk.
		if
			self._csr_dp_last_absorb
			and self._csr_dp_last_absorb > 0
			and managers.hud
			and managers.hud.set_absorb_active
		then
			local base_absorb = managers.player
					and managers.player.damage_absorption
					and managers.player:damage_absorption()
				or 0
			managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, base_absorb)
			self._csr_dp_last_absorb = base_absorb
		end
		return
	end

	-- Decay the shield linearly in DISCRETE TICKS every DRAIN_INTERVAL seconds.
	-- Per-tick chunk = `base_armor * decay_rate * DRAIN_INTERVAL`, independent of
	-- current value and stack count. Between ticks the shield is FROZEN.
	-- Default tuning: 5 s × 0.01666/s = 8.33 % of base MaxArmor per tick. 1-stack
	-- cap (50 % base) drains in 6 ticks = 30 s; each extra stack adds 30 s.
	local DRAIN_INTERVAL = 5.0
	self._csr_dp_drain_timer = (self._csr_dp_drain_timer or 0) + dt
	if self._csr_dp_drain_timer >= DRAIN_INTERVAL then
		self._csr_dp_drain_timer = self._csr_dp_drain_timer - DRAIN_INTERVAL
		local base_armor = _G.CSR_Original_MaxArmor and _G.CSR_Original_MaxArmor(self) or self:_max_armor()
		local decay_rate = (_G.CSR_ItemConstants and _G.CSR_ItemConstants.dearest_decay_rate) or 0.10
		local decayed = base_armor * decay_rate * DRAIN_INTERVAL
		self._csr_dp_armor = math.max(0, bonus - decayed)
	end

	-- Push the shield amount into vanilla's absorb pipeline so its
	-- _animate_update_absorb coroutine draws a properly-shaped, blinking
	-- chunk on the armor radial — same visual the Maniac perk produces.
	-- Only call when the value changes: HUDTeammate:set_absorb_active sends
	-- a network packet on every call, so a per-frame call would be 60 Hz spam.
	if managers.hud and managers.hud.set_absorb_active then
		local base_absorb = managers.player
				and managers.player.damage_absorption
				and managers.player:damage_absorption()
			or 0
		local new_absorb = base_absorb + self._csr_dp_armor
		if self._csr_dp_last_absorb ~= new_absorb then
			managers.hud:set_absorb_active(HUDManager.PLAYER_PANEL, new_absorb)
			self._csr_dp_last_absorb = new_absorb
		end
	end
end)

-- == INIT: Reset shield on player spawn ==
Hooks:PostHook(PlayerDamage, "init", "CSR_DearestPossession_Init", function(self)
	self._csr_dp_armor = 0
	self._csr_dp_drain_timer = 0
	self._csr_dp_last_absorb = nil
end)
