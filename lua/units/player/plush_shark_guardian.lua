-- PLUSH SHARK Guardian - Death prevention mechanic
-- When the player receives lethal damage:
-- 1. Cancels the damage
-- 2. Restores 20% HP
-- 3. Grants invulnerability for 10+ seconds
-- 4. BLOCKS Swan Song activation (takes priority over the perk)
-- 5. Recharges only when released from custody

if not RequiredScript then
	return
end



-- ==========================================
-- PLUSH SHARK SOUND LOADING (v2.50)
-- ==========================================
-- Load sound buffer ONCE at mod init, use during activation
-- v2.50: Save ModPath NOW before other mods overwrite it via DelayedCalls

_G.CSR_PlushSharkSoundBuffer = nil

-- v2.50: CRITICAL - Save ModPath at MODULE LOAD TIME
-- Other mods (ProjectCellBeta, BeardLib) overwrite global ModPath AFTER our mod loads
-- but BEFORE DelayedCalls callback executes
local SAVED_MOD_PATH = ModPath

-- Delayed load to ensure XAudio is available
DelayedCalls:Add("CSR_LoadPlushSharkSound", 1.0, function()

	local base_path = Application:base_path()

	-- Normalize base_path trailing separator
	if base_path and base_path:sub(-1) ~= "/" and base_path:sub(-1) ~= "\\" then
		base_path = base_path .. "/"
	end

	local relative_path = SAVED_MOD_PATH .. "assets/sounds/plush_shark_activate.ogg"
	local absolute_path = base_path .. relative_path


	-- Check file exists (binary mode for OGG file)
	local file_handle = io.open(absolute_path, "rb")
	if not file_handle then
		file_handle = io.open(relative_path, "rb")
		if not file_handle then
			return
		else
			file_handle:close()
		end
	else
		file_handle:close()
	end

	-- Load with XAudio
	if not (_G.blt and _G.blt.xaudio) then
		return
	end

	blt.xaudio.setup()

	-- Try loading buffer with ABSOLUTE path first
	local success, buffer = pcall(function()
		return XAudio.Buffer:new(absolute_path)
	end)

	if success and buffer then
		_G.CSR_PlushSharkSoundBuffer = buffer
	else

		-- Fallback: relative path
		local success2, buffer2 = pcall(function()
			return XAudio.Buffer:new(relative_path)
		end)

		if success2 and buffer2 then
			_G.CSR_PlushSharkSoundBuffer = buffer2
		else
		end
	end

end)

-- === GLOBAL STATE ===
CSR_PlushShark = CSR_PlushShark or {
	charge_available = false,
	invulnerability_end_time = 0,
	stacks = 0
}

