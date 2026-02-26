-- JIRO'S LAST WISH - Sprint during melee charge + melee damage
-- Grants an ability to sprint while charging a melee attack.
-- Increases melee damage by 50% (+50% per stack, linear).

if not RequiredScript then
	return
end



ModifierJiroLastWish = ModifierJiroLastWish or class(CSRBaseModifier)
ModifierJiroLastWish.desc_id = "csr_jiro_last_wish_desc"

-- Sprint during melee charge using proper vanilla flow.
-- Pattern from Hinaomi's Rebalance: don't force _running = true,
-- instead call _start_action_running() normally so stamina is consumed.
if PlayerStandard then

	-- Step 1: Before melee starts, remember if player was already running
	Hooks:PreHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_RememberRunning", function(self)
		if not CSR_ActiveBuffs or not CSR_ActiveBuffs.jiro_last_wish then return end
		if self._running and not self._end_running_expire_t then
			self._csr_jiro_was_running = true
		end
	end)

	-- Step 2: After melee starts, resume running via normal mechanism
	Hooks:PostHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_ResumeRunning", function(self, t)
		if not CSR_ActiveBuffs or not CSR_ActiveBuffs.jiro_last_wish then return end
		if self._csr_jiro_was_running then
			self._csr_jiro_was_running = nil
			self:_start_action_running(t)
		end
	end)

	-- Step 3: When _start_action_running is called (player presses Shift OR step 2 above),
	-- allow running during melee charge with all vanilla checks (stamina, direction, etc.)
	Hooks:PostHook(PlayerStandard, "_start_action_running", "CSR_JiroLastWish_RunDuringMelee", function(self, t)
		if not CSR_ActiveBuffs or not CSR_ActiveBuffs.jiro_last_wish then return end
		if not self:_is_meleeing() then return end

		-- No movement direction — queue the intent but don't sprint
		if not self._move_dir then
			self._running_wanted = true
			return
		end

		-- Can't sprint on ladder or zipline
		if self:on_ladder() or self:_on_zipline() then
			return
		end

		-- Can't sprint in air or while crouching (unless can stand)
		if self._state_data.in_air or (self._state_data.ducking and not self:_can_stand()) then
			self._running_wanted = true
			return
		end

		if not self:_can_run_directional() then
			return
		end

		self._running_wanted = false

		-- Respect no_run rule and stamina threshold (stamina drains normally)
		if managers.player:get_player_rule("no_run") or not self._unit:movement():is_above_stamina_threshold() then
			return
		end

		-- Play start-running camera shake if headbob is enabled
		if (not self._state_data.shake_player_start_running or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)) and managers.user:get_setting("use_headbob") then
			self._state_data.shake_player_start_running = self._ext_camera:play_shaker("player_start_running", 0.75)
		end

		self:set_running(true)
		self._end_running_expire_t = nil
		self._start_running_t = t
		self:_interupt_action_ducking(t)
	end)

else
end

