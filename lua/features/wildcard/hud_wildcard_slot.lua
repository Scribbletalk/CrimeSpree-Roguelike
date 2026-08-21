-- HUD Wildcard Slot: shows the owned wildcard to the left of the health radial.
-- Two modes (hud_wildcard_use_bar pref): CCW radial reveal (default) or vertical bar.
-- CCW trick: VertexColorTexturedRadial only sweeps CW; negative-width texture_rect
-- flips the sweep but also mirrors the icon, so we pre-mirror the DDS and apply both.
-- Cooldowns are published by each active via CSR_SetWildcardCooldown (file-locals are
-- unreadable from here). Passives never publish -> progress=0 -> icon always full.
-- Parented to hud_panel (not teammate_panel) to avoid clipping and halign="right" math.

if not RequiredScript then
	return
end

-- Returns the bare item type string of the local player's wildcard, or nil.
-- in_csr_heist() first: ownership is a run-long inventory fact, so on its own it would show this
-- slot in vanilla heists played while a run exists. nil here takes update_widget's hide path.
local function find_owned_wildcard()
	local mgr = managers and managers.csr
	if not (mgr and mgr.held_wildcard and mgr.local_peer_id) then
		return nil
	end
	if not (mgr.in_csr_heist and mgr:in_csr_heist()) then
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

-- Prefer csr_<type>_mirror DDS for CCW sweep; fall back to item icon (CW) if missing.
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

-- hud_wildcard_use_bar preference: nil/false = icon mode (default).
local function use_bar_mode()
	return managers and managers.csr and managers.csr:setting("hud_wildcard_use_bar") == true
end

local function set_layer_visible(slot_panel, name, visible)
	local child = slot_panel:child(name)
	if child and child:visible() ~= visible then
		child:set_visible(visible)
	end
end

-- Diesel panels are userdata; can't store state on them directly.
local function update_widget(slot_panel, state, dt)
	if not alive(slot_panel) then
		return
	end
	-- Throttle the inventory scan: held_wildcard() iterates the whole inventory, and
	-- wildcard ownership only changes on pick/use (rare). A 0.25s detection lag is invisible.
	state.scan_t = (state.scan_t or 0) - (dt or 0)
	if state.scan_t <= 0 then
		state.scan_t = 0.25
		state.owned = find_owned_wildcard()
	end
	local owned = state.owned
	if not owned then
		if slot_panel:visible() then
			slot_panel:set_visible(false)
		end
		state.current = nil
		state.displayed_progress = nil
		state.last_progress = nil
		state.last_bar_mode = nil
		return
	end

	local icon = slot_panel:child("wildcard_icon")
	if not icon then
		return
	end

	if state.current ~= owned then
		state.current = owned
		state.displayed_progress = nil
		state.last_progress = nil -- force the layer/color re-apply below for the new icon
		state.last_bar_mode = nil
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

	local progress = state.displayed_progress
	local bar_mode = use_bar_mode()

	-- Steady state (cooldown full, mode unchanged): visuals identical to last frame.
	-- Skip the layer flips + per-frame Color()/fill rebuild to avoid HUD GC churn.
	if progress == state.last_progress and bar_mode == state.last_bar_mode then
		return
	end
	state.last_progress = progress
	state.last_bar_mode = bar_mode

	-- Both layer sets are pre-built; switching modes is a pure visibility flip.
	set_layer_visible(slot_panel, "wildcard_icon_dim", not bar_mode)
	set_layer_visible(slot_panel, "wildcard_icon", not bar_mode)
	set_layer_visible(slot_panel, "wildcard_bar_frame", bar_mode)
	set_layer_visible(slot_panel, "wildcard_bar_bg", bar_mode)
	set_layer_visible(slot_panel, "wildcard_bar_fill", bar_mode)

	if bar_mode then
		-- progress=1 = empty (fresh press), 0 = full (ready). Diesel Y is top-down:
		-- growing from the bottom shrinks h and raises y together.
		local fill = slot_panel:child("wildcard_bar_fill")
		local bg = slot_panel:child("wildcard_bar_bg")
		if fill and bg then
			local h_total = bg:h()
			local fill_h = math.floor(h_total * (1 - progress) + 0.5)
			fill:set_h(fill_h)
			fill:set_y(bg:y() + h_total - fill_h)
		end
	else
		-- Color.r drives the CCW radial reveal via VertexColorTexturedRadial.
		icon:set_color(Color(1, 1 - progress, 1, 1))
	end
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

		-- Match the radial size (incl. its 4px padding) for visual symmetry.
		local size = radial_health_panel:w()
		local gap = 6

		local slot_panel = hud_panel:panel({
			name = "csr_wildcard_slot",
			visible = false,
			layer = 1,
			w = size,
			h = size,
		})

		-- Faded background icon; always visible so the slot stays legible during cooldown.
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

		-- Bar-mode layers (hidden by default). Frame/bg/fill sandwich; fill uses
		-- blend_mode="add" to glow like the radial's additive health fill.
		local bar_w = 10
		local bar_x = size - bar_w
		local magenta = Color(1, 0.9, 0.27, 0.72)
		local frame_color = Color(1, 0.4, 0.4, 0.4)
		local bg_color = Color(1, 0.05, 0.05, 0.05)
		slot_panel:rect({
			name = "wildcard_bar_frame",
			color = frame_color,
			alpha = 1,
			layer = 0,
			visible = false,
			x = bar_x,
			y = 0,
			w = bar_w,
			h = size,
		})
		slot_panel:rect({
			name = "wildcard_bar_bg",
			color = bg_color,
			alpha = 0.35,
			layer = 1,
			visible = false,
			x = bar_x + 1,
			y = 1,
			w = bar_w - 2,
			h = size - 2,
		})
		slot_panel:rect({
			name = "wildcard_bar_fill",
			color = magenta,
			alpha = 1,
			blend_mode = "add",
			layer = 2,
			visible = false,
			x = bar_x + 1,
			y = 1,
			w = bar_w - 2,
			h = size - 2,
		})

		local state = { current = nil, displayed_progress = nil }
		local radial_ref = radial_health_panel
		slot_panel:animate(function(o)
			local dt = 0
			while alive(o) do
				-- Re-anchor each frame: world_x is zero at hook time (HUDManager sets it after new).
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
