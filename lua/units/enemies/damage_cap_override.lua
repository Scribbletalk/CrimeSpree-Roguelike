-- Per-hit removal of DAMAGE_CLAMP_BULLET/EXPLOSION/SHOCK and _lower_health_percentage_limit
-- so high-damage builds can one-shot tanky enemies. Clamps are saved+restored each hit
-- because _char_tweak is a shared table -- mutating it would leak to every enemy of that type.
--
-- PERF: Pre/Post fire on the same CopDamage instance atomically, so temp values are
-- stashed in self.__csr_* fields (NOT a module table keyed by tostring(unit:key())).
-- That removes 2 string allocs + 1 table alloc per bullet hit -> zero per-hit garbage.

if not RequiredScript then
	return
end

-- No-leak gate: CSR temp job active, but vanilla CS manager not active.
local function csr_heist_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

if CopDamage then
	-- Captain uses LOWER_HEALTH_PERCENTAGE_LIMIT as his shield/phase-transition; never neutralize it.
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

	local function neutralize_lower_limit(self)
		if is_protected(self) then
			return
		end
		if self._lower_health_percentage_limit then
			self.__csr_saved_lower = self._lower_health_percentage_limit
			self._lower_health_percentage_limit = nil
		end
	end

	local function restore_lower_limit(self)
		if self.__csr_saved_lower then
			self._lower_health_percentage_limit = self.__csr_saved_lower
			self.__csr_saved_lower = nil
		end
	end

	-- BULLET --------------------------------------------------------------------
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_RemoveDamageCap_Bullet", function(self, attack_data)
		if not csr_heist_active() or not attack_data then
			return
		end
		if self._converted then
			return -- converts keep vanilla caps
		end

		-- Inflate _HEALTH_INIT 20% to lift bullet's HP-granularity quantize ceiling and avoid off-by-1 kills.
		self.__csr_saved_hinit = self._HEALTH_INIT
		self._HEALTH_INIT = self._HEALTH_INIT * 1.2
		self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100

		self.__csr_clamp_bullet = self._char_tweak.DAMAGE_CLAMP_BULLET
		self.__csr_clamp_headshot = self._char_tweak.headshot_dmg_mul
		self.__csr_bullet_saved = true
		self._char_tweak.DAMAGE_CLAMP_BULLET = math.ceil(self._health) + 1
		if self._char_tweak.headshot_dmg_mul and self._char_tweak.headshot_dmg_mul < 1 then
			self._char_tweak.headshot_dmg_mul = 1
		end

		neutralize_lower_limit(self)
	end)

	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_RestoreDamageCap_Bullet", function(self)
		if not csr_heist_active() then
			return
		end
		if self.__csr_saved_hinit then
			self._HEALTH_INIT = self.__csr_saved_hinit
			self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100
			self.__csr_saved_hinit = nil
		end
		if self.__csr_bullet_saved then
			self._char_tweak.DAMAGE_CLAMP_BULLET = self.__csr_clamp_bullet
			self._char_tweak.headshot_dmg_mul = self.__csr_clamp_headshot
			self.__csr_bullet_saved = nil
			self.__csr_clamp_bullet = nil
			self.__csr_clamp_headshot = nil
		end
		restore_lower_limit(self)
	end)

	-- EXPLOSION -----------------------------------------------------------------
	-- explosion_damage_mul applies after the clamp, so scale the cap by 1/mul.
	Hooks:PreHook(CopDamage, "damage_explosion", "CSR_RemoveDamageCap_Explosion", function(self, attack_data)
		if not csr_heist_active() then
			return
		end
		if self._converted then
			return
		end
		local mul = (self._char_tweak.damage and self._char_tweak.damage.explosion_damage_mul) or 1
		self.__csr_clamp_exp = self._char_tweak.DAMAGE_CLAMP_EXPLOSION
		self.__csr_exp_saved = true
		self._char_tweak.DAMAGE_CLAMP_EXPLOSION = math.ceil(self._health / mul) + 1
		neutralize_lower_limit(self)
	end)

	Hooks:PostHook(CopDamage, "damage_explosion", "CSR_RestoreDamageCap_Explosion", function(self)
		if not csr_heist_active() then
			return
		end
		if self.__csr_exp_saved then
			self._char_tweak.DAMAGE_CLAMP_EXPLOSION = self.__csr_clamp_exp
			self.__csr_exp_saved = nil
			self.__csr_clamp_exp = nil
		end
		restore_lower_limit(self)
	end)

	-- MELEE ---------------------------------------------------------------------
	-- No flat melee clamp; only lower-health limit needs neutralizing.
	Hooks:PreHook(CopDamage, "damage_melee", "CSR_RemoveDamageCap_Melee", function(self, attack_data)
		if not csr_heist_active() then
			return
		end
		if self._converted then
			return
		end
		neutralize_lower_limit(self)
	end)

	Hooks:PostHook(CopDamage, "damage_melee", "CSR_RestoreDamageCap_Melee", function(self)
		if not csr_heist_active() then
			return
		end
		restore_lower_limit(self)
	end)

	-- FIRE ----------------------------------------------------------------------
	-- No flat fire clamp; only lower-health limit needs neutralizing.
	Hooks:PreHook(CopDamage, "damage_fire", "CSR_RemoveDamageCap_Fire", function(self, attack_data)
		if not csr_heist_active() then
			return
		end
		if self._converted then
			return
		end
		neutralize_lower_limit(self)
	end)

	Hooks:PostHook(CopDamage, "damage_fire", "CSR_RestoreDamageCap_Fire", function(self)
		if not csr_heist_active() then
			return
		end
		restore_lower_limit(self)
	end)

	-- SHOCK / SIMPLE ------------------------------------------------------------
	-- damage_simple (shock/electrocution + sniper-graze) has DAMAGE_CLAMP_SHOCK and
	-- the same _HEALTH_INIT quantize as bullet; mirror bullet hook, no headshot handling.
	Hooks:PreHook(CopDamage, "damage_simple", "CSR_RemoveDamageCap_Shock", function(self, attack_data)
		if not csr_heist_active() or not attack_data then
			return
		end
		if self._converted then
			return
		end

		self.__csr_saved_hinit = self._HEALTH_INIT
		self._HEALTH_INIT = self._HEALTH_INIT * 1.2
		self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100

		self.__csr_clamp_shock = self._char_tweak.DAMAGE_CLAMP_SHOCK
		self.__csr_shock_saved = true
		self._char_tweak.DAMAGE_CLAMP_SHOCK = math.ceil(self._health) + 1

		neutralize_lower_limit(self)
	end)

	Hooks:PostHook(CopDamage, "damage_simple", "CSR_RestoreDamageCap_Shock", function(self)
		if not csr_heist_active() then
			return
		end
		if self.__csr_saved_hinit then
			self._HEALTH_INIT = self.__csr_saved_hinit
			self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100
			self.__csr_saved_hinit = nil
		end
		if self.__csr_shock_saved then
			self._char_tweak.DAMAGE_CLAMP_SHOCK = self.__csr_clamp_shock
			self.__csr_shock_saved = nil
			self.__csr_clamp_shock = nil
		end
		restore_lower_limit(self)
	end)
end

csr_log("[CSR] damage_cap_override.lua loaded (per-hit enemy damage-cap removal)")
