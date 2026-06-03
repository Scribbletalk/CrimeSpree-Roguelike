-- HUD Wildcard Slot (U1) — shows the local player's owned wildcard to the LEFT
-- of the health circle, with a counterclockwise radial recharge reveal.
--
-- Direction trick: Diesel's VertexColorTexturedRadial sweeps clockwise only, and
-- the texture_rect negative-width UV flip that reverses the sweep ALSO mirrors
-- the icon. We point each icon at a PRE-MIRRORED DDS (csr_<type>_mirror) and apply
-- texture_rect={w,0,-w,h} at draw time — the two mirrors cancel visually while the
-- UV flip still reverses the sweep. Addon wildcards with no mirror DDS fall back to
-- their own icon (sweep stays clockwise; still functional).
--
-- Cooldown source: active wildcards publish to _G.CSR_WildcardCooldowns via the
-- dispatcher's CSR_SetWildcardCooldown (cooldown_end is a file-local in each item,
-- so it can't be read directly). Passive wildcards (Side Satchel) never publish, so
-- progress reads 0 → icon drawn at full alpha.
--
-- Hidden when no wildcard is owned. Layout: player_panel/teammates_panel both clip
-- children and the local player's teammate_panel uses halign="right", which breaks
-- naive :x() arithmetic. We parent the slot to the top-level hud_panel (no clipping)
-- and position via world_x/world_y relative to the radial's actual screen position.

if not RequiredScript then
	return
end

-- Owned wildcard = managers.csr:held_wildcard(local_peer_id) (bare type, or nil).
local function find_owned_wildcard()
	local mgr = managers and managers.csr
	if not (mgr and mgr.held_wildcard and mgr.local_peer_id) then
		return nil
	end
	return mgr:held_wildcard(mgr:local_peer_id())
end

-- Returns 0..1 where 1 = fresh-pressed (icon empty), 0 = ready (icon full).
-- Passive / unpublished wildcards return 0.
local function cooldown_progress(item_type)
	local cd = _G.CSR_WildcardCooldowns and _G.CSR_WildcardCooldowns[item_type]
	if not cd or (cd.duration or 0) <= 0 then
		return 0
	end
	local now = TimerManager:game():time()
	local remaining = (cd.ends or 0) - now
	if remaining <= 0 then
		return 0
	end
	if remaining > cd.duration then
		remaining = cd.duration
	end
	return remaining / cd.duration
end

-- Resolve the icon for a wildcard type. Prefer the pre-mirrored DDS (CCW sweep);
-- fall back to the item's own icon (CW sweep) for addon wildcards without a mirror.
-- Returns texture (path) and texture_rect.
local function resolve_icon(item_type)
	local hud_icons = tweak_data and tweak_data.hud_icons
	if not hud_icons then
		return nil, nil
	end
	local mirror = hud_icons["csr_" .. tostring(item_type) .. "_mirror"]
	if mirror and mirror.texture then
		return mirror.texture, { 128, 0, -128, 128 }
	end
	local mgr = managers and managers.csr
	local def = mgr and mgr.item_def and mgr:item_def(item_type)
	local raw = def and def.icon
	if raw then
		local tex, rect = _G.CSR.icon_data(raw)
		if tex then
			return tex, rect
		end
	end
	return nil, nil
end

local function apply_icon_texture(slot_panel, item_type)
	local tex, rect = resolve_icon(item_type)
	if not tex or not rect then
		return
	end
	for _, name in ipairs({ "wildcard_icon", "wildcard_icon_dim" }) do
		local bm = slot_panel:child(name)
		if bm then
			bm:set_image(tex)
			bm:set_texture_rect(rect[1], rect[2], rect[3], rect[4])
		end
	end
end

