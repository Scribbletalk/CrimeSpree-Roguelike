-- Turron (wildcard) — on key press: instant +33% max HP heal + a 5s window of
-- 33% damage reduction. 90s cooldown. Stealth-allowed (heal/DR aren't loud).
--
-- Active item: registered with the wildcard dispatcher. The dispatcher already
-- gates in_csr_heist / down / arrested before calling us.
--
-- DR is applied via a PreHook on PlayerDamage:_calc_armor_damage — the single
-- funnel for every damage variant (bullet/melee/explosion/fire), so one hook
-- scales armor consumption AND leftover-to-HP uniformly.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local HEAL_PCT = 0.33 -- instant heal: 33% of max HP
local DR_PCT = 0.33 -- 33% incoming damage reduction during the window
local DR_DURATION = 5 -- seconds the DR window stays open
local COOLDOWN = 90

-- Green DR vignette (reuses the shared csr_guilt_vignette alpha-mask shape).
local VIGNETTE_TEX = "guis/textures/pd2/crime_spree/csr_guilt_vignette"
local VIGNETTE_NAME = "csr_turron_dr_vignette"
local VIGNETTE_COLOR = Color(1, 0.2, 1.0, 0.4) -- soft green; subtle, not neon
local VIGNETTE_ALPHA_PEAK = 0.22
local VIGNETTE_FADE_IN = 0.2
local VIGNETTE_FADE_OUT = 0.6

-- Per-heist active state. File-locals (file dofile'd once). Reset in spawned_player.
local cooldown_end = 0
local dr_end = 0

local function csr_mgr()
	local mgr = managers and managers.csr
	if mgr and mgr.in_csr_heist and mgr:in_csr_heist() then
		return mgr
	end
	return nil
end

local function is_local_pd(self)
	local pu = managers.player and managers.player:player_unit()
	return pu and self._unit == pu
end

-- Subtle green vignette held for the DR window: fade in, hold, fade out.
local function show_dr_vignette(duration)
	pcall(function()
		local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if not hud_script or not hud_script.panel then
			return
		end
		local panel = hud_script.panel
		local existing = panel:child(VIGNETTE_NAME)
		if existing then
			panel:remove(existing)
		end
		local bm = panel:bitmap({
			name = VIGNETTE_NAME,
			texture = VIGNETTE_TEX,
			blend_mode = "add",
			color = VIGNETTE_COLOR,
			alpha = 0,
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			layer = 200,
		})
		bm:animate(function(o)
			local fade_in_t = 0
			while fade_in_t < VIGNETTE_FADE_IN do
				local dt = coroutine.yield()
				fade_in_t = fade_in_t + dt
				o:set_alpha(VIGNETTE_ALPHA_PEAK * (fade_in_t / VIGNETTE_FADE_IN))
			end
			o:set_alpha(VIGNETTE_ALPHA_PEAK)
			local hold = duration - VIGNETTE_FADE_IN - VIGNETTE_FADE_OUT
			while hold > 0 do
				hold = hold - coroutine.yield()
			end
			local fade_out_t = 0
			while fade_out_t < VIGNETTE_FADE_OUT do
				local dt = coroutine.yield()
				fade_out_t = fade_out_t + dt
				o:set_alpha(VIGNETTE_ALPHA_PEAK * (1 - fade_out_t / VIGNETTE_FADE_OUT))
			end
			o:set_alpha(0)
		end)
		-- Belt-and-suspenders: remove the bitmap shortly after the anim finishes.
		DelayedCalls:Add("CSR_Turron_VignetteRemove", duration + 0.2, function()
			pcall(function()
				local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
				if s and s.panel then
					local p = s.panel:child(VIGNETTE_NAME)
					if p then
						s.panel:remove(p)
					end
				end
			end)
		end)
	end)
end

-- Cooldown-ready chime. Suppressed if the player left the heist or no longer owns it.
local function play_cooldown_ready()
	local mgr = csr_mgr()
	if not mgr then
		return
	end
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		if state == "victoryscreen" or state == "gameoverscreen" then
			return
		end
	end
	if mgr:owned("turron") <= 0 then
		return
	end
	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("turron_recharge")
	end
end

-- Dispatcher entry point. player_unit is the local player (dispatcher-validated).
local function activate_turron(player_unit)
	local mgr = csr_mgr()
	if not mgr then
		return
	end
	if mgr:owned("turron") <= 0 then
		return
	end
	local now = TimerManager:game():time()
	if now < (cooldown_end or 0) then
		return
	end
	if not alive(player_unit) then
		return
	end
	local cdmg = player_unit:character_damage()
	if not cdmg then
		return
	end
	if (cdmg.dead and cdmg:dead()) or (cdmg.bleed_out and cdmg:bleed_out()) or (cdmg.arrested and cdmg:arrested()) then
		return
	end

	if _G.CSR and _G.CSR.play_sound then
		_G.CSR.play_sound("turron_activate", { unit = player_unit })
	end

	-- Instant heal: percent-of-max. _max_health() cap enforced inside change_health.
	if cdmg.restore_health then
		pcall(cdmg.restore_health, cdmg, HEAL_PCT, false)
	end

	dr_end = now + DR_DURATION
	cooldown_end = now + COOLDOWN
	if _G.CSR_SetWildcardCooldown then
		_G.CSR_SetWildcardCooldown("turron", cooldown_end, COOLDOWN)
	end

	show_dr_vignette(DR_DURATION)
	DelayedCalls:Add("CSR_Turron_CooldownReady", COOLDOWN, play_cooldown_ready)
end

_G.CSR.register_item({
	type = "turron",
	rarity = "wildcard",
	name = "csr_logbook_turron_name",
	desc = "csr_item_turron_desc",
	full_desc = "csr_logbook_turron_effect",
	notes = "csr_logbook_turron_notes",
	icon = "csr_turron",
	icon_scale = 1.0,

	hooks = {
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_TURRON_DR_HOOKED then
				return
			end
			_G._CSR_TURRON_DR_HOOKED = true

			-- Scale incoming damage by (1 - DR) while the window is open. One PreHook
			-- on the _calc_armor_damage funnel covers every variant.
			Hooks:PreHook(PlayerDamage, "_calc_armor_damage", "CSR_Turron_DR", function(self, attack_data)
				if not attack_data or not attack_data.damage then
					return
				end
				if not is_local_pd(self) then
					return
				end
				if not csr_mgr() then
					return
				end
				local mgr = managers.csr
				if mgr:owned("turron") <= 0 then
					return
				end
				if TimerManager:game():time() > (dr_end or 0) then
					return
				end
				attack_data.damage = attack_data.damage * (1 - DR_PCT)
			end)
		end,

		["lib/managers/playermanager"] = function()
			if _G._CSR_TURRON_PM_HOOKED then
				return
			end
			_G._CSR_TURRON_PM_HOOKED = true

			-- Reset cooldown + DR on spawn (per-heist).
			Hooks:PostHook(PlayerManager, "spawned_player", "CSR_TurronInit", function()
				cooldown_end = 0
				dr_end = 0
				if _G.CSR_SetWildcardCooldown then
					_G.CSR_SetWildcardCooldown("turron", 0, COOLDOWN)
				end
			end)

			-- Register with the wildcard dispatcher (idempotent — keyed by type).
			if _G.CSR_RegisterWildcardActive then
				_G.CSR_RegisterWildcardActive("turron", activate_turron)
			end
		end,
	},
})
