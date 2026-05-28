-- Crime Spree Roguelike -- Remove Enemy Damage Cap.
--
-- During a CSR heist, lift the per-hit caps that stop high-damage builds from
-- one-shotting tanky enemies, so the per-rank damage scaling (rank_passives.lua)
-- actually pays off. Two distinct vanilla caps, both applied inside CopDamage's
-- damage_* methods and verified against the source:
--
--   1. DAMAGE_CLAMP_BULLET / DAMAGE_CLAMP_EXPLOSION / DAMAGE_CLAMP_SHOCK -- a flat
--      math.min on the incoming damage (copdamage.lua damage_bullet:671,
--      damage_explosion:2086, damage_simple:2242 -- damage_simple is the
--      shock/electrocution + sniper-graze path). We raise the TARGET's clamp to
--      ~(health + 1) just before the hit so any single shot/blast/zap can be
--      lethal, then restore it right after.
--      NOTE: DAMAGE_CLAMP_MELEE / _FIRE / _DOT do NOT exist in this build -- a
--      grep of the whole lib tree finds them read nowhere -- so melee/fire/dot
--      have no flat clamp to lift (the 6.2 code that set them was dead writes).
--
--   2. _lower_health_percentage_limit (from char_tweak.LOWER_HEALTH_PERCENTAGE_LIMIT)
--      -- caps a hit so the enemy can't drop below a fraction of max HP
--      (_apply_min_health_limit, called by EVERY damage_* method: bullet 758,
--      fire 1854, dot 1971, explosion 2113, simple 2249, melee 2736). This is the
--      real one-shot blocker for melee/fire. We neutralize it per-hit on all five
--      hooked paths and restore after.
--
-- self._char_tweak is the SHARED tweak_data.character[name] table (same ref as
-- self._unit:base():char_tweak() -- CopDamage/CopBase init both read
-- tweak_data.character[tweak_table]). So clamps MUST be saved + restored per-hit
-- or they leak to the next enemy of that type. The save tables double as the
-- "was saved" flag so a genuine nil clamp restores correctly.
--
-- Two exceptions, both preserving vanilla balance:
--   * Converts (Jokers): early-return, leaving vanilla caps untouched (Partners
--     in Crime balance). With no global wipe their caps are already vanilla, so
--     there is nothing to restore.
--   * Captain / phalanx_vip: _lower_health_percentage_limit is his shield-invuln
--     + phase-transition mechanic; never neutralize it (is_protected).
--
-- Attacker-agnostic (hooks the TARGET's CopDamage) so it covers players, AI
-- teammate bots, sentries, jokers. Role-agnostic too: the cap is applied on
-- whichever machine runs damage_* (a client predicts + the host applies
-- authoritatively), so we raise it on both -- exactly like the original.
--
-- Ported from 6.2 (units/enemies/damage_cap_override.lua). The 6.2 companion that
-- wiped DAMAGE_CLAMP_* globally on CharacterTweakData:init was DROPPED: the
-- per-hit override is self-sufficient and leak-free, and dropping it removes the
-- init-only timing + difficulty-reapply + Global.crime_spree.in_progress gating
-- problems. Gate is the U1 no-leak job signal (csr_heist_active), not the
-- persisted is_active() flag (feedback_csr_only_no_vanilla_leak).

if not RequiredScript then
	return
end

-- CSR heist = the temp "crime_spree" job with vanilla Crime Spree NOT active --
-- the no-leak signal shared with combat_modifiers.lua / mission_lifecycle.lua.
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
	-- Per-unit backups for the per-hit save/restore (keyed by unit:key()).
	local saved_health_init = {}
	local saved_lower_limit = {}

	-- phalanx_vip (Captain) uses LOWER_HEALTH_PERCENTAGE_LIMIT as his shield-invuln
	-- + phase-transition mechanic. Detect via FINAL_LOWER_HEALTH_PERCENTAGE_LIMIT
	-- (vanilla sets it only on phalanx_vip) plus the phalanx_vip tag as a fallback
	-- for partial tweak clones.
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

	-- BULLET --------------------------------------------------------------------
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_RemoveDamageCap_Bullet", function(self, attack_data)
		if not csr_heist_active() or not attack_data then
			return
		end
		if self._converted then
			return -- converts keep vanilla caps
		end
		local unit_key = tostring(self._unit:key())

		-- damage_bullet quantizes damage into _HEALTH_GRANULARITY buckets via
		-- _HEALTH_INIT_PRECENT (copdamage.lua:756-757), and that math.clamp ceils a
		-- single hit at _HEALTH_INIT. Inflate _HEALTH_INIT 20% to lift that ceiling +
		-- give rounding headroom so an otherwise-lethal shot isn't left 1 HP short.
		saved_health_init[unit_key] = self._HEALTH_INIT
		self._HEALTH_INIT = self._HEALTH_INIT * 1.2
		self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100

		-- Clamp just above current HP so any single hit can kill. Save headshot_dmg_mul
		-- too (we drop a sub-1 reduction below) so nothing leaks past the heist.
		self.__csr_saved_clamps = {
			bullet = self._char_tweak.DAMAGE_CLAMP_BULLET,
			headshot = self._char_tweak.headshot_dmg_mul,
		}
		self._char_tweak.DAMAGE_CLAMP_BULLET = math.ceil(self._health) + 1
		if self._char_tweak.headshot_dmg_mul and self._char_tweak.headshot_dmg_mul < 1 then
			self._char_tweak.headshot_dmg_mul = 1
		end

		neutralize_lower_limit(self, unit_key)
	end)

	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_RestoreDamageCap_Bullet", function(self)
		if not csr_heist_active() then
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
			self._char_tweak.headshot_dmg_mul = self.__csr_saved_clamps.headshot
			self.__csr_saved_clamps = nil
		end
		restore_lower_limit(self, unit_key)
	end)

	-- EXPLOSION -----------------------------------------------------------------
	-- explosion_damage_mul is applied AFTER the clamp, so raise the cap
	-- proportionally: ceil(health / mul) + 1 ensures (cap * mul) > health.
	Hooks:PreHook(CopDamage, "damage_explosion", "CSR_RemoveDamageCap_Explosion", function(self, attack_data)
		if not csr_heist_active() then
			return
		end
		if self._converted then
			return
		end
		local mul = (self._char_tweak.damage and self._char_tweak.damage.explosion_damage_mul) or 1
		self.__csr_saved_clamp_explosion = { value = self._char_tweak.DAMAGE_CLAMP_EXPLOSION }
		self._char_tweak.DAMAGE_CLAMP_EXPLOSION = math.ceil(self._health / mul) + 1
		neutralize_lower_limit(self, tostring(self._unit:key()))
	end)

	Hooks:PostHook(CopDamage, "damage_explosion", "CSR_RestoreDamageCap_Explosion", function(self)
		if not csr_heist_active() then
			return
		end
		if self.__csr_saved_clamp_explosion then
			self._char_tweak.DAMAGE_CLAMP_EXPLOSION = self.__csr_saved_clamp_explosion.value
			self.__csr_saved_clamp_explosion = nil
		end
		restore_lower_limit(self, tostring(self._unit:key()))
	end)

	-- MELEE ---------------------------------------------------------------------
	-- No flat melee clamp in this build; the only per-hit cap is the lower-health
	-- limit, so just neutralize that (+ restore after).
	Hooks:PreHook(CopDamage, "damage_melee", "CSR_RemoveDamageCap_Melee", function(self, attack_data)
		if not csr_heist_active() then
			return
		end
		if self._converted then
			return
		end
		neutralize_lower_limit(self, tostring(self._unit:key()))
	end)

	Hooks:PostHook(CopDamage, "damage_melee", "CSR_RestoreDamageCap_Melee", function(self)
		if not csr_heist_active() then
			return
		end
		restore_lower_limit(self, tostring(self._unit:key()))
	end)

	-- FIRE ----------------------------------------------------------------------
	-- Same as melee: no flat fire clamp, only the lower-health limit to neutralize.
	Hooks:PreHook(CopDamage, "damage_fire", "CSR_RemoveDamageCap_Fire", function(self, attack_data)
		if not csr_heist_active() then
			return
		end
		if self._converted then
			return
		end
		neutralize_lower_limit(self, tostring(self._unit:key()))
	end)

	Hooks:PostHook(CopDamage, "damage_fire", "CSR_RestoreDamageCap_Fire", function(self)
		if not csr_heist_active() then
			return
		end
		restore_lower_limit(self, tostring(self._unit:key()))
	end)

	-- SHOCK / SIMPLE ------------------------------------------------------------
	-- damage_simple is the shock/electrocution (+ sniper-graze) path. It DOES have
	-- a flat clamp (DAMAGE_CLAMP_SHOCK, 2242) plus the same _HEALTH_INIT quantize
	-- (2246-2248) as bullet, so mirror the bullet hook: inflate _HEALTH_INIT for
	-- rounding headroom, raise the clamp to ~(health + 1), neutralize lower-limit.
	-- No headshot handling -- damage_simple has none.
	Hooks:PreHook(CopDamage, "damage_simple", "CSR_RemoveDamageCap_Shock", function(self, attack_data)
		if not csr_heist_active() or not attack_data then
			return
		end
		if self._converted then
			return
		end
		local unit_key = tostring(self._unit:key())

		saved_health_init[unit_key] = self._HEALTH_INIT
		self._HEALTH_INIT = self._HEALTH_INIT * 1.2
		self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100

		self.__csr_saved_clamp_shock = { value = self._char_tweak.DAMAGE_CLAMP_SHOCK }
		self._char_tweak.DAMAGE_CLAMP_SHOCK = math.ceil(self._health) + 1

		neutralize_lower_limit(self, unit_key)
	end)

	Hooks:PostHook(CopDamage, "damage_simple", "CSR_RestoreDamageCap_Shock", function(self)
		if not csr_heist_active() then
			return
		end
		local unit_key = tostring(self._unit:key())
		if saved_health_init[unit_key] then
			self._HEALTH_INIT = saved_health_init[unit_key]
			self._HEALTH_INIT_PRECENT = self._HEALTH_INIT / 100
			saved_health_init[unit_key] = nil
		end
		if self.__csr_saved_clamp_shock then
			self._char_tweak.DAMAGE_CLAMP_SHOCK = self.__csr_saved_clamp_shock.value
			self.__csr_saved_clamp_shock = nil
		end
		restore_lower_limit(self, unit_key)
	end)
end

csr_log("[CSR] damage_cap_override.lua loaded (per-hit enemy damage-cap removal)")
