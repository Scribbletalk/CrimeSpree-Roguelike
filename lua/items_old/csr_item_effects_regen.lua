-- CSR item-effect dispatcher — PlayerDamage health restoration.
--
-- Every item that restores the LOCAL player's health lives here, grouped by the
-- thing they have in common (healing the player) rather than by hook phase:
--   (1) regen_max_hp_pct (Worn Band-Aid)    — heal a % of max HP every N seconds.
--   (2) emergency_heal   (The Edge)          — cooldown-gated heal + brief invuln
--                                              when HP drops below a threshold or a
--                                              hit would be lethal.
--   (3) guardian_revive  (Plush Shark)       — on the LAST down before custody,
--                                              cancel it (heal full + restore one
--                                              down + armor) and grant invuln.
--
-- All three hook PlayerDamage, so this one chunk (already hooked on playerdamage
-- in mod.txt) owns them. (2) and (3) share ONE PostHook on _chk_can_take_dmg that
-- returns false while either invuln window is open — the PostHook return overrides
-- the original's result (SuperBLT Hooks.lua), which stacks with other mods' hooks;
-- a raw override would shadow them. Per-life state rides on the PlayerDamage
-- instance and resets in one init PostHook, so Plush Shark's charge refreshes on
-- every (re)spawn — heist start AND custody release — but NOT on a teammate
-- bleed-out revive (same unit, init does not re-fire).
--
-- Priority on a lethal down: Plush Shark first (the big save — restores the down,
-- armor and a long invuln), then The Edge for any down Plush Shark didn't take.
--
-- All effects are local-player-scoped (each peer heals/revives its own player and
-- syncs its own revive count via the vanilla _send_set_revives path), so they are
-- MP-symmetric by construction. Every kind is composable: an addon may register
-- its own item of any of the three kinds and each runs independently; a single
-- item reduces to the 6.2 behaviour exactly.
--
-- Dropped from the 6.2 line (depend on systems not in this slice): the VHUDPlus /
-- WFHud / PocoHud timed-buff events (HUD-compat unported) and the
-- EnvironmentController:set_bleedout_underlay call (no such method in vanilla — its
-- 6.2 nil-guard never passed).

if not RequiredScript then
	return
end

-- Plush Shark invuln vignette (DB id registered in lua/tweakdata/hudicons.lua).
local PLUSH_VIGNETTE = "guis/textures/pd2/crime_spree/csr_guilt_vignette"

-- The manager with the registry helpers IF a run is active, else nil.
local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.is_run_active and mgr:is_run_active() and mgr.items_of_kind then
		return mgr
	end
	return nil
end

-- True only for the local player's PlayerDamage (remote husks are ignored).
local function is_local_pd(self)
	local pu = managers.player and managers.player:player_unit()
	return pu and self._unit == pu
end

-- ============ The Edge — emergency_heal ============

-- Cooldown is per item-type so multiple emergency_heal items run on their own timers.
local function edge_cd_ready(self, item, now)
	local cd = self._csr_edge_cd and self._csr_edge_cd[item.type]
	return not cd or (now - cd) >= (item.effect.cooldown or 120)
end

-- Heal + arm cooldown + open the invuln window for one emergency_heal item.
local function do_edge_heal(self, item, stacks, now)
	local max_hp = self:_max_health()
	if not max_hp or max_hp <= 0 then
		return false
	end
	local e = item.effect
	-- Flat HP is authored in display units; /stats_present_multiplier -> internal.
	local scale = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local pct_heal = max_hp * (e.heal_pct or 0.20)
	local flat_heal = ((e.heal_flat or 20) + math.max(0, stacks - 1) * (e.heal_flat_extra or 40)) / scale
	local new_hp = math.max(self:get_real_health(), 0) + pct_heal + flat_heal
	self:set_health(new_hp)

	self._csr_edge_cd = self._csr_edge_cd or {}
	self._csr_edge_cd[item.type] = now
	self._csr_edge_invuln_end = now + (e.invuln or 1.0)
	self._csr_edge_saved_hp = new_hp

	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("the_edge_activate", { volume = 0.8 })
	end
	local mgr = managers.csr
	if mgr and mgr:debug_enabled() then
		mgr:debug_log(string.format("the_edge heal +%.1f internal HP (stacks=%d)", new_hp, stacks))
	end
	return true
end

