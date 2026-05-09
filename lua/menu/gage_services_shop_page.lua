-- Crime Spree Roguelike - Gage's Services Shop Page
-- Renders 3 item cards, reroll button, token counter for the Shop tab of the
-- Gage Services menu. Reads state from CSR_PlayerItems[local_peer_id] and the
-- shop manager; mutates via CSR_ShopManager API.

if not RequiredScript then
	return
end

CrimeSpreeGageServicesShopPage = CrimeSpreeGageServicesShopPage or class()

local CARD_W = 280
local CARD_H = 360
local CARD_GAP = 30
-- Vertical layout: dialogue (0..70) → toolbar (80..116) → cards (120..480).
-- Tab panel height = content_panel:h() - 120 = 480 (gage_services_menu.lua:181).
local CARD_TOP = 120

local DIALOGUE_TOP = 0
local DIALOGUE_HEIGHT = 70
-- Dialogue strip spans the full tab panel width (computed in _create_dialogue_strip
-- from self._panel:w()) so it lines up with the full-width SHOP tab above.
local DIALOGUE_X = 0
local TOOLBAR_TOP = 80 -- tokens + reroll row, sits below the dialogue strip

-- Rarity colors matching items_page.lua / logbook_page.lua / item_frames_in_selection.lua
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(0, 0.95, 0),
	rare = Color(0.3, 0.7, 1),
	contraband = Color(1, 0.4, 0),
}

-- Maps registry `type` to logbook `id` used in csr_logbook_<id>_effect
-- localization keys. Only entries whose type differs from the loc-key suffix
-- are listed here.
--
-- Source of truth: cross-reference `lua/core/item_registry.lua` (entry.type)
-- with `lua/managers/localization.lua` (csr_logbook_<id>_effect keys). When
-- adding a new item, if entry.type matches the loc-key suffix you don't need
-- to add an entry here; if they differ, add the mapping.
--
-- Currently empty: every registry type was renamed to match its loc-key suffix
-- so no translation is needed. Kept around for future entries that can't
-- afford the rename (e.g. preserving back-compat with another consumer).
local TYPE_TO_LOGBOOK_ID = {}

-- Only csr_frame.dds exists on disk; all rarities reuse it and rely on RARITY_COLORS
-- for tinting (same approach as logbook_menu.lua:210-213).
local FRAME_KEYS = {
	common = "csr_frame",
	uncommon = "csr_frame",
	rare = "csr_frame",
	contraband = "csr_frame",
}

function CrimeSpreeGageServicesShopPage:init(panel, parent)
	self._panel = panel
	self._parent = parent
	self._cards = {}
	self:_setup()
	-- Expose the live instance so debug tools / sync code can call :refresh()
	-- when the shop is open (mirrors CSR_ItemsPageInstance pattern).
	_G.CSR_GageServicesShopPageInstance = self
end

function CrimeSpreeGageServicesShopPage:_setup()
	self:_create_token_counter()
	self:_create_reroll_button()
	self:_create_dialogue_strip()
	self:_create_cards()
	-- On open, animate the heist-locked greeting line typewriter-style.
	self:_set_dialogue_line(CSR_ShopManager.get_or_pick_greeting(), true)
	self:refresh()
end

function CrimeSpreeGageServicesShopPage:_create_dialogue_strip()
	local strip_w = self._panel:w()
	self._dialogue_panel = self._panel:panel({
		name = "csr_gage_dialogue",
		w = strip_w,
		h = DIALOGUE_HEIGHT,
		x = DIALOGUE_X,
		y = DIALOGUE_TOP,
	})
	self._dialogue_panel:rect({
		color = Color(0, 0, 0),
		alpha = 0.5,
		layer = 0,
	})
	-- Plain bordered box (sides 2 = solid line). Color carries its own alpha;
	-- 0.4 makes the border faintly visible without competing with the cards
	-- below.
	if BoxGuiObject then
		self._dialogue_box = BoxGuiObject:new(self._dialogue_panel, {
			sides = { 2, 2, 2, 2 },
			color = Color(0.2, 1, 1, 1),
		})
	end
	self._dialogue_text = self._dialogue_panel:text({
		name = "csr_gage_dialogue_text",
		text = "",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 24,
		color = Color(0.9, 0.9, 0.9),
		align = "left",
		vertical = "center",
		wrap = true,
		word_wrap = true,
		x = 16,
		y = 0,
		w = strip_w - 32,
		h = DIALOGUE_HEIGHT,
		layer = 1,
	})