-- === STACK COUNT AND INITIALIZATION ===
Hooks:PostHook(PlayerManager, "spawned_player", "CSR_PlushSharkInit", function(self)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		CSR_PlushShark.charge_available = false
		CSR_PlushShark.stacks = 0
		return
	end

	-- Count PLUSH SHARK stacks
	local stacks = 0
	local modifiers = managers.crime_spree:active_modifiers() or {}

	for _, mod in ipairs(modifiers) do
		if mod.id and string.find(mod.id, "player_plush_shark", 1, true) then
			stacks = stacks + 1
		end
	end

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
Hooks:PreHook(PlayerManager, "activate_temporary_upgrade", "CSR_PlushSharkBlockSwanSong", function(self, category, upgrade)
	-- Check flag: Plush Shark just triggered
	if _G.CSR_PlushSharkJustActivated then
		-- Block any temporary upgrades tied to Swan Song
		if category == "temporary" and (
			upgrade == "revive_health_boost" or  -- Swan Song health boost
			upgrade == "berserker_damage_multiplier" or  -- Swan Song damage
			upgrade == "revive_dmg_reduction"  -- Swan Song damage reduction
		) then
			return false  -- Abort activation
		end
	end
end)

-- === HOOK ON BLEED OUT (MOMENT OF GOING DOWN) ===
-- Hook the moment the player is about to fall rather than the damage itself
Hooks:PreHook(PlayerDamage, "_check_bleed_out", "CSR_PlushSharkGuardianBleedOut", function(self)
	-- Guard: charge must be available
	if not CSR_PlushShark.charge_available then
		return
	end

	-- Guard: player must be at 0 HP (about to die)
	local current_hp = self:get_real_health()


	if current_hp <= 0 then

		-- CRITICAL: Set flag BEFORE anything else
		-- This blocks Swan Song from activating
		_G.CSR_PlushSharkJustActivated = true

		-- Reset flag after 0.2s (once all systems have processed the damage)
		DelayedCalls:Add("CSR_PlushSharkResetFlag", 0.2, function()
			_G.CSR_PlushSharkJustActivated = false
		end)

		-- 1. Restore 20% HP (prevent going down)
		local max_hp = self:_max_health()
		local heal_amount = max_hp * 0.20
		self:set_health(heal_amount)

		-- 2. Enable invulnerability
		local duration = 10 + (CSR_PlushShark.stacks - 1) * 20
		CSR_PlushShark.invulnerability_end_time = TimerManager:game():time() + duration

		-- 2.5. PLAY ACTIVATION SOUND
		local player_unit = managers.player:player_unit()


		if _G.CSR_PlushSharkSoundBuffer and player_unit then
			-- Cleanup old source
			if self._csr_plush_shark_sound then
				pcall(function()
					if not self._csr_plush_shark_sound:is_closed() then
						self._csr_plush_shark_sound:stop()
						self._csr_plush_shark_sound:close()
					end
				end)
			end

			local sound_success, sound_err = pcall(function()
				self._csr_plush_shark_sound = XAudio.UnitSource:new(player_unit, _G.CSR_PlushSharkSoundBuffer)

				self._csr_plush_shark_sound:set_volume(1.0)

				self._csr_plush_shark_sound:play()
			end)

			if not sound_success then
			else
			end
		else
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
					total = duration + 0.1
				})
			end

			self._csr_plush_shark_active = true
			self._csr_plush_shark_start_time = TimerManager:game():time()
			self._csr_plush_shark_duration = duration
		end)

		-- 4. Consume the charge
		CSR_PlushShark.charge_available = false

		-- 5. CANCEL BLEED OUT (return false to prevent going down)
		return false
	end
end)

-- === INVULNERABILITY (BLOCK ALL DAMAGE) ===
-- Hook on _chk_can_take_dmg for full invulnerability
local original_chk_can_take_dmg = PlayerDamage._chk_can_take_dmg
function PlayerDamage:_chk_can_take_dmg(...)
	local current_time = TimerManager:game():time()

	-- If Plush Shark invulnerability is active, block all damage
	if CSR_PlushShark.invulnerability_end_time > current_time then
		return false
	end

	return original_chk_can_take_dmg(self, ...)
end

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
					total = total_duration + 0.1  -- Ensure current < total
				})
			end
		end)
	else
		-- Disable visual effects (pcall for safety)
		pcall(function()
			-- Visual effects
			if managers and managers.environment_controller and managers.environment_controller.set_bleedout_underlay then
				managers.environment_controller:set_bleedout_underlay(false)
			end
			if SoundDevice and SoundDevice.set_rtpc then
				SoundDevice:set_rtpc("downed_filter", 0)
			end

			-- Disable Swan Song radial
			if managers.hud then
				managers.hud:set_teammate_custom_radial(HUDManager.PLAYER_PANEL, {
					current = 0,
					total = 0
				})
				-- FIXED v2.41: Radial automatically hidden when current=0
				-- remove_teammate_ability_panel() does not exist in vanilla
			end

		end)

		self._csr_plush_shark_active = false
		self._csr_plush_shark_duration = nil
	end
end)

