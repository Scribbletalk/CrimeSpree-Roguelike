-- Shocking Surprise (loud modifier) -- a Taser that dies releases an electric
-- burst: a particle + sound at the corpse and a brief slow (sprint blocked) on
-- every player within range. Ported from the 6.2 mechanic (modifiers/shocking
-- surprise.lua); U1 keeps it all here via the modifier's behavior hooks.
--
-- No engine ModifierX class: the effect is hand-rolled below. HOST-authoritative
-- (enemy death is server-side): the host detects the Taser death, applies the slow
-- to itself if in range, and RPCs every in-range remote peer to slow locally. The
-- client receiver trusts the host -- it does NOT re-check active_modifiers, because
-- the run seed isn't synced to clients, so a client-derived modifier set can differ
-- from the host's (same reason apply_modifiers is host-only).
--
-- Uses the dedicated csr_shocking_overlay texture (registered in hudicons.lua):
-- a 1920x1080 overlay with cyan electric arcs drawn at the screen edges and a
-- clear centre. Rendered white + additive (the art carries its own colour) and
-- scaled up 1.25x so the edge arcs bleed off-screen -- same look as the 6.2
-- original. Values mirror the 6.2 constants shocking_surprise_radius (500) /
-- _slow_mul (0.4) / _duration (3) / _decay (0.5).
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
local OVERLAY_SCALE = 1.25 -- >1 so the edge arcs extend past the screen bounds

-- True only when a run is active AND Shocking Surprise is in the active set. Used
-- host-side only (detection); the client receiver trusts the host instead.
local function ss_active()
	local mgr = managers and managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active() and mgr.active_modifiers) then
		return false
	end
	for _, e in ipairs(mgr:active_modifiers("loud")) do
		if e.id == "shocking_surprise" then
			return true
		end
	end
	return false
end

-- Flickering electric overlay on the fullscreen HUD for `duration` s, then fade.
-- Vanilla API, pcall-isolated (same panel:bitmap pattern as plush_shark.lua).
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
		-- Scale up + centre so the edge arcs bleed past the screen bounds.
		local bw = math.floor(panel:w() * OVERLAY_SCALE)
		local bh = math.floor(panel:h() * OVERLAY_SCALE)
		local bm = panel:bitmap({
			name = "csr_shocking_overlay",
			texture = OVERLAY_TEX,
			blend_mode = "add",
			color = Color(1, 1, 1, 1), -- white: the texture carries its own colour (Rule #6)
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

-- Apply the taser slow to the LOCAL player + show the overlay. Local-scoped, so
-- valid both host-side (host in range) and on a client (RPC receiver).
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

	hooks = {
		["lib/units/enemies/cop/copdamage"] = function()
			if _G._CSR_SHOCKING_SURPRISE_HOOKED then
				return
			end
			_G._CSR_SHOCKING_SURPRISE_HOOKED = true

			-- Capture the Taser's position BEFORE death (ragdoll can move the corpse).
			-- _tweak_table == "taser" is the vanilla unit-type check (coplogicbase.lua).
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

			-- On the Taser death (HOST only): after a 1s delay, electric burst + slow
			-- every in-range player. Host applies to itself; in-range peers get an RPC.
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
					-- World burst + sound at the corpse (host-side visual).
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

					-- Notify in-range remote peers (each slows its own local player).
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

			-- Client receiver: the host says a Taser died near me -> slow locally.
			-- Trusts the host (see header) -- no active_modifiers re-check.
			-- Routed through the shared MP router (mp_sync.lua); it dispatches by id.
			if _G.CSR_MP and _G.CSR_MP.register_handler then
				_G.CSR_MP.register_handler(RPC_NAME, function(sender, data)
					slow_local()
				end)
			end
		end,
	},
})
