-- TURRON — Wildcard active item.
-- On key press: instant +33% max HP heal + 5s 20% damage reduction window.
-- 90s cooldown. Stealth-allowed (no whisper-mode break — heal/DR aren't loud).
-- Carry-1 wildcard. Registered with the wildcard dispatcher.
--
-- Damage reduction: PreHook on PlayerDamage:_calc_armor_damage — that's the
-- funnel for all damage variants (bullet/melee/explosion/fire) per
-- pd2_calc_armor_damage_funnel.md. Reducing attack_data.damage there scales
-- both armor consumption AND leftover-to-HP uniformly.

if not RequiredScript then
	return
end

ModifierTurron = ModifierTurron or class(CSRBaseModifier)
ModifierTurron.desc_id = "csr_turron_desc"
ModifierTurron.icon = "csr_turron"

local function const(key, default)
	-- Re-read each call so live tweaks via base_modifier.lua reload pick up.
	local t = _G.CSR_ItemConstants or {}
	if t[key] ~= nil then
		return t[key]
	end
	return default
end

-- Per-player active state. Reset on spawn / new heist via spawned_player.
_G.CSR_Turron = _G.CSR_Turron
	or {
		cooldown_end = 0, -- game time when the next press is allowed
		dr_end = 0, -- game time when the DR window closes
	}

local function fire_hud_buff_event(name, duration)
	if CSR_VHUDPlusEvent then
		pcall(CSR_VHUDPlusEvent, "timed_buff", "activate", name, {
			t = TimerManager:game():time(),
			duration = duration,
		})
	end
	if CSR_WFHudEvent then
		pcall(CSR_WFHudEvent, "activate", name, { duration = duration })
	end
	if CSR_PocoHudEvent then
		pcall(CSR_PocoHudEvent, "activate", name, { duration = duration })
	end
end

-- Subtle green DR vignette. Reuses the existing `csr/guilt_vignette` texture
-- (alpha-mask vignette shape, colour applied via bitmap), tinted green and
-- held for the 5s DR window. Fades in fast, holds, then fades out smoothly
-- so the player gets a clear "protection ending" cue.
local VIGNETTE_TEX_PATH = "csr/guilt_vignette"
local VIGNETTE_NAME = "csr_turron_dr_vignette"
local VIGNETTE_COLOR = Color(1, 0.2, 1.0, 0.4) -- soft green-cyan; subtle, not neon
local VIGNETTE_ALPHA_PEAK = 0.22
local VIGNETTE_FADE_IN = 0.2
local VIGNETTE_FADE_OUT = 0.6

-- ModPath can be overwritten by later-loading mods (ProjectCellBeta, BeardLib)
-- between file load and DelayedCalls — capture now per plush_shark_guardian.lua
-- pattern. Registration is idempotent under pcall; same Idstring is also
-- registered by plush_shark_guardian.lua / civilian_damage_hook.lua.
local SAVED_MOD_PATH = ModPath
pcall(function()
	local file = SAVED_MOD_PATH .. "assets/csr/guilt_vignette.texture"
	DB:create_entry(Idstring("texture"), Idstring(VIGNETTE_TEX_PATH), file)
end)

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
			texture = VIGNETTE_TEX_PATH,
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
			if hold > 0 then
				local h = 0
				while h < hold do
					local dt = coroutine.yield()
					h = h + dt
				end
			end
			local fade_out_t = 0
			while fade_out_t < VIGNETTE_FADE_OUT do
				local dt = coroutine.yield()
				fade_out_t = fade_out_t + dt
				o:set_alpha(VIGNETTE_ALPHA_PEAK * (1 - fade_out_t / VIGNETTE_FADE_OUT))
			end
			o:set_alpha(0)
		end)
		-- Belt-and-suspenders cleanup: remove the bitmap shortly after the
		-- animation finishes, in case the coroutine was interrupted.
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

-- Cooldown-ready chime. Suppressed if the player has left the heist or no
-- longer owns the item (mirrors the FF pattern).
local function play_cooldown_ready()
	if not _G.CSR_PlaySound then
		return
	end
	if not (managers and managers.crime_spree and managers.crime_spree:is_active()) then
		return
	end
	-- End-screen: is_active() stays true through victoryscreen/gameoverscreen.
	if game_state_machine then
		local state = game_state_machine:current_state_name()
		if state == "victoryscreen" or state == "gameoverscreen" then
			return
		end
	end
	if not _G.CSR_CountStacks or CSR_CountStacks("player_turron_") <= 0 then
		return
	end
	-- 2D so the player always hears it regardless of camera position.
	pcall(_G.CSR_PlaySound, "turron_recharge")
