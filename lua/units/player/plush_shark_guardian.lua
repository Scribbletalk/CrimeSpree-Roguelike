-- PLUSH SHARK Guardian - Custody prevention mechanic
-- Triggers ONLY on the last down before custody (next bleedout = custody).
-- When triggered:
-- 1. Cancels the bleedout (heals HP back to full)
-- 2. Restores 1 down (revives counter +1, so the player has a normal bleedout in reserve)
-- 3. Restores armor
-- 4. Grants invulnerability for 10+ seconds (linear per stack)
-- 5. BLOCKS Swan Song activation (takes priority over the perk)
-- 6. Recharges only when released from custody

if not RequiredScript then
	return
end

-- Activation sound is loaded centrally by lua/core/sound_preloader.lua and
-- played via _G.CSR_PlaySound below.

-- v2.50: CRITICAL - Save ModPath at MODULE LOAD TIME for the vignette texture
-- registration below. Other mods (ProjectCellBeta, BeardLib) overwrite global
-- ModPath AFTER our mod loads but BEFORE DelayedCalls callback executes.
local SAVED_MOD_PATH = ModPath

-- Register vignette texture via DB:create_entry (no BeardLib dependency)
pcall(function()
	local file = SAVED_MOD_PATH .. "assets/csr/guilt_vignette.texture"
	DB:create_entry(Idstring("texture"), Idstring("csr/guilt_vignette"), file)
end)

-- === GLOBAL STATE ===
CSR_PlushShark = CSR_PlushShark or {
	charge_available = false,
	invulnerability_end_time = 0,
	stacks = 0,
}

-- === STACK COUNT AND INITIALIZATION ===
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_PlushSharkInit", function(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		CSR_PlushShark.charge_available = false
		CSR_PlushShark.stacks = 0
		return
	end

	-- Count PLUSH SHARK stacks
	local shark_stacks = CSR_CountStacks("player_plush_shark_")
	local stacks = shark_stacks

	-- Initialize global state
	if stacks > 0 then
		CSR_PlushShark.charge_available = true
		CSR_PlushShark.invulnerability_end_time = 0
		CSR_PlushShark.stacks = stacks

		-- v2.50: Debug logging
	else
		CSR_PlushShark.charge_available = false
		CSR_PlushShark.stacks = 0
	end
end)

-- === BLOCK SWAN SONG WHEN PLUSH SHARK TRIGGERS ===
-- PreHook on activate_temporary_upgrade to block Swan Song
Hooks:PreHook(
	PlayerManager,
	"activate_temporary_upgrade",
	"CSR_PlushSharkBlockSwanSong",
	function(self, category, upgrade)
		-- Check flag: Plush Shark just triggered
		if _G.CSR_PlushSharkJustActivated then
			-- Block any temporary upgrades tied to Swan Song
			if
				category == "temporary"
				and (
					upgrade == "revive_health_boost" -- Swan Song health boost
					or upgrade == "berserker_damage_multiplier" -- Swan Song damage
					or upgrade == "revive_dmg_reduction"
				) -- Swan Song damage reduction
			then
				return false -- Abort activation
			end
		end
	end
)