end

-- Set the dialogue line shown in the strip. Accepts a localization key; the
-- displayed text is prefixed with "> " (PD2's bitmap fonts have no runtime
-- italic, so the chevron is what signals "this is dialogue").
-- When animate=true, runs a typewriter reveal via panel:animate (coroutine).
function CrimeSpreeGageServicesShopPage:_set_dialogue_line(loc_key, animate)
	if not self._dialogue_text then
		return
	end
	local line = managers.localization:text(loc_key or "")
	if line and string.find(line, "^ERROR", 1) then
		line = ""
	end
	local target = "> " .. line
	-- Skip if the displayed line is already the requested one. Avoids restarting
	-- the typewriter animation when the same line is set twice (e.g. rapid buy
	-- clicks during the pre-roll window leaving the dialogue stuck on "> ").
	if self._dialogue_target == target then
		return
	end
	self._dialogue_target = target
	if not animate then
		self._dialogue_text:set_text(target)
		return
	end
	-- Typewriter reveal. Diesel's panel:animate runs the function as a
	-- coroutine and resumes each frame with dt. Calling :animate again on the
	-- same object cancels the previous one, so reroll/purchase mid-animation
	-- safely takes over.
	self._dialogue_text:stop()
	self._dialogue_text:set_text("")
	self._dialogue_text:animate(function(o)
		-- Pre-roll: empty box for a beat before the typewriter starts. Gives
		-- the menu's open transition time to settle so the line doesn't fight
		-- the panel fade-in.
		local delay = 0.2
		local waited = 0
		while waited < delay do
			waited = waited + (coroutine.yield() or 0)
		end
		local total_chars = #target
		local duration = math.max(0.4, total_chars * 0.025) -- ~25ms/char, min 0.4s
		local elapsed = 0
		while elapsed < duration do
			local dt = coroutine.yield()
			elapsed = elapsed + (dt or 0)
			local n = math.min(total_chars, math.floor(total_chars * elapsed / duration))
			o:set_text(string.sub(target, 1, n))
		end
		o:set_text(target)
	end)
end

function CrimeSpreeGageServicesShopPage:_create_token_counter()
	-- x=0 / right-edge math align with SHOP tab and dialogue strip (all flush
	-- with the tab panel edges = flush with the SHOP button edges).
	local icon_size = 16
	local font_size = 26
	-- PD2 bitmap fonts leave empty cap-padding above the glyph; nudge the text
	-- element down so the digits visually sit centered against the icon.
	local text_y_nudge = 0
	self._token_text = self._panel:text({
		name = "csr_token_counter",
		text = "",
		font = tweak_data.menu.pd2_large_font,
		font_size = font_size,
		color = Color(1, 1, 1),
		align = "left",
		x = icon_size + 6,
		y = TOOLBAR_TOP + text_y_nudge,
		w = 400 - (icon_size + 6),
		h = font_size,
	})
	self._token_icon = self._panel:bitmap({
		name = "csr_token_counter_icon",
		texture = "guis/textures/pd2/crime_spree/csr_gage_token",
		x = 0,
		y = TOOLBAR_TOP + math.round((font_size - icon_size) / 2),
		w = icon_size,
		h = icon_size,
		layer = 1,
	})
end

