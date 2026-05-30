-- The Edge (uncommon) — cooldown-gated emergency heal + brief invuln when HP
-- drops below a threshold (or a hit would be lethal).
-- Cross-item priority with Plush Shark: see csr_emergency_heal_priority.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local HP_THRESHOLD = 0.10
local HEAL_PCT = 0.20
local HEAL_FLAT = 20
local HEAL_FLAT_EXTRA = 40
local INVULN = 1.0
local COOLDOWN = 120

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

local function is_local_pd(self)
	local pu = managers.player and managers.player:player_unit()
	return pu and self._unit == pu
end

local function edge_cd_ready(self, now)
	local cd = self._csr_edge_cd
	return not cd or (now - cd) >= COOLDOWN
end

local function do_edge_heal(self, stacks, now)
	local max_hp = self:_max_health()
	if not max_hp or max_hp <= 0 then
		return false
	end
	-- Flat HP authored in display units; /scale → internal.
	local scale = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local pct_heal = max_hp * HEAL_PCT
	local flat_heal = (HEAL_FLAT + math.max(0, stacks - 1) * HEAL_FLAT_EXTRA) / scale
	local new_hp = math.max(self:get_real_health(), 0) + pct_heal + flat_heal
	self:set_health(new_hp)

	self._csr_edge_cd = now
	self._csr_edge_invuln_end = now + INVULN
	self._csr_edge_saved_hp = new_hp

	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("the_edge_activate", { volume = 1.0 })
	end
	local mgr = managers.csr
	if mgr and mgr:debug_enabled() then
		mgr:debug_log(string.format("the_edge heal -> %.1f internal HP (stacks=%d)", new_hp, stacks))
	end
	return true
end

_G.CSR.register_item({
	type = "the_edge",
	rarity = "uncommon",
	name = "csr_logbook_the_edge_name",
	desc = "csr_item_the_edge_desc",
	full_desc = "csr_logbook_the_edge_effect",
	notes = "csr_logbook_the_edge_notes",
	icon = "csr_the_edge",
	icon_scale = 1.0,

	hooks = {
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_THE_EDGE_HOOKED then
				return
			end
			_G._CSR_THE_EDGE_HOOKED = true

			-- Lethal down: heal BEFORE vanilla _check_bleed_out. Yield to an armed guardian.
			Hooks:PreHook(PlayerDamage, "_check_bleed_out", "CSR_Edge_BleedOut", function(self)
				local mgr = csr_mgr()
				if not mgr or not is_local_pd(self) or not self.get_real_health then
					return
				end
				if self:get_real_health() > 0 then
					return
				end
				if self._csr_guardian_armed and (self:get_revives() or 0) == 1 then
					return
				end
				local now = TimerManager:game():time()
				local stacks = mgr:owned("the_edge")
				if stacks > 0 and edge_cd_ready(self, now) then
					do_edge_heal(self, stacks, now)
				end
			end)

			-- Non-lethal: dropped below threshold but still alive. Also re-applies saved HP
			-- during an active window (covers DOT/fire slipping past _chk_can_take_dmg).
			local function on_damage(self)
				local mgr = csr_mgr()
				if not mgr or not is_local_pd(self) or not self.get_real_health then
					return
				end
				local now = TimerManager:game():time()
				if self._csr_edge_invuln_end and now < self._csr_edge_invuln_end then
					if self._csr_edge_saved_hp then
						self:set_health(self._csr_edge_saved_hp)
					end
					return
				end
				if self:get_real_health() <= 0 then
					return -- lethal path owns this
				end
				local max_hp = self:_max_health()
				if not max_hp or max_hp <= 0 then
					return
				end
				local ratio = self:get_real_health() / max_hp
				local stacks = mgr:owned("the_edge")
				if stacks > 0 and edge_cd_ready(self, now) and ratio < HP_THRESHOLD then
					do_edge_heal(self, stacks, now)
				end
			end
			Hooks:PostHook(PlayerDamage, "damage_bullet", "CSR_Edge_Bullet", on_damage)
			Hooks:PostHook(PlayerDamage, "damage_melee", "CSR_Edge_Melee", on_damage)
			Hooks:PostHook(PlayerDamage, "damage_explosion", "CSR_Edge_Explosion", on_damage)

			-- Invuln gate. Returning nothing keeps earlier hook's result (Plush's gate).
			Hooks:PostHook(PlayerDamage, "_chk_can_take_dmg", "CSR_Edge_Invuln", function(self)
				if self._csr_edge_invuln_end and TimerManager:game():time() < self._csr_edge_invuln_end then
					return false
				end
			end)

			Hooks:PostHook(PlayerDamage, "init", "CSR_Edge_Init", function(self)
				self._csr_edge_cd = nil
				self._csr_edge_invuln_end = nil
				self._csr_edge_saved_hp = nil
			end)
		end,
	},
})