-- === HOOK ON BLEED OUT (MOMENT OF GOING DOWN) ===
-- Hook the moment the player is about to fall rather than the damage itself.
-- Only triggers on the LAST DOWN BEFORE CUSTODY: get_revives() == 1 means
-- vanilla _check_bleed_out is about to decrement revives 1 → 0, which sets
-- _down_time = 0 in vanilla and routes the player straight to custody.
Hooks:PreHook(PlayerDamage, "_check_bleed_out", "CSR_PlushSharkGuardianBleedOut", function(self)
	-- Guard: charge must be available
	if not CSR_PlushShark.charge_available then
		return
	end

	-- Guard: player must be at 0 HP (about to bleed out)
	local current_hp = self:get_real_health()
	if current_hp > 0 then
		return
	end

	-- Guard: only trigger on the last down (next bleedout = custody)
	local current_revives = self:get_revives() or 0
	if current_revives ~= 1 then
		return
	end

	do
		-- CRITICAL: Set flag BEFORE anything else
		-- This blocks Swan Song from activating
		_G.CSR_PlushSharkJustActivated = true

		-- Reset flag after 0.2s (once all systems have processed the damage)
		DelayedCalls:Add("CSR_PlushSharkResetFlag", 0.2, function()
			_G.CSR_PlushSharkJustActivated = false
		end)

		-- 1. Restore HP (prevent going down) and armor
		local C = _G.CSR_ItemConstants or {}
		local max_hp = self:_max_health()
		local heal_amount = max_hp * (C.plush_shark_heal_pct or 1.00)
		self:set_health(heal_amount)

		-- Restore armor to full
		if C.plush_shark_restore_armor ~= false then
			local max_armor = self:_max_armor()
			self:set_armor(max_armor)
		end

		-- 1b. Restore 1 down: revives 1 → 2, capped at the player's max lives.
		-- Without this, vanilla never decrements (we cancelled the bleedout by healing),
		-- but the player would still be one tick away from custody on their next down.
		local max_lives = self._lives_init + (managers.player:upgrade_value("player", "additional_lives", 0) or 0)
		local new_revives = math.min(current_revives + 1, max_lives)
		self._revives = Application:digest_value(new_revives, true)
		if self._send_set_revives then
			self:_send_set_revives()
		end
		if managers.environment_controller and managers.environment_controller.set_last_life then
			managers.environment_controller:set_last_life(new_revives <= 1)
		end

		-- 2. Enable invulnerability
		local duration = (C.plush_shark_invuln_base or 10)
			+ (CSR_PlushShark.stacks - 1) * (C.plush_shark_invuln_extra or 20)
		CSR_PlushShark.invulnerability_end_time = TimerManager:game():time() + duration

		-- VHUDPlus: show invulnerability timer
		if CSR_VHUDPlusEvent then
			CSR_VHUDPlusEvent("timed_buff", "activate", "csr_plush_shark_invuln", {
				t = TimerManager:game():time(),
				duration = duration,
			})
		end
		if CSR_WFHudEvent then
			CSR_WFHudEvent("activate", "plush_shark_invuln", { duration = duration })
		end
		if CSR_PocoHudEvent then
			CSR_PocoHudEvent("activate", "plush_shark_invuln", { duration = duration })
		end

		-- 2.5. PLAY ACTIVATION SOUND — 2D (relative to listener, no 3D attenuation).
		-- Centralized loader picks a random variant; cleanup_old prevents
		-- the rare double-trigger from layering two plays.
		if _G.CSR_PlaySound then
			self._csr_plush_shark_sound = _G.CSR_PlaySound("plush_shark_activate", {
				volume_key = "plush_shark_sound_volume",
				cleanup_old = self._csr_plush_shark_sound,
			})
		end

		-- 3. Enable invulnerability visuals
		pcall(function()
			-- Visuals similar to Swan Song (for feedback)
			if managers.environment_controller and managers.environment_controller.set_bleedout_underlay then
				managers.environment_controller:set_bleedout_underlay(true)
			end
			if SoundDevice and SoundDevice.set_rtpc then
				SoundDevice:set_rtpc("downed_filter", 1)
			end

			-- Activate custom radial for Enhanced Vanilla HUD
			if managers.hud then
				-- NOTE: current must be < total to trigger the EVH effect
				managers.hud:set_teammate_custom_radial(HUDManager.PLAYER_PANEL, {
					current = duration,
					total = duration + 0.1,
				})
			end

			-- Blue pulsing vignette for duration of invulnerability
			local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
			if hud_script and hud_script.panel then
				local panel = hud_script.panel
				local old = panel:child("csr_plush_shark_vignette")
				if old then
					panel:remove(old)
				end

				local bm = panel:bitmap({
					name = "csr_plush_shark_vignette",
					texture = "csr/guilt_vignette",
					blend_mode = "add",
					color = Color(0, 0.4, 1),
					x = 0,
					y = 0,
					w = panel:w(),
					h = panel:h(),
					layer = 200,
				})

				-- Sine-wave pulse: alpha oscillates between 0.15 and 0.55
				bm:animate(function(o)
					local elapsed = 0
					while true do
						local dt = coroutine.yield()
						elapsed = elapsed + dt
						o:set_alpha(0.35 + 0.20 * math.sin(elapsed * math.pi * 2 / 1.5))
					end
				end)
			end

			self._csr_plush_shark_active = true
			self._csr_plush_shark_start_time = TimerManager:game():time()
			self._csr_plush_shark_duration = duration
		end)

		-- 4. Consume the charge
		CSR_PlushShark.charge_available = false
	end
end)

