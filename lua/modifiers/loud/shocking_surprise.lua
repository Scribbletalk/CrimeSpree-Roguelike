-- Shocking Surprise (loud) — a Taser death releases an electric burst that slows
-- every player in range. Host detects, applies to self, RPCs in-range clients;
-- clients trust the host (run seed isn't synced). See csr_modifier_file_pattern.md.

if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local RADIUS = 500
local SLOW_MUL = 0.4
local DURATION = 3
local DECAY_TIME = 0.5
local RPC_NAME = "CSR_ShockingSurprise"
local OVERLAY_TEX = "guis/textures/pd2/crime_spree/csr_shocking_overlay"
local FLICKER_INTERVAL = 0.08
local OVERLAY_SCALE = 1.25 -- >1 so edge arcs bleed past screen bounds

-- Host-side only (detection); clients trust the host.
local function ss_active()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist() and mgr.active_modifiers) then
		return false
	end
	for _, e in ipairs(mgr:active_modifiers("loud")) do
		if e.id == "shocking_surprise" then
			return true
		end
	end
	return false
end

local function show_overlay(duration)
	pcall(function()
		local hud = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
		if not (hud and hud.panel) then
			return
		end
		local panel = hud.panel
		local old = panel:child("csr_shocking_overlay")
		if old then
			panel:remove(old)
		end
		local bw = math.floor(panel:w() * OVERLAY_SCALE)
		local bh = math.floor(panel:h() * OVERLAY_SCALE)
		local bm = panel:bitmap({
			name = "csr_shocking_overlay",
			texture = OVERLAY_TEX,
			blend_mode = "add",
			color = Color(1, 1, 1, 1),
			alpha = 0.4,
			x = math.floor((panel:w() - bw) / 2),
			y = math.floor((panel:h() - bh) / 2),
			w = bw,
			h = bh,
			layer = 200,
		})
		bm:animate(function(o)
			local t = duration
			local flicker = 0
			while t > 0 do
				local dt = coroutine.yield()
				t = t - dt
				flicker = flicker + dt
				if flicker >= FLICKER_INTERVAL then
					flicker = 0
					o:set_alpha(0.2 + math.random() * 0.5)
				end
				if t < 0.5 then
					o:set_alpha(o:alpha() * math.max(t, 0) / 0.5)
				end
			end
			o:set_alpha(0)
		end)
		DelayedCalls:Add("CSR_ShockingOverlayRemove", duration + 0.2, function()
			pcall(function()
				local s = managers.hud and managers.hud:script(PlayerBase.PLAYER_INFO_HUD_FULLSCREEN_PD2)
				local p = s and s.panel and s.panel:child("csr_shocking_overlay")
				if p then
					s.panel:remove(p)
				end
			end)
		end)
	end)
end

-- Apply slow to local player + show overlay. Used both host-side and on RPC receive.
local function slow_local()
	local pu = managers.player and managers.player:player_unit()
	if not alive(pu) then
		return
	end
	local cd = pu:character_damage()
	if not (cd and cd.apply_slowdown) then
		return
	end
	pcall(function()
		cd:apply_slowdown({
			id = "csr_shocking_surprise",
			mul = SLOW_MUL,
			duration = DURATION,
			decay_time = DECAY_TIME,
			prevents_running = true,
		})
	end)
	show_overlay(DURATION)
end

_G.CSR.register_modifier({
	id = "shocking_surprise",
	category = "loud",
	loc = "menu_cs_modifier_shocking_surprise",
	icon = "csr_shocking_surprise",
	data = {},
	loc_macros = { dur = DURATION },

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_SHOCKING_SURPRISE_HOOKED then
				return
			end
			_G._CSR_SHOCKING_SURPRISE_HOOKED = true

			-- Snapshot the Taser position BEFORE death — ragdoll moves the corpse.
			Hooks:PreHook(CopDamage, "die", "CSR_ShockingSurprise_CapturePos", function(self)
				if not ss_active() then
					return
				end
				local base = self._unit and self._unit:base()
				if base and base._tweak_table == "taser" then
					local pos = Vector3(0, 0, 0)
					mvector3.set(pos, self._unit:position())
					self._csr_taser_death_pos = pos
				end
			end)

			-- Host: 1s after the Taser dies, burst + slow every in-range player.
			Hooks:PostHook(CopDamage, "die", "CSR_ShockingSurprise_OnDeath", function(self)
				if not Network:is_server() then
					return
				end
				local burst_pos = self._csr_taser_death_pos
				if not burst_pos then
					return
				end
				self._csr_taser_death_pos = nil

				DelayedCalls:Add("CSR_ShockingSurprise_" .. tostring(self._unit:key()), 1, function()
					pcall(function()
						World:effect_manager():spawn({
							effect = Idstring("effects/particles/explosions/electric_grenade"),
							position = burst_pos,
							normal = math.UP,
						})
					end)
					pcall(function()
						local src = SoundDevice:create_source("csr_shocking_surprise")
						src:set_position(burst_pos)
						src:post_event("gl_electric_explode")
					end)

					-- Host's own player, if in range.
					local hp = managers.player and managers.player:player_unit()
					if alive(hp) and mvector3.distance(burst_pos, hp:position()) <= RADIUS then
						slow_local()
					end

					-- Notify in-range remote peers.
					if LuaNetworking and managers.network and managers.network:session() and managers.criminals then
						for _, peer in pairs(managers.network:session():peers() or {}) do
							local pid = peer and peer:id()
							if pid and pid ~= 1 then
								local peer_unit = managers.criminals:character_unit_by_peer_id(pid)
								if
									alive(peer_unit)
									and mvector3.distance(burst_pos, peer_unit:position()) <= RADIUS
								then
									LuaNetworking:SendToPeer(pid, RPC_NAME, "")
								end
							end
						end
					end
				end)
			end)

			-- Client receiver — trusts the host.
			if _G.CSR_MP and _G.CSR_MP.register_handler then
				_G.CSR_MP.register_handler(RPC_NAME, function(sender, data)
					slow_local()
				end)
			end
		end,
	},
})