function CrimeSpreeGageServicesShopPage:_create_reroll_button()
	-- Mirrors the token wallet at the left of the toolbar: same pd2_large_font,
	-- same icon size, same heights — just sits flush against the right edge of
	-- the tab panel instead of the left. Layout reads "REROLL [icon] N".
	local font_size = 26
	local icon_size = 16
	local icon_gap = 6
	local cost_gap = 6
	local btn_h = font_size + 4
	-- Reserve enough horizontal space for a 3-digit cost; trailing pixels are
	-- harmless because the click target is the panel and the panel is right-flush.
	local cost_area_w = 48

	local label_text = utf8.to_upper(managers.localization:text("csr_gage_services_reroll"))
	-- pd2_large_font at size 26 averages ~15px per uppercase glyph; used both as
	-- the up-front panel-width estimate and as a fallback if text_rect hasn't
	-- laid out yet on first frame.
	local est_label_w = #label_text * 15
	local btn_w = est_label_w + icon_gap + icon_size + cost_gap + cost_area_w

	self._reroll_panel = self._panel:panel({
		name = "csr_reroll_btn",
		w = btn_w,
		h = btn_h,
		x = self._panel:w() - btn_w,
		y = TOOLBAR_TOP,
	})

	self._reroll_text = self._reroll_panel:text({
		name = "csr_reroll_text",
		text = label_text,
		font = tweak_data.menu.pd2_large_font,
		font_size = font_size,
		color = tweak_data.screen_colors.button_stage_3,
		align = "left",
		x = 0,
		y = math.round((btn_h - font_size) / 2),
		w = btn_w,
		h = font_size,
		layer = 2,
	})
	local _, _, label_w = self._reroll_text:text_rect()
	if not label_w or label_w <= 0 then
		label_w = est_label_w
	end
	self._reroll_text:set_w(label_w)

	self._reroll_icon = self._reroll_panel:bitmap({
		name = "csr_reroll_icon",
		texture = "guis/textures/pd2/crime_spree/csr_gage_token",
		x = label_w + icon_gap,
		y = math.round((btn_h - icon_size) / 2),
		w = icon_size,
		h = icon_size,
		layer = 2,
	})

	local cost_x = label_w + icon_gap + icon_size + cost_gap
	self._reroll_cost_text = self._reroll_panel:text({
		name = "csr_reroll_cost",
		text = "",
		font = tweak_data.menu.pd2_large_font,
		font_size = font_size,
		color = Color(1, 1, 1),
		align = "left",
		x = cost_x,
		y = math.round((btn_h - font_size) / 2),
		w = btn_w - cost_x,
		h = font_size,
		layer = 2,
	})

	-- Stash so refresh() can shrink-wrap the panel to fit the actual cost-glyph
	-- width: the panel anchors to the right edge of the tab content, so any
	-- trailing empty pixels on its right side push the visible content inward.
	self._reroll_cost_x = cost_x
	self._reroll_cost_font_size = font_size
end

function CrimeSpreeGageServicesShopPage:_create_cards()
	local total_w = CARD_W * 3 + CARD_GAP * 2
	local start_x = math.floor((self._panel:w() - total_w) / 2)

	for i = 1, 3 do
		local card_panel = self._panel:panel({
			name = "csr_card_" .. i,
			w = CARD_W,
			h = CARD_H,
			x = start_x + (i - 1) * (CARD_W + CARD_GAP),
			y = CARD_TOP,
		})
		self._cards[i] = {
			panel = card_panel,
			populated = false,
			frame = nil,
			icon = nil,
			name_text = nil,
			rarity_text = nil,
			effect_text = nil,
			price_text = nil,
			buy_panel = nil,
			owned_text = nil,
			sold_overlay = nil,
		}
	end
end

