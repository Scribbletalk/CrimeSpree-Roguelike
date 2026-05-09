-- Crime Spree Roguelike - Civilian Damage Hook
-- Calls OnCivilianKilled() for active Civilian Alarm modifiers when a civilian dies

if not RequiredScript then
	return
end

-- === GUILT FLASH (red vignette) ===
-- Registers texture through DB:create_entry, then displays it as a
-- red additive bitmap over the fullscreen HUD panel, fading out over 0.5s.

local FLASH_DURATION = 0.5
local FLASH_COLOR = Color(1, 0, 0)
local FLASH_TEX_PATH = "csr/guilt_vignette"

-- Register vignette texture via DB:create_entry (no BeardLib dependency)
pcall(function()
	local file = ModPath .. "assets/csr/guilt_vignette.texture"
	DB:create_entry(Idstring("texture"), Idstring(FLASH_TEX_PATH), file)
end)

local function trigger_guilt_flash()
	pcall(function()
		local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if not hud_script or not hud_script.panel then
			return
		end
		local panel = hud_script.panel

		-- Remove any previous flash still fading out
		local existing = panel:child("csr_guilt_flash")
		if existing then
			panel:remove(existing)
		end

		local bm = panel:bitmap({
			name = "csr_guilt_flash",
			texture = FLASH_TEX_PATH,
			blend_mode = "add",
			color = FLASH_COLOR,
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			layer = 200,
		})

		-- Fade out over FLASH_DURATION seconds
		bm:animate(function(o)
			local t = FLASH_DURATION
			while t > 0 do
				local dt = coroutine.yield()
				t = math.max(t - dt, 0)
				o:set_alpha(t / FLASH_DURATION)
			end
		end)

		-- Remove bitmap after animation ends
		DelayedCalls:Add("CSR_GuiltFlashRemove", FLASH_DURATION + 0.1, function()
			pcall(function()
				local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
				if s and s.panel then
					local p = s.panel:child("csr_guilt_flash")
					if p then
						s.panel:remove(p)
					end
				end
			end)
		end)
	end)
end

-- === CIVILIAN DEATH HOOK ===

local original_die = CivilianDamage.die

_G.CSR_SafeOverride(CivilianDamage, "die", "Guilty Conscience", original_die, function(self, attack_data, ...)
	local result = original_die(self, attack_data, ...)

	if managers.crime_spree and managers.crime_spree:is_active() then
		-- CIVILIAN GUILT: works in both stealth and loud, but ONLY if the local player
		-- killed the civilian. Deaths from cops, teammates, or environment don't count.
		local killed_by_local_player = attack_data
			and attack_data.attacker_unit
			and alive(attack_data.attacker_unit)
			and attack_data.attacker_unit:base()
			and attack_data.attacker_unit:base().is_local_player == true

		if killed_by_local_player and CSR_ActiveBuffs and CSR_ActiveBuffs.civilian_guilt then
			-- Cap is reached when guilt_max_penalty / guilt_hp_penalty kills are done
			local GC = _G.CSR_ItemConstants or {}
			local max_kills = math.floor((GC.guilt_max_penalty or 0.30) / (GC.guilt_hp_penalty or 0.05))
			local still_reducing = (_G.CSR_CivilianGuiltKills or 0) < max_kills

			_G.CSR_CivilianGuiltKills = (_G.CSR_CivilianGuiltKills or 0) + 1

			-- Cap current HP to new (reduced) max HP
			pcall(function()
				local player_unit = managers.player and managers.player:player_unit()
				if not player_unit or not alive(player_unit) then
					return
				end
				local char_dmg = player_unit:character_damage()
				if not char_dmg then
					return
				end

				local new_max = char_dmg:_max_health()
				local current = char_dmg:get_real_health()
				if current > new_max then
					char_dmg:set_health(new_max)
					if char_dmg._send_set_health then
						char_dmg:_send_set_health()
					end
				end
			end)

			-- Brief red edge flash, only while max HP is still being reduced
			if still_reducing then
				trigger_guilt_flash()
			end
		end

		-- NOTE: Civilian Alarm modifier only works in stealth
		local in_stealth = managers.groupai and managers.groupai:state():whisper_mode()

		if not in_stealth then
			return result
		end

		-- Cheap pre-check: skip the scan entirely if no civilian_alarm modifier is active
		local any_alarm = _G.CSR_HasModifierPrefix
			and (
				CSR_HasModifierPrefix("civilian_alarm_1_")
				or CSR_HasModifierPrefix("civilian_alarm_2_")
				or CSR_HasModifierPrefix("civilian_alarm_3_")
			)

		if any_alarm then
			local active_modifiers = managers.crime_spree:active_modifiers()
			if active_modifiers then
				for _, modifier_data in ipairs(active_modifiers) do
					if
						modifier_data.id
						and (
							modifier_data.id:match("civilian_alarm_1_")
							or modifier_data.id:match("civilian_alarm_2_")
							or modifier_data.id:match("civilian_alarm_3_")
						)
					then
						local modifier_class = modifier_data.class
						if modifier_class and modifier_class.OnCivilianKilled then
							modifier_class:OnCivilianKilled()
						end
					end
				end
			end
		end
	end

	return result
end)
