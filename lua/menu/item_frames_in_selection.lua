-- Crime Spree Roguelike - Item rarity frames in the modifier selection popup
-- Adds colored rarity frames behind item icons when choosing between missions.

if not RequiredScript then
	return
end

-- Icon scale relative to vanilla size (0.75 = 75% of vanilla)
local ICON_SCALE = 0.72
-- Per-item scale overrides (multiplied with ICON_SCALE)
-- Built from _G.CSR_IconScale (keyed by icon name) + item registry (maps prefix → icon)
local ICON_SCALE_OVERRIDES = {}
do
	local scales = _G.CSR_IconScale or {}
	for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
		local s = scales[item.icon]
		if s then
			ICON_SCALE_OVERRIDES[item.id_prefix] = s
		end
	end
end
-- Frame scale relative to scaled icon size
local FRAME_SCALE = 1.4

-- Rarity frame icons and colors (same as items_page.lua)
-- All rarities use the same frame (rare) to avoid icon sizing issues
local RARITY_FRAMES = {
	common = { frame = "csr_frame", color = Color.white },
	uncommon = { frame = "csr_frame", color = Color(0, 0.95, 0) },
	rare = { frame = "csr_frame", color = Color(0.3, 0.7, 1) },
	contraband = { frame = "csr_frame", color = Color(1, 0.4, 0) },
	wildcard = { frame = "csr_frame", color = Color(1, 0.3, 0.8) },
}

-- Modifier ID prefix → rarity (generated from centralized registry)
local ITEM_RARITIES = {}
-- Modifier ID prefix (no trailing "_") → full id_prefix (with "_") for CSR_CountStacks
local ITEM_ID_PREFIXES = {}
for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
	local key = item.id_prefix:sub(1, -2)
	ITEM_RARITIES[key] = item.rarity
	ITEM_ID_PREFIXES[key] = item.id_prefix
end

-- Match modifier ID (e.g. "player_health_boost_1") to rarity via prefix
local function get_item_rarity(mod_id)
	if not mod_id then
		return nil
	end
	for prefix, rarity in pairs(ITEM_RARITIES) do
		if string.find(mod_id, prefix, 1, true) == 1 then
			return rarity
		end
	end
	return nil
end

-- Match modifier ID to its registry id_prefix (with trailing "_") for stack counting
local function get_item_id_prefix(mod_id)
	if not mod_id then
		return nil
	end
	for prefix, full_prefix in pairs(ITEM_ID_PREFIXES) do
		if string.find(mod_id, prefix, 1, true) == 1 then
			return full_prefix
		end
	end
	return nil
end

-- Add a rarity frame behind the icon on a CrimeSpreeModifierButton
local function add_frame_to_button(btn)
	if not btn or not btn._data or not btn._data.id then
		return
	end

	local rarity = get_item_rarity(btn._data.id)
	if not rarity then
		return
	end

	local frame_info = RARITY_FRAMES[rarity]
	if not frame_info then
		return
	end

	-- Look up frame texture in hud_icons
	if not tweak_data.hud_icons or not tweak_data.hud_icons[frame_info.frame] then
		return
	end
	local frame_data = tweak_data.hud_icons[frame_info.frame]

	-- Add frame to btn._panel (208x298) to avoid clipping by _image panel
	-- Position it at the same center as _image using _image_pos
	local parent_panel = btn._panel
	if not parent_panel then
		return
	end

	local base_size = btn._image_size or 128
	local frame_size = base_size * FRAME_SCALE
	local cx = btn._image_pos and btn._image_pos.x or (parent_panel:w() * 0.5)
	local cy = btn._image_pos and btn._image_pos.y or (base_size / 2 + 20)

	-- Frame is larger than the icon, visible as a border around it
	-- Store reference on button so update() can animate it
	btn._csr_rarity_frame = parent_panel:bitmap({
		name = "csr_rarity_frame",
		texture = frame_data.texture,
		texture_rect = frame_data.texture_rect,
		w = frame_size,
		h = frame_size,
		x = cx - frame_size / 2,
		y = cy - frame_size / 2,
		color = frame_info.color,
		layer = 5,
	})
end