-- Build the static visual structure of a card for a given registry entry.
-- Only called once per card slot (when first populated). Subsequent refreshes
-- update only the dynamic elements (sold overlay, price color, owned badge).
function CrimeSpreeGageServicesShopPage:_build_card_visuals(card, entry)
	local panel = card.panel
	local rcolor = RARITY_COLORS[entry.rarity] or Color(1, 1, 1)
	local frame_key = FRAME_KEYS[entry.rarity] or "csr_frame"

	-- Dark card background
	panel:rect({
		name = "card_bg",
		x = 0,
		y = 0,
		w = panel:w(),
		h = panel:h(),
		color = Color(0, 0, 0),
		alpha = 0.55,
		layer = -1,
	})

	-- Frame + icon. csr_frame.dds is a hexagonal outline; icon nests inside its
	-- transparent center. Same single-texture pattern as logbook_menu.lua and
	-- items_page.lua (color is what changes per rarity, not the texture).
	local icon_size = 80
	local frame_size = 170
	local frame_center_x = panel:w() / 2
	local frame_center_y = 95

	-- 1. Rarity-colored frame, sized around the icon (NOT stretched to card).
	if tweak_data.hud_icons and tweak_data.hud_icons[frame_key] then
		local fd = tweak_data.hud_icons[frame_key]
		card.frame = panel:bitmap({
			name = "frame",
			texture = fd.texture,
			texture_rect = fd.texture_rect,
			w = frame_size,
			h = frame_size,
			color = rcolor,
			layer = 0,
		})
		card.frame:set_center(frame_center_x, frame_center_y)
	end

	-- 2. Icon, centered in frame
	if tweak_data.hud_icons and tweak_data.hud_icons[entry.icon] then
		local id = tweak_data.hud_icons[entry.icon]
		card.icon = panel:bitmap({
			name = "icon",
			texture = id.texture,
			texture_rect = id.texture_rect,
			w = icon_size,
			h = icon_size,
			color = Color(1, 1, 1),
			layer = 2,
		})
		card.icon:set_center(frame_center_x, frame_center_y)
	end

	-- localization.lua builds each item key as "NAME\ndescription" (line 239).
	-- Split off the name portion; use the rest as the short selection-popup desc.
	local localized = managers.localization:text(entry.loc_key or "")
	local newline_pos = string.find(localized, "\n", 1, true)
	local item_name = newline_pos and string.sub(localized, 1, newline_pos - 1) or localized
	local desc_text = newline_pos and string.sub(localized, newline_pos + 1) or ""

	-- 3. Item name (just below the frame)
	card.name_text = panel:text({
		name = "name",
		text = string.upper(item_name),
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = rcolor,
		align = "center",
		x = 0,
		y = 188,
		w = panel:w(),
		h = 26,
		layer = 2,
	})

	-- 4. Description (selection-popup text — short flavor desc, white)
	card.effect_text = panel:text({
		name = "effect",
		text = desc_text,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = Color(1, 1, 1),
		align = "center",
		wrap = true,
		word_wrap = true,
		x = 12,
		y = 220,
		w = panel:w() - 24,
		h = 80,
		layer = 2,
	})

	-- 6. Owned-stack badge (hidden by default; refresh() shows when owned > 0)
	card.owned_text = panel:text({
		name = "owned",
		text = "",
		font = tweak_data.menu.pd2_small_font,
		font_size = 20,
		color = Color(1, 0.7, 0.2),
		align = "center",
		x = 0,
		y = 302,
		w = panel:w(),
		h = 18,
		visible = false,
		layer = 2,
	})

	-- 7. Price icon + text (left-aligned, bottom)
	local price = CSR_TokensManager.price_for_rarity(entry.rarity)
	local price_font_size = 24
	local price_icon_size = 16
	card.price_icon = panel:bitmap({
		name = "price_icon",
		texture = "guis/textures/pd2/crime_spree/csr_gage_token",
		x = 16,
		y = panel:h() - 38,
		w = price_icon_size,
		h = price_icon_size,
		layer = 2,
	})
	card.price_text = panel:text({
		name = "price",
		text = tostring(price),
		font = tweak_data.menu.pd2_medium_font,
		font_size = price_font_size,
		color = Color(1, 1, 1),
		align = "left",
		x = 16 + price_icon_size + 4,
		y = panel:h() - 40,
		w = 80,
		h = price_font_size,
		layer = 2,
	})

	-- 8. Buy button (right-aligned, bottom) — vanilla PD2 menu button styling:
	-- bare text in `button_stage_3` blue, brightens to `button_stage_2` cyan on
	-- hover, with an underline that appears on hover.
	card.buy_panel = panel:panel({
		name = "buy_btn",
		x = panel:w() - 96,
		y = panel:h() - 42,
		w = 80,
		h = 30,
	})
	card.buy_text = card.buy_panel:text({
		name = "buy_text",
		text = utf8.to_upper(managers.localization:text("csr_gage_services_buy")),
		font = tweak_data.menu.pd2_medium_font,
		font_size = 24,
		color = tweak_data.screen_colors.button_stage_3,
		align = "center",
		vertical = "center",
		x = 0,
		y = 0,
		w = card.buy_panel:w(),
		h = card.buy_panel:h(),
		layer = 2,
	})
	-- Hover underline — drawn from the rendered glyph rect so it sits flush
	-- under the text and tracks any future text changes.
	local btx, bty, btw, bth = card.buy_text:text_rect()
	card.buy_underline = card.buy_panel:rect({
		name = "buy_underline",
		x = btx,
		y = bty + bth,
		w = btw,
		h = 2,
		color = tweak_data.screen_colors.button_stage_2,
		visible = false,
		layer = 2,
	})

	-- 9. SOLD overlay (hidden by default; covers entire card)
	card.sold_overlay = panel:panel({
		name = "sold_overlay",
		w = panel:w(),
		h = panel:h(),
		x = 0,
		y = 0,
		visible = false,
		layer = 10,
	})
	card.sold_overlay:rect({
		color = Color(0, 0, 0),
		alpha = 0.65,
		layer = 0,
	})
	card.sold_overlay:text({
		name = "sold_text",
		text = managers.localization:text("csr_gage_services_sold"),
		font = tweak_data.menu.pd2_large_font,
		font_size = 32,
		color = Color(1, 0.3, 0.3),
		align = "center",
		vertical = "center",
		x = 0,
		y = 0,
		w = panel:w(),
		h = panel:h(),
		layer = 1,
	})