-- === INVULNERABILITY (BLOCK ALL DAMAGE) ===
-- Hook on _chk_can_take_dmg for full invulnerability
-- Handles BOTH Plush Shark and The Edge invulnerability windows
local original_chk_can_take_dmg = PlayerDamage._chk_can_take_dmg
_G.CSR_SafeOverride(PlayerDamage, "_chk_can_take_dmg", "Plush Shark", original_chk_can_take_dmg, function(self, ...)
	local current_time = TimerManager:game():time()

	-- If Plush Shark invulnerability is active, block all damage
	if CSR_PlushShark.invulnerability_end_time > current_time then
		return false
	end

	-- If The Edge invulnerability is active, block all damage
	if self._csr_edge_invuln_end and current_time < self._csr_edge_invuln_end then
		return false
	end

	return original_chk_can_take_dmg(self, ...)
end)

-- === CUSTODY SYSTEM (RECHARGE) ===

-- Method 1: Hook on PlayerDamage.revived
Hooks:PostHook(PlayerDamage, "revived", "CSR_PlushSharkCustodyRecharge", function(self, by_teammate)
	-- Guard: player must have PLUSH SHARK stacks
	if CSR_PlushShark.stacks == 0 then
		return
	end

	-- Guard: player was in custody (released, not revived by a teammate)
	if not by_teammate then
		-- Restore charge
		CSR_PlushShark.charge_available = true
		CSR_PlushShark.invulnerability_end_time = 0

		-- Clear active flag
		if self._csr_plush_shark_active then
			self._csr_plush_shark_active = false
			self._csr_plush_shark_duration = nil

			-- Remove blue vignette
			pcall(function()
				local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
				if hud_script and hud_script.panel then
					local v = hud_script.panel:child("csr_plush_shark_vignette")
					if v then
						hud_script.panel:remove(v)
					end
				end
			end)

			-- Cleanup sound source
			if self._csr_plush_shark_sound and not self._csr_plush_shark_sound:is_closed() then
				self._csr_plush_shark_sound:close()
				self._csr_plush_shark_sound = nil
			end
		end
	end
end)

-- === DISABLE VISUAL EFFECT WHEN INVULNERABILITY ENDS ===

Hooks:PostHook(PlayerDamage, "update", "CSR_PlushSharkUpdateVisuals", function(self, unit, t, dt)
	-- Guard: Plush Shark effect must be active
	if not self._csr_plush_shark_active then
		return
	end

	-- Update radial timer
	local current_time = TimerManager:game():time()
	local time_remaining = CSR_PlushShark.invulnerability_end_time - current_time

	if time_remaining > 0 then
		-- Update radial with remaining time
		pcall(function()
			if managers.hud then
				-- NOTE: current must be < total for EVH
				local total_duration = self._csr_plush_shark_duration or 10
				managers.hud:set_teammate_custom_radial(HUDManager.PLAYER_PANEL, {
					current = time_remaining,
					total = total_duration + 0.1, -- Ensure current < total
				})
			end
		end)
	else
		-- Disable visual effects (pcall for safety)
		pcall(function()
			-- Visual effects
			if
				managers
				and managers.environment_controller
				and managers.environment_controller.set_bleedout_underlay
			then
				managers.environment_controller:set_bleedout_underlay(false)
			end
			if SoundDevice and SoundDevice.set_rtpc then
				SoundDevice:set_rtpc("downed_filter", 0)
			end

			-- Disable Swan Song radial
			if managers.hud then
				managers.hud:set_teammate_custom_radial(HUDManager.PLAYER_PANEL, {
					current = 0,
					total = 0,
				})
			end

			-- Fade out blue vignette over 0.3 seconds then remove
			local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
			if hud_script and hud_script.panel then
				local v = hud_script.panel:child("csr_plush_shark_vignette")
				if v then
					local start_alpha = v:alpha()
					v:animate(function(o)
						local t = 0.3
						while t > 0 do
							local dt = coroutine.yield()
							t = math.max(t - dt, 0)
							o:set_alpha(t / 0.3 * start_alpha)
						end
					end)
					DelayedCalls:Add("CSR_PlushSharkVignetteRemove", 0.4, function()
						pcall(function()
							local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
							if s and s.panel then
								local p = s.panel:child("csr_plush_shark_vignette")
								if p then
									s.panel:remove(p)
								end
							end
						end)
					end)
				end
			end
		end)

		self._csr_plush_shark_active = false
		self._csr_plush_shark_duration = nil
	end
end)
