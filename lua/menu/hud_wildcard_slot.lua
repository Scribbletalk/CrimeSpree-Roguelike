-- HUD Wildcard Slot — shows the player's currently-owned wildcard to the
-- left of the health circle. Two render modes, live-switchable from the
-- options menu via CSR_Settings.values.hud_wildcard_use_bar:
--
--  * Icon mode (default) — bitmap with a counterclockwise radial cooldown
--    reveal. Direction trick: Diesel's VertexColorTexturedRadial sweeps
--    clockwise only, and the standard texture_rect negative-width UV flip
--    that reverses the sweep ALSO mirrors the icon. We point each icon at a
--    PRE-MIRRORED DDS and then apply texture_rect={w,0,-w,h} at draw time —
--    the two mirrors cancel visually while the UV flip still reverses sweep.
--  * Bar mode — vertical magenta strip flush against the radial's left side,
--    filling bottom-to-top as the cooldown depletes. Passive wildcards (no
--    cooldown) show a permanently full bar.
--
-- Hidden when no wildcard is owned. Active wildcards (Familiar Friend, Turron)
-- drive the cooldown mask from their `_G.CSR_<Name>.cooldown_end` state.
-- Passive wildcards (Side Satchel, Hippocratic Oath) report progress=0, which
-- the icon mode reads as full alpha and the bar mode reads as full height.
--
-- Layout note: player_panel and teammates_panel both clip children at their
-- bounds, AND teammate_panel uses halign="right" for the local player which
-- breaks naive :x()-summing arithmetic. We parent the slot to the full
-- hud_panel (top-level, no clipping, screen-sized) and use world_x / world_y
-- to position it relative to the radial's actual rendered screen position.
-- Vanilla layout is left completely untouched.

if not RequiredScript then
	return
end

-- Active wildcards expose `cooldown_end` (game time) and a CSR_ItemConstants
-- key for the max duration. Passive wildcards have no CD entry.
-- Each `icon` here points at a PRE-MIRRORED DDS so the slot's
-- texture_rect={w,0,-w,h} flip un-mirrors the visual and simultaneously
-- reverses the radial sweep direction.
local WILDCARD_DEFS = {
	["player_familiar_friend_"] = {
		icon = "csr_familiar_friend_mirror",
		state_key = "CSR_FamiliarFriend",
		const_key = "familiar_friend_cooldown",
		default_cd = 60,
	},
	["player_turron_"] = {
		icon = "csr_turron_mirror",
		state_key = "CSR_Turron",
		const_key = "turron_cooldown",
		default_cd = 90,
	},
	["player_side_satchel_"] = {
		icon = "csr_side_satchel_mirror",
	},
	["player_hippocratic_oath_"] = {
		icon = "csr_hippocratic_oath_mirror",
	},
}

