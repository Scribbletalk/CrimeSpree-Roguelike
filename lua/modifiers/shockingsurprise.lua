-- Crime Spree Roguelike - Shocking Surprise Modifier
-- Forced loud modifier: tasers release an electric burst on death,
-- slowing nearby players for a few seconds

if not RequiredScript then
	return
end

local required = string.lower(RequiredScript)

-- === COPDAMAGE HOOK: detect taser death ===
if required == "lib/units/enemies/cop/copdamage" then
	local function CSR_log(...)
		if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
			log("[CSR][ShockingSurprise] " .. table.concat({ ... }))
		end
	end

	local C = _G.CSR_ItemConstants or {}
	local RADIUS = C.shocking_surprise_radius or 500
	local SLOW_MUL = C.shocking_surprise_slow_mul or 0.4
	local DURATION = C.shocking_surprise_duration or 3
	local DECAY_TIME = C.shocking_surprise_decay or 0.5

	local function is_active()
		if not managers.crime_spree or not managers.crime_spree.is_active or not managers.crime_spree:is_active() then
			return false
		end
		return _G.CSR_HasModifierPrefix and CSR_HasModifierPrefix("csr_shocking_surprise") or false
	end

	-- Capture taser position BEFORE death (ragdoll mods may move the body)
	Hooks:PreHook(CopDamage, "die", "CSR_ShockingSurprise_CapturePos", function(self)
		local ok, tweak = pcall(function()
			return self._unit:base()._tweak_table
		end)
		if ok and tweak and string.find(tweak, "taser") then
			self._csr_death_pos = mvector3.copy(self._unit:position())
		end
	end)

	-- Apply slowdown to a single player unit (local).
	local function apply_slowdown_to_local(duration, slow_mul, decay_time)
		local player_unit = managers.player and managers.player:local_player()
		if not player_unit then
			return
		end
		local char_dmg = player_unit:character_damage()
		if not char_dmg or not char_dmg.apply_slowdown then
			return
		end
		pcall(function()
			char_dmg:apply_slowdown({
				id = "csr_shocking_surprise",
				mul = slow_mul,
				duration = duration,
				decay_time = decay_time,
				prevents_running = true,
			})
		end)
		if CSR_ShockingSurprise_ShowOverlay then
			CSR_ShockingSurprise_ShowOverlay(duration)
		end
	end

	-- Client receiver: host sends this when a taser died near a remote peer.
	Hooks:Add("NetworkReceivedData", "CSR_ShockingSurprise_Net", function(sender, id, data)
		if id ~= "CSR_ShockingSurprise" then
			return
		end
		if not is_active() then
			return
		end
		local C2 = _G.CSR_ItemConstants or {}
		apply_slowdown_to_local(
			C2.shocking_surprise_duration or 3,
			C2.shocking_surprise_slow_mul or 0.4,
			C2.shocking_surprise_decay or 0.5
		)
		CSR_log("Received ShockingSurprise from host, slowdown applied")
	end)

	Hooks:PostHook(CopDamage, "die", "CSR_ShockingSurprise_OnDeath", function(self, attack_data)
		if not is_active() then
			return
		end

		-- Check if this enemy is a taser (position was captured in PreHook)
		local taser_pos = self._csr_death_pos
		if not taser_pos then
			return
		end
		self._csr_death_pos = nil

		-- 1 second delay before effect
		local pos_copy = mvector3.copy(taser_pos)
		DelayedCalls:Add("CSR_ShockingSurprise_" .. tostring(self._unit:key()), 1, function()
			-- Electric grenade visual effect + sound
			local eff_ok, eff_err = pcall(function()
				World:effect_manager():spawn({
					effect = Idstring("effects/particles/explosions/electric_grenade"),
					position = pos_copy,
					normal = math.UP,
				})
			end)
			if not eff_ok then
				log("[CSR][ShockingSurprise] Effect spawn error: " .. tostring(eff_err))
			end

			local snd_ok, snd_err = pcall(function()
				local sound_source = SoundDevice:create_source("csr_shocking_surprise")
				sound_source:set_position(pos_copy)
				sound_source:post_event("gl_electric_explode")
			end)
			if not snd_ok then
				log("[CSR][ShockingSurprise] Sound error: " .. tostring(snd_err))
			end

			-- Apply slowdown to local player (host-side)
			local player_unit = managers.player and managers.player:local_player()
			if player_unit then
				local player_pos = player_unit:position()
				if player_pos then
					local dist = mvector3.distance(pos_copy, player_pos)
					if dist <= RADIUS then
						CSR_log("Taser died within range of host (" .. math.floor(dist) .. "cm), applying slowdown")
						apply_slowdown_to_local(DURATION, SLOW_MUL, DECAY_TIME)
					end
				end
			end

			-- Notify remote peers who are within range (host only)
			if CSR_MP and CSR_MP.is_host and CSR_MP.is_host() and LuaNetworking then
				local session = managers.network and managers.network:session()
				if session and managers.criminals then
					for _, peer in pairs(session:peers() or {}) do
						local pid = peer and peer:id()
						if pid and pid ~= 1 then
							local peer_unit = managers.criminals:character_unit_by_peer_id(pid)
							if peer_unit and alive(peer_unit) then
								local peer_pos = peer_unit:position()
								if peer_pos then
									local dist = mvector3.distance(pos_copy, peer_pos)
									if dist <= RADIUS then
										CSR_log(
											"Taser died within range of peer "
												.. pid
												.. " ("
												.. math.floor(dist)
												.. "cm), notifying"
										)
										LuaNetworking:SendToPeer(pid, "CSR_ShockingSurprise", "")
									end
								end
							end
						end
					end
				end
			end
		end)
	end)

