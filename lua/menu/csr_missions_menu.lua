-- CSRMissionsMenuComponent — fork of vanilla CrimeSpreeMissionsMenuComponent.
--
-- Origin: pd2_source_code/lib/managers/menu/crimespreemissionsmenucomponent.lua (775 lines)
-- Strategy: byte-for-byte copy with class renames + backend swapped from
-- managers.crime_spree to managers.csr. Diesel UI primitives (WalletGuiObject,
-- BoxGuiObject, BlackMarketGui, tweak_data.*) are left intact — per
-- REFACTOR_PLAN we replace the vanilla-CS-Lua surface, not the engine surface.
--
-- Class renames:
--   CrimeSpreeMissionsMenuComponent -> CSRMissionsMenuComponent
--   CrimeSpreeMissionButton         -> CSRMissionButton
--
-- Backend swaps:
--   managers.crime_spree:server_missions()  -> managers.csr:mission_set()
--   managers.crime_spree:current_mission()  -> managers.csr:current_mission()
--   managers.crime_spree:select_mission(x)  -> managers.csr:select_mission(x)
--   managers.crime_spree:get_random_mission -> managers.csr:get_random_mission
--   managers.crime_spree:_is_host()         -> self:_is_host()
--
-- Dropped (vanilla-CS features outside the alpha mission-select scope):
--   show_crash_dialog / clear_crash_dialog  (vanilla CS crash recovery)
--   has_consumable_value / consumable_value (vanilla CS consumables)
--   send_crime_spree_mission_data           (MP sync — REFACTOR_PLAN §4.4, later slice)
--   server_has_failed                       (host-fail propagation — later slice)

CSRMissionsMenuComponent = CSRMissionsMenuComponent or class(MenuGuiComponentGeneric)
local padding = 10
local large_padding = 32
local size = 280
-- Vertical gap between the measured bottom of the foreground title text and the
-- top of the sidebar. Single visual tunable: raise it to push the sidebar down,
-- lower it to pull the sidebar up toward the header. Kept small — the massive
-- ghost behind the title is alpha 0.4 and its visible glyphs sit well above its
-- 90px box, so a modest clearance avoids overlap without wasting space.
local sidebar_title_gap = 16

-- Items feature-panel layout. Rarity palette includes contraband even though
-- contraband items are excluded from the SELECTION-WINDOW pool (6.3 drop-rate
-- redesign cut them from random rolls): the items themselves still exist and
-- can reach a player's inventory through other paths (e.g. the shop when ported
-- back), so the inventory view needs the matching frame tint. Contraband
-- orange matches the logbook's RARITY_FRAMES.contraband (logbook_menu.lua:257).
local items_panel_rarity_colors = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
	wildcard = Color(1, 1, 0.3, 0.8),
}
-- items_panel_icon_size is misnamed historically -- it is the CELL size (used
-- for the grid step and hover hit-test). The visible icon and the visible frame
-- have their own sizes below; the frame deliberately overflows the cell so it
-- reads as a card that's "a bit bigger than the icon" (user spec).
local items_panel_icon_size = 64
local items_panel_frame_size = 72
local items_panel_icon_gap = 8
local items_panel_grid_cols = 7
local items_panel_peer_header_h = 22
local items_panel_peer_gap = 16
local items_panel_padding = 16
CSRMissionsMenuComponent.button_size = {
	w = size * 0.6666666666666666,
	h = size * 0.5 * 0.6666666666666666,
	title_h = tweak_data.menu.pd2_medium_font_size + 4,
}
CSRMissionsMenuComponent.menu_nodes = {
	start_menu = "crime_spree_lobby",
	mission_end_menu = "main",
}