end

-- Count how many stacks of a given item type the local player owns.
-- Items are stored as { id = "player_health_boost_1", level = N }; match via id_prefix.
function CrimeSpreeGageServicesShopPage:_get_owned_stack_count(item_type)
	local peer_id = CSR_TokensManager.local_peer_id()
	local pdata = _G.CSR_PlayerItems and _G.CSR_PlayerItems[peer_id]
	if not pdata or not pdata.items then
		return 0
	end

	-- Look up the id_prefix for this type from the registry
	local entry = _G.CSR_ITEM_BY_TYPE and _G.CSR_ITEM_BY_TYPE[item_type]
	if not entry or not entry.id_prefix then
		return 0
	end

	local id_prefix = entry.id_prefix
	local count = 0
	for _, item in ipairs(pdata.items) do
		if item.id and string.find(item.id, id_prefix, 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Refresh all dynamic UI elements to match current state.
-- Safe to call multiple times in a row (idempotent).
function CrimeSpreeGageServicesShopPage:refresh()
	-- Bail if the page has been destroyed -- the menu component's close path
	-- removes the panel but external callers (debug button, sync) might still
	-- hold a stale instance pointer. Calling :set_text on a dead Diesel object
	-- triggers a C++ access violation.
	if not self._panel or not alive(self._panel) then
		return
	end

	local peer_id = CSR_TokensManager.local_peer_id()

	-- Token counter
	local wallet = CSR_TokensManager.get_wallet(peer_id)
	if self._token_text then
		self._token_text:set_text(tostring(wallet))
	end

	-- Reroll button cost + affordability tint. Label color is hover-driven in
	-- mouse_moved (button_stage_3 default / button_stage_2 hover); only the
	-- cost number dims red when the player can't afford. Token icon stays
	-- white always — it's an iconographic anchor, not part of the warning.
	local reroll_cost = CSR_ShopManager.reroll_cost(peer_id)
	local can_afford_reroll = wallet >= reroll_cost
	if self._reroll_cost_text then
		local cost_str = tostring(reroll_cost)
		self._reroll_cost_text:set_text(cost_str)
		self._reroll_cost_text:set_color(can_afford_reroll and Color(1, 1, 1) or Color(1, 0.5, 0.5))
		-- Shrink-wrap: resize the cost text element + reroll panel so the
		-- right-flush content actually ends at self._panel:w(). Without this,
		-- a 1-digit cost leaves ~33px of dead pixels between digit and panel
		-- edge — the panel is right-flush, but the visible content isn't.
		local _, _, cw = self._reroll_cost_text:text_rect()
		if not cw or cw <= 0 then
			cw = #cost_str * (self._reroll_cost_font_size or 26) * 0.6
		end
		self._reroll_cost_text:set_w(cw)
		if self._reroll_panel and self._reroll_cost_x then
			local new_btn_w = self._reroll_cost_x + cw
			self._reroll_panel:set_w(new_btn_w)
			self._reroll_panel:set_x(self._panel:w() - new_btn_w)
		end
	end

	-- Cards
	local lineup = CSR_ShopManager.get_lineup(peer_id) or {}
	for i = 1, 3 do
		self:_refresh_card(i, lineup[i], wallet)
	end
end

-- Update one card slot. Builds visuals on first call, then only updates dynamic parts.
function CrimeSpreeGageServicesShopPage:_refresh_card(slot_index, slot, wallet)
	local card = self._cards[slot_index]
	if not card then
		return
	end

	if not slot then
		card.panel:set_visible(false)
		return
	end
	card.panel:set_visible(true)

	-- Resolve registry entry for this slot's item type
	local entry = _G.CSR_ITEM_BY_TYPE and _G.CSR_ITEM_BY_TYPE[slot.type]
	if not entry then
		card.panel:set_visible(false)
		return
	end

	-- Build visuals the first time (or if the slot type changed after a reroll)
	if not card.populated or card.populated_type ~= slot.type then
		-- Clear old visuals when this slot holds a different item after reroll
		if card.populated then
			card.panel:clear()
			-- Reset card sub-element references
			card.frame = nil
			card.icon = nil
			card.name_text = nil
			card.rarity_text = nil
			card.effect_text = nil
			card.price_text = nil
			card.price_icon = nil
			card.buy_panel = nil
			card.buy_text = nil
			card.buy_underline = nil
			card.owned_text = nil
			card.sold_overlay = nil
		end
		self:_build_card_visuals(card, entry)
		card.populated = true
		card.populated_type = slot.type
	end

	-- Sold state: show overlay, hide buy button
	if card.sold_overlay then
		card.sold_overlay:set_visible(slot.sold == true)
	end
	if card.buy_panel then
		card.buy_panel:set_visible(not slot.sold)
	end

	-- Buy button affordability color
	if card.price_text then
		local price = CSR_TokensManager.price_for_rarity(entry.rarity)
		local can_buy = not slot.sold and wallet >= price
		card.price_text:set_color(can_buy and Color(1, 1, 1) or Color(1, 0.5, 0.5))
	end

	-- Owned-stack badge
	if card.owned_text then
		local owned = self:_get_owned_stack_count(slot.type)
		if owned > 0 then
			card.owned_text:set_text(
				managers.localization:text("csr_gage_services_owned_x", { count = tostring(owned) })
			)
			card.owned_text:set_visible(true)
		else
			card.owned_text:set_visible(false)
		end
	end
end

-- === Mouse handling ===

function CrimeSpreeGageServicesShopPage:mouse_pressed(button, x, y)
	if button ~= Idstring("0") then
		return false
	end

	-- Reroll button
	if self._reroll_panel and self._reroll_panel:inside(x, y) then
		self:_on_reroll()
		return true
	end

	-- Buy buttons on cards
	for i = 1, 3 do
		local card = self._cards[i]
		if
			card
			and card.buy_panel
			and card.panel:visible()
			and card.buy_panel:visible()
			and card.buy_panel:inside(x, y)
		then
			self:_on_buy(i)
			return true
		end
	end

	return false
end

function CrimeSpreeGageServicesShopPage:mouse_moved(o, x, y)
	local hovered = nil

	if self._reroll_panel and self._reroll_panel:inside(x, y) then
		hovered = "reroll"
	end

	if not hovered then
		for i = 1, 3 do
			local card = self._cards[i]
			if
				card
				and card.buy_panel
				and card.panel:visible()
				and card.buy_panel:visible()
				and card.buy_panel:inside(x, y)
			then
				hovered = "buy_" .. i
				break
			end
		end
	end

	if hovered ~= self._last_hovered then
		if hovered and managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("highlight")
		end
		-- Repaint buy buttons: hovered card → bright cyan + underline; rest → default blue.
		for i = 1, 3 do
			local card = self._cards[i]
			if card and card.buy_text and card.buy_underline then
				local is_hot = hovered == "buy_" .. i
				card.buy_text:set_color(
					is_hot and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3
				)
				card.buy_underline:set_visible(is_hot)
			end
		end
		-- Reroll label color follows the same hover stages as buy buttons, but
		-- without the underline (just the cyan brighten-on-hover).
		if self._reroll_text then
			local is_hot = hovered == "reroll"
			self._reroll_text:set_color(
				is_hot and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3
			)
		end
		self._last_hovered = hovered
	end

	return false, hovered and "link" or "arrow"
end

-- === Action handlers ===

-- Flash the token counter and icon red then fade to white to signal a denied purchase.
function CrimeSpreeGageServicesShopPage:_flash_token_denied()
	if not self._token_text then
		return
	end
	local icon = self._token_icon
	self._token_text:animate(function(o)
		over(0.5, function(p)
			local c = math.lerp(0.3, 1, p)
			local col = Color(1, 1, c, c)
			o:set_color(col)
			if icon then
				icon:set_color(col)
			end
		end)
	end)
end

function CrimeSpreeGageServicesShopPage:_on_reroll()
	if CSR_ShopManager.reroll(CSR_TokensManager.local_peer_id()) then
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("stinger_new_weapon")
		end
		self:_set_dialogue_line(CSR_ShopManager.pick_reroll_line(), true)
		self:refresh()
	else
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("menu_error")
		end
		self:_flash_token_denied()
	end
end

function CrimeSpreeGageServicesShopPage:_on_buy(slot_index)
	if CSR_ShopManager.purchase(CSR_TokensManager.local_peer_id(), slot_index) then
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("item_sell")
		end
		self:_set_dialogue_line(CSR_ShopManager.pick_purchase_line(), true)
		self:refresh()
	else
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("menu_error")
		end
		self:_flash_token_denied()
	end
end