-- === PLAYERDAMAGE HOOK: screen overlay during slowdown ===
elseif required == "lib/units/beings/player/playerdamage" then
	local OVERLAY_TEX = "csr/shocking_surprise_screen_overlay"
	local OVERLAY_NAME = "csr_shocking_surprise_overlay"
	local FLICKER_INTERVAL = 0.08 -- seconds between flicker updates

	-- Register overlay texture via DB:create_entry
	pcall(function()
		local file = ModPath .. "assets/csr/shocking_surprise_screen_overlay.texture"
		DB:create_entry(Idstring("texture"), Idstring(OVERLAY_TEX), file)
	end)

	-- Show flickering fullscreen electric overlay
	local OVERLAY_NAME = "csr_ss_fullscreen"

	function CSR_ShockingSurprise_ShowOverlay(duration)
		pcall(function()
			local hud_script = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
			if not hud_script or not hud_script.panel then
				return
			end
			local panel = hud_script.panel

			-- Remove existing overlay
			local existing = panel:child(OVERLAY_NAME)
			if existing then
				panel:remove(existing)
			end

			-- Scale up slightly and center so vignette edges extend beyond screen bounds
			local scale = 1.25
			local bw = math.floor(panel:w() * scale)
			local bh = math.floor(panel:h() * scale)
			local bx = math.floor((panel:w() - bw) / 2)
			local by = math.floor((panel:h() - bh) / 2)

			local bmp = panel:bitmap({
				name = OVERLAY_NAME,
				texture = OVERLAY_TEX,
				blend_mode = "add",
				color = Color.white,
				alpha = 0.4,
				x = bx,
				y = by,
				w = bw,
				h = bh,
				layer = 200,
			})

			-- Flickering animation
			bmp:animate(function(o)
				local t = duration
				local flicker_timer = 0
				while t > 0 do
					local dt = coroutine.yield()
					t = t - dt
					flicker_timer = flicker_timer + dt
					if flicker_timer >= FLICKER_INTERVAL then
						flicker_timer = 0
						o:set_alpha(0.2 + math.random() * 0.5)
					end
					if t < 0.5 then
						o:set_alpha(o:alpha() * (t / 0.5))
					end
				end
				o:set_alpha(0)
			end)

			-- Remove bitmap after duration
			DelayedCalls:Add("CSR_ShockingSurprise_OverlayRemove", duration + 0.2, function()
				pcall(function()
					local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
					if s and s.panel then
						local p = s.panel:child(OVERLAY_NAME)
						if p then
							s.panel:remove(p)
						end
					end
				end)
			end)
		end)
	end
end -- RequiredScript routing

-- === MODIFIER STUB CLASS ===
if not ModifierNoHurtAnims then
	return
end

ModifierShockingSurprise = class(ModifierNoHurtAnims)
ModifierShockingSurprise.desc_id = "menu_cs_modifier_shocking_surprise"

function ModifierShockingSurprise:init(data)
	-- No-op: effect is handled dynamically via CopDamage death hook
end

function ModifierShockingSurprise:modify_value(id, value)
	-- Override parent: shocking surprise should NOT block stagger animations
	return value
end