end

local function activate_turron(player_unit)
	-- Cooldown gate.
	local now = TimerManager:game():time()
	if now < (_G.CSR_Turron.cooldown_end or 0) then
		return
	end

	if not alive(player_unit) then
		return
	end

	local cdmg = player_unit:character_damage()
	if not cdmg then
		return
	end
	-- Down / arrested / dead are filtered by the dispatcher already, but the
	-- 0.6s charge delay in FF means re-checks are cheap insurance against
	-- state changes between dispatch and execution. Turron has no charge
	-- delay, but keep the guard for symmetry.
	if cdmg.dead and cdmg:dead() then
		return
	end
	if cdmg.bleed_out and cdmg:bleed_out() then
		return
	end
	if cdmg.arrested and cdmg:arrested() then
		return
	end

	local heal_pct = const("turron_heal_pct", 0.33)
	local dr_duration = const("turron_dr_duration", 5)
	local cooldown = const("turron_cooldown", 90)

	-- Activation SFX.
	if _G.CSR_PlaySound then
		pcall(_G.CSR_PlaySound, "turron_activate", { unit = player_unit })
	end

	-- Instant heal: percent-of-max via restore_health(pct, is_static=false).
	-- Vanilla _max_health() cap is enforced inside change_health.
	if cdmg.restore_health then
		pcall(cdmg.restore_health, cdmg, heal_pct, false)
	end

	-- Open the DR window. The PreHook below reads dr_end on every damage tick.
	_G.CSR_Turron.dr_end = now + dr_duration
	_G.CSR_Turron.cooldown_end = now + cooldown

	fire_hud_buff_event("csr_turron_dr", dr_duration)
	fire_hud_buff_event("csr_turron_cd", cooldown)

	-- Visual feedback: subtle green vignette for the DR window with fade-out.
	show_dr_vignette(dr_duration)

	-- Schedule the cooldown-ready chime to match the cooldown end timestamp.
	DelayedCalls:Add("CSR_Turron_CooldownReady", cooldown, play_cooldown_ready)
end

-- DR PreHook: scale incoming damage by (1 - dr_pct) while the window is open.
-- Hooks PlayerDamage:_calc_armor_damage — the funnel for all damage variants.
-- Per pd2_calc_armor_damage_funnel.md, ONE PreHook covers every variant.
if PlayerDamage and not _G._CSR_TURRON_DR_HOOKED then
	_G._CSR_TURRON_DR_HOOKED = true

	Hooks:PreHook(PlayerDamage, "_calc_armor_damage", "CSR_Turron_DR", function(self, attack_data)
		if not attack_data or not attack_data.damage then
			return
		end
		-- Local-player only — _G.CSR_Turron state is per-machine, not per-unit.
		local player_unit = self._unit
		if not player_unit or not alive(player_unit) then
			return
		end
		local base = player_unit.base and player_unit:base()
		if not base or base.is_local_player ~= true then
			return
		end
		-- In-CS only.
		if not (managers.crime_spree and managers.crime_spree:is_active()) then
			return
		end
		-- Owned + window-open gate.
		if not _G.CSR_CountStacks or CSR_CountStacks("player_turron_") <= 0 then
			return
		end
		local now = TimerManager:game():time()
		if now > (_G.CSR_Turron.dr_end or 0) then
			return
		end
		local dr_pct = const("turron_dr_pct", 0.20)
		attack_data.damage = attack_data.damage * (1 - dr_pct)
	end)
end

-- Reset cooldown + DR on spawn (per-heist).
if PlayerManager and not _G._CSR_TURRON_PM_HOOKED then
	_G._CSR_TURRON_PM_HOOKED = true

	Hooks:PostHook(PlayerManager, "spawned_player", "CSR_TurronInit", function(self)
		_G.CSR_Turron.cooldown_end = 0
		_G.CSR_Turron.dr_end = 0
	end)

	-- Register with the wildcard dispatcher.
	if _G.CSR_RegisterWildcardActive then
		_G.CSR_RegisterWildcardActive("player_turron_", activate_turron)
	end
end
