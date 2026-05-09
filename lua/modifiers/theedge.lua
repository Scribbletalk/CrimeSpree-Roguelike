-- THE EDGE - Emergency heal on cooldown when critically low HP
-- Trigger: HP drops below threshold OR lethal damage while cooldown is ready
-- Effect: restore HP + invulnerability window
-- Architecture: PreHook on _check_bleed_out (catches lethal hits, like Plush Shark)
--              + PostHook on damage_* (catches non-lethal drops below threshold)

if not RequiredScript then
	return
end

-- Debug-mode-gated logger. Hot paths (do_edge_heal, _check_bleed_out PreHook,
-- damage_* PostHooks) all funnel through CSR_log, and those fire on every hit
-- the local player takes during combat — leaving them unconditional would
-- write multiple lines per second to mods/logs/log.txt. Gating on debug_mode
-- keeps the bring-up diagnostics available when needed and silent otherwise.
local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR TheEdge] " .. tostring(msg))
	end
end

ModifierTheEdge = ModifierTheEdge or class(CSRBaseModifier)
ModifierTheEdge.desc_id = "csr_the_edge_desc"

-- Activation sound is loaded centrally by lua/core/sound_preloader.lua and
-- played via _G.CSR_PlaySound below.

-- Count stacks
local function get_edge_stacks()
	return CSR_CountStacks("player_the_edge_")
end

-- Only trigger for local player
local function is_local_player(self)
	local pu = managers.player and managers.player:player_unit()
	return pu and self._unit == pu
end

-- Check cooldown availability
local function is_cooldown_ready(self)
	local C = _G.CSR_ItemConstants or {}
	local cooldown = C.the_edge_cooldown or 60
	local now = TimerManager:game():time()
	if self._csr_edge_last_trigger and (now - self._csr_edge_last_trigger) < cooldown then
		return false
	end
	return true
end

-- Perform the heal and set invulnerability
local function do_edge_heal(self)
	local stacks = get_edge_stacks()
	if stacks <= 0 then
		return false
	end

	local C = _G.CSR_ItemConstants or {}
	local now = TimerManager:game():time()

	self._csr_edge_last_trigger = now

	-- Activation sound — 2D playback. Centralized loader handles buffer
	-- lifecycle; cleanup_old stops any previous play of this sound on rapid
	-- re-trigger.
	if _G.CSR_PlaySound then
		self._csr_edge_sound = _G.CSR_PlaySound("the_edge_activate", {
			volume_key = "the_edge_sound_volume",
			cleanup_old = self._csr_edge_sound,
		})
	end

	-- VHUDPlus: show cooldown timer
	local cooldown = C.the_edge_cooldown or 60
	if CSR_VHUDPlusEvent then
		CSR_VHUDPlusEvent("timed_buff", "activate", "csr_the_edge_cd", {
			t = now,
			duration = cooldown,
		})
	end
	if CSR_WFHudEvent then
		CSR_WFHudEvent("activate", "the_edge_cd", { duration = cooldown })
	end
	if CSR_PocoHudEvent then
		CSR_PocoHudEvent("activate", "the_edge_cd", { duration = cooldown })
	end

	local max_hp = self:_max_health()
	if not max_hp or max_hp <= 0 then
		return false
	end

	local heal_pct = C.the_edge_heal_pct or 0.20
	local heal_flat_base = C.the_edge_heal_flat or 20
	local heal_flat_extra = C.the_edge_heal_flat_extra or 40

	-- Calculate heal amount (flat HP is display units -> convert to internal)
	local display_scale = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 5
	local pct_heal = max_hp * heal_pct
	local flat_heal = (heal_flat_base + math.max(0, stacks - 1) * heal_flat_extra) / display_scale
	local total_heal = pct_heal + flat_heal

	local current_hp = self:get_real_health()
	-- Pass uncapped target so any overheal flows through DP's set_health
	-- interceptor and converts to temporary shields. Vanilla set_health
	-- clamps internally if DP isn't active, so this is safe either way.
	local new_hp = math.max(current_hp, 0) + total_heal
	self:set_health(new_hp)

	-- Invulnerability window
	local invuln_time = C.the_edge_invuln or 0.5
	self._csr_edge_invuln_end = now + invuln_time
	self._csr_edge_saved_hp = new_hp

	-- VHUDPlus: show brief invulnerability timer
	if CSR_VHUDPlusEvent then
		CSR_VHUDPlusEvent("timed_buff", "activate", "csr_the_edge_invuln", {
			t = now,
			duration = invuln_time,
		})
	end
	if CSR_WFHudEvent then
		CSR_WFHudEvent("activate", "the_edge_invuln", { duration = invuln_time })
	end
	if CSR_PocoHudEvent then
		CSR_PocoHudEvent("activate", "the_edge_invuln", { duration = invuln_time })
	end

	CSR_log(
		"TRIGGERED! Stacks: "
			.. stacks
			.. " healed to: "
			.. string.format("%.1f", new_hp * display_scale)
			.. " display HP, next in "
			.. (C.the_edge_cooldown or 60)
			.. "s"
	)
	return true
end

-- === LETHAL DAMAGE: PreHook on _check_bleed_out (same pattern as Plush Shark) ===
-- Fires when HP hits 0, BEFORE vanilla processes bleed-out
Hooks:PreHook(PlayerDamage, "_check_bleed_out", "CSR_TheEdge_BleedOut", function(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	if not is_local_player(self) then
		return
	end
	if not self.get_real_health then
		return
	end
	if self:get_real_health() > 0 then
		return
	end
	if not is_cooldown_ready(self) then
		return
	end

	if do_edge_heal(self) then
		CSR_log("Prevented bleed-out via _check_bleed_out hook")
		return false
	end
end)

-- === NON-LETHAL DAMAGE: PostHook on damage functions ===
-- Catches cases where HP drops below threshold but stays above 0
local function check_edge_trigger(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return
	end
	if not is_local_player(self) then
		return
	end
	if not self.get_real_health then
		return
	end

	local now = TimerManager:game():time()

	-- During invulnerability window: restore HP to saved amount
	if self._csr_edge_invuln_end and now < self._csr_edge_invuln_end then
		if self._csr_edge_saved_hp then
			self:set_health(self._csr_edge_saved_hp)
		end
		return
	end

	-- Skip if already dead/downed (handled by _check_bleed_out hook above)
	if self:get_real_health() <= 0 then
		return
	end

	if not is_cooldown_ready(self) then
		return
	end

	local stacks = get_edge_stacks()
	if stacks <= 0 then
		return
	end

	-- Check HP threshold
	local C = _G.CSR_ItemConstants or {}
	local current_hp = self:get_real_health()
	local max_hp = self:_max_health()
	if not max_hp or max_hp <= 0 then
		return
	end

	local threshold = C.the_edge_hp_threshold or 0.10
	if current_hp / max_hp >= threshold then
		return
	end

	do_edge_heal(self)
end

Hooks:PostHook(PlayerDamage, "damage_bullet", "CSR_TheEdge_Bullet", function(self)
	check_edge_trigger(self)
end)

Hooks:PostHook(PlayerDamage, "damage_melee", "CSR_TheEdge_Melee", function(self)
	check_edge_trigger(self)
end)

Hooks:PostHook(PlayerDamage, "damage_explosion", "CSR_TheEdge_Explosion", function(self)
	check_edge_trigger(self)
end)

-- Reset on mission start
Hooks:PostHook(PlayerDamage, "init", "CSR_TheEdge_Init", function(self)
	self._csr_edge_last_trigger = nil
	self._csr_edge_invuln_end = nil
	self._csr_edge_saved_hp = nil
end)
