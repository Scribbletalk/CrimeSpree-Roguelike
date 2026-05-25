-- Guilty Conscience (loud modifier) -- each civilian YOU kill permanently lowers
-- your max health for the mission (-5% per kill, capped at -30%) and flashes a red
-- vignette. Only the LOCAL player's kills count (teammates, cops, the environment
-- do not). Ported from the 6.2 mechanic, which lived in three places (playermanager
-- health_skill_multiplier + spawn reset, CivilianDamage:die hook, HUD flash); U1
-- keeps it all here via the modifier's behavior hooks.
--
-- No engine ModifierX class: the effect is hand-rolled below. The passport carries a
-- `hooks` table (same dispatch as items -- see extension_api register_modifier), so
-- each hook installs when its target script loads.
--
-- Values mirror the 6.2 constants guilt_hp_penalty (0.05) / guilt_max_penalty (0.30).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local HP_PENALTY_PER_KILL = 0.05
local MAX_PENALTY = 0.30
local VIGNETTE_TEX = "guis/textures/pd2/crime_spree/csr_guilt_vignette" -- registered in hudicons.lua
local FLASH_DURATION = 0.5

-- Run-scoped kill counter. File-local: the file is dofile'd once, so the hook
-- closures below all share it; spawned_player resets it per heist.
local guilt_kills = 0

-- True only when a run is active AND Guilty Conscience is in the active set for
-- this run (rank/seed-derived).
local function guilt_active()
	local mgr = managers and managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active() and mgr.active_modifiers) then
		return false
	end
	for _, e in ipairs(mgr:active_modifiers("loud")) do
		if e.id == "civilian_guilt" then
			return true
		end
	end
	return false
end

-- Brief red edge flash on the fullscreen HUD, fading over FLASH_DURATION. Vanilla
-- API, pcall-isolated (same panel:bitmap pattern as plush_shark.lua's vignette).
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
			color = Color(1, 1, 0, 0), -- 4-arg red (Rule #6)
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

_G.CSR.register_modifier({
	id = "civilian_guilt",
	category = "loud",
	loc = "menu_cs_modifier_civilian_guilt",
	icon = "csr_guilty_conscience",
	data = {},

	hooks = {
		-- Max-HP penalty + per-heist reset. health_skill_multiplier is a return-value
		-- method -> raw chain wrap (CSR convention, same as dog_tags.lua); the _G guard
		-- stops a double-wrap. Composes with dog_tags' own wrap (each captures its orig).
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

			-- Reset the per-heist counter when the local player spawns.
			Hooks:PostHook(PlayerManager, "spawned_player", "CSR_CivilianGuilt_Reset", function()
				guilt_kills = 0
			end)
		end,

		-- Kill tracking + HP cap + flash. die() receives attack_data (verified in pd2
		-- source). Only the LOCAL player's kills count; flash fires on every one.
		["lib/units/civilians/civiliandamage"] = function()
			if _G._CSR_CIVILIAN_GUILT_DIE_HOOKED then
				return
			end
			_G._CSR_CIVILIAN_GUILT_DIE_HOOKED = true

			Hooks:PostHook(CivilianDamage, "die", "CSR_CivilianGuilt_Die", function(self, attack_data)
				if not guilt_active() then
					return
				end
				local au = attack_data and attack_data.attacker_unit
				local by_local = au and alive(au) and au:base() and au:base().is_local_player == true
				if not by_local then
					return
				end

				guilt_kills = guilt_kills + 1

				-- Cap current HP to the freshly-lowered max (health_skill_multiplier now
				-- reflects the new kill count).
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
			end)
		end,
	},
})