function CSRMissionsMenuComponent:init(ws, fullscreen_ws, node)
	self._ws = ws
	self._fullscreen_ws = fullscreen_ws
	self._init_layer = self._ws:panel():layer()
	self._fullscreen_panel = self._fullscreen_ws:panel():panel({})

	if not Global.game_settings.is_playing then
		WalletGuiObject.set_wallet(self._ws:panel())
		WalletGuiObject.set_layer(30)
		WalletGuiObject.move_wallet(10, -10)
	end

	self._buttons = {}

	-- The component now builds on BOTH the crime_spree_lobby node AND the
	-- mission_end_menu "main" node (csr_missions_wiring.lua fix #3). The
	-- branded "Crime Spree Roguelike" title and the left sidebar are
	-- LOBBY-ONLY chrome — on the end screen they must not render (user
	-- report 2026-05-18). node-name is the deterministic boundary, the same
	-- signal csr_missions_wiring.lua gates the build on.
	local pnode = node and node.parameters and node:parameters()
	self._is_lobby = pnode ~= nil and pnode.name == "crime_spree_lobby"

	self:_setup()
end

function CSRMissionsMenuComponent:close()
	WalletGuiObject.close_wallet(self._ws:panel())
	self._ws:panel():remove(self._panel)
	self._fullscreen_ws:panel():remove(self._fullscreen_panel)
end

function CSRMissionsMenuComponent:_setup()
	local parent = self._ws:panel()

	if alive(self._panel) then
		parent:remove(self._panel)
	end

	self._panel = parent:panel({
		layer = self._init_layer,
	})

	-- Mission cards' bottom edge (applied below via self._buttons_panel:set_bottom).
	-- Hoisted so the sidebar can be built with its height pinned to it — the
	-- sidebar sits at y=0, so h == bottom makes its bottom line up with the cards.
	local bottom = parent:bottom() - tweak_data.menu.pd2_large_font_size * 1.5

	-- _create_title() is called UNCONDITIONALLY: it sets self._title_bottom,
	-- and _create_sidebar anchors its top to that
	-- (top = self._title_bottom + sidebar_title_gap). Skipping the title would
	-- make _title_bottom nil -> top collapses to sidebar_title_gap -> the
	-- sidebar shifts UP and grows taller (user report 2026-05-18 — NOT
	-- requested). The title is lobby-only chrome, so on the end screen its
	-- visible elements are hidden INSIDE _create_title instead: the geometry
	-- (self._title_bottom) is preserved, only the text is not drawn. Sidebar
	-- stays byte-identical to the lobby.
	self:_create_title()
	self:_create_sidebar(bottom)

	local w = (self.button_size.w + padding) * tweak_data.crime_spree.gui.missions_displayed - padding
	local h = self.button_size.h + self.button_size.title_h
	self._title_panel = self._panel:panel({})

	self._title_panel:set_w(w)
	self._title_panel:set_h(tweak_data.menu.pd2_medium_font_size)
	self._title_panel:set_right(parent:right())
	self._title_panel:set_bottom(bottom - h - 4)
	-- The header row's text is built entirely by _create_status_bar: spree RANK
	-- on the left (replacing the old static "SELECT NEXT HEIST" label) and the
	-- DIFFICULTY on the right, both on this single line above the cards.
	self:_create_status_bar(w)

	self._buttons_panel = self._panel:panel({})

	self._buttons_panel:set_w(w)
	self._buttons_panel:set_h(h)
	self._buttons_panel:set_right(parent:right())
	self._buttons_panel:set_bottom(bottom)

	-- Built here (not in _create_sidebar) because it measures BOTH the sidebar
	-- and the now-positioned mission-cards panel for its left/right bounds.
	self:_create_feature_panels()

	local default_index = nil

	for idx = 1, tweak_data.crime_spree.gui.missions_displayed do
		-- Hardening (intentional deviation from the vanilla fork): vanilla
		-- guaranteed server_missions() was always populated; ours can be short
		-- if a tier resolved empty. Skip unrenderable slots instead of building
		-- a card with nil .add/.level (crash_report_2026_05_16_19_45).
		local data = managers.csr:mission_set()[idx]
		if data then
			local btn = CSRMissionButton:new(idx, self._buttons_panel, data)

			btn:set_callback(callback(self, self, "_select_mission", idx))
			table.insert(self._buttons, btn)

			-- Re-highlight the still-selected mission on rebuild. The pick
			-- survives sub-screen round-trips (Inventory/Options) and is only
			-- cleared on a genuine lobby exit -- managers.csr:select_mission(false)
			-- in the CSR_ClearMissionOnLeaveLobby PostHook on the vanilla
			-- _dialog_leave_lobby_yes (csr_contract_callbacks.lua).
			if managers.csr:current_mission() == data.id then
				default_index = idx
			end
		end
	end

	if not managers.menu:is_pc_controller() then
		default_index = default_index or 1
	end

	if default_index then
		self:_set_button_index_selected(default_index, true)
	end

	self._host_failed_text = self._buttons_panel:text({
		halign = "right",
		vertical = "bottom",
		layer = 51,
		wrap = true,
		align = "right",
		word_wrap = true,
		y = 0,
		x = 0,
		valign = "bottom",
		text = managers.localization:text("menu_cs_host_failed_text"),
		color = Color.white,
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
	})
	local _, _, _, h = self._host_failed_text:text_rect()

	self._host_failed_text:set_h(h)
	self._host_failed_text:set_bottom(self._buttons_panel:h())

	self._host_failed = self._buttons_panel:text({
		halign = "right",
		vertical = "bottom",
		layer = 51,
		wrap = true,
		align = "right",
		word_wrap = true,
		y = 0,
		x = 0,
		valign = "bottom",
		text = managers.localization:to_upper_text("menu_cs_host_failed"),
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})
	local _, _, _, h = self._host_failed:text_rect()

	self._host_failed:set_h(h)
	self._host_failed:set_bottom(self._host_failed_text:top())

	-- Forked vanilla CS "Start the Heist" button. Vanilla surfaced this as the
	-- crime_spree_lobby node's `spree_start` menu item; it is not showing in the
	-- forked flow. We rebuild it with the exact widget + params vanilla uses in
	-- crimespreemissionendoptions.lua for its menu_cs_start option: CrimeSpreeButton
	-- (forked as CSRStartButton) with pd2_large_font + shrink_wrap_button, then
	-- right-aligned. Child of self._panel so vanilla close() cleans it up.
	self._start_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size)

	self._start_button:set_button("BTN_START")
	self._start_button:set_text(managers.localization:to_upper_text("menu_cs_start"))
	self._start_button:set_callback(callback(self, self, "_start_pressed"))

	if managers.menu:is_pc_controller() then
		self._start_button:shrink_wrap_button()
	end

	self._start_button:panel():set_right(self._buttons_panel:right())
	self._start_button:panel():set_bottom(parent:bottom() - padding)

	-- Forked vanilla CS "Reroll" button. Same widget as start (vanilla builds
	-- both corner buttons from one CrimeSpreeButton class in
	-- crimespreemissionendoptions.lua); the reroll/second corner uses
	-- pd2_large_font_size * 0.8 and sits to the LEFT of start with a
	-- large_padding gap (set_right(start:left() - large_padding)).
	self._reroll_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size * 0.8)

	self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_reroll"))
	self._reroll_button:set_callback(callback(self, self, "_reroll_pressed"))

	if managers.menu:is_pc_controller() then
		self._reroll_button:shrink_wrap_button()
	end

	self._reroll_button:panel():set_right(self._start_button:panel():left() - large_padding)
	self._reroll_button:panel():set_bottom(self._start_button:panel():bottom())

	-- Slice B context button, LEFT of Reroll. Same CSRStartButton widget as
	-- Reroll. Its label + callback (and the Start/Reroll failed-lock) are set
	-- by _refresh_action_buttons(), called here and from refresh() so the
	-- failed state re-applies whenever the panel rebuilds.
	self._action_button =
		CSRStartButton:new(self._panel, tweak_data.menu.pd2_large_font, tweak_data.menu.pd2_large_font_size * 0.8)

	self._action_button:panel():set_bottom(self._reroll_button:panel():bottom())
	self:_refresh_action_buttons()

	-- Black scrim behind the Start / Reroll buttons. Spans the full 3-card
	-- mission-row width (same `w` and right edge as self._buttons_panel above)
	-- so it reads as a backing plate aligned with the cards. Created after the
	-- buttons so it can measure them, but pinned to layer 1 -- well below the
	-- CSRStartButton panels (layer 1000, see CSRStartButton:init) -- so Diesel's
	-- per-layer child sort draws it underneath regardless of insertion order.
	-- color + alpha (not a 3-arg Color, Rule #6): same rect idiom CSRStartButton
	-- uses for its highlight. Child of self._panel, so vanilla close() cleans it
	-- up. Start/Reroll are never toggled in refresh(), so neither is this.
	local actions_vpad = 6
	local start_panel = self._start_button:panel()
	self._actions_bg = self._panel:rect({
		layer = 1,
		color = Color.black,
		alpha = 0.4,
	})
	self._actions_bg:set_w(w)
	self._actions_bg:set_h(start_panel:h() + actions_vpad * 2)
	self._actions_bg:set_right(self._buttons_panel:right())
	self._actions_bg:set_bottom(start_panel:bottom() + actions_vpad)
	self:refresh()
end

function CSRMissionsMenuComponent:_create_title()
	-- Top-left branded header in the vanilla lobby "crew page" style
	-- (contractboxgui.lua:8-84, the PLANNING-PHASE-looking title): a crisp
	-- pd2_large_font foreground on the safe workspace plus a huge faded blue
	-- pd2_massive_font ghost on the fullscreen workspace, coordinate-mapped with
	-- safe_to_full_16_9 so the ghost lines up without being clipped by the safe
	-- area. Copied 1:1 from vanilla; only the text (csr_header_title, registered
	-- in csr_contract_wiring.lua) and component panels differ. We route the lobby
	-- box to CrimeSpreeContractBoxGui (which draws no crewpage header), so this
	-- corner is free and there is no double-up with vanilla. MenuBackdropGUI.
	-- animate_bg_text is intentionally NOT called: it is a verified no-op
	-- (pd2_menubackdrop_animate_bg_text_noop) -- the ghost is static in vanilla.
	-- Children of self._panel / self._fullscreen_panel, both removed in close().
	local title = self._panel:text({
		vertical = "top",
		name = "csr_title",
		align = "left",
		text = managers.localization:to_upper_text("csr_header_title"),
		font_size = tweak_data.menu.pd2_large_font_size,
		font = tweak_data.menu.pd2_large_font,
		color = tweak_data.screen_colors.text,
	})
	local _, _, w, h = title:text_rect()

	title:set_size(w, h)

	-- Measured bottom of the solid foreground title, in self._panel (safe)
	-- coords. The sidebar starts at this + sidebar_title_gap. We anchor to the
	-- measured text (not modelled ghost-box geometry): the ghost is alpha 0.4
	-- and top-aligned in an oversized box, so its visible glyphs end only a
	-- little below the foreground — a small gap clears both.
	self._title_bottom = title:bottom()

	-- End screen: the measurement above is kept (the sidebar anchors to it),
	-- but the branded title itself is lobby-only chrome and must not render
	-- here (user report 2026-05-18). Hide rather than skip so geometry holds.
	if not self._is_lobby then
		title:set_visible(false)
	end

	if MenuBackdropGUI then
		local ghost_h = 90
		local ghost_move_y = 9
		local bg_text = self._fullscreen_panel:text({
			name = "csr_title",
			vertical = "top",
			h = ghost_h,
			alpha = 0.4,
			align = "left",
			layer = 1,
			text = managers.localization:to_upper_text("csr_header_title"),
			font_size = tweak_data.menu.pd2_massive_font_size,
			font = tweak_data.menu.pd2_massive_font,
			color = tweak_data.screen_colors.button_stage_3,
		})
		local x, y = managers.gui_data:safe_to_full_16_9(title:world_x(), title:world_center_y())

		bg_text:set_world_left(x)
		bg_text:set_world_center_y(y)
		bg_text:move(-13, ghost_move_y)

		-- End screen: hide the faded ghost too (lobby-only chrome).
		if not self._is_lobby then
			bg_text:set_visible(false)
		end
	end
end

function CSRMissionsMenuComponent:_create_sidebar(bottom)
	-- CrimeNet-style left sidebar, forked from CrimeNetSidebarGui /
	-- CrimeNetSidebarItem (crimenetsidebargui.lua). Visual recipe copied 1:1
	-- (256-wide panel, 0.4 black + test_blur_df backdrop, BoxGui border, icon +
	-- underscored-uppercase label rows). The collapse/expand, glow, pulse,
	-- attention/separator subclasses and controller snap are intentionally
	-- dropped — user asked for "just the panel" for now. Buttons are
	-- placeholders with no callbacks; behaviour wired in a later pass.
	-- Child of self._panel so the existing close() (removes self._panel) cleans
	-- it up. CSR-only by construction: this component is built only for the
	-- crime_spree_lobby node. The panel spans [top, bottom]: `top` clears the
	-- title (measured foreground bottom + sidebar_title_gap) so the sidebar
	-- never overlaps the header text or its faint ghost; `bottom` is the
	-- mission cards' bottom edge so the two line up.
	local top = (self._title_bottom or 0) + sidebar_title_gap

	-- Pass self as owner so the sidebar's Items row can toggle the
	-- component-owned Items panel (geometry spans sidebar -> mission cards).
	self._sidebar = CSRSidebar:new(self._panel, top, bottom, self)
end

-- Feature panels: rectangular panels that open to the RIGHT of the sidebar
-- when its Items / Modifiers / Rewards row is clicked. All three share the
-- EXACT same region -- height == the sidebar's height, spanning the empty gap
-- with a symmetric `padding` margin on both sides (from the sidebar and from
-- the leftmost mission card -- user spec 2026-05-19). Built once here (hidden),
-- toggled by visibility; lifetime is tied to self._panel, which the existing
-- close() removes, so no extra teardown is needed (same ownership model as the
-- sidebar). Visual recipe is the sidebar's 1:1 (0.4 black rect + test_blur_df
-- backdrop + BoxGui frame); content is a later pass, exactly how the sidebar
-- itself started as "just the panel".
--
-- Requires self._sidebar (built in _create_sidebar above) and
-- self._buttons_panel (built in _setup before this is called) to measure the
-- left/right bounds; both are children of self._panel, so all coordinates are
-- in the same space.
function CSRMissionsMenuComponent:_create_feature_panels()
	if not self._sidebar or not self._buttons_panel then
		return
	end

	local sb = self._sidebar:panel()
	-- Symmetric `padding` gap on BOTH sides: from the sidebar on the left and
	-- from the leftmost mission card on the right (user refinement 2026-05-19 --
	-- flush-to-card was too wide).
	local left = sb:right() + padding
	local right = self._buttons_panel:left() - padding
	local width = math.max(right - left, 0)
	local px, py, ph = left, sb:top(), sb:h()

	-- One panel per content category, all built identically and pinned to the
	-- same rect (they are mutually exclusive -- see toggle_feature_panel).
	local function build()
		local p = self._panel:panel({
			layer = 100,
		})

		p:set_w(width)
		p:set_h(ph)
		p:set_x(px)
		p:set_y(py)

		local bg = p:panel({
			layer = -1,
		})

		bg:rect({
			alpha = 0.4,
			color = Color.black,
		})
		bg:bitmap({
			texture = "guis/textures/test_blur_df",
			name = "blur_bg",
			halign = "scale",
			layer = -1,
			render_template = "VertexColorTexturedBlur3D",
			valign = "scale",
			w = bg:w(),
			h = bg:h(),
		})

		-- Frame discarded like the sidebar's own border (anonymous, never
		-- referenced again); the panel-tree teardown removes it.
		BoxGuiObject:new(
			p:panel({
				layer = 100,
			}),
			{
				sides = {
					1,
					1,
					1,
					1,
				},
			}
		)

		p:set_visible(false)

		return p
	end

	self._feature_panels = {
		items = build(),
		modifiers = build(),
		rewards = build(),
	}

	-- Initial population so the panel has content the first time the sidebar
	-- opens it. Re-populated on every toggle-on for MP-sync arrival (item counts
	-- can change while the lobby is up once the sync slice lands).
	self:_populate_items_panel()
end

-- Mutually exclusive: the three panels occupy the SAME rect, so showing one
-- hides the others; clicking the already-open row closes it (toggle off).
function CSRMissionsMenuComponent:toggle_feature_panel(key)
	if not self._feature_panels then
		return
	end

	local target = self._feature_panels[key]

	if not target or not alive(target) then
		return
	end

	local show = not target:visible()

	self:hide_feature_panels()
	target:set_visible(show)

	if show and key == "items" then
		-- Rebuild on toggle-on so newly granted items or peer joins are reflected
		-- without needing to leave/re-enter the lobby. Cheap (≤ 28 items × N peers).
		self:_populate_items_panel()
	end
end

-- Hide every feature panel. Also driven by the sidebar's Hide Sidebar collapse
-- (the panel is component-owned, not sidebar chrome, so CSRSidebar:set_collapsed
-- asks the owner to hide it -- user spec 2026-05-19).
function CSRMissionsMenuComponent:hide_feature_panels()
	if not self._feature_panels then
		return
	end

	for _, p in pairs(self._feature_panels) do
		if alive(p) then
			p:set_visible(false)
		end
	end

	-- A hidden items panel cannot be hovered; drop any active tooltip so it does
	-- not linger on top of the sidebar / mission cards.
	self:_clear_items_tooltip()
	self._items_hover_target = nil
end

