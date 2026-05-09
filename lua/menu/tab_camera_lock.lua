-- Crime Spree Roguelike - Lock camera + fire + show mouse cursor while TAB
-- is held. Movement (WASD/jump/crouch) stays free.
--
-- Strategy: surgical lock instead of full controller disable.
--   * Zero the "look" axis multiplier on MenuManager's controller — same
--     connection vanilla touches in playerstandard.lua:1225 via
--     set_mouse_sensitivity. Mouse-look reads through this multiplier, so
--     (0,0,0) freezes the camera without disabling any other input.
--   * Refresh PlayerStandard._menu_closed_fire_cooldown from a PreHook on
--     PlayerStandard:update every frame TAB is held. Vanilla decrements
--     this field by dt each frame (playerstandard.lua:387-388) and the
--     action-forbidden check at line 4910 sets action_forbidden=true while
--     it's > 0 — same mechanism vanilla uses for post-menu fire grace.
--     PreHooking _check_action_primary_attack does NOT work here (see
--     pd2_menu_closed_fire_cooldown memory) — writing the field directly
--     is the only path that reliably gates fire.
--   * Call _check_stop_shooting on lock so auto-fire mid-burst halts (the
--     cooldown only blocks NEW fire actions, not ongoing).
--   * mouse_pointer:use_mouse renders the cursor.
--
-- Because the player controller stays enabled, vanilla's
-- btn_stats_screen_release path fires naturally on TAB release →
-- hide_stats_screen → our PostHook unlocks. No keyboard poll, no
-- DelayedCalls, no flag manipulation — vanilla drives the lifecycle.

if not RequiredScript then
	return
end

local POINTER_ID = "csr_tab_lock_pointer"
local FIRE_GRACE_S = 0.15

local _state = nil

local function get_look_connection()
	local mm = managers.menu
	if not mm or not mm._controller then
		return nil
	end
	local setup = mm._controller.get_setup and mm._controller:get_setup()
	if not setup then
		return nil
	end
	return setup.get_connection and setup:get_connection("look") or nil
end

local function start_fire_grace()
	local pu = managers.player and managers.player:player_unit()
	if not (pu and alive(pu)) then
		return
	end
	local mvt = pu:movement()
	if not mvt or not mvt.current_state then
		return
	end
	local pstate = mvt:current_state()
	if pstate and pstate._menu_closed_fire_cooldown ~= nil then
		pstate._menu_closed_fire_cooldown = math.max(pstate._menu_closed_fire_cooldown, FIRE_GRACE_S)
	end
end

-- Lazy PlayerStandard hooks. Registered on first show because
-- PlayerStandard isn't guaranteed loaded at file-load time (this file
-- is hooked under hudmanagerpd2, which loads before player state
-- classes).
local _fire_hook_registered = false
local _saved_visible_flag -- closure-shared between jump/duck pre and post hooks
local function register_fire_hook()
	if _fire_hook_registered or not PlayerStandard then
		return
	end
	_fire_hook_registered = true

	-- Fire block: refresh _menu_closed_fire_cooldown each frame TAB is held.
	-- We hook PlayerStandard:update (which runs before vanilla's own dt
	-- decrement at playerstandard.lua:387-388), so by the time the
	-- action-forbidden check at line 4910 runs, the field is freshly
	-- topped up and primary_attack stays gated.
	Hooks:PreHook(PlayerStandard, "update", "CSR_TabCameraLock_BlockFireUpdate", function(self, t, dt)
		if not _state then
			return
		end
		self._menu_closed_fire_cooldown = math.max(self._menu_closed_fire_cooldown or 0, 0.2)
		-- Stop ongoing auto-fire mid-burst — cooldown gates new fire
		-- actions but doesn't interrupt _shooting=true on its own.
		if self._shooting and self._check_stop_shooting then
			pcall(function()
				self:_check_stop_shooting()
			end)
		end
	end)

	-- Jump + duck unblock: vanilla forbids both when stats_screen_visible()
	-- returns true (jump at line 4039, duck at line 4654). We briefly flip
	-- the flag false for the duration of those two checks so the player
	-- can still move while TAB is held, then restore it so the rest of
	-- the frame (in particular btn_stats_screen_release detection at
	-- line 655, which REQUIRES the flag true) works normally.
	local function unlock_visible(self)
		if not _state then
			return
		end
		local pb = self._unit and self._unit:base()
		if pb then
			_saved_visible_flag = pb._stats_screen_visible
			pb._stats_screen_visible = false
		end
	end
	local function relock_visible(self)
		if _saved_visible_flag == nil then
			return
		end
		local pb = self._unit and self._unit:base()
		if pb then
			pb._stats_screen_visible = _saved_visible_flag
		end
		_saved_visible_flag = nil
	end

	Hooks:PreHook(PlayerStandard, "_check_action_jump", "CSR_TabCameraLock_AllowJumpPre", unlock_visible)
	Hooks:PostHook(PlayerStandard, "_check_action_jump", "CSR_TabCameraLock_AllowJumpPost", relock_visible)
	Hooks:PreHook(PlayerStandard, "_check_action_duck", "CSR_TabCameraLock_AllowDuckPre", unlock_visible)
	Hooks:PostHook(PlayerStandard, "_check_action_duck", "CSR_TabCameraLock_AllowDuckPost", relock_visible)

	-- Steelsight (ADS) block: vanilla's _check_action_steelsight at
	-- playerstandard.lua:4663 has no stats_screen_visible() gate and
	-- doesn't read the fire cooldown either. Zero the input flags before
	-- the original sees them so neither btn_steelsight_press nor _release
	-- triggers an enter/exit while TAB is held.
	Hooks:PreHook(
		PlayerStandard,
		"_check_action_steelsight",
		"CSR_TabCameraLock_BlockSteelsight",
		function(self, t, input)
			if not _state then
				return
			end
			if input then
				input.btn_steelsight_press = false
				input.btn_steelsight_release = false
			end
		end
	)
