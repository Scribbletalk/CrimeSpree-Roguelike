-- Plush Shark (rare) -- guardian angel: on the LAST down before custody, cancel
-- it (heal full + restore one down + armor) and grant a long invulnerability.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- All effects are local-player-scoped (each peer revives its own player and syncs
-- its own revive count via the vanilla _send_set_revives path), so MP-symmetric.
--
-- Cross-item priority with The Edge (emergency_heal): this item sets a per-life
-- flag self._csr_guardian_armed (true on (re)spawn, false once consumed). The Edge
-- yields its lethal-down heal while a guardian is armed and will catch the down,
-- so Plush takes priority regardless of hook-install order. Both items' invuln
-- gates stack independently on _chk_can_take_dmg (SuperBLT keeps an earlier hook's
-- false return when a later hook returns nothing).
--
-- Dropped from the 6.2 line (systems not in this slice): the HUD timed-buff events
-- (HUD-compat unported) and EnvironmentController:set_bleedout_underlay (no such
-- vanilla method -- its 6.2 nil-guard never passed).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

-- Invuln vignette (DB id registered in lua/tweakdata/hudicons.lua).
local PLUSH_VIGNETTE = "guis/textures/pd2/crime_spree/csr_guilt_vignette"

-- True only for the local player's PlayerDamage (remote husks are ignored).
local function is_local_pd(self)
	local pu = managers.player and managers.player:player_unit()
	return pu and self._unit == pu
end

-- Blue pulsing vignette + Swan-Song-style radial for the invuln window. Vanilla
-- API, pcall-isolated: visuals can never break the mechanic.
local function plush_start_visuals(self, duration)
	self._csr_plush_active = true
	self._csr_plush_duration = duration
	pcall(function()
		if managers.hud then
			-- current < total so EVH treats it as an active custom radial.
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
				-- 4-arg per Rule #6: blue (r=0, g=0.4, b=1). Alpha driven by the pulse.
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

-- Remove the vignette (fade over 0.3s) and clear the radial.
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

-- Fire the guardian: cancel the bleed-out (heal full + restore one down + armor)
-- and open the invuln window. Returns true if it fired.
local function try_plush_guardian(self, mgr, now)
	if not self._csr_guardian_armed then
		return false
	end
	-- Only the LAST down before custody: revives == 1 means the next bleed-out
	-- vanilla would decrement 1 -> 0 and route straight to custody.
	if (self:get_revives() or 0) ~= 1 then
		return false
	end
	local stacks = mgr:owned("plush_shark")
	if stacks <= 0 then
		return false
	end

	local max_hp = self:_max_health()
	if max_hp and max_hp > 0 then
		self:set_health(max_hp * 1.00) -- heal_pct 1.00
	end
	self:set_armor(self:_max_armor()) -- restore_armor

	-- Restore one down (revives +1, capped at max lives). Without this the player
	-- is still one tick from custody on their next down even though we healed.
	local current = self:get_revives() or 0
	local new_revives = math.min(current + 1, self:get_revives_max())
	self._revives = Application:digest_value(new_revives, true)
	if self._send_set_revives then
		self:_send_set_revives()
	end
	if managers.environment_controller and managers.environment_controller.set_last_life then
		managers.environment_controller:set_last_life(new_revives <= 1)
	end

	-- invuln_base 10 + (stacks-1)*invuln_extra 20.
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

-- The manager IF a run is active, else nil.
local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.is_run_active and mgr:is_run_active() then
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

			-- Lethal down: heal BEFORE vanilla _check_bleed_out runs (it gates its
			-- body on get_real_health() == 0, so a heal here cancels the bleed-out;
			-- a PreHook return cannot abort the original in SuperBLT).
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

			-- Invuln gate: block damage while the window is open. Returning nothing
			-- keeps any earlier hook's result (e.g. The Edge's gate).
			Hooks:PostHook(PlayerDamage, "_chk_can_take_dmg", "CSR_PlushShark_Invuln", function(self)
				if self._csr_plush_invuln_end and TimerManager:game():time() < self._csr_plush_invuln_end then
					return false
				end
			end)

			-- Invuln visuals: count the radial down, fade the vignette when the
			-- window ends. Zero cost until the guardian fires.
			Hooks:PostHook(PlayerDamage, "update", "CSR_PlushShark_Visuals", function(self, unit, t, dt)
				if not self._csr_plush_active then
					return
				end
				local remaining = (self._csr_plush_invuln_end or 0) - TimerManager:game():time()
				if remaining > 0 then
					pcall(function()
						if managers.hud then
							local total = self._csr_plush_duration or 10
							managers.hud:set_teammate_custom_radial(
								HUDManager.PLAYER_PANEL,
								{ current = remaining, total = total + 0.1 }
							)
						end
					end)
				else
					plush_stop_visuals(self)
				end
			end)

			-- Reset per-life state on (re)spawn. Refreshes the guardian charge on
			-- heist start and custody release, but not on a teammate revive (same
			-- unit, init does not re-fire). _csr_guardian_armed is the shared flag
			-- The Edge reads to yield priority.
			Hooks:PostHook(PlayerDamage, "init", "CSR_PlushShark_Init", function(self)
				-- Armed = owned AND charge fresh. Picks are lobby-only, so init-time
				-- ownership equals down-time ownership; re-evaluated on every respawn
				-- (heist start, custody release). The Edge reads this flag (not the
				-- item type) to yield priority, so the flag must imply "will fire".
				local mgr = managers.csr
				self._csr_guardian_armed = (mgr and mgr.owned and mgr:owned("plush_shark") > 0) or false
				self._csr_plush_invuln_end = nil
				self._csr_plush_active = false
				self._csr_plush_duration = nil
			end)
		end,
	},
})
