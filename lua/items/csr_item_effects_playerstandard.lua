-- CSR item effects - PlayerStandard side. Two unrelated items share this script
-- (so they share one mod.txt entry); each is in its own clearly-marked section.
--
-- (1) Generic stat dispatch: movement_speed (Escape Plan, stat_hyperbolic).
--     Multiplies PlayerStandard:_get_max_walk_speed's return by (1 + bonus),
--     the same shape the 6.2 line used (playerstandard.lua). Stacks
--     multiplicatively with any vanilla speed multiplier.
--
-- (2) Bespoke behavior: Jiro's Last Wish -- sprint while charging a melee
--     attack. This half of Jiro is NOT a declarative effect kind (the +melee
--     damage half is, see csr_item_effects_melee.lua); it is item-specific
--     PlayerStandard behavior, copied 1:1 from the proven 6.2 mechanic
--     (modifiers/jirolastwish.lua) with only the ownership gate swapped from
--     CSR_ActiveBuffs.jiro_last_wish to the registry's has_item. When the
--     callback escape-hatch lands (design migration step 4) this could move to
--     an on_apply callback; for now a gated hook file is the simplest path
--     (feedback_simple_approach_first).
--
-- Critical Rule #1 exception for _get_max_walk_speed: it RETURNS a value, so a
-- raw chain wrap (not PostHook) is used, per the CSR return-value convention
-- (feedback_rule1_return_value_exception). The Jiro hooks carry no return value
-- so they use Hooks:Pre/PostHook. The _G guard stops a hot-reload from
-- compounding the raw-wrapped speed.

if not RequiredScript then
	return
end

-- Combined hyperbolic bonus for one stat across every registered stat_hyperbolic
-- item the local player owns -- see csr_item_effects.lua for the formula notes.
-- Duplicated here per the established self-contained-file convention.
local function csr_stat_hyperbolic_bonus(stat)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return 0
	end
	if not mgr.registered_items then
		return 0
	end
	local pid = mgr:local_peer_id()
	local remain = 1
	for _, item in ipairs(mgr:registered_items()) do
		local e = item.effect
		if e and e.kind == "stat_hyperbolic" and e.stat == stat then
			local stacks = mgr:item_count(pid, item.type)
			if stacks > 0 then
				local k = (e.k_num or 1) / (e.k_den or 1)
				local b = (e.cap or 1) * (1 - 1 / (1 + k * stacks))
				remain = remain * (1 - b)
			end
		end
	end
	return 1 - remain
end

-- True only when a run is active AND the local player owns the given item type.
local function csr_owns(item_type)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return false
	end
	if not mgr.has_item then
		return false
	end
	return mgr:has_item(mgr:local_peer_id(), item_type)
end

if PlayerStandard and not _G._CSR_ITEM_EFFECTS_PLAYERSTANDARD_HOOKED then
	_G._CSR_ITEM_EFFECTS_PLAYERSTANDARD_HOOKED = true

	-- (1) Escape Plan -- movement speed.
	local orig_walk = PlayerStandard._get_max_walk_speed
	if orig_walk then
		function PlayerStandard:_get_max_walk_speed(t, force_run)
			local speed = orig_walk(self, t, force_run)
			if type(speed) ~= "number" then
				return speed
			end
			local bonus = csr_stat_hyperbolic_bonus("movement_speed")
			if bonus ~= 0 then
				speed = speed * (1 + bonus)
			end
			return speed
		end
	end

	-- (2) Jiro's Last Wish -- sprint while charging a melee attack.
	-- Pattern from Hinaomi's Rebalance: don't force _running = true, call
	-- _start_action_running() normally so stamina is consumed.

	-- Step 1: before melee starts, remember if the player was already running.
	Hooks:PreHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_RememberRunning", function(self)
		if not csr_owns("jiro_last_wish") then
			return
		end
		if self._running and not self._end_running_expire_t then
			self._csr_jiro_was_running = true
		end
	end)

	-- Step 2: after melee starts, resume running via the normal mechanism.
	Hooks:PostHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_ResumeRunning", function(self, t)
		if not csr_owns("jiro_last_wish") then
			return
		end
		if self._csr_jiro_was_running then
			self._csr_jiro_was_running = nil
			self:_start_action_running(t)
		end
	end)

	-- Step 3: when _start_action_running is called (player presses Shift OR step
	-- 2 above), allow running during melee charge with all vanilla checks
	-- (stamina, direction, etc.).
	Hooks:PostHook(PlayerStandard, "_start_action_running", "CSR_JiroLastWish_RunDuringMelee", function(self, t)
		if not csr_owns("jiro_last_wish") then
			return
		end
		if not self:_is_meleeing() then
			return
		end

		-- No movement direction -- queue the intent but don't sprint.
		if not self._move_dir then
			self._running_wanted = true
			return
		end

		-- Can't sprint on ladder or zipline.
		if self:on_ladder() or self:_on_zipline() then
			return
		end

		-- Can't sprint in air or while crouching (unless can stand).
		if self._state_data.in_air or (self._state_data.ducking and not self:_can_stand()) then
			self._running_wanted = true
			return
		end

		if not self:_can_run_directional() then
			return
		end

		self._running_wanted = false

		-- Respect no_run rule and stamina threshold (stamina drains normally).
		if managers.player:get_player_rule("no_run") or not self._unit:movement():is_above_stamina_threshold() then
			return
		end

		-- Play start-running camera shake if headbob is enabled.
		if
			(
				not self._state_data.shake_player_start_running
				or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)
			) and managers.user:get_setting("use_headbob")
		then
			self._state_data.shake_player_start_running = self._ext_camera:play_shaker("player_start_running", 0.75)
		end

		self:set_running(true)
		self._end_running_expire_t = nil
		self._start_running_t = t
		self:_interupt_action_ducking(t)
	end)
end
