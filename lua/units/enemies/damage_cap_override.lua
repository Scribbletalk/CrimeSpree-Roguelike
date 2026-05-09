-- Crime Spree Roguelike - Remove Damage Cap (Direct Override)
-- Raises the vanilla damage clamp just before each hit so one-shot kills work at high CS levels.
--
-- Attacker-agnostic: hooks run on the TARGET enemy's CopDamage:damage_* methods,
-- so the cap removal applies to players, AI teammate bots, sentry guns, jokers,
-- and any other attacker that routes through `unit:character_damage():damage_*`.
--
-- Converts (Jokers) are excepted: the PreHook restores their vanilla caps from
-- the `__CSR_ORIG_*` backup saved by remove_damage_cap.lua, so Partners in Crime
-- balance still holds. Without that restore they'd die faster than vanilla
-- intends (see why: the init-time wipe nils the caps globally on the shared
-- _char_tweak, so early-exiting here would leave them uncapped).

if not RequiredScript then
	return
end

if CopDamage then
	-- Track original _HEALTH_INIT per unit so we can restore it after the bullet hook
	local saved_health_init = {}
	-- Track original _lower_health_percentage_limit (used by Phalanx, Captain,
	-- and LIES-added heavies to cap per-hit damage to a fraction of max HP).
	-- Neutralize during our damage call, restore after so vanilla phase
	-- mechanics (Captain second phase) still work.
	local saved_lower_limit = {}

	-- LOWER_HEALTH_PERCENTAGE_LIMIT is used by vanilla's Captain (phalanx_vip)
	-- as his shield-invulnerable + phase-transition mechanic. We detect that
	-- via FINAL_LOWER_HEALTH_PERCENTAGE_LIMIT (vanilla only sets this on
	-- phalanx_vip; no casual mod touches it) and also check the phalanx_vip
	-- tag as a fallback for mods that clone the tweak partially. Earlier
	-- versions tried `boss` / `miniboss` / `captain` tags, but grep of vanilla
	-- charactertweakdata confirms none of those strings are ever assigned to
	-- `.tags` — they could only match mods that happened to agree with us,
	-- so they were dead weight.
	local function is_protected(self)
		local tweak = self._char_tweak
		if not tweak then
			return false
		end
		if tweak.FINAL_LOWER_HEALTH_PERCENTAGE_LIMIT then
			return true
		end
		if tweak.tags then
			for _, tag in ipairs(tweak.tags) do
				if tag == "phalanx_vip" then
					return true
				end
			end
		end
		return false
	end

	local function neutralize_lower_limit(self, unit_key)
		if is_protected(self) then
			return
		end
		if self._lower_health_percentage_limit then
			saved_lower_limit[unit_key] = self._lower_health_percentage_limit
			self._lower_health_percentage_limit = nil
		end
	end

	local function restore_lower_limit(self, unit_key)
		if saved_lower_limit[unit_key] then
			self._lower_health_percentage_limit = saved_lower_limit[unit_key]
			saved_lower_limit[unit_key] = nil
		end
	end

	-- PreHook: raise _HEALTH_INIT and clamp values before damage is applied
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_RemoveDamageCap_Bullet", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if not attack_data then
			return
		end

		-- Convert path: temporarily restore vanilla caps on the shared tweak
		-- so Partners in Crime balance holds. PostHook wipes them back.
		if self._converted then
			if self._char_tweak.__CSR_CAPS_SAVED then
				self.__csr_convert_restore = {
					bullet = self._char_tweak.DAMAGE_CLAMP_BULLET,
					shock = self._char_tweak.DAMAGE_CLAMP_SHOCK,
					headshot = self._char_tweak.headshot_dmg_mul,
				}
				self._char_tweak.DAMAGE_CLAMP_BULLET = self._char_tweak.__CSR_ORIG_DAMAGE_CLAMP_BULLET
				self._char_tweak.DAMAGE_CLAMP_SHOCK = self._char_tweak.__CSR_ORIG_DAMAGE_CLAMP_SHOCK
				self._char_tweak.headshot_dmg_mul = self._char_tweak.__CSR_ORIG_HEADSHOT_DMG_MUL
			end
			return
		end

		local unit_key = tostring(self._unit:key())

		-- Temporarily inflate _HEALTH_INIT by 20% so the vanilla minimum-health limiter
		-- doesn't leave the enemy alive at 1 HP after an otherwise-lethal shot
		saved_health_init[unit_key] = self._HEALTH_INIT
		self._HEALTH_INIT = self._HEALTH_INIT * 1.2
		self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100

		-- Set the damage clamp just above current HP so any single hit can kill.
		-- _char_tweak is SHARED across all enemies of this character type, so we
		-- must restore these in the PostHook — otherwise the smart_cap leaks to
		-- the next hit (or stays leaked forever if the next PreHook early-exits).
		-- File #1 (remove_damage_cap.lua) usually leaves these as nil, so we
		-- use a flag-table instead of a nil-vs-value check to know we saved.
		self.__csr_saved_clamps = {
			bullet = self._char_tweak.DAMAGE_CLAMP_BULLET,
			shock = self._char_tweak.DAMAGE_CLAMP_SHOCK,
		}
		local smart_cap = math.ceil(self._health) + 1
		self._char_tweak.DAMAGE_CLAMP_BULLET = smart_cap
		self._char_tweak.DAMAGE_CLAMP_SHOCK = smart_cap

		-- Disable the headshot damage reduction on specials that normally cap it below 1
		if self._char_tweak.headshot_dmg_mul and self._char_tweak.headshot_dmg_mul < 1 then
			self._char_tweak.headshot_dmg_mul = 1
		end

		neutralize_lower_limit(self, unit_key)
	end)

	-- PostHook: restore original _HEALTH_INIT so other systems aren't affected
	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_RestoreHealthInit", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end

		-- Convert path: revert the shared tweak to its wiped state for non-converts.
		if self.__csr_convert_restore then
			self._char_tweak.DAMAGE_CLAMP_BULLET = self.__csr_convert_restore.bullet
			self._char_tweak.DAMAGE_CLAMP_SHOCK = self.__csr_convert_restore.shock
			self._char_tweak.headshot_dmg_mul = self.__csr_convert_restore.headshot
			self.__csr_convert_restore = nil
			return
		end

		local unit_key = tostring(self._unit:key())
		if saved_health_init[unit_key] then
			self._HEALTH_INIT = saved_health_init[unit_key]
			self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100
			saved_health_init[unit_key] = nil
		end
		if self.__csr_saved_clamps then
			self._char_tweak.DAMAGE_CLAMP_BULLET = self.__csr_saved_clamps.bullet
			self._char_tweak.DAMAGE_CLAMP_SHOCK = self.__csr_saved_clamps.shock
			self.__csr_saved_clamps = nil
		end
		restore_lower_limit(self, unit_key)
	end)

	-- Raise explosion clamp before each explosion hit.
	-- explosion_damage_mul is applied AFTER the clamp, so the cap must be raised
	-- proportionally: cap = ceil(health / mul) + 1 ensures (cap * mul) > health.
	Hooks:PreHook(CopDamage, "damage_explosion", "CSR_RemoveDamageCap_Explosion", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if self._converted then
			if self._char_tweak.__CSR_CAPS_SAVED then
				self.__csr_convert_restore_explosion = { value = self._char_tweak.DAMAGE_CLAMP_EXPLOSION }
				self._char_tweak.DAMAGE_CLAMP_EXPLOSION = self._char_tweak.__CSR_ORIG_DAMAGE_CLAMP_EXPLOSION
			end
			return
		end
		local mul = (self._char_tweak.damage and self._char_tweak.damage.explosion_damage_mul) or 1
		local smart_cap = math.ceil(self._health / mul) + 1
		self.__csr_saved_clamp_explosion = { value = self._char_tweak.DAMAGE_CLAMP_EXPLOSION }
		self._char_tweak.DAMAGE_CLAMP_EXPLOSION = smart_cap
		neutralize_lower_limit(self, tostring(self._unit:key()))
	end)

	Hooks:PostHook(CopDamage, "damage_explosion", "CSR_RestoreLowerLimit_Explosion", function(self)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if self.__csr_convert_restore_explosion then
			self._char_tweak.DAMAGE_CLAMP_EXPLOSION = self.__csr_convert_restore_explosion.value
			self.__csr_convert_restore_explosion = nil
			return
		end
		if self.__csr_saved_clamp_explosion then
			self._char_tweak.DAMAGE_CLAMP_EXPLOSION = self.__csr_saved_clamp_explosion.value
			self.__csr_saved_clamp_explosion = nil
		end
		restore_lower_limit(self, tostring(self._unit:key()))
	end)

	-- Raise melee clamp before each melee hit
	Hooks:PreHook(CopDamage, "damage_melee", "CSR_RemoveDamageCap_Melee", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if self._converted then
			if self._char_tweak.__CSR_CAPS_SAVED then
				self.__csr_convert_restore_melee = { value = self._char_tweak.DAMAGE_CLAMP_MELEE }
				self._char_tweak.DAMAGE_CLAMP_MELEE = self._char_tweak.__CSR_ORIG_DAMAGE_CLAMP_MELEE
			end
			return
		end
		local smart_cap = math.ceil(self._health) + 1
		self.__csr_saved_clamp_melee = { value = self._char_tweak.DAMAGE_CLAMP_MELEE }
		self._char_tweak.DAMAGE_CLAMP_MELEE = smart_cap
		neutralize_lower_limit(self, tostring(self._unit:key()))
	end)

	Hooks:PostHook(CopDamage, "damage_melee", "CSR_RestoreLowerLimit_Melee", function(self)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if self.__csr_convert_restore_melee then
			self._char_tweak.DAMAGE_CLAMP_MELEE = self.__csr_convert_restore_melee.value
			self.__csr_convert_restore_melee = nil
			return
		end
		if self.__csr_saved_clamp_melee then
			self._char_tweak.DAMAGE_CLAMP_MELEE = self.__csr_saved_clamp_melee.value
			self.__csr_saved_clamp_melee = nil
		end
		restore_lower_limit(self, tostring(self._unit:key()))
	end)

	-- Raise fire/DOT clamp before each fire tick.
	-- fire_damage_mul applied after clamp, same fix as explosion.
	Hooks:PreHook(CopDamage, "damage_fire", "CSR_RemoveDamageCap_Fire", function(self, attack_data)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if self._converted then
			if self._char_tweak.__CSR_CAPS_SAVED then
				self.__csr_convert_restore_fire = {
					fire = self._char_tweak.DAMAGE_CLAMP_FIRE,
					dot = self._char_tweak.DAMAGE_CLAMP_DOT,
				}
				self._char_tweak.DAMAGE_CLAMP_FIRE = self._char_tweak.__CSR_ORIG_DAMAGE_CLAMP_FIRE
				self._char_tweak.DAMAGE_CLAMP_DOT = self._char_tweak.__CSR_ORIG_DAMAGE_CLAMP_DOT
			end
			return
		end
		local mul = (self._char_tweak.damage and self._char_tweak.damage.fire_damage_mul) or 1
		local smart_cap = math.ceil(self._health / mul) + 1
		self.__csr_saved_clamp_fire = {
			fire = self._char_tweak.DAMAGE_CLAMP_FIRE,
			dot = self._char_tweak.DAMAGE_CLAMP_DOT,
		}
		self._char_tweak.DAMAGE_CLAMP_FIRE = smart_cap
		self._char_tweak.DAMAGE_CLAMP_DOT = smart_cap
		neutralize_lower_limit(self, tostring(self._unit:key()))
	end)

	Hooks:PostHook(CopDamage, "damage_fire", "CSR_RestoreLowerLimit_Fire", function(self)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if self.__csr_convert_restore_fire then
			self._char_tweak.DAMAGE_CLAMP_FIRE = self.__csr_convert_restore_fire.fire
			self._char_tweak.DAMAGE_CLAMP_DOT = self.__csr_convert_restore_fire.dot
			self.__csr_convert_restore_fire = nil
			return
		end
		if self.__csr_saved_clamp_fire then
			self._char_tweak.DAMAGE_CLAMP_FIRE = self.__csr_saved_clamp_fire.fire
			self._char_tweak.DAMAGE_CLAMP_DOT = self.__csr_saved_clamp_fire.dot
			self.__csr_saved_clamp_fire = nil
		end
		restore_lower_limit(self, tostring(self._unit:key()))
	end)
end