end

Hooks:PostHook(HUDManager, "show_stats_screen", "CSR_TabCameraLock_Show", function(self)
	-- Only enhance TAB in Crime Spree heists. Outside CS, vanilla's
	-- stats-screen behavior stays untouched: no camera lock, no fire/
	-- steelsight block, no mouse cursor. Same gate pattern we use for
	-- tab_difficulty_skulls — is_active() only, not in_progress(), so a
	-- stale in_progress flag from a previous CS can't leak in.
	local cs = managers.crime_spree
	if not cs or not cs.is_active or not cs:is_active() then
		return
	end
	register_fire_hook()
	if _state then
		return
	end
	if not managers.mouse_pointer or not managers.mouse_pointer.use_mouse then
		return
	end

	local conn = get_look_connection()
	if not conn or not conn.get_multiplier or not conn.set_multiplier then
		return
	end

	-- End any in-progress steelsight FIRST, before snapshotting the look
	-- multiplier. _end_action_steelsight → _stance_entered →
	-- managers.menu:set_mouse_sensitivity(self:in_steelsight()) at
	-- playerstandard.lua:1227 rewrites the multiplier to the non-zoom
	-- value. If we captured saved_mult while still aimed, we'd restore
	-- the zoom-reduced sensitivity on TAB release.
	local pu_for_steel = managers.player and managers.player:player_unit()
	if pu_for_steel and alive(pu_for_steel) and pu_for_steel:movement() then
		local pstate = pu_for_steel:movement():current_state()
		if pstate and pstate._state_data and pstate._state_data.in_steelsight and pstate._end_action_steelsight then
			pcall(function()
				pstate:_end_action_steelsight(TimerManager:game():time())
			end)
		end
	end

	-- Save current multiplier as a Vector3 copy. get_multiplier returns
	-- a live Vector3 — without copying, our zero-write would also
	-- overwrite the saved value.
	local cur = conn:get_multiplier()
	local saved_mult = Vector3(cur.x, cur.y, cur.z)

	pcall(function()
		conn:set_multiplier(Vector3(0, 0, 0))
		if managers.controller and managers.controller.request_rebind_connections then
			managers.controller:request_rebind_connections()
		end
	end)

	pcall(function()
		managers.mouse_pointer:use_mouse({
			id = POINTER_ID,
			-- Forward cursor moves to the right-panel hover handler so it
			-- can run hit-tests and show/hide item tooltips. Signature
			-- per managers.mouse_pointer:use_mouse callbacks: (o, x, y).
			mouse_move = function(o, x, y)
				if _G.CSR_StatsTabsItems_OnMouseMove then
					_G.CSR_StatsTabsItems_OnMouseMove(x, y)
				end
			end,
			-- Dispatch to the right-panel tab handler. tab_items_panel.lua
			-- registers CSR_StatsTabsItems_OnMousePress; if it consumes
			-- the click (returns true), we're done. No-op otherwise so
			-- vanilla pass-through behavior stays normal.
			mouse_press = function(o, button, x, y)
				if _G.CSR_StatsTabsItems_OnMousePress then
					_G.CSR_StatsTabsItems_OnMousePress(button, x, y)
				end
			end,
		})
	end)

	-- Halt any in-progress auto-fire on lock entry. Without this, an
	-- automatic weapon already firing at the moment of TAB-press keeps
	-- cycling because _shooting is true; our cooldown only blocks NEW
	-- starts. (Steelsight is exited above, before saved_mult capture.)
	local pu = managers.player and managers.player:player_unit()
	if pu and alive(pu) and pu:movement() then
		local pstate = pu:movement():current_state()
		if pstate and pstate._check_stop_shooting then
			pcall(function()
				pstate:_check_stop_shooting()
			end)
		end
	end

	_state = {
		saved_mult = saved_mult,
	}
end)

Hooks:PostHook(HUDManager, "hide_stats_screen", "CSR_TabCameraLock_Hide", function(self)
	if not _state then
		return
	end
	local saved_mult = _state.saved_mult
	_state = nil

	-- Drop the items-tab tooltip if one's open. It's parented to the
	-- HUDStatsScreen root (not _right), so vanilla's recreate_right doesn't
	-- wipe it on the next show — without this, it lingers on screen.
	local stats = self._hud_statsscreen
	if stats and stats._csr_tooltip and alive(stats._csr_tooltip) then
		stats._csr_tooltip:set_visible(false)
	end

	if managers.mouse_pointer then
		pcall(function()
			managers.mouse_pointer:remove_mouse(POINTER_ID)
		end)
	end

	local conn = get_look_connection()
	if conn and conn.set_multiplier and saved_mult then
		pcall(function()
			conn:set_multiplier(saved_mult)
			if managers.controller and managers.controller.request_rebind_connections then
				managers.controller:request_rebind_connections()
			end
		end)
	end

	start_fire_grace()
end)