-- Add an "x N owned" badge in the empty padding strip above the icon.
-- Mirrors the shop card's owned indicator (Color(1, 0.7, 0.2) + same loc key).
local function add_owned_badge_to_button(btn)
	if not btn or not btn._panel then
		return
	end
	if btn._csr_owned_text then
		return
	end
	local badge_h = 16
	btn._csr_owned_text = btn._panel:text({
		name = "csr_owned",
		text = "",
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size or 18,
		color = Color(1, 0.7, 0.2),
		align = "center",
		x = 0,
		y = btn._panel:h() - badge_h - 2,
		w = btn._panel:w(),
		h = badge_h,
		visible = false,
		layer = 6,
	})
end

-- Refresh the owned badge text/visibility for the current item on the button.
local function refresh_owned_badge(btn)
	if not btn or not btn._csr_owned_text then
		return
	end
	local mod_id = btn._data and btn._data.id
	local id_prefix = get_item_id_prefix(mod_id)
	if not id_prefix or not _G.CSR_CountStacks then
		btn._csr_owned_text:set_visible(false)
		return
	end
	local count = CSR_CountStacks(id_prefix)
	if count > 0 then
		btn._csr_owned_text:set_text(
			managers.localization:text("csr_gage_services_owned_x", { count = tostring(count) })
		)
		btn._csr_owned_text:set_visible(true)
	else
		btn._csr_owned_text:set_visible(false)
	end
end

