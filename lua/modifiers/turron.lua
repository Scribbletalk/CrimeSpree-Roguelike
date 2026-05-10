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