-- Lethal save (HP already 0): fire the first ready emergency_heal item (no
-- threshold test — we are at 0 HP). Returns true if one fired.
local function try_edge_lethal(self, mgr, now)
	local items = mgr:items_of_kind("emergency_heal")
	local pid = mgr:local_peer_id()
	for i = 1, #items do
		local item = items[i]
		local stacks = mgr:item_count(pid, item.type)
		if stacks > 0 and edge_cd_ready(self, item, now) then
			return do_edge_heal(self, item, stacks, now)
		end
	end
	return false
end

-- Non-lethal trigger: fire the first ready item whose HP threshold the player is under.
local function try_edge_threshold(self, mgr, now)
	local max_hp = self:_max_health()
	if not max_hp or max_hp <= 0 then
		return
	end
	local ratio = self:get_real_health() / max_hp
	local items = mgr:items_of_kind("emergency_heal")
	local pid = mgr:local_peer_id()
	for i = 1, #items do
		local item = items[i]
		local stacks = mgr:item_count(pid, item.type)
		if stacks > 0 and edge_cd_ready(self, item, now) and ratio < (item.effect.hp_threshold or 0.10) then
			do_edge_heal(self, item, stacks, now)
			return
		end
	end
end

-- ============ Plush Shark — guardian_revive ============

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
			local old = panel:child("csr_plush_shark_vignette")
			if old then
				panel:remove(old)
			end
			local bm = panel:bitmap({
				name = "csr_plush_shark_vignette",
				texture = PLUSH_VIGNETTE,
				blend_mode = "add",
				-- 4-arg per Rule #6: blue (r=0, g=0.4, b=1). The 6.2 line wrote a
				-- 3-arg Color(0, 0.4, 1), which Diesel reads as (a=0, r=0.4, g=1) =
				-- green, not the intended blue. Alpha is driven by the pulse anim.
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
			local v = hud_script.panel:child("csr_plush_shark_vignette")
			if v then
				local start_alpha = v:alpha()
				v:animate(function(o)
					local t = 0.3
					while t > 0 do
						t = math.max(t - coroutine.yield(), 0)
						o:set_alpha(t / 0.3 * start_alpha)
					end
				end)
				DelayedCalls:Add("CSR_PlushVignetteRemove", 0.4, function()
					pcall(function()
						local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
						local p = s and s.panel and s.panel:child("csr_plush_shark_vignette")
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
-- and open the invuln window. Returns true if it fired (so The Edge stands down).
local function try_plush_guardian(self, mgr, now)
	if not self._csr_plush_charge then
		return false
	end
	-- Only the LAST down before custody: revives == 1 means the next bleed-out
	-- vanilla would decrement 1 -> 0 and route straight to custody.
	if (self:get_revives() or 0) ~= 1 then
		return false
	end
	local items = mgr:items_of_kind("guardian_revive")
	local pid = mgr:local_peer_id()
	local item, stacks
	for i = 1, #items do
		local n = mgr:item_count(pid, items[i].type)
		if n > 0 then
			item, stacks = items[i], n
			break
		end
	end
	if not item then
		return false
	end

	local e = item.effect
	local max_hp = self:_max_health()
	if max_hp and max_hp > 0 then
		self:set_health(max_hp * (e.heal_pct or 1.00))
	end
	if e.restore_armor ~= false then
		self:set_armor(self:_max_armor())
	end

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

	local duration = (e.invuln_base or 10) + math.max(0, stacks - 1) * (e.invuln_extra or 20)
	self._csr_plush_invuln_end = now + duration
	self._csr_plush_charge = false

	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("plush_shark_activate", { volume = 0.85 })
	end
	plush_start_visuals(self, duration)
	if mgr:debug_enabled() then
		mgr:debug_log(string.format("plush_shark guardian fired (invuln %.0fs)", duration))
	end
	return true
end

-- ============ Hooks ============

if PlayerDamage and not _G._CSR_ITEM_EFFECTS_REGEN_HOOKED then
	_G._CSR_ITEM_EFFECTS_REGEN_HOOKED = true

	-- Worn Band-Aid: heal-over-time. Per-item timers on self._csr_regen_timers so a
	-- second regen item with a different interval ticks at its own cadence.
	-- Hyperbolic stacking: k = (max_pct - first_pct)/first_pct, regen_pct =
	-- max_pct*stacks/(stacks + k) (= first_pct at 1 stack, asymptotes to max_pct).
	Hooks:PostHook(PlayerDamage, "update", "CSR_RegenTick", function(self, unit, t, dt)
		local mgr = csr_mgr()
		if not mgr then
			return
		end
		if self:is_downed() or self:dead() then
			return
		end

		self._csr_regen_timers = self._csr_regen_timers or {}

		local heal_total = 0
		local pid = mgr:local_peer_id()
		local max_hp_cached -- read once per tick, only if needed

		local items = mgr:items_of_kind("regen_max_hp_pct")
		for i = 1, #items do
			local item = items[i]
			local e = item.effect
			local stacks = mgr:item_count(pid, item.type)
			if stacks > 0 then
				local interval = e.interval or 5
				local timer = (self._csr_regen_timers[item.type] or 0) + dt
				if timer >= interval then
					timer = timer - interval
					local first = e.first_pct or 0.01
					local maxp = e.max_pct or 0.20
					local k = (maxp - first) / first
					local pct = maxp * stacks / (stacks + k)
					max_hp_cached = max_hp_cached or self:_max_health()
					heal_total = heal_total + max_hp_cached * pct
					if mgr:debug_enabled() then
						mgr:debug_log(
							string.format("worn_bandaid tick +%.1f HP (stacks=%d)", max_hp_cached * pct, stacks)
						)
					end
				end
				self._csr_regen_timers[item.type] = timer
			else
				-- No longer owned: reset its timer so a re-pick doesn't fire a partial cycle.
				self._csr_regen_timers[item.type] = 0
			end
		end

		if heal_total > 0 then
			self:set_health(self:get_real_health() + heal_total)
		end
	end)

	-- The Edge / Plush Shark — lethal down. Heal BEFORE vanilla _check_bleed_out
	-- runs: it gates its whole body on get_real_health() == 0, so a heal here
	-- cancels the bleed-out (a PreHook return cannot abort the original in SuperBLT).
	-- Plush Shark takes priority, then The Edge.
	Hooks:PreHook(PlayerDamage, "_check_bleed_out", "CSR_Survival_BleedOut", function(self)
		local mgr = csr_mgr()
		if not mgr or not is_local_pd(self) or not self.get_real_health then
			return
		end
		if self:get_real_health() > 0 then
			return
		end
		local now = TimerManager:game():time()
		if try_plush_guardian(self, mgr, now) then
			return
		end
		try_edge_lethal(self, mgr, now)
	end)

	-- The Edge — non-lethal: HP dropped below the threshold but stayed above 0.
	local function on_damage(self)
		local mgr = csr_mgr()
		if not mgr or not is_local_pd(self) or not self.get_real_health then
			return
		end
		local now = TimerManager:game():time()
		-- Inside an Edge invuln window, restore the saved HP (covers DOT/fire that
		-- slips past _chk_can_take_dmg).
		if self._csr_edge_invuln_end and now < self._csr_edge_invuln_end then
			if self._csr_edge_saved_hp then
				self:set_health(self._csr_edge_saved_hp)
			end
			return
		end
		if self:get_real_health() <= 0 then
			return -- lethal path owns this
		end
		try_edge_threshold(self, mgr, now)
	end
	Hooks:PostHook(PlayerDamage, "damage_bullet", "CSR_Survival_Bullet", on_damage)
	Hooks:PostHook(PlayerDamage, "damage_melee", "CSR_Survival_Melee", on_damage)
	Hooks:PostHook(PlayerDamage, "damage_explosion", "CSR_Survival_Explosion", on_damage)

	-- Shared invuln gate (The Edge + Plush Shark): block damage while either window
	-- is open. PostHook return overrides the original; returning nothing keeps it.
	Hooks:PostHook(PlayerDamage, "_chk_can_take_dmg", "CSR_Survival_Invuln", function(self)
		if not self._csr_plush_invuln_end and not self._csr_edge_invuln_end then
			return
		end
		local now = TimerManager:game():time()
		if self._csr_plush_invuln_end and now < self._csr_plush_invuln_end then
			return false
		end
		if self._csr_edge_invuln_end and now < self._csr_edge_invuln_end then
			return false
		end
	end)

	-- Plush Shark invuln visuals: count the radial down, fade the vignette when the
	-- window ends. Zero cost until the guardian fires.
	Hooks:PostHook(PlayerDamage, "update", "CSR_Survival_PlushVisuals", function(self, unit, t, dt)
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

	-- Reset per-life state on (re)spawn. Refreshes Plush Shark's charge on heist
	-- start and custody release, but not on a teammate revive (same unit).
	Hooks:PostHook(PlayerDamage, "init", "CSR_Survival_Init", function(self)
		self._csr_edge_cd = nil
		self._csr_edge_invuln_end = nil
		self._csr_edge_saved_hp = nil
		self._csr_plush_charge = true
		self._csr_plush_invuln_end = nil
		self._csr_plush_active = false
		self._csr_plush_duration = nil
	end)
end