-- Resolve a per-peer accent color (4-arg Color form, per Critical Rule #6).
-- tweak_data.peer_vector_colors is the same source vanilla teammate contours and
-- chat use, so the panel color-codes match what the player already associates
-- with each peer everywhere else in the UI.
function CSRMissionsMenuComponent:_items_panel_peer_color(peer_id)
	local v = tweak_data and tweak_data.peer_vector_colors and tweak_data.peer_vector_colors[peer_id]
	if v then
		return Color(1, v.x, v.y, v.z)
	end
	return Color.white
end

-- Deterministic peer order: local peer first (always present, never duplicated),
-- then remote peers ascending by id. Used as the per-peer section order in the
-- items panel so adding/removing a teammate does not jumble existing sections.
function CSRMissionsMenuComponent:_collect_peers_for_items_panel(local_pid)
	local out = {}
	local seen = {}

	local nm = managers and managers.network
	local session = nm and nm.session and nm:session()

	local local_peer = session and session.local_peer and session:local_peer()
	if local_peer then
		local lid = local_peer:id()
		out[1] = {
			id = lid,
			name = (local_peer.name and local_peer:name()) or "Player",
			color = self:_items_panel_peer_color(lid),
		}
		seen[lid] = true
	else
		out[1] = {
			id = local_pid,
			name = "Player",
			color = self:_items_panel_peer_color(local_pid),
		}
		seen[local_pid] = true
	end

	if session and session.peers then
		local peers = session:peers() or {}
		local remote = {}
		for pid, peer in pairs(peers) do
			if not seen[pid] then
				remote[#remote + 1] = {
					id = pid,
					name = (peer.name and peer:name()) or ("Peer " .. tostring(pid)),
					color = self:_items_panel_peer_color(pid),
				}
			end
		end
		table.sort(remote, function(a, b)
			return a.id < b.id
		end)
		for _, p in ipairs(remote) do
			out[#out + 1] = p
		end
	end

	return out
end

-- Build / rebuild the items feature-panel content from the live manager state.
-- Idempotent: prior content panel is torn down first, hit-target list reset.
-- MP-shaped from day one (per-peer cycle); other peers render empty until the
-- count-model sync slice lands (design O4) -- the UI then just starts showing
-- their items with no code change.
function CSRMissionsMenuComponent:_populate_items_panel()
	if not self._feature_panels or not alive(self._feature_panels.items) then
		return
	end
	local panel = self._feature_panels.items

	if self._items_content and alive(self._items_content) then
		panel:remove(self._items_content)
	end
	self._items_content = nil
	self._items_hit_targets = {}
	self:_clear_items_tooltip()
	self._items_hover_target = nil

	local content = panel:panel({
		layer = 5,
	})
	self._items_content = content

	local mgr = managers and managers.csr
	if not mgr or not mgr.registered_items then
		return
	end

	local by_type = {}
	for _, def in ipairs(mgr:registered_items()) do
		by_type[def.type] = def
	end

	local local_pid = mgr:local_peer_id()
	local peers_list = self:_collect_peers_for_items_panel(local_pid)

	-- No section title: the sidebar row "Items" already labels the panel; an in-
	-- panel "ITEMS" header was visual duplication. Per-peer color-strip headers
	-- carry the structure on their own.
	local y = items_panel_padding
	local section_w = panel:w() - items_panel_padding * 2

	for _, peer_info in ipairs(peers_list) do
		local pid = peer_info.id
		local pcolor = peer_info.color

		local header = content:panel({
			x = items_panel_padding,
			y = y,
			w = section_w,
			h = items_panel_peer_header_h,
		})

		header:rect({
			name = "peer_color_strip",
			color = pcolor,
			w = 4,
			h = header:h(),
		})
		header:text({
			name = "peer_name",
			-- Local peer is identifiable by their color strip (matches chat /
			-- teammate contour color); no "(you)" suffix needed.
			text = peer_info.name,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = pcolor,
			x = 12,
			y = 0,
			w = header:w() - 12,
			h = header:h(),
			vertical = "center",
		})

		y = y + items_panel_peer_header_h + 4

		local counts = mgr:player_items(pid) or {}
		local items_list = {}
		for item_type, count in pairs(counts) do
			local def = by_type[item_type]
			if def and count > 0 then
				items_list[#items_list + 1] = { def = def, count = count }
			end
		end

		if #items_list == 0 then
			-- Empty section: peer header stands alone, no body text. Advance Y
			-- by the standard gap so the next peer section keeps its spacing.
			y = y + items_panel_peer_gap
		else
			table.sort(items_list, function(a, b)
				if (a.def.rarity or "") ~= (b.def.rarity or "") then
					return (a.def.rarity or "") < (b.def.rarity or "")
				end
				return (a.def.type or "") < (b.def.type or "")
			end)

			local grid_x = items_panel_padding + 16
			local frame_tex, frame_rect = tweak_data.hud_icons:get_icon_data("csr_frame")

			local frame_overflow = (items_panel_frame_size - items_panel_icon_size) / 2
			local icon_inset = 12

			for i, entry in ipairs(items_list) do
				local col = (i - 1) % items_panel_grid_cols
				local row = math.floor((i - 1) / items_panel_grid_cols)
				local ix = grid_x + col * (items_panel_icon_size + items_panel_icon_gap)
				local iy = y + row * (items_panel_icon_size + items_panel_icon_gap)

				-- Frame is a SIBLING of the cell on `content`, not a child, so its
				-- 72x72 footprint can overflow the 64x64 cell by 4px each side --
				-- giving the frame a bigger visible read than the icon while
				-- keeping the cell as the precise hit-test footprint. Layer 5 here
				-- + cell layer 10 below puts the icon above the frame even though
				-- the frame extends past the cell bounds (no clipping).
				local frame_bmp = content:bitmap({
					name = "rarity_frame",
					texture = frame_tex,
					texture_rect = frame_rect,
					x = ix - frame_overflow,
					y = iy - frame_overflow,
					w = items_panel_frame_size,
					h = items_panel_frame_size,
					layer = 5,
				})
				frame_bmp:set_color(items_panel_rarity_colors[entry.def.rarity] or Color.white)

				local cell = content:panel({
					x = ix,
					y = iy,
					w = items_panel_icon_size,
					h = items_panel_icon_size,
					layer = 10,
				})

				local icon_tex, icon_rect = tweak_data.hud_icons:get_icon_data(entry.def.icon or "csr_dog_tags")
				cell:bitmap({
					name = "item_icon",
					texture = icon_tex,
					texture_rect = icon_rect,
					x = icon_inset,
					y = icon_inset,
					w = items_panel_icon_size - icon_inset * 2,
					h = items_panel_icon_size - icon_inset * 2,
					layer = 10,
				})

				-- Stack badge: shown unconditionally (including count == 1) per user
				-- request -- the explicit "x1" makes the inventory parse as a
				-- stack-count view rather than as a roster of unique entries.
				-- Pinned top-right. y is NEGATIVE so the glyph sits on the frame's
				-- top edge instead of inside the icon area: Diesel does not clip
				-- panel children to parent bounds, so a -y child of the cell just
				-- renders above the cell. Magnitude matches frame_overflow so the
				-- badge sits flush with the visible frame top.
				cell:text({
					name = "stack_badge",
					text = "x" .. tostring(entry.count),
					font = tweak_data.menu.pd2_small_font,
					font_size = tweak_data.menu.pd2_small_font_size,
					color = Color.white,
					align = "right",
					vertical = "top",
					x = -3,
					y = -4,
					w = items_panel_icon_size,
					h = items_panel_icon_size,
					layer = 20,
				})

				self._items_hit_targets[#self._items_hit_targets + 1] = {
					panel = cell,
					def = entry.def,
					count = entry.count,
				}
			end

			local rows = math.ceil(#items_list / items_panel_grid_cols)
			y = y + rows * (items_panel_icon_size + items_panel_icon_gap) - items_panel_icon_gap + items_panel_peer_gap
		end
	end
end

-- Edge-triggered hover for the items grid. mouse_moved is event-driven (not a
-- per-frame path), so the linear walk over hit targets is fine; the targets
-- list is small (28 items × N peers in the worst case).
function CSRMissionsMenuComponent:_items_panel_mouse_moved(x, y)
	local panel = self._feature_panels and self._feature_panels.items
	if not panel or not alive(panel) or not panel:visible() then
		if self._items_hover_target ~= nil then
			self._items_hover_target = nil
			self:_clear_items_tooltip()
		end
		return false
	end
	if not self._items_hit_targets or #self._items_hit_targets == 0 then
		return false
	end

	local hovered = nil
	for _, target in ipairs(self._items_hit_targets) do
		if alive(target.panel) and target.panel:inside(x, y) then
			hovered = target
			break
		end
	end

	if hovered ~= self._items_hover_target then
		self._items_hover_target = hovered
		self:_clear_items_tooltip()
		if hovered then
			-- No "highlight" hover SFX: items are passive inventory entries,
			-- not selectable controls, and per-cell hover audio in a dense grid
			-- would chatter as the cursor crosses cells (user spec 2026-05-20).
			self:_show_items_tooltip(hovered)
		end
	end

	return hovered ~= nil
end

function CSRMissionsMenuComponent:_clear_items_tooltip()
	if self._items_tooltip and alive(self._items_tooltip) then
		self._panel:remove(self._items_tooltip)
	end
	self._items_tooltip = nil
end

-- Tooltip anchored to the hovered icon (not the cursor). Floats above the items
-- panel on self._panel layer 200 so it overlaps the sidebar / cards cleanly.
-- Clamped to self._panel bounds so an icon near the panel edge does not push
-- the tooltip off-screen.
function CSRMissionsMenuComponent:_show_items_tooltip(target)
	if not target or not alive(target.panel) then
		return
	end
	local def = target.def
	local pad = 6
	local tip_w = 200
	local name_h = tweak_data.menu.pd2_small_font_size + 2

	-- Build at placeholder height so we can host the text nodes for measurement.
	-- BoxGuiObject and the bg rect are added AFTER the final resize -- BoxGui
	-- bakes its corner/edge sprite positions at construction time, so creating
	-- it pre-resize leaves the corners stranded at the placeholder dimensions
	-- (the visible artefact the user reported as "weird corners").
	local tip = self._panel:panel({
		layer = 200,
		w = tip_w,
		h = 200,
	})
	self._items_tooltip = tip

	local name_color = items_panel_rarity_colors[def.rarity] or Color.white
	local name_text = tip:text({
		name = "tooltip_name",
		text = def.name or "",
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = name_color,
		x = pad,
		y = pad,
		w = tip_w - pad * 2,
		h = name_h,
		layer = 5,
	})

	-- Desc wraps within tip_w-2*pad; measured h tracks however many lines the
	-- text actually needs, so a one-word desc isn't padded with blank space.
	local desc_text = tip:text({
		name = "tooltip_desc",
		text = def.desc or "",
		font = tweak_data.menu.pd2_small_font,
		font_size = tweak_data.menu.pd2_small_font_size,
		color = tweak_data.screen_colors.text,
		x = pad,
		y = pad + name_h + 2,
		w = tip_w - pad * 2,
		h = 160,
		wrap = true,
		wrap_word = true,
		layer = 5,
	})
	local _, _, _, dh = desc_text:text_rect()
	desc_text:set_h(dh)

	-- Final size, THEN chrome: BoxGui captures the panel's w/h at construction.
	local tip_h = pad + name_h + 2 + dh + pad
	tip:set_h(tip_h)

	tip:rect({
		name = "tooltip_bg",
		color = Color.black,
		alpha = 0.9,
		layer = 0,
		w = tip_w,
		h = tip_h,
	})
	BoxGuiObject:new(tip, {
		sides = { 1, 1, 1, 1 },
	})

	local cell_x, cell_y = target.panel:world_position()
	local panel_x, panel_y = self._panel:world_position()
	local local_x = cell_x - panel_x
	local local_y = cell_y - panel_y

	local tx = local_x + items_panel_icon_size + 6
	if tx + tip_w > self._panel:w() then
		tx = local_x - tip_w - 6
	end
	if tx < 0 then
		tx = 0
	end

	local ty = local_y
	if ty + tip_h > self._panel:h() then
		ty = self._panel:h() - tip_h - 4
	end
	if ty < 0 then
		ty = 0
	end

	tip:set_position(tx, ty)
end

function CSRMissionsMenuComponent:_create_status_bar(w)
	-- The header row directly above the mission cards (it replaces the old
	-- static "SELECT NEXT HEIST" label) shows three values on one line:
	--   MISSIONS COMPLETED (left)  |  RANK (center)  |  DIFFICULTY (right)
	-- All three are parented to self._title_panel with vertical/valign "bottom"
	-- so the baselines line up, and all follow the single self._title_panel
	-- visibility toggle in refresh(). RANK uses align "center" so it floats
	-- between the left/right anchored labels. Backend reads go through
	-- managers.csr (the refactor's single source of truth).
	-- Difficulty is mapped id -> loc via vanilla tweak_data.difficulty_name_ids
	-- (NOT "menu_difficulty_"..id -- engine ids like "overkill" don't match that
	-- pattern: that id localizes to "Very Hard", not "Overkill"). Child of
	-- self._panel, so the existing close() (removes self._panel) cleans it up.
	--
	-- Yellow highlight for the dynamic values only (rank number + Crime Spree
	-- glyph, and the difficulty name) -- the static "RANK"/"DIFFICULTY:" labels
	-- stay white. 4-arg Color per Rule #6 (3-arg Color drops blue). Applied as
	-- a sub-string recolor via set_range_color, the same vanilla-proven pattern
	-- used for the mission-card risk text further down this file.
	local highlight = Color(1, 1, 1, 0)
	-- U+E018: the Crime Spree glyph (same codepoint csr_localization.lua emits
	-- as the raw bytes \xEE\x80\x98); utf8.char keeps it consistent with the
	-- existing utf8.char(0xE012) usage there.
	local cs_glyph = utf8.char(0xE018)

	-- Left anchor: how many heists were completed in the current run. Reads the
	-- dedicated managers.csr:missions_completed() counter (NOT rank -- the two
	-- are distinct concepts; see csr_game_manager.lua default_state comment).
	local missions_prefix = managers.localization:to_upper_text("csr_lobby_missions_completed") .. ": "
	local missions_str = missions_prefix .. tostring(managers.csr:missions_completed())
	local missions_text = self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		align = "left",
		halign = "left",
		valign = "bottom",
		text = missions_str,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	missions_text:set_range_color(utf8.len(missions_prefix), utf8.len(missions_str), highlight)

	-- Center anchor: spree RANK, floating between the left/right labels.
	local rank_prefix = managers.localization:to_upper_text("csr_lobby_rank") .. ": "
	local rank_str = rank_prefix .. tostring(managers.csr:rank()) .. " " .. cs_glyph
	local rank_text = self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		align = "center",
		halign = "center",
		valign = "bottom",
		text = rank_str,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	rank_text:set_range_color(utf8.len(rank_prefix), utf8.len(rank_str), highlight)

	local diff_id = managers.csr:difficulty()
	local diff_name_id = tweak_data.difficulty_name_ids[diff_id]
	local diff_text = diff_name_id and managers.localization:to_upper_text(diff_name_id) or tostring(diff_id)

	-- Right-aligned on the same self._title_panel line as the rank text;
	-- vertical/valign "bottom" matches the rank text so the baselines align.
	-- refresh() toggles self._title_panel visibility, so this child follows it.
	local diff_prefix = managers.localization:to_upper_text("csr_lobby_difficulty") .. ": "
	local diff_full = diff_prefix .. diff_text
	local diff_label = self._title_panel:text({
		layer = 51,
		vertical = "bottom",
		align = "right",
		halign = "right",
		valign = "bottom",
		text = diff_full,
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	diff_label:set_range_color(utf8.len(diff_prefix), utf8.len(diff_full), highlight)

	-- Notification line ABOVE the status row, right-aligned over DIFFICULTY:
	-- a yellow, clickable reminder that the player still owes roguelike item
	-- picks. The hit target is a snug panel (not the w-wide title row) so only
	-- the words react -- this file hit-tests panels everywhere (sidebar, cards),
	-- never raw text objects, so we follow that convention. Child of
	-- self._panel, so the existing close() (removes self._panel) cleans it up.
	-- Same yellow as the rank/difficulty highlight above for visual coherence
	-- (4-arg Color per Rule #6; this is a=1 r=1 g=1 b=0 == yellow).
	-- Default (left/top) align: the text is snugged to its glyphs by
	-- make_fine_text in _refresh_unselected_items and pinned to (0,0), then the
	-- hit-panel is sized to it and right-anchored over DIFFICULTY. Right edge
	-- stays put as the digit count changes (panel grows leftward).
	-- Two-state yellow: dim by default, full bright on hover (mouse_moved
	-- swaps these). Bright == the rank/difficulty highlight yellow above for
	-- coherence; dim is the same hue scaled down. 4-arg Color per Rule #6
	-- (a=1, r, g, b=0 == yellow).
	self._unselected_color_dim = Color(1, 0.85, 0.78, 0)
	self._unselected_color_bright = Color(1, 1, 1, 0)

	self._unselected_panel = self._panel:panel({
		layer = 51,
	})
	-- Near-transparent yellow backing plate, same rect idiom as self._actions_bg
	-- (color sets RGB, the alpha field sets the final translucency -- Rule #6:
	-- this is 4-arg a=1 r=1 g=1 b=0 == yellow, not a 3-arg Color). Child of
	-- self._panel (NOT the snug hit-panel): it spans the whole mission row
	-- while the hit-panel stays snug around the words, so it needs its own
	-- visibility toggle. Layer 1 so Diesel's per-layer sort draws it under the
	-- layer-51 hit-panel (and its layer-52 text). Sized in _refresh_unselected_items.
	self._unselected_bg = self._panel:rect({
		layer = 1,
		color = Color(1, 1, 1, 0),
		alpha = 0.1,
	})
	self._unselected_items = self._unselected_panel:text({
		layer = 52,
		text = "",
		color = self._unselected_color_dim,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size * 1.2,
	})

	-- Populate text, snug the hit-panel, and apply pending>0 visibility. The
	-- host-fail hide in refresh() can still override this (passed as `allowed`).
	self:_refresh_unselected_items(true)
end

-- How many roguelike item picks the player still owes. The entitlement is the
-- HOST's spree rank (user spec); subtract what the local player already owns.
-- Items bought with Gage tokens must NOT count toward the rank quota ("это на
-- будущее"): tokens/shop are not ported in 6.3 so every owned item is currently
-- a rank item -- when the token slice lands, filter token-sourced items out of
-- the `owned` count right here.
function CSRMissionsMenuComponent:_unselected_item_count()
	if not managers.csr then
		return 0
	end

	local host_rank = managers.csr:host_rank() or 0
	local peer_id = managers.csr:local_peer_id()
	-- total_item_count = sum of stacks across all owned types (the count model
	-- replaced the id-list, so #player_items would be wrong on the map).
	local owned = managers.csr:total_item_count(peer_id)

	return math.max(0, host_rank - owned)
end

-- Refresh the notification's text + size + visibility. `allowed == false`
-- force-hides it (host-fail state), otherwise it shows only when the player
-- actually owes picks. Called from _create_status_bar (initial) and refresh()
-- (event-driven, never per-frame), so the table alloc in :text{} is fine.
function CSRMissionsMenuComponent:_refresh_unselected_items(allowed)
	if not self._unselected_panel or not alive(self._unselected_panel) then
		return
	end

	local count = self:_unselected_item_count()
	-- to_upper_text (not text): all-caps, same as the csr_lobby_rank/difficulty
	-- labels on the status row below. It takes the macro table too (vanilla
	-- uses to_upper_text("menu_cs_level", { ... }) the same way).
	self._unselected_items:set_text(managers.localization:to_upper_text("csr_lobby_unselected_items", {
		count = count,
	}))

	-- Snug the text to its glyphs with the canonical PD2 helper
	-- (blackmarketgui.lua:2416 -- set_size + ROUNDED set_position; the original
	-- of this fork uses the same call in CrimeSpreeMissionButton:update_button_text).
	-- Doing the resize by hand without the position re-pin left the glyphs
	-- drawn outside the moved panel: panel hoverable, text invisible. Then pin
	-- the text to (0,0) and wrap the hit-panel exactly around it so only the
	-- words are clickable, right-anchored over DIFFICULTY.
	BlackMarketGui.make_fine_text(nil, self._unselected_items)

	-- Padded backing plate (vanilla-button feel): the snug text sits inside a
	-- slightly larger panel so the yellow plate has breathing room, and the
	-- click/hover area equals the visible plate. bg fills the panel; both grow
	-- leftward since the right edge is pinned over DIFFICULTY.
	local pad_x, pad_y = 8, 3
	local tw, th = self._unselected_items:w(), self._unselected_items:h()
	self._unselected_items:set_position(pad_x, pad_y)
	self._unselected_panel:set_size(tw + pad_x * 2, th + pad_y * 2)
	self._unselected_panel:set_right(self._title_panel:right())
	-- Sit clearly ABOVE the status row (one medium line of clearance), not
	-- hugging it. Re-applied every refresh so a re-snug keeps the gap.
	self._unselected_panel:set_bottom(self._title_panel:top() - tweak_data.menu.pd2_medium_font_size)

	-- Backing plate: height == the TEXT glyph height (th), not the padded hit
	-- panel; width spans the whole mission row -- from the left edge of the
	-- leftmost card to the right edge over DIFFICULTY. self._title_panel shares
	-- w and right edge with self._buttons_panel (the cards), so right-anchoring
	-- at title_panel:right() with w == title_panel:w() lands exactly there.
	-- Vertically centred on the hit panel (the text is centred in it), so the
	-- th-tall plate sits flush behind the glyphs.
	self._unselected_bg:set_w(self._title_panel:w())
	self._unselected_bg:set_h(th)
	self._unselected_bg:set_right(self._title_panel:right())
	self._unselected_bg:set_center_y(self._unselected_panel:center_y())

	-- Reset to the dim base colour on (re)build; mouse_moved brightens it on
	-- hover. Stale hover can't persist a bright colour through a refresh.
	self._unselected_items:set_color(self._unselected_color_dim)
	self._unselected_items_hover = false

	self._unselected_visible = allowed ~= false and count > 0
	self._unselected_panel:set_visible(self._unselected_visible)
	-- bg is a sibling under self._panel, not a child of the hit panel, so the
	-- panel's set_visible above does NOT cover it -- toggle it on the same flag.
	self._unselected_bg:set_visible(self._unselected_visible)
end

-- Open the forked item-selection window (csr_item_selection.lua). That file
-- owns the register/hide-chrome lifecycle and exposes _G.CSR_OpenItemSelectionDebug;
-- _G._csr_item_selection_debug is its own "is it open" flag, which we reuse as
-- the guard. CSR_OpenItemSelectionDebug is NOT idempotent -- a second call
-- re-registers the component and overwrites its live-component-order snapshot
-- (the "after close, CSR buttons dead" bug it documents), so only open when
-- nothing is open yet. Nil-guarded: the window file is menu-loaded, but stay
-- defensive in case load order/strip changes. The pool is still the debug set
-- until CSRGameManager:roll_item_pool lands; this wires the trigger now.
function CSRMissionsMenuComponent:_on_unselected_items_clicked()
	-- Click SFX, same event the mission cards / sidebar post on activation
	-- (managers.menu_component:post_event("menu_enter"), see _set_button_index_selected).
	managers.menu_component:post_event("menu_enter")

	if _G.CSR_OpenItemSelectionDebug and not _G._csr_item_selection_debug then
		_G.CSR_OpenItemSelectionDebug()
	end
end

function CSRMissionsMenuComponent:_start_pressed()
	-- Mirrors vanilla CrimeSpreeMissionEndOptions:perform_start, but routed
	-- through our forked callback. csr_start_game already guards on
	-- managers.csr:current_mission() == nil with a menu_error post.
	MenuCallbackHandler:csr_start_game()
end

function CSRMissionsMenuComponent:_reroll_pressed()
	-- Mirrors vanilla CrimeSpreeMissionEndOptions:perform_reroll. csr_reroll
	-- already guards on is_randomizing() (menu_error) and drives our component's
	-- randomize_crimespree(); it is the free-reroll fork (no continental coins).
	MenuCallbackHandler:csr_reroll()
end

-- A failed run (lobby only) locks mission select / Start until the player
-- resolves it via the paid Continue or End Spree. has_failed() is a persisted
-- managers.csr flag set by csr_mission_lifecycle on a lost heist.
function CSRMissionsMenuComponent:_is_locked()
	return self._is_lobby and managers.csr and managers.csr:has_failed() == true
end

-- Thin wrappers to the backend-swapped contract callbacks (same pattern as
-- _start_pressed -> csr_start_game). end_csr/return_to_csr_lobby/csr_continue
-- now act on managers.csr (Slice B backend swap).
function CSRMissionsMenuComponent:_action_end_spree()
	MenuCallbackHandler:end_csr()
end

function CSRMissionsMenuComponent:_action_return_to_lobby()
	MenuCallbackHandler:return_to_csr_lobby()
end

function CSRMissionsMenuComponent:_action_continue()
	MenuCallbackHandler:csr_continue()
end

-- Sets the context button (left of Reroll) + the Start/Reroll failed-lock.
-- Called at build and from refresh() so the failed state always re-applies.
function CSRMissionsMenuComponent:_refresh_action_buttons()
	local locked = self:_is_locked()

	if self._action_button then
		-- Loc: csr_end_spree / csr_return_to_lobby follow the csr_* convention
		-- (CSR-owned wording, like csr_lobby_rank). menu_cs_continue is the
		-- existing vanilla key (crimespreemissionendoptions.lua:80).
		if self._is_lobby then
			self._action_button:set_text(managers.localization:to_upper_text("csr_end_spree"))
			self._action_button:set_callback(callback(self, self, "_action_end_spree"))
		else
			self._action_button:set_text(managers.localization:to_upper_text("csr_return_to_lobby"))
			self._action_button:set_callback(callback(self, self, "_action_return_to_lobby"))
		end

		if managers.menu:is_pc_controller() then
			self._action_button:shrink_wrap_button()
		end

		self._action_button:panel():set_right(self._reroll_button:panel():left() - large_padding)
		self._action_button:panel():set_bottom(self._reroll_button:panel():bottom())
	end

	if self._start_button then
		-- Failed: Start hidden (cannot launch a heist on a failed run).
		self._start_button:panel():set_visible(not locked)
	end

	if self._reroll_button then
		if locked then
			self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_continue"))
			self._reroll_button:set_callback(callback(self, self, "_action_continue"))
		else
			self._reroll_button:set_text(managers.localization:to_upper_text("menu_cs_reroll"))
			self._reroll_button:set_callback(callback(self, self, "_reroll_pressed"))
		end

		if managers.menu:is_pc_controller() then
			self._reroll_button:shrink_wrap_button()
		end
	end
end

function CSRMissionsMenuComponent:update_mission(btn_idx)
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and (btn_idx == nil or btn:index() == btn_idx) then
			btn:update_mission(managers.csr:mission_set()[btn:index()])
		end
	end
end

function CSRMissionsMenuComponent:randomize_crimespree(btn_idx)
	managers.csr:select_mission(false)
	self:_select_mission(0)

	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and (btn_idx == nil or btn:index() == btn_idx) then
			btn:randomize(managers.csr:mission_set()[btn:index()])
		end
	end
end

function CSRMissionsMenuComponent:is_randomizing()
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and btn:is_randomizing() then
			return true
		end
	end

	return false
end

function CSRMissionsMenuComponent:selection_index()
	return self._selected_button or 0
end

function CSRMissionsMenuComponent:move_selection(dir)
	if not self:_is_host() then
		return false
	end

	self:_set_button_index_selected(self._selected_button, false)

	self._selected_button = self:selection_index() + dir

	if self._selected_button > #self._buttons then
		self._selected_button = 1
	elseif self._selected_button < 1 then
		self._selected_button = #self._buttons
	end

	self:_set_button_index_selected(self._selected_button, true)
end

function CSRMissionsMenuComponent:_select_mission(idx)
	if self._selected_button ~= idx then
		self:_set_button_index_selected(self._selected_button, false)
	end

	self._selected_button = idx

	self:_set_button_index_selected(idx, true)
end

function CSRMissionsMenuComponent:_set_button_index_selected(idx, selected)
	if not idx then
		return false
	end

	-- Failed run is locked: no mission can be selected until Continue (pay)
	-- or End Spree. The cards stay visible but inert.
	if selected and self:_is_locked() then
		return false
	end

	self._selected_button = idx
	local btn = self._buttons[idx]

	if btn then
		btn:set_selected(selected)
		btn:set_active(selected)

		-- Diverges DELIBERATELY from vanilla crimespreemissionsmenucomponent.lua
		-- (which calls select_mission(btn:mission_id()) unconditionally). In the
		-- CSR fork csr_start_game reads managers.csr:current_mission() directly,
		-- and reroll/_select_mission(0) deselects the old card AFTER
		-- reroll_mission_set() already nil'd current_mission. The vanilla
		-- unconditional call re-selects the old (still-attached) mission_data on
		-- that deselect, so Start launched the pre-reroll heist. Push the pick
		-- into the manager only when actually selecting; clear it on deselect so
		-- a reroll (and a genuine deselect) leaves current_mission nil.
		if selected then
			managers.csr:select_mission(btn:mission_id())
		else
			managers.csr:select_mission(false)
		end

		if selected and self:_is_host() then
			managers.menu_component:post_event("menu_enter")
		end

		-- MP mission-data sync deferred to a later slice (REFACTOR_PLAN §4.4).
	end
end

function CSRMissionsMenuComponent:get_selected_index()
	for idx, btn in ipairs(self._buttons) do
		if btn._type == "CSRMissionButton" and btn:is_active() then
			return btn:index()
		end
	end
end

function CSRMissionsMenuComponent:_is_host()
	return Network:is_server() or Global.game_settings.single_player
end

function CSRMissionsMenuComponent:refresh()
	-- Host-fail propagation is a later MP slice; nothing is hidden in alpha.
	local hide = false

	for idx, btn in ipairs(self._buttons) do
		if hide then
			btn:panel():hide()
		else
			btn:panel():show()
		end
	end

	self._host_failed_text:set_visible(hide)
	self._host_failed:set_visible(hide)
	-- Rank + difficulty are both children of self._title_panel, so this single
	-- toggle covers the whole header row.
	self._title_panel:set_visible(not hide)

	-- The reminder is a sibling of self._title_panel (own snug panel, not a
	-- child of the row), so it needs its own toggle. Re-evaluates the pending
	-- count every refresh -- the pick total can change across sub-screen
	-- round-trips -- and stays hidden while the host-fail screen is up.
	self:_refresh_unselected_items(not hide)

	-- Re-apply the context button + failed-lock every refresh so returning to
	-- a FAILED lobby comes up locked (Start hidden, Reroll -> Continue).
	self:_refresh_action_buttons()
end

function CSRMissionsMenuComponent.get_height()
	return CSRMissionsMenuComponent.button_size.h
		+ CSRMissionsMenuComponent.button_size.title_h
		+ tweak_data.menu.pd2_medium_font_size
end

function CSRMissionsMenuComponent:update(t, dt)
	local randomizing = self:is_randomizing()

	for idx, btn in ipairs(self._buttons) do
		btn:update(t, dt)
	end

	if self._sidebar then
		self._sidebar:update(t, dt)
	end

	if not managers.menu:is_pc_controller() and randomizing and not self:is_randomizing() then
		self:_select_mission(1)
	end
end

function CSRMissionsMenuComponent:mouse_moved(o, x, y)
	if not self:_is_host() or not managers.menu:is_pc_controller() then
		return
	end

	local used, pointer = nil

	-- The sidebar is a child object of THIS component but is geometrically
	-- disjoint from the mission cards: the sidebar column and
	-- self._buttons_panel never overlap (verified from runtime bounds
	-- 2026-05-19 -- sidebar x:[0,160], cards x:[618,1198]). So the sidebar
	-- needs NO coupling with the card-hover logic: forward the cursor to it
	-- purely for its own button highlight / hover-sound and let it report
	-- whether it consumed the cursor. The card loop below is independently
	-- bounded to self._buttons_panel, so a cursor over the sidebar simply
	-- yields cards_area=false and no card reacts. Removing the previous
	-- "over_sidebar" early-return (which force-cleared every card's
	-- set_selected and juggled the pointer) eliminated the entire
	-- collapse->expand flicker class -- the two were only ever coupled by
	-- that band-aid.
	if self._sidebar then
		local s_used, s_pointer = self._sidebar:mouse_moved(x, y)

		if s_used then
			used = true
			pointer = s_pointer or pointer
		end
	end

	-- Bound mission-card hover to the cards' OWN container. A card is only
	-- hover-selected when the cursor is inside self._buttons_panel AND inside
	-- that card. Without the container check, any widget drawn over the card
	-- area on a higher layer (the social-hub notification toast, lobby code,
	-- future overlays) makes the card behind it flicker as the cursor moves,
	-- because mouse_moved otherwise hit-tests cards across the whole screen
	-- (user report 2026-05-19, generalises the sidebar fix above).
	local cards_area = self._buttons_panel and alive(self._buttons_panel) and self._buttons_panel:inside(x, y)

	for idx, btn in ipairs(self._buttons) do
		btn:set_selected(cards_area and btn:inside(x, y) or false)

		if btn:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if self._start_button then
		self._start_button:set_selected(self._start_button:inside(x, y))

		if self._start_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if self._reroll_button then
		self._reroll_button:set_selected(self._reroll_button:inside(x, y))

		if self._reroll_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	if self._action_button then
		self._action_button:set_selected(self._action_button:inside(x, y))

		if self._action_button:is_selected() then
			pointer = "link"
			used = true
		end
	end

	-- Unselected-items reminder: link cursor on hover, mirroring the buttons
	-- above. self._unselected_visible already folds in the pending>0 + host-fail
	-- gating, so an invisible reminder can never be hovered. (Hover/click are
	-- only reached for host/SP -- mouse_moved early-returns for non-host, same
	-- as mission selection; full per-client behaviour is a later slice.)
	local was_unselected_hover = self._unselected_items_hover == true
	self._unselected_items_hover = self._unselected_visible == true
		and self._unselected_panel ~= nil
		and alive(self._unselected_panel)
		and self._unselected_panel:inside(x, y)

	if self._unselected_items_hover then
		pointer = "link"
		used = true

		-- Hover SFX once on the false->true transition (NOT every mouse_moved
		-- while inside) -- the exact gate vanilla CrimeNetSidebarItem:set_highlight
		-- uses. "highlight" is the vanilla menu hover event
		-- (crimenetsidebargui.lua:604; also CSRSidebarItem:set_highlight here).
		if not was_unselected_hover then
			managers.menu:post_event("highlight")
		end
	end

	-- Brighten on hover, dim otherwise (mirrors the buttons' set_selected here;
	-- mouse_moved is event-driven, not a per-frame path, so set_color is cheap).
	if self._unselected_visible and alive(self._unselected_panel) then
		self._unselected_items:set_color(
			self._unselected_items_hover and self._unselected_color_bright or self._unselected_color_dim
		)
	end

	-- Items feature panel hover -> tooltip + edge-gated highlight SFX. Returns
	-- true when an item icon is under the cursor so the pointer flips to "link"
	-- (mirroring the unselected-items reminder + mission cards). Hidden-panel
	-- case is handled inside the method (drops any stale tooltip).
	if self:_items_panel_mouse_moved(x, y) then
		pointer = "link"
		used = true
	end

	return used, pointer
end

-- NOTE: MenuComponentManager dispatches this via
-- run_return_on_all_live_components("mouse_pressed", button, x, y)
-- (menucomponentmanager.lua:1693) — i.e. the component is called as
-- mouse_pressed(self, button, x, y), only THREE args. Vanilla declares
-- (o, button, x, y) and gets away with it because its body only calls
-- confirm_pressed() and never reads the (shifted) coords. Our sidebar branch
-- needs real x,y, so we must use the correct 3-arg signature here.
function CSRMissionsMenuComponent:mouse_pressed(button, x, y)
	-- Sidebar click uses real cursor coords (confirm_pressed has none). With
	-- placeholder buttons (no callbacks) this returns nil and falls through, so
	-- card/start/reroll handling is unchanged until sidebar callbacks land.
	if self._sidebar and self._sidebar:mouse_pressed(x, y) then
		return true
	end

	return self:confirm_pressed()
end

function CSRMissionsMenuComponent:confirm_pressed()
	if not self:_is_host() then
		return nil
	end

	for idx, btn in ipairs(self._buttons) do
		if btn:is_selected() and btn:callback() then
			btn:callback()()

			return true
		end
	end

	if self._start_button and self._start_button:is_selected() and self._start_button:callback() then
		self._start_button:callback()()

		return true
	end

	if self._reroll_button and self._reroll_button:is_selected() and self._reroll_button:callback() then
		self._reroll_button:callback()()

		return true
	end

	if self._action_button and self._action_button:is_selected() and self._action_button:callback() then
		self._action_button:callback()()

		return true
	end

	if self._unselected_items_hover then
		self:_on_unselected_items_clicked()

		return true
	end
end

function CSRMissionsMenuComponent:dummy_trigger()
	return self:confirm_pressed()
end

function CSRMissionsMenuComponent:move_left()
	self:move_selection(-1)
end

function CSRMissionsMenuComponent:move_right()
	self:move_selection(1)
end

function CSRMissionsMenuComponent:input_focus() end

CSRMissionButton = CSRMissionButton or class(MenuGuiItem)
CSRMissionButton._type = "CSRMissionButton"
CSRMissionButton.RandomState = {
	Cleanup = 5,
	Rollback = 3,
	Done = 4,
	Slow = 2,
	Spin = 1,
}

function CSRMissionButton:init(idx, parent, mission_data)
	self._idx = idx
	self._mission_data = mission_data
	self._panel = parent:panel({
		layer = 60,
		name = "mission_" .. tostring(self._mission_data.id),
		w = CSRMissionsMenuComponent.button_size.w,
		h = CSRMissionsMenuComponent.button_size.h + CSRMissionsMenuComponent.button_size.title_h,
		x = (CSRMissionsMenuComponent.button_size.w + padding) * (idx - 1),
	})
	self._image_panel = self._panel:panel({
		h = self._panel:h() - CSRMissionsMenuComponent.button_size.title_h,
	})
	self._mission_bg = self._image_panel:rect({
		layer = -2,
		color = Color.black,
	})
	local texture, rect = tweak_data.hud_icons:get_icon_data(mission_data.icon)

	if not texture or not DB:has(Idstring("texture"), texture) then
		texture = "guis/dlcs/cee/textures/pd2/crime_spree/missions_atlas"
		rect = {
			0,
			0,
			280,
			140,
		}
	end

	self._mission_image = self._image_panel:bitmap({
		blend_mode = "add",
		name = "mission_image",
		layer = 9,
		stream = true,
		texture = texture,
		texture_rect = rect,
		w = self._panel:w(),
		h = self._panel:h(),
	})
	local image_scanlines = self._image_panel:bitmap({
		texture = "guis/dlcs/chill/textures/pd2/rooms/safehouse_room_preview_effect",
		name = "scalines",
		layer = 11,
		wrap_mode = "wrap",
		texture_rect = {
			0,
			0,
			512,
			512,
		},
		w = self._panel:w(),
		h = self._panel:h(),
	})
	local h = tweak_data.menu.pd2_medium_font_size
	self._info_panel = self._panel:panel({
		layer = 50,
		h = h,
	})

	self._info_panel:set_top(padding * 0.5)

	local h = CSRMissionsMenuComponent.button_size.title_h
	local level_name_bg = self._panel:rect({
		y = self._panel:h() - h,
		h = h,
		color = Color(0.05, 0.05, 0.05),
	})
	self._highlight_name = self._panel:rect({
		layer = 1,
		y = self._panel:h() - h,
		h = h,
		color = tweak_data.screen_colors.button_stage_3,
	})
	self._level_text = self._panel:text({
		halign = "center",
		vertical = "center",
		layer = 51,
		align = "center",
		text = "",
		y = 0,
		x = 0,
		valign = "center",
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	BlackMarketGui.make_fine_text(self, self._level_text)
	self._level_text:set_center_x(self._panel:w() * 0.5)

	self._info_text = self._info_panel:text({
		halign = "center",
		vertical = "center",
		layer = 1,
		align = "center",
		text = "",
		y = 0,
		x = 0,
		valign = "center",
		color = Color.white,
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
	})

	self:update_info_text(self._mission_data)

	self._bg = self._panel:rect({
		alpha = 0.4,
		layer = -1,
		color = Color.black,
	})
	self._highlight = self._panel:rect({
		blend_mode = "add",
		layer = -1,
		color = tweak_data.screen_colors.button_stage_3,
	})
	self._blur = self._panel:bitmap({
		texture = "guis/textures/test_blur_df",
		layer = -1,
		halign = "scale",
		alpha = 1,
		render_template = "VertexColorTexturedBlur3D",
		valign = "scale",
		w = self._panel:w(),
		h = self._panel:h(),
	})
	self._border_panel = self._panel:panel({
		layer = 20,
	})

	BoxGuiObject:new(self._border_panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})

	self._active_border = BoxGuiObject:new(self._border_panel, {
		sides = {
			2,
			2,
			2,
			2,
		},
	})

	self:update_button_text()
	self:refresh()
end

function CSRMissionButton:refresh()
	-- Fork divergence from vanilla CrimeSpreeMissionButton:refresh (which keys
	-- _bg purely on is_selected): vanilla CS auto-launches the heist the instant
	-- a mission is picked, so a chosen card is never left on screen to hover
	-- away from. CSR keeps the chosen mission card persistent in the lobby, so
	-- with vanilla's rule the chosen card's _bg pulses every time the cursor
	-- enters/leaves it (set_selected toggles via the hover loop while is_active
	-- stays true -- runtime-confirmed 2026-05-19). Gate _bg on is_active too so
	-- the chosen card holds its selected look regardless of hover; the other
	-- three lines already depend on is_active and were always stable.
	self._bg:set_visible(not (self:is_selected() or self:is_active()))
	self._highlight:set_visible(self:is_active() or self:is_selected())
	self._highlight_name:set_visible(self:is_active() or self:is_selected())
	self._active_border:set_visible(self:is_active())
end

function CSRMissionButton:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRMissionButton:panel()
	return self._panel
end

function CSRMissionButton:index()
	return self._idx
end

function CSRMissionButton:callback()
	return self._callback
end

function CSRMissionButton:set_callback(clbk)
	self._callback = clbk
end

function CSRMissionButton:is_randomizing()
	return self._randomize ~= nil
end

function CSRMissionButton:update(t, dt)
	if self._randomize then
		if self._randomize.state == CSRMissionButton.RandomState.Spin then
			self._randomize.t = self._randomize.t - dt
			local speed = math.clamp(
				self._randomize.t * tweak_data.crime_spree.gui.spin_speed,
				unpack(tweak_data.crime_spree.gui.spin_speed_limit)
			)

			self:_move_random_texts(speed, dt)

			if self._randomize.t <= 0 then
				self._randomize.t = nil
				self._randomize.state = CSRMissionButton.RandomState.Slow
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Slow then
			local slow_time = {
				0.1,
				0.3,
			}
			local speed = tweak_data.crime_spree.gui.spin_speed_limit[1]

			if self._randomize.t then
				speed = speed * self._randomize.t / slow_time[2]
			end

			self:_move_random_texts(speed, dt)

			if not self._randomize.t and math.abs(self._level_text:y() - self:button_text_h()) < 2 then
				self._randomize.t = math.rand(unpack(slow_time))
			end

			if self._randomize.t then
				self._randomize.t = self._randomize.t - dt

				if self._randomize.t <= 0 then
					self._randomize.t = nil
					self._randomize.state = CSRMissionButton.RandomState.Rollback
				end
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Rollback then
			local speed = (self._level_text:y() - self:button_text_h()) * dt

			self:_move_random_texts(-200, dt)

			local dis = self._level_text:y() - self:button_text_h()

			if dis < 0.1 then
				self._randomize.state = CSRMissionButton.RandomState.Done
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Done then
			local fade_out_t = 0.5

			self:update_button_text()
			self:update_info_text()

			if not self._randomize.t then
				self._randomize.t = fade_out_t
			else
				self._randomize.t = self._randomize.t - dt

				for i, text in ipairs(self._random_texts) do
					if i > 1 then
						text:set_alpha(self._randomize.t / fade_out_t)
					end
				end

				self._info_panel:set_alpha(1 - self._randomize.t / fade_out_t)
				self._mission_image:set_alpha(1 - self._randomize.t / fade_out_t)
				self._mission_bg:set_alpha(1 - self._randomize.t / fade_out_t)

				if self._randomize.t <= 0 then
					self._randomize.state = CSRMissionButton.RandomState.Cleanup
				end
			end
		elseif self._randomize.state == CSRMissionButton.RandomState.Cleanup then
			self:_cleanup_random_texts()

			self._randomize = nil
		end
	end
end

function CSRMissionButton:randomize(mission_data)
	self._mission_data = mission_data
	self._randomize = {
		state = CSRMissionButton.RandomState.Spin,
		t = math.rand(unpack(tweak_data.crime_spree.gui.randomize_time)),
	}

	self._info_panel:set_alpha(0)
	self._mission_image:set_alpha(0)
	self._mission_bg:set_alpha(0)
	self:_create_random_texts()
end

function CSRMissionButton:update_mission(mission_data)
	self._mission_data = mission_data

	self:update_button_text(nil, mission_data)
	self:update_info_text(mission_data)
end

function CSRMissionButton:update_button_text(text, mission_data, dont_reset_pos)
	text = text or self._level_text
	mission_data = mission_data or self._mission_data
	local level_tweak = tweak_data.levels[mission_data.level.level_id] or {}

	text:set_text(managers.localization:to_upper_text(level_tweak.name_id))
	text:set_font_size(tweak_data.menu.pd2_small_font_size)

	local x, y, w, h = text:text_rect()

	if self._panel:w() <= w then
		text:set_font_size(tweak_data.menu.pd2_small_font_size * 0.8)
	end

	BlackMarketGui.make_fine_text(self, text)
	text:set_center_x(self._panel:w() * 0.5)

	if not dont_reset_pos then
		text:set_y(self:button_text_h())
	end
end

function CSRMissionButton:button_text_h()
	return self._panel:h() - tweak_data.menu.pd2_small_font_size - 4
end

function CSRMissionButton:update_info_text(mission_data)
	mission_data = mission_data or self._mission_data
	local text = ""
	local spacer = " "
	local category = self:_get_mission_category(mission_data)

	if category then
		local timer_text = managers.localization:get_default_macro("BTN_SPREE_" .. utf8.to_upper(category))
		text = text .. timer_text
	end

	local level_tweak = tweak_data.levels[mission_data.level.level_id]

	if level_tweak and level_tweak.ghost_bonus then
		local stealth_text = managers.localization:get_default_macro("BTN_SPREE_STEALTH")
		text = text .. spacer .. stealth_text
	end

	text = text .. spacer
	local len = utf8.len(text)
	-- Vanilla passes mission_data.add here -- the per-mission rank increment
	-- from vanilla CS tweak_data, which varies by mission length/difficulty.
	-- The CSR rebalance makes every completed heist worth a FLAT rank amount
	-- (rank_per_heist), so the card must advertise that same flat value, not
	-- the vanilla per-mission number. This is the exact value the player
	-- actually receives -- csr_mission_lifecycle.lua awards
	-- managers.csr:constant("rank_per_heist") on a successful heist with the
	-- identical `or 1` fallback, so the card and the payout never disagree.
	local inc_text = managers.localization:text("menu_cs_lobby_mission_inc", {
		inc = managers.csr:constant("rank_per_heist") or 1,
	})
	text = text .. inc_text

	self._info_text:set_text(text)
	self._info_text:set_range_color(len, len + utf8.len(inc_text), tweak_data.screen_colors.crime_spree_risk)

	local texture, rect = tweak_data.hud_icons:get_icon_data(mission_data.icon)

	if not texture or not DB:has(Idstring("texture"), texture) then
		texture = "guis/dlcs/cee/textures/pd2/crime_spree/missions_atlas"
		rect = {
			0,
			0,
			280,
			140,
		}
	end

	self._mission_image:set_image(texture)

	if rect then
		self._mission_image:set_texture_rect(unpack(rect))
	end
end

function CSRMissionButton:_create_random_texts()
	self:_cleanup_random_texts()

	self._random_texts = {}

	table.insert(self._random_texts, self._level_text)

	for i = 1, 8 do
		local text = self._panel:text({
			halign = "center",
			vertical = "center",
			layer = 1,
			align = "center",
			text = "",
			y = 0,
			x = 0,
			valign = "center",
			color = Color.white,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
		})

		table.insert(self._random_texts, text)
		self:update_button_text(text, managers.csr:get_random_mission(), true)

		if i > 1 then
			text:set_bottom(self._random_texts[i]:top())
		else
			text:set_bottom(self._panel:top())
		end

		text:set_center_x(self._panel:w() * 0.5)
	end
end

function CSRMissionButton:_cleanup_random_texts()
	if self._random_texts then
		for i, text in ipairs(self._random_texts) do
			if i > 1 then
				self._panel:remove(text)
			end
		end

		self._random_texts = nil
	end
end

function CSRMissionButton:_move_random_texts(speed, dt)
	for i, text in ipairs(self._random_texts) do
		text:set_y(text:y() + speed * dt)

		if self._panel:h() < text:y() then
			local idx = (i - 1) % #self._random_texts

			if idx == 0 then
				idx = #self._random_texts or idx
			end

			text:set_bottom(self._random_texts[idx]:top())

			if i == 1 then
				self:update_button_text(nil, nil, true)
			else
				self:update_button_text(text, managers.csr:get_random_mission(), true)
			end
		end
	end
end

function CSRMissionButton:_get_mission_category(mission)
	if mission.add <= 5 then
		return "short"
	elseif mission.add <= 7 then
		return "medium"
	else
		return "long"
	end
end

function CSRMissionButton:mission_id()
	return (self._mission_data or {}).id
end

-- CSRStartButton — byte-for-byte fork of vanilla CrimeSpreeButton
-- (pd2_source_code/lib/managers/menu/crimespreemodifiersmenucomponent.lua:526-614).
-- This is the SAME widget vanilla CS uses for its "Start the Heist" option
-- (crimespreemissionendoptions.lua builds it with menu_cs_start + pd2_large_font
-- + shrink_wrap_button): a clean right-aligned large-font text button with a
-- faint add-blend highlight, NOT a boxed/blurred panel. Class rename only; the
-- widget is backend-agnostic (pure Diesel UI). The callback owner
-- (CSRMissionsMenuComponent:_start_pressed) routes to our forked csr_start_game.
CSRStartButton = CSRStartButton or class(MenuGuiItem)
CSRStartButton._type = "CSRStartButton"

function CSRStartButton:init(parent, font, font_size)
	self._w = 0.35
	self._color = tweak_data.screen_colors.button_stage_3
	self._selected_color = tweak_data.screen_colors.button_stage_2
	self._links = {}
	self._panel = parent:panel({
		layer = 1000,
		x = parent:w() * (1 - self._w) - padding,
		w = parent:w() * self._w,
		h = font_size or tweak_data.menu.pd2_medium_font_size,
	})

	self._panel:set_bottom(parent:h())

	self._text = self._panel:text({
		y = 0,
		blend_mode = "add",
		align = "right",
		text = "",
		halign = "right",
		x = 0,
		layer = 1,
		color = self._color,
		font = font or tweak_data.menu.pd2_medium_font,
		font_size = font_size or tweak_data.menu.pd2_medium_font_size,
	})
	self._highlight = self._panel:rect({
		blend_mode = "add",
		alpha = 0.2,
		valign = "scale",
		halign = "scale",
		layer = 10,
		color = self._color,
	})

	self:refresh()
end

function CSRStartButton:refresh()
	self._highlight:set_visible(self:is_selected())
	self._highlight:set_color(self:is_selected() and self._selected_color or self._color)
	self._text:set_color(self:is_selected() and self._selected_color or self._color)
end

function CSRStartButton:panel()
	return self._panel
end

function CSRStartButton:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRStartButton:callback()
	return self._callback
end

function CSRStartButton:set_callback(clbk)
	self._callback = clbk
end

function CSRStartButton:set_button(btn)
	self._btn = btn
end

function CSRStartButton:set_text(text)
	local prefix = not managers.menu:is_pc_controller()
			and self._btn
			and managers.localization:get_default_macro(self._btn)
		or ""

	self._text:set_text(prefix .. text)
end

function CSRStartButton:get_link(dir)
	return self._links[dir]
end

function CSRStartButton:set_link(dir, item)
	self._links[dir] = item
end

function CSRStartButton:update(t, dt) end

function CSRStartButton:shrink_wrap_button(w_padding, h_padding)
	local _, _, w, h = self._text:text_rect()

	self._panel:set_size(w + (w_padding or 0), h + (h_padding or 0))
end

-- CSRSidebar / CSRSidebarItem — fork of vanilla CrimeNetSidebarGui /
-- CrimeNetSidebarItem (pd2_source_code/lib/managers/menu/crimenetsidebargui.lua).
-- Visual recipe copied 1:1: 256-wide panel pinned to the workspace left edge,
-- 0.4 black rect + test_blur_df backdrop on a layer -1 sub-panel, BoxGui border,
-- and per-row icon + underscored-uppercase label with a 0.66 black highlight bg.
-- Deliberately NOT forked (user wants "just the panel"): collapse/expand state,
-- glow, pulse colour, controller mouse-snap, the tweak_data.gui.crime_net.sidebar
-- data drive, and the Attention/Separator/Safehouse/etc. item subclasses. Items
-- here are a static placeholder list with no callbacks; behaviour is a later
-- pass. Pure Diesel UI — no managers.crime_spree / managers.csr reads; CSR-only
-- scoping is guaranteed by the owning component (built only for crime_spree_lobby).
CSRSidebar = CSRSidebar or class()
CSRSidebar._type = "CSRSidebar"
CSRSidebar.WIDTH = 160 -- vanilla CrimeNet sidebar is 256; CSR uses a narrower panel
-- CSR feature rows, in the order the user requested. icon ids are real vanilla
-- hud_icons used by the live CrimeNet sidebar (guitweakdata.lua:1840+) so they
-- resolve through tweak_data.hud_icons:get_icon_data — they are PLACEHOLDERS
-- only (final art TBD). Callbacks are wired per-row as features get ported;
-- rows without one are inert until then.
local function csr_open_logbook()
	-- Reuse the ported open-node callback (lua/menu/logbook_button.lua), which
	-- wraps managers.menu:open_node("csr_logbook_screen"). Resolved at click
	-- time, so load order with the logbook scripts doesn't matter.
	local has_cb = MenuCallbackHandler ~= nil and MenuCallbackHandler.CSR_OpenLogbook ~= nil
	log("[CSR Logbook] sidebar Logbook clicked; CSR_OpenLogbook present=" .. tostring(has_cb))

	if has_cb then
		MenuCallbackHandler:CSR_OpenLogbook()
	end
end

-- Sidebar row callbacks are invoked as btn:callback()(owner) where owner is the
-- CSRMissionsMenuComponent (CSRSidebar:mouse_pressed passes self._owner). The
-- feature panels are component-owned (they span from the sidebar to the mission
-- cards, geometry the sidebar itself doesn't know), so each row forwards to the
-- owner with its category key. The factory returns a stateless module-level
-- closure (captures only the constant key, no instance state -- safe to share
-- across instances). nil/method-guarded so a missing owner is inert.
local function csr_feature_toggle(key)
	return function(owner)
		if owner and owner.toggle_feature_panel then
			owner:toggle_feature_panel(key)
		end
	end
end

CSRSidebar.ITEMS = {
	-- Divider between the always-visible Hide/Show toggle (built before this
	-- list, pinned to the top) and the content rows. Built in the same loop, so
	-- it joins self._buttons and is hidden/non-interactive on collapse like the
	-- other separators — no special-casing needed.
	{ separator = true },
	{ text = "Items", icon = "sidebar_basics", callback = csr_feature_toggle("items") },
	{ text = "Modifiers", icon = "sidebar_mutators", callback = csr_feature_toggle("modifiers") },
	{ text = "Rewards", icon = "sidebar_broker", callback = csr_feature_toggle("rewards") },
	{ separator = true },
	{ text = "Gage Services", icon = "sidebar_gage" },
	{ separator = true },
	{ text = "Logbook", icon = "sidebar_codex", callback = csr_open_logbook },
}

function CSRSidebar:init(parent, top, bottom, owner)
	-- owner = the CSRMissionsMenuComponent. Stored so row callbacks can act on
	-- component-owned UI (e.g. the Items panel) via btn:callback()(self._owner).
	self._owner = owner
	self._buttons = {}
	self._panel = parent:panel({
		w = CSRSidebar.WIDTH,
		y = top,
		h = bottom - top,
		layer = 100,
	})
	self._bg_panel = self._panel:panel({
		layer = -1,
	})

	self._bg_panel:rect({
		alpha = 0.4,
		color = Color.black,
	})
	self._bg_panel:bitmap({
		texture = "guis/textures/test_blur_df",
		name = "blur_bg",
		halign = "scale",
		layer = -1,
		render_template = "VertexColorTexturedBlur3D",
		valign = "scale",
		w = self._bg_panel:w(),
		h = self._bg_panel:h(),
	})

	self._collapsed = false

	local item_margin = 2

	-- Always-visible collapse toggle, pinned to the top of the sidebar. It is
	-- deliberately NOT part of the collapsible content (set_collapsed never
	-- touches it), so it stays on screen as a "SHOW_SIDEBAR" affordance once the
	-- rest is hidden. Same CSRSidebarItem widget + vanilla "sidebar_expand" icon
	-- (hudiconstweakdata.lua — the exact icon the live CrimeNet sidebar uses for
	-- its collapse control) as every other row. CSRSidebarItem callbacks are
	-- invoked as btn:callback()(owner) in mouse_pressed; this arg-less closure
	-- ignores the owner and just forwards to self:toggle_collapsed().
	self._toggle = CSRSidebarItem:new(self._panel, {
		position = padding,
		text = "Hide Sidebar",
		icon = "sidebar_expand",
		callback = function()
			self:toggle_collapsed()
		end,
	})

	table.insert(self._buttons, self._toggle)

	local next_position = padding + self._toggle:panel():height() + item_margin

	for _, item in ipairs(CSRSidebar.ITEMS) do
		local btn

		if item.separator then
			btn = CSRSidebarSeparator:new(self._panel, {
				position = next_position,
			})
		else
			btn = CSRSidebarItem:new(self._panel, {
				position = next_position,
				text = item.text,
				icon = item.icon,
				callback = item.callback,
			})
		end

		next_position = next_position + btn:panel():height() + item_margin

		table.insert(self._buttons, btn)
	end

	-- Stored (was an anonymous panel in vanilla) so set_collapsed can hide the
	-- frame along with the rest of the collapsible content.
	self._border_panel = self._panel:panel({
		layer = 100,
	})
	self._border = BoxGuiObject:new(self._border_panel, {
		sides = {
			1,
			1,
			1,
			1,
		},
	})
end

-- Collapse toggle. The toggle button itself is always left visible/interactive;
-- only the backdrop, the rows, and the frame are hidden. inside() still returns
-- geometric hits on a set_visible(false) panel, so mouse_moved/mouse_pressed
-- gate the non-toggle rows on self._collapsed rather than on visibility.
function CSRSidebar:toggle_collapsed()
	self:set_collapsed(not self._collapsed)
end

function CSRSidebar:set_collapsed(collapsed)
	self._collapsed = collapsed and true or false

	if self._bg_panel then
		self._bg_panel:set_visible(not self._collapsed)
	end

	if self._border_panel then
		self._border_panel:set_visible(not self._collapsed)
	end

	for _, btn in ipairs(self._buttons) do
		if btn ~= self._toggle then
			btn:panel():set_visible(not self._collapsed)
		end
	end

	-- Collapsing also hides the component-owned feature panel (Items/Modifiers/
	-- Rewards) -- it is opened from a sidebar row, so it must not linger when the
	-- sidebar is hidden (user spec 2026-05-19). Expanding does NOT reopen it; the
	-- player re-clicks the row. owner/method-guarded (inert if absent).
	if self._collapsed and self._owner and self._owner.hide_feature_panels then
		self._owner:hide_feature_panels()
	end

	self._toggle:set_text(self._collapsed and "Show Sidebar" or "Hide Sidebar")
end

function CSRSidebar:panel()
	return self._panel
end

function CSRSidebar:mouse_moved(x, y)
	local used, pointer = false, nil

	for _, btn in ipairs(self._buttons) do
		-- While collapsed only the toggle is live (hidden rows still hit-test).
		if (btn == self._toggle or not self._collapsed) and btn:accepts_interaction() then
			local inside = btn:inside(x, y)

			-- No no_sound / force_update args (vanilla CrimeNetSidebarGui
			-- :mouse_moved calls set_highlight(true)/(false) bare): the change
			-- guard fires the hover sound once per transition, never per frame.
			btn:set_highlight(inside)

			if inside then
				used = true
				pointer = "link"
			end
		end
	end

	return used, pointer
end

function CSRSidebar:mouse_pressed(x, y)
	for _, btn in ipairs(self._buttons) do
		-- While collapsed only the toggle is live (hidden rows still hit-test).
		if
			(btn == self._toggle or not self._collapsed)
			and btn:accepts_interaction()
			and btn:inside(x, y)
			and btn:callback()
		then
			-- Click feedback, posted centrally (vanilla scatters this into every
			-- clbk_*; one site here covers all rows + the toggle + future
			-- callbacks). Same event the mission cards / tabs use elsewhere in
			-- this file. Row callbacks must therefore NOT post their own click
			-- sound or it double-triggers.
			managers.menu_component:post_event("menu_enter")
			-- Pass the owning component so component-scoped rows (Items) can act
			-- on it; the arg-less closures (toggle / csr_open_logbook) ignore it.
			btn:callback()(self._owner)

			return true
		end
	end
end

function CSRSidebar:update(t, dt)
	for _, btn in ipairs(self._buttons) do
		btn:update(t, dt)
	end
end

-- CSRSidebarSeparator — fork of vanilla CrimeNetSidebarSeparator
-- (crimenetsidebargui.lua:457-491), 1:1 minus the collapse width-swap (we have
-- no collapse). A non-interactive 10px row with the vanilla dotted divider
-- texture. Texture path verified present in extracted assets
-- (guis/dlcs/sju/textures/pd2/crimenet_menu_dots_df.texture).
CSRSidebarSeparator = CSRSidebarSeparator or class()
CSRSidebarSeparator._type = "CSRSidebarSeparator"

function CSRSidebarSeparator:init(parent_panel, parameters)
	self._panel = parent_panel:panel({
		h = 10,
		layer = 10,
		w = parent_panel:width() - padding * 2,
		x = padding,
		y = parameters.position,
	})

	local bitmap = self._panel:bitmap({
		texture = "guis/dlcs/sju/textures/pd2/crimenet_menu_dots_df",
		name = "separator",
		color = tweak_data.screen_colors.button_stage_3,
	})

	bitmap:set_center_y(self._panel:height() * 0.5)
end

function CSRSidebarSeparator:panel()
	return self._panel
end

function CSRSidebarSeparator:accepts_interaction()
	return false
end

function CSRSidebarSeparator:update(t, dt) end

CSRSidebarItem = CSRSidebarItem or class()
CSRSidebarItem._type = "CSRSidebarItem"

function CSRSidebarItem:init(panel, parameters)
	local font_size = math.ceil(tweak_data.menu.pd2_small_font_size)
	local icon_size = 24
	local panel_size = math.max(font_size, icon_size)
	self._callback = parameters.callback
	self._panel = panel:panel({
		halign = "scale",
		layer = 10,
		valign = "scale",
		w = panel:w() - padding * 2,
		h = panel_size,
		x = padding,
		y = parameters.position,
	})

	local texture, rect = tweak_data.hud_icons:get_icon_data(parameters.icon)

	self._icon = self._panel:bitmap({
		name = "icon",
		blend_mode = "normal",
		layer = 1,
		texture = texture,
		texture_rect = rect,
		w = icon_size,
		h = icon_size,
	})
	self._text = self._panel:text({
		text = "",
		name = "title",
		valign = "scale",
		halign = "scale",
		blend_mode = "normal",
		y = 2,
		layer = 2,
		font = tweak_data.menu.pd2_medium_font,
		font_size = font_size,
		color = tweak_data.screen_colors.button_stage_3,
		x = icon_size + 4,
		h = font_size,
	})

	self:set_text(parameters.text or "")

	self._bg = self._panel:rect({
		blend_mode = "normal",
		layer = 1,
		halign = "scale",
		alpha = 0.66,
		valign = "scale",
		x = icon_size,
		color = Color.black,
	})

	self:set_highlight(false, true)
end

function CSRSidebarItem:inside(x, y)
	return self._panel:inside(x, y)
end

function CSRSidebarItem:panel()
	return self._panel
end

function CSRSidebarItem:callback()
	return self._callback
end

function CSRSidebarItem:accepts_interaction()
	return true
end

-- Signature restored to vanilla CrimeNetSidebarItem:set_highlight 1:1
-- (enabled, no_sound, force_update). The block (and thus the hover "highlight"
-- sound) only runs on a real state change unless force_update is set; the init
-- call passes no_sound=true so building the sidebar is silent, exactly like
-- vanilla (crimenetsidebargui.lua:553/584-608). managers.menu:post_event
-- ("highlight") is the same hover event vanilla uses (verified line 604).
function CSRSidebarItem:set_highlight(enabled, no_sound, force_update)
	if self._highlight ~= enabled or force_update then
		self._text:set_visible(true)
		self._bg:set_visible(enabled)
		self._text:set_color(enabled and Color.white or tweak_data.screen_colors.button_stage_2)
		self._icon:set_color(enabled and Color.white or tweak_data.screen_colors.button_stage_2)
		self._bg:set_color(Color.black)

		if not no_sound then
			managers.menu:post_event("highlight")
		end

		self._highlight = enabled
	end
end

function CSRSidebarItem:set_text(text)
	-- Vanilla quirk preserved 1:1 (CrimeNetSidebarItem:set_text): upper-case and
	-- spaces -> underscores. Keeps the look identical to the CrimeNet sidebar.
	text = utf8.to_upper(text)
	text = text:gsub(" ", "_")

	self._text:set_text(text)
end

function CSRSidebarItem:update(t, dt) end

log("[CSR] csr_missions_menu.lua loaded (Slice 8 fork + start button)")