local function find_owned_wildcard()
	if not _G.CSR_GetLocalItems then
		return nil
	end
	local items = CSR_GetLocalItems()
	if not items then
		return nil
	end
	for i = 1, #items do
		local id = items[i] and items[i].id
		if type(id) == "string" then
			for prefix, _ in pairs(WILDCARD_DEFS) do
				if id:sub(1, #prefix) == prefix then
					return prefix
				end
			end
		end
	end
	return nil
end

-- Returns 0..1 where 1 = fresh-pressed (mask fully covers), 0 = ready (mask
-- invisible). Passive wildcards always return 0.
local function cooldown_progress(prefix)
	local def = WILDCARD_DEFS[prefix]
	if not def or not def.state_key then
		return 0
	end
	local state = _G[def.state_key]
	if not state then
		return 0
	end
	local now = TimerManager:game():time()
	local cd_end = state.cooldown_end or 0
	if now >= cd_end then
		return 0
	end
	local C = _G.CSR_ItemConstants or {}
	local cd_max = C[def.const_key] or def.default_cd
	if cd_max <= 0 then
		return 0
	end
	local remaining = cd_end - now
	if remaining > cd_max then
		remaining = cd_max
	end
	return remaining / cd_max
end

local function apply_icon_texture(slot_panel, def)
	local td = tweak_data and tweak_data.hud_icons and tweak_data.hud_icons[def.icon]
	if not td then
		return
	end
	-- Texture is pre-mirrored on disk; texture_rect with negative width here
	-- un-mirrors it visually AND flips the VertexColorTexturedRadial sweep
	-- direction to counterclockwise. Both bitmap layers share the same flip.
	for _, name in ipairs({ "wildcard_icon", "wildcard_icon_dim" }) do
		local bm = slot_panel:child(name)
		if bm then
			bm:set_image(td.texture)
			bm:set_texture_rect(128, 0, -128, 128)
		end
	end
end

local function use_bar_mode()
	return CSR_Settings and CSR_Settings.values and CSR_Settings.values.hud_wildcard_use_bar == true
end

local function set_layer_visible(slot_panel, name, visible)
	local child = slot_panel:child(name)
	if child and child:visible() ~= visible then
		child:set_visible(visible)
	end
end

-- State is held in this Lua table (not on the panel — Diesel panels are
-- userdata and silently drop arbitrary field assignments per
-- pd2_diesel_userdata_no_field_assignment.md). Each panel gets its own
-- `state` closure created at hook time.
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

	local def = WILDCARD_DEFS[owned]
	local icon = slot_panel:child("wildcard_icon")
	if not icon then
		return
	end

	if state.current ~= owned then
		state.current = owned
		state.displayed_progress = nil
		apply_icon_texture(slot_panel, def)
	end

	if not slot_panel:visible() then
		slot_panel:set_visible(true)
	end

	local target = cooldown_progress(owned)

	-- Ease displayed_progress toward target so visual changes are never
	-- one-frame snaps. Activation drains the bar/icon from full to empty
	-- gradually instead of teleporting; the final approach to "ready"
	-- softens the otherwise-abrupt frame where target hits 0.
	-- Exponential smoothing: time-to-90% ≈ ln(10)/8 ≈ 0.29s at any framerate.
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

	-- Toggle which mode's layers are drawn. Both layer sets are pre-built;
	-- swapping is just a visibility flip, so the option takes effect live
	-- (no rebuild needed when the player toggles the setting mid-heist).
	set_layer_visible(slot_panel, "wildcard_icon_dim", not bar_mode)
	set_layer_visible(slot_panel, "wildcard_icon", not bar_mode)
	set_layer_visible(slot_panel, "wildcard_bar_frame", bar_mode)
	set_layer_visible(slot_panel, "wildcard_bar_bg", bar_mode)
	set_layer_visible(slot_panel, "wildcard_bar_fill", bar_mode)

	if bar_mode then
		-- progress=1 fresh-press (bar empty), progress=0 ready (bar full).
		-- Diesel's Y axis is top-down, so growing from the bottom means
		-- shrinking h and raising y together.
		local fill = slot_panel:child("wildcard_bar_fill")
		local bg = slot_panel:child("wildcard_bar_bg")
		if fill and bg then
			local h_total = bg:h()
			local fill_h = math.floor(h_total * (1 - progress) + 0.5)
			fill:set_h(fill_h)
			fill:set_y(bg:y() + h_total - fill_h)
		end
	else
		-- Radial reveal applied directly to the icon. progress = 1 fresh-press
		-- (icon empty) → 0 ready (icon fully drawn). Color.r drives how much
		-- of the icon is rendered counterclockwise via VertexColorTexturedRadial.
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

		-- Slot dimensions = same as radial (incl. its 4px padding) for visual symmetry.
		local size = radial_health_panel:w()
		local gap = 6

		local slot_panel = hud_panel:panel({
			name = "csr_wildcard_slot",
			visible = false,
			layer = 1,
			w = size,
			h = size,
		})

		-- Dim background layer: always-visible faded icon, so the slot stays
		-- legible during cooldown (player can still see what wildcard they have).
		-- Initial texture is the pre-mirrored familiar_friend (replaced per
		-- wildcard by apply_icon_texture); texture_rect un-mirrors it visually.
		slot_panel:bitmap({
			name = "wildcard_icon_dim",
			texture = "guis/textures/pd2/crime_spree/csr_familiar_friend_mirror",
			texture_rect = { 128, 0, -128, 128 },
			layer = 0,
			alpha = 0.35,
			w = size,
			h = size,
		})

		-- Bright top layer: radial-revealed counterclockwise via the R channel.
		-- Texture is pre-mirrored; the negative-width texture_rect un-mirrors
		-- it visually AND reverses the VertexColorTexturedRadial sweep direction.
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

		-- Bar-mode layers (hidden by default; update_widget shows them when
		-- CSR_Settings.values.hud_wildcard_use_bar is true). Three-layer
		-- sandwich mirroring HUDTeammate:_create_radial_health style:
		--   * frame  — thin gray outline like hud_radialbg ring
		--   * bg     — dark inner area behind the fill
		--   * fill   — bright magenta with blend_mode="add" so it glows
		--              against the dark bg, the same trick the radial uses
		--              for hud_health (additive blend over a gray ring).
		-- Width 10px so the 1px frame on each side leaves ~8px of bright
		-- fill visible. Right-aligned in the slot panel so the bar sits
		-- flush against the gap-side edge nearest the radial.
		local bar_w = 10
		local bar_x = size - bar_w
		-- RGB scaled ~0.9 from the wildcard hex ff4dcc so the additive fill
		-- glows a touch less hot against the dark bg — same hue, lower contribution.
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
				-- Re-anchor slot to current radial world position each frame.
				-- This must run inside animate (not at hook time) because the
				-- HUDManager calls set_x on teammate_panel AFTER HUDTeammate:new
				-- returns — at hook time, world_x reads pre-positioning zeroes.
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