-- State held in this Lua table (Diesel panels are userdata and silently drop
-- arbitrary field assignments). Each panel gets its own state closure at hook time.
local function update_widget(slot_panel, state, dt)
	if not alive(slot_panel) then
		return
	end
	local owned = find_owned_wildcard()
	if not owned then
		if slot_panel:visible() then
			slot_panel:set_visible(false)
		end
		state.current = nil
		state.displayed_progress = nil
		return
	end

	local icon = slot_panel:child("wildcard_icon")
	if not icon then
		return
	end

	if state.current ~= owned then
		state.current = owned
		state.displayed_progress = nil
		apply_icon_texture(slot_panel, owned)
	end

	if not slot_panel:visible() then
		slot_panel:set_visible(true)
	end

	local target = cooldown_progress(owned)

	-- Ease displayed_progress toward target so the reveal is never a one-frame snap.
	-- Exponential smoothing: time-to-90% ~= ln(10)/8 ~= 0.29s at any framerate.
	if state.displayed_progress == nil then
		state.displayed_progress = target
	else
		local k = 1 - math.exp(-8 * (dt or 0.016))
		local delta = target - state.displayed_progress
		state.displayed_progress = state.displayed_progress + delta * k
		if math.abs(target - state.displayed_progress) < 0.001 then
			state.displayed_progress = target
		end
	end

	-- progress = 1 fresh-press (icon empty) -> 0 ready (icon fully drawn). Color.r
	-- drives how much of the icon renders CCW via VertexColorTexturedRadial.
	icon:set_color(Color(1, 1 - state.displayed_progress, 1, 1))
end

if HUDTeammate and not _G._CSR_WILDCARD_SLOT_HOOKED then
	_G._CSR_WILDCARD_SLOT_HOOKED = true

	Hooks:PostHook(HUDTeammate, "_create_radial_health", "CSR_WildcardSlot_Create", function(self, radial_health_panel)
		if not self._main_player then
			return
		end
		local teammates_panel = self._panel and self._panel:parent()
		local hud_panel = teammates_panel and teammates_panel:parent()
		if not hud_panel then
			return
		end

		-- Hot-reload safe: remove a pre-existing slot before recreating.
		local existing = hud_panel:child("csr_wildcard_slot")
		if existing then
			hud_panel:remove(existing)
		end

		-- Slot matches the radial size (incl. its 4px padding) for visual symmetry.
		local size = radial_health_panel:w()
		local gap = 6

		local slot_panel = hud_panel:panel({
			name = "csr_wildcard_slot",
			visible = false,
			layer = 1,
			w = size,
			h = size,
		})

		-- Dim background layer: always-visible faded icon so the slot stays legible
		-- during cooldown. Placeholder texture replaced per wildcard by apply_icon_texture.
		slot_panel:bitmap({
			name = "wildcard_icon_dim",
			texture = "guis/textures/pd2/crime_spree/csr_familiar_friend_mirror",
			texture_rect = { 128, 0, -128, 128 },
			layer = 0,
			alpha = 0.35,
			w = size,
			h = size,
		})

		-- Bright top layer: radial-revealed CCW via the R channel.
		slot_panel:bitmap({
			name = "wildcard_icon",
			texture = "guis/textures/pd2/crime_spree/csr_familiar_friend_mirror",
			texture_rect = { 128, 0, -128, 128 },
			render_template = "VertexColorTexturedRadial",
			layer = 1,
			alpha = 1,
			color = Color(1, 1, 1, 1),
			w = size,
			h = size,
		})

		local state = { current = nil, displayed_progress = nil }
		local radial_ref = radial_health_panel
		slot_panel:animate(function(o)
			local dt = 0
			while alive(o) do
				-- Re-anchor to the radial's current world position each frame. Must run
				-- inside animate (not at hook time): HUDManager calls set_x on the
				-- teammate_panel AFTER HUDTeammate:new returns, so world_x reads zero at hook time.
				if alive(radial_ref) then
					o:set_world_x(radial_ref:world_x() - size - gap)
					o:set_world_y(radial_ref:world_y())
				end
				pcall(update_widget, o, state, dt)
				dt = coroutine.yield()
			end
		end)
	end)
end