-- PreHook: restore image to vanilla size before vanilla's update reads it
-- Without this, vanilla smoothsteps from our shrunken size → compounds to zero
if CrimeSpreeModifierButton then
	Hooks:PreHook(CrimeSpreeModifierButton, "update", "CSR_RestoreVanillaSize", function(self)
		if self._csr_vanilla_size and self._image then
			self._image:set_size(self._csr_vanilla_size, self._csr_vanilla_size)
		end
	end)

	-- PostHook: read vanilla's clean result, then apply our scales
	Hooks:PostHook(CrimeSpreeModifierButton, "update", "CSR_UpdateFrameAnimation", function(self, t, dt)
		if not self._image or not self._image_pos then
			return
		end

		-- Buttons are reused between popups: refresh frame when item changes
		local current_id = self._data and self._data.id
		if current_id ~= self._csr_tracked_id then
			self._csr_tracked_id = current_id
			-- Hide old frame (can't remove from panel, so set alpha to 0)
			if self._csr_rarity_frame then
				pcall(function()
					self._csr_rarity_frame:set_alpha(0)
				end)
				self._csr_rarity_frame = nil
			end
			-- Apply frame for new item
			if current_id then
				add_frame_to_button(self)
			end
			-- Owned badge (created lazily, refreshed every item change)
			add_owned_badge_to_button(self)
			refresh_owned_badge(self)
		end

		-- Capture and store vanilla's smoothstep result for next frame's PreHook
		local vanilla_s = self._image:w()
		self._csr_vanilla_size = vanilla_s

		-- Icon: scaled down from vanilla, with per-item override
		local item_scale = ICON_SCALE
		if current_id then
			for prefix, mult in pairs(ICON_SCALE_OVERRIDES) do
				if string.find(current_id, prefix, 1, true) == 1 then
					item_scale = ICON_SCALE * mult
					break
				end
			end
		end
		self._image:set_size(vanilla_s * item_scale, vanilla_s * item_scale)
		self._image:set_center(self._image_pos.x, self._image_pos.y)

		-- Frame: independent scale from same vanilla base → perfect sync
		if self._csr_rarity_frame then
			local frame_s = vanilla_s * FRAME_SCALE
			self._csr_rarity_frame:set_size(frame_s, frame_s)
			self._csr_rarity_frame:set_center(self._image_pos.x, self._image_pos.y)
		end
	end)
end

-- Hook: after all modifier buttons are created in _setup, add frames + AUTO-FILL button
if CrimeSpreeModifiersMenuComponent then
	Hooks:PostHook(CrimeSpreeModifiersMenuComponent, "_setup", "CSR_AddFramesToButtons", function(self)
		if not self._buttons then
			return
		end

		for _, btn in ipairs(self._buttons) do
			-- Only CrimeSpreeModifierButton has _data; skip finalize/back CrimeSpreeButton
			if btn._data and btn._data.id then
				add_frame_to_button(btn)
				add_owned_badge_to_button(btn)
				refresh_owned_badge(btn)
			end
		end

		-- === AUTO-FILL button (for both host and client) ===
		if not managers.menu:is_pc_controller() then
			return
		end
		if not self._button_panel or not alive(self._button_panel) then
			return
		end

		-- Find finalize button (first CrimeSpreeButton after modifier buttons)
		local max_mods = tweak_data.crime_spree.max_modifiers_displayed or 3
		local finalize_btn = self._buttons[max_mods + 1]
		if not finalize_btn or not finalize_btn.panel or not finalize_btn:panel() then
			return
		end

		local padding = 10 -- same as vanilla _setup

		-- Auto-fill callback: fill all pending slots with random non-contraband items
		self._csr_auto_fill_confirmed = function(self_ref)
			local registry = _G.CSR_ITEM_REGISTRY
			if not registry then
				return
			end

			-- Build pool excluding contraband and scrap. Wildcards are
			-- carry-1: they're allowed in the pool only when the player has
			-- no wildcard. Once one is picked (or the player already owned
			-- one going in), subsequent iterations skip wildcards entirely.
			-- Scrap items have no modifier class and exist only as printer
			-- fodder produced by the in-world scrapper.
			local function build_pool(allow_wildcard)
				local p = {}
				for _, item_def in ipairs(registry) do
					if item_def.rarity ~= "contraband" and not item_def.is_scrap then
						if item_def.rarity ~= "wildcard" or allow_wildcard then
							table.insert(p, item_def)
						end
					end
				end
				return p
			end

			local function player_owns_wildcard()
				local items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
				for _, it in ipairs(items) do
					if it.id then
						for _, def in ipairs(registry) do
							if def.rarity == "wildcard" and string.find(it.id, def.id_prefix, 1, true) == 1 then
								return true
							end
						end
					end
				end
				return false
			end

			local has_wildcard = player_owns_wildcard()
			local pool = build_pool(not has_wildcard)
			if #pool == 0 then
				return
			end

			-- How many to fill
			local pending = self_ref:modifiers_to_select()
			if pending <= 0 then
				return
			end

			-- Deterministic RNG seeded per player
			local seed = _G.CSR_MP_RunSeed or _G.CSR_CurrentSeed or 0
			local peer_id = CSR_LocalPeerId and CSR_LocalPeerId() or 1
			local player_seed = seed + peer_id * 104729
			local item_count = CSR_GetLocalItems and #CSR_GetLocalItems() or 0

			-- Track picks (by type) so we can list them in chat below. Recorded
			-- after select_modifier returns — if vanilla's early-out ever
			-- rejects, we skip claiming it. The chat is INTENTIONALLY built
			-- from claimed picks rather than diffing CSR_PlayerItems: a
			-- mismatch with the items tab is itself the diagnostic signal we
			-- want to see when something silently drops a pick downstream.
			local pick_counts = {}
			local pick_order = {}

			-- DEBUG (unconditional): saturate logging while we hunt the
			-- "auto-fill chat lists item I don't have" bug. Strip once fixed.
			log(
				"[CSR AutoFill] BEGIN pending="
					.. tostring(pending)
					.. " items_before="
					.. tostring(item_count)
					.. " pool_size="
					.. tostring(#pool)
					.. " peer_id="
					.. tostring(peer_id)
					.. " run_seed="
					.. tostring(seed)
			)

			for i = 1, pending do
				math.randomseed(player_seed + item_count * 1337 + i * 7919)
				local pick = pool[math.random(1, #pool)]
				local mod_id = pick.id_prefix .. "0"

				local before_count = CSR_GetLocalItems and #CSR_GetLocalItems() or -1
				-- select_modifier adds to _global.modifiers, PostHook CSR_TransferPlayerItem
				-- calls CSR_AddItem to add to CSR_PlayerItems
				local ok = managers.crime_spree:select_modifier(mod_id)
				local after_count = CSR_GetLocalItems and #CSR_GetLocalItems() or -1

				log(
					"[CSR AutoFill] iter="
						.. tostring(i)
						.. "/"
						.. tostring(pending)
						.. " type="
						.. tostring(pick.type)
						.. " mod_id="
						.. tostring(mod_id)
						.. " select_returned="
						.. tostring(ok)
						.. " items: "
						.. tostring(before_count)
						.. " -> "
						.. tostring(after_count)
						.. (before_count == after_count and "  <-- NO ADD!" or "")
				)

				if ok ~= false then
					if not pick_counts[pick.type] then
						pick_counts[pick.type] = 0
						table.insert(pick_order, pick.type)
					end
					pick_counts[pick.type] = pick_counts[pick.type] + 1

					-- Carry-1 wildcard: after picking one, rebuild the pool
					-- without wildcards so subsequent iterations skip them.
					if pick.rarity == "wildcard" and not has_wildcard then
						has_wildcard = true
						pool = build_pool(false)
						if #pool == 0 then
							break
						end
					end
				end

				item_count = item_count + 1
			end

			math.randomseed(os.time())

			managers.menu_component:post_event("item_buy")

			if MenuCallbackHandler and MenuCallbackHandler.save_progress then
				MenuCallbackHandler:save_progress()
			end

			-- Broadcast updated items to peers
			if _G.CSR_MP and CSR_MP.broadcast_own_items then
				CSR_MP.broadcast_own_items()
			end

			-- Refresh items page
			if _G.CSR_ItemsPageInstance and _G.CSR_ItemsPageInstance._setup_items then
				pcall(function()
					_G.CSR_ItemsPageInstance:_setup_items()
				end)
			end

			-- DEBUG (unconditional): final state after the loop. Compare the
			-- pick_counts here with what shows up in the items tab — a
			-- mismatch means a downstream hook silently dropped something.
			local count_parts = {}
			for _, t in ipairs(pick_order) do
				table.insert(count_parts, t .. "x" .. tostring(pick_counts[t]))
			end
			local final_items = CSR_GetLocalItems and CSR_GetLocalItems() or {}
			log(
				"[CSR AutoFill] END items_after="
					.. tostring(#final_items)
					.. " pick_counts={"
					.. table.concat(count_parts, ", ")
					.. "}"
			)

			-- Chat message: list each pick claimed by select_modifier, with xN
			-- for duplicates. Uses csr_logbook_<type>_name for the localized
			-- display name; falls back to the raw type string if missing.
			if _G.CSR_MP and CSR_MP.chat_message and #pick_order > 0 then
				local parts = {}
				for _, t in ipairs(pick_order) do
					local name_key = "csr_logbook_" .. t .. "_name"
					local name = managers.localization:exists(name_key) and managers.localization:text(name_key) or t
					local count = pick_counts[t]
					if count > 1 then
						table.insert(parts, name .. " x" .. count)
					else
						table.insert(parts, name)
					end
				end
				CSR_MP.chat_message("Auto-filled: " .. table.concat(parts, ", "))
			end

			-- Close popup (same as vanilla _on_finalize_modifier when all items selected)
			self_ref:_on_back()
			-- Refresh lobby node so buttons update to "Start the heist"
			pcall(function()
				managers.menu:active_menu().logic:refresh_node("crime_spree_lobby")
			end)
		end

		-- Confirmation dialog wrapper to prevent misclicks
		self._csr_auto_fill = function(self_ref)
			local dialog_data = {
				title = managers.localization:text("csr_auto_fill_confirm_title"),
				text = managers.localization:text("csr_auto_fill_confirm_text"),
				id = "csr_auto_fill_confirm",
			}
			local yes_button = {
				text = managers.localization:text("dialog_yes"),
				callback_func = function()
					self._csr_auto_fill_confirmed(self_ref)
				end,
			}
			local no_button = {
				text = managers.localization:text("dialog_no"),
				cancel_button = true,
			}
			dialog_data.button_list = { yes_button, no_button }
			managers.system_menu:show(dialog_data)
		end

		local auto_fill_btn = CrimeSpreeButton:new(self._button_panel)
		auto_fill_btn:set_text(managers.localization:to_upper_text("csr_auto_fill_items"))
		auto_fill_btn:set_callback(callback(self, self, "_csr_auto_fill"))
		auto_fill_btn:shrink_wrap_button(0, 0)
		table.insert(self._buttons, auto_fill_btn)

		-- Position to the left of finalize (SELECT) button
		auto_fill_btn:panel():set_right(finalize_btn:panel():left() - padding * 3)

		-- Navigation links
		auto_fill_btn:set_link("right", finalize_btn)
		finalize_btn:set_link("left", auto_fill_btn)
		auto_fill_btn:set_link("up", self._buttons[1])

		self._csr_auto_fill_btn = auto_fill_btn
	end)
end

-- === LOBBY STATUS: "SELECTING ITEM" ===
-- Handled in ready_system.lua via PostHook on LobbyCharacterData:update_character_menu_state.
-- Vanilla's set_lobby_character_menu_state chain doesn't reliably update the visible text,
-- so we override _state_text directly every frame when a peer is selecting.
