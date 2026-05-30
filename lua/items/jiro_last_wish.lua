-- Jiro's Last Wish (rare) — +50%/stack melee damage, and sprint while charging melee.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local function csr_owns_jiro()
	local mgr = managers and managers.csr
	if not mgr or not mgr.in_csr_heist or not mgr:in_csr_heist() then
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
	icon_scale = 1.0,

	hooks = {
		-- Melee damage: +50%/stack (multiplies dmg and dmg_effect).
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
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
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

		-- Sprint while charging melee. Pattern from Hinaomi's Rebalance — don't force
		-- _running = true; call _start_action_running so stamina drains normally.
		["lib/units/beings/player/states/playerstandard"] = function()
			if _G._CSR_JIRO_SPRINT_HOOKED then
				return
			end
			_G._CSR_JIRO_SPRINT_HOOKED = true

			Hooks:PreHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_RememberRunning", function(self)
				if not csr_owns_jiro() then
					return
				end
				if self._running and not self._end_running_expire_t then
					self._csr_jiro_was_running = true
				end
			end)

			Hooks:PostHook(PlayerStandard, "_start_action_melee", "CSR_JiroLastWish_ResumeRunning", function(self, t)
				if not csr_owns_jiro() then
					return
				end
				if self._csr_jiro_was_running then
					self._csr_jiro_was_running = nil
					self:_start_action_running(t)
				end
			end)

			Hooks:PostHook(PlayerStandard, "_start_action_running", "CSR_JiroLastWish_RunDuringMelee", function(self, t)
				if not csr_owns_jiro() then
					return
				end
				if not self:_is_meleeing() then
					return
				end

				if not self._move_dir then
					self._running_wanted = true
					return
				end

				if self:on_ladder() or self:_on_zipline() then
					return
				end

				if self._state_data.in_air or (self._state_data.ducking and not self:_can_stand()) then
					self._running_wanted = true
					return
				end

				if not self:_can_run_directional() then
					return
				end

				self._running_wanted = false

				if
					managers.player:get_player_rule("no_run")
					or not self._unit:movement():is_above_stamina_threshold()
				then
					return
				end

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
