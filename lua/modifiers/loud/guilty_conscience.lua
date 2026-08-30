-- Guilty Conscience (loud) — each civ YOU kill permanently lowers your max HP
-- for the heist (-5% per kill, capped at -30%) and flashes a red vignette.
-- Class-less / hand-rolled — effect lives in the hooks below.

if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local HP_PENALTY_PER_KILL = 0.05
local MAX_PENALTY = 0.30
local HP_PENALTY_PCT = string.format("%g", HP_PENALTY_PER_KILL * 100)
local MAX_PENALTY_PCT = string.format("%g", MAX_PENALTY * 100)
local VIGNETTE_TEX = "guis/textures/pd2/crime_spree/csr_guilt_vignette"
local FLASH_DURATION = 0.5

-- Run-scoped, reset on spawn.
local guilt_kills = 0

local function guilt_active()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist() and mgr.active_modifiers) then
		return false
	end
	for _, e in ipairs(mgr:active_modifiers("loud")) do
		if e.id == "civilian_guilt" then
			return true
		end
	end
	return false
end

local function trigger_guilt_flash()
	pcall(function()
		local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if not (hud and hud.panel) then
			return
		end
		local panel = hud.panel
		local old = panel:child("csr_guilt_flash")
		if old then
			panel:remove(old)
		end
		local bm = panel:bitmap({
			name = "csr_guilt_flash",
			texture = VIGNETTE_TEX,
			blend_mode = "add",
			color = Color(1, 1, 0, 0),
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			layer = 200,
		})
		bm:animate(function(o)
			local t = FLASH_DURATION
			while t > 0 do
				t = math.max(t - coroutine.yield(), 0)
				o:set_alpha(t / FLASH_DURATION)
			end
		end)
		DelayedCalls:Add("CSR_GuiltFlashRemove", FLASH_DURATION + 0.1, function()
			pcall(function()
				local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
				local p = s and s.panel and s.panel:child("csr_guilt_flash")
				if p then
					s.panel:remove(p)
				end
			end)
		end)
	end)
end

-- Civ-death handler: count the LOCAL player's civ kills, cap HP to the lowered max, flash.
-- Shared by the CivilianDamage and HuskCivilianDamage die hooks (registered below).
local function handle_civ_death(_, attack_data)
	if not guilt_active() then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	local by_local = au and alive(au) and au:base() and au:base().is_local_player == true
	if not by_local then
		return
	end

	guilt_kills = guilt_kills + 1

	-- Cap current HP to the freshly-lowered max.
	local pu = managers.player and managers.player:player_unit()
	if pu and alive(pu) then
		local cd = pu:character_damage()
		if cd and cd._max_health and cd.get_real_health and cd.set_health then
			local new_max = cd:_max_health()
			if cd:get_real_health() > new_max then
				cd:set_health(new_max)
				if cd._send_set_health then
					cd:_send_set_health()
				end
			end
		end
	end

	trigger_guilt_flash()
end

_G.CSR.register_modifier({
	id = "civilian_guilt",
	category = "loud",
	loc = "csr_modifier_civilian_guilt",
	icon = "csr_guilty_conscience",
	data = {},
	loc_macros = { pct = HP_PENALTY_PCT, max_pct = MAX_PENALTY_PCT },

	hooks = {
		-- HP penalty + reset on spawn.
		["lib/managers/playermanager"] = function()
			if _G._CSR_CIVILIAN_GUILT_HP_HOOKED then
				return
			end
			_G._CSR_CIVILIAN_GUILT_HP_HOOKED = true

			local orig = PlayerManager.health_skill_multiplier
			if orig then
				function PlayerManager:health_skill_multiplier()
					local v = orig(self)
					-- Short-circuit so the active-set scan is skipped until you kill one.
					if guilt_kills <= 0 or not guilt_active() then
						return v
					end
					local reduction = math.min(guilt_kills * HP_PENALTY_PER_KILL, MAX_PENALTY)
					return math.max(0.01, v * (1 - reduction))
				end
			end

			Hooks:PostHook(PlayerManager, "spawned_player", "CSR_CivilianGuilt_Reset", function()
				guilt_kills = 0
			end)
		end,

		-- Local-player civ kill: count + cap current HP to new max + flash.
		-- Hook BOTH CivilianDamage (host real units) and HuskCivilianDamage (guest's host-spawned
		-- civs): the husk class OVERRIDES die(), so a PostHook on the parent never fires for the
		-- guest's own kills. attack_data.attacker_unit is the local player on both paths, so the
		-- by_local gate inside handle_civ_death keeps each machine to its own kills (no double-count).
		["lib/units/civilians/civiliandamage"] = function()
			if _G._CSR_CIVILIAN_GUILT_DIE_HOOKED then
				return
			end
			_G._CSR_CIVILIAN_GUILT_DIE_HOOKED = true
			Hooks:PostHook(CivilianDamage, "die", "CSR_CivilianGuilt_Die", handle_civ_death)
		end,
		["lib/units/civilians/huskciviliandamage"] = function()
			if _G._CSR_CIVILIAN_GUILT_HUSK_DIE_HOOKED then
				return
			end
			_G._CSR_CIVILIAN_GUILT_HUSK_DIE_HOOKED = true
			Hooks:PostHook(HuskCivilianDamage, "die", "CSR_CivilianGuilt_Die_Husk", handle_civ_death)
		end,
	},
})
