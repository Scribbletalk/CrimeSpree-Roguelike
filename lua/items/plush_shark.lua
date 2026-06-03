-- Plush Shark (rare) — guardian angel: on the LAST down before custody, cancel
-- it (heal full + restore one down + armor) and grant long invulnerability.
-- Cross-item priority with The Edge: see csr_emergency_heal_priority.md.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local PLUSH_VIGNETTE = "guis/textures/pd2/crime_spree/csr_guilt_vignette"

local function is_local_pd(self)
	local pu = managers.player and managers.player:player_unit()
	return pu and self._unit == pu
end

-- Blue pulsing vignette + Swan-Song-style radial. pcall-isolated.
local function plush_start_visuals(self, duration)
	self._csr_plush_active = true
	self._csr_plush_duration = duration
	pcall(function()
		if managers.hud then
			managers.hud:set_teammate_custom_radial(
				HUDManager.PLAYER_PANEL,
				{ current = duration, total = duration + 0.1 }
			)
		end
		local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if hud_script and hud_script.panel then
			local panel = hud_script.panel
			local old = panel:child("plush_shark_vignette")
			if old then
				panel:remove(old)
			end
			local bm = panel:bitmap({
				name = "plush_shark_vignette",
				texture = PLUSH_VIGNETTE,
				blend_mode = "add",
				color = Color(1, 0, 0.4, 1),
				x = 0,
				y = 0,
				w = panel:w(),
				h = panel:h(),
				layer = 200,
			})
			bm:animate(function(o)
				local elapsed = 0
				while true do
					local dt = coroutine.yield()
					elapsed = elapsed + dt
					o:set_alpha(0.35 + 0.20 * math.sin(elapsed * math.pi * 2 / 1.5))
				end
			end)
		end
	end)
end

local function plush_stop_visuals(self)
	self._csr_plush_active = false
	self._csr_plush_duration = nil
	pcall(function()
		if managers.hud then
			managers.hud:set_teammate_custom_radial(HUDManager.PLAYER_PANEL, { current = 0, total = 0 })
		end
		local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if hud_script and hud_script.panel then
			local v = hud_script.panel:child("plush_shark_vignette")
			if v then
				local start_alpha = v:alpha()
				v:animate(function(o)
					local t = 0.3
					while t > 0 do
						t = math.max(t - coroutine.yield(), 0)
						o:set_alpha(t / 0.3 * start_alpha)
					end
				end)
				DelayedCalls:Add("PlushVignetteRemove", 0.4, function()
					pcall(function()
						local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
						local p = s and s.panel and s.panel:child("plush_shark_vignette")
						if p then
							s.panel:remove(p)
						end
					end)
				end)
			end
		end
	end)
end

-- Reused radial-data table + closure-free pusher for the per-frame countdown.
-- HUDTeammate:set_custom_radial reads current/total synchronously (no ref retained),
-- so one table can be overwritten every frame -> zero per-frame allocation.
local plush_radial_data = { current = 0, total = 0 }
local function plush_push_radial(remaining, total)
	if managers.hud then
		plush_radial_data.current = remaining
		plush_radial_data.total = total + 0.1
		managers.hud:set_teammate_custom_radial(HUDManager.PLAYER_PANEL, plush_radial_data)
	end
end

-- Cancel bleed-out + grant invuln. Returns true if it fired.
local function try_plush_guardian(self, mgr, now)
	if mgr:item_heal_blocked() then
		return false
	end
	if not self._csr_guardian_armed then
		return false
	end
	-- Only the LAST down before custody.
	if (self:get_revives() or 0) ~= 1 then
		return false
	end
	local stacks = mgr:owned("plush_shark")
	if stacks <= 0 then
		return false
	end

	local max_hp = self:_max_health()
	if max_hp and max_hp > 0 then
		self:set_health(max_hp * 1.00)
	end
	self:set_armor(self:_max_armor())

	-- Restore one down (capped at max lives) so the next down isn't insta-custody.
	local current = self:get_revives() or 0
	local new_revives = math.min(current + 1, self:get_revives_max())
	self._revives = Application:digest_value(new_revives, true)
	if self._send_set_revives then
		self:_send_set_revives()
	end
	if managers.environment_controller and managers.environment_controller.set_last_life then
		managers.environment_controller:set_last_life(new_revives <= 1)
	end

	local duration = 10 + math.max(0, stacks - 1) * 20
	self._csr_plush_invuln_end = now + duration
	self._csr_guardian_armed = false

	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("plush_shark_activate", { volume = 0.85 })
	end
	plush_start_visuals(self, duration)
	if mgr:debug_enabled() then
		mgr:debug_log(string.format("plush_shark guardian fired (invuln %.0fs)", duration))
	end
	return true
end

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

_G.CSR.register_item({
	type = "plush_shark",
	rarity = "rare",
	name = "csr_logbook_plush_shark_name",
	desc = "csr_item_plush_shark_desc",
	full_desc = "csr_logbook_plush_shark_effect",
	notes = "csr_logbook_plush_shark_notes",
	icon = "csr_plush_shark",
	icon_scale = 1.0,

	hooks = {
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_PLUSH_SHARK_HOOKED then
				return
			end
			_G._CSR_PLUSH_SHARK_HOOKED = true

			-- Heal BEFORE vanilla _check_bleed_out (it gates on real_health == 0).
			Hooks:PreHook(PlayerDamage, "_check_bleed_out", "CSR_PlushShark_BleedOut", function(self)
				local mgr = csr_mgr()
				if not mgr or not is_local_pd(self) or not self.get_real_health then
					return
				end
				if self:get_real_health() > 0 then
					return
				end
				try_plush_guardian(self, mgr, TimerManager:game():time())
			end)

			-- Invuln gate. Returning nothing keeps any earlier hook's result (e.g. The Edge's).
			Hooks:PostHook(PlayerDamage, "_chk_can_take_dmg", "CSR_PlushShark_Invuln", function(self)
				if self._csr_plush_invuln_end and TimerManager:game():time() < self._csr_plush_invuln_end then
					return false
				end
			end)

			-- Radial countdown + fade the vignette when the window ends.
			Hooks:PostHook(PlayerDamage, "update", "CSR_PlushShark_Visuals", function(self, unit, t, dt)
				if not self._csr_plush_active then
					return
				end
				local remaining = (self._csr_plush_invuln_end or 0) - TimerManager:game():time()
				if remaining > 0 then
					pcall(plush_push_radial, remaining, self._csr_plush_duration or 10)
				else
					plush_stop_visuals(self)
				end
			end)

			-- Per-life state reset. Fires on heist start + custody release, NOT on teammate revive.
			Hooks:PostHook(PlayerDamage, "init", "CSR_PlushShark_Init", function(self)
				local mgr = managers.csr
				-- Armed iff owned at spawn; The Edge reads this flag to yield priority.
				self._csr_guardian_armed = (mgr and mgr.owned and mgr:owned("plush_shark") > 0) or false
				self._csr_plush_invuln_end = nil
				self._csr_plush_active = false
				self._csr_plush_duration = nil
			end)
		end,
	},
})
