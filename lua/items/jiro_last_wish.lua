-- Jiro's Last Wish (rare) -- +50% melee damage per copy owned, AND sprint while
-- charging a melee attack.
--
-- Two-part item: the melee-damage half hooks BlackMarketManager (return-value
-- raw wrap); the sprint-while-charging half is bespoke PlayerStandard behavior
-- (Hooks:Pre/PostHook, no return value), copied 1:1 from the proven 6.2 mechanic
-- (modifiers/jirolastwish.lua) with the ownership gate swapped to the registry.
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

-- True only when a run is active AND the local player owns Jiro.
local function csr_owns_jiro()
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() then
		return false
	end
	return mgr:owned("jiro_last_wish") > 0
end

_G.CSR.register_item({
	type = "jiro_last_wish",
	rarity = "rare",
	name = "csr_logbook_jiro_last_wish_name",
	desc = "csr_item_jiro_last_wish_desc",
	full_desc = "csr_logbook_jiro_last_wish_effect",
	notes = "csr_logbook_jiro_last_wish_notes",
	icon = "csr_jiro_last_wish",

	hooks = {
		-- (1) Melee damage: scale equipped_melee_weapon_damage_info's dmg and
		-- dmg_effect by (1 + 0.5*owned). Mirrors the 6.2 constant jiro_melee_bonus
		-- (0.5). Stacks multiplicatively with Evidence Rounds' melee bonus (each
		-- item wraps independently). Return-value method -> raw chain wrap.
		["lib/managers/blackmarketmanager"] = function()
			if _G._CSR_JIRO_MELEE_HOOKED then
				return
			end
			_G._CSR_JIRO_MELEE_HOOKED = true
			local orig = BlackMarketManager.equipped_melee_weapon_damage_info
			if not orig then
				return
			end
			function BlackMarketManager:equipped_melee_weapon_damage_info(lerp_value)
				local dmg, dmg_effect = orig(self, lerp_value)
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					return dmg, dmg_effect
				end
				local bonus = 0.5 * mgr:owned("jiro_last_wish")
				if bonus ~= 0 and type(dmg) == "number" then
					local mul = 1 + bonus
					dmg = dmg * mul
					if type(dmg_effect) == "number" then
						dmg_effect = dmg_effect * mul
					end
				end
				return dmg, dmg_effect
			end
		end,

		-- (2) Sprint while charging a melee attack. Pattern from Hinaomi's
		-- Rebalance: don't force _running = true, call _start_action_running()
		-- normally so stamina is consumed. Three cooperating hooks.
		["lib/units/beings/player/states/playerstandard"] = function()
			if _G._CSR_JIRO_SPRINT_HOOKED then
				return
			end
			_G._CSR_JIRO_SPRINT_HOOKED = true

			-- Before melee starts, remember if the player was already running.
			Hooks:PreHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_RememberRunning", function(self)
				if not csr_owns_jiro() then
					return
				end
				if self._running and not self._end_running_expire_t then
					self._csr_jiro_was_running = true
				end
			end)

			-- After melee starts, resume running via the normal mechanism.
			Hooks:PostHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_ResumeRunning", function(self, t)
				if not csr_owns_jiro() then
					return
				end
				if self._csr_jiro_was_running then
					self._csr_jiro_was_running = nil
					self:_start_action_running(t)
				end
			end)

			-- When _start_action_running is called (Shift OR the resume above),
			-- allow running during melee charge with all vanilla checks.
			Hooks:PostHook(PlayerStandard, "_start_action_running", "CSR_JiroLastWish_RunDuringMelee", function(self, t)
				if not csr_owns_jiro() then
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
				if
					managers.player:get_player_rule("no_run")
					or not self._unit:movement():is_above_stamina_threshold()
				then
					return
				end

				-- Play start-running camera shake if headbob is enabled.
				if
					(
						not self._state_data.shake_player_start_running
						or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)
					) and managers.user:get_setting("use_headbob")
				then
					self._state_data.shake_player_start_running =
						self._ext_camera:play_shaker("player_start_running", 0.75)
				end

				self:set_running(true)
				self._end_running_expire_t = nil
				self._start_running_t = t
				self:_interupt_action_ducking(t)
				local mgr = managers.csr
				if mgr and mgr:debug_enabled() then
					mgr:debug_log("jiro_last_wish: sprint during melee charge")
				end
			end)
		end,
	},
})
