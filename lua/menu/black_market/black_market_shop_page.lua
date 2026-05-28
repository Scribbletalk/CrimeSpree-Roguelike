-- Crime Spree Roguelike - Gage's Services Shop Page.
-- Renders the Gage dialogue strip, token counter, reroll button and 3 item
-- cards for the Shop tab. U1 port of the pre-refactor shop page: backend swapped
-- from CSR_ShopManager/CSR_TokensManager/CSR_PlayerItems/CSR_ITEM_BY_TYPE to
-- CSR_Shop (lua/managers/shop.lua) + managers.csr. Item name/desc now come from
-- the registry def's separate name/desc loc keys (the old single loc_key
-- "NAME\ndesc" model is gone). Rarity-frame colours use proper 4-arg Color()
-- (the pre-refactor 3-arg values were alpha,red,green — blue missing).

if not RequiredScript then
	return
end

CrimeSpreeBlackMarketShopPage = CrimeSpreeBlackMarketShopPage or class()

local CARD_W = 210
local CARD_H = 360
local CARD_GAP = 20
-- Vertical layout: dialogue (0..70) -> toolbar (80..116) -> cards (120..480).
local CARD_TOP = 120
local DIALOGUE_TOP = 0
local DIALOGUE_HEIGHT = 70
local DIALOGUE_X = 0
local TOOLBAR_TOP = 80

-- 4-arg rarity colours, matching item_selection.lua.
-- Contraband (orange) is included: slot 4 is always a contraband card.
local RARITY_COLORS = {
	common = Color.white,
	uncommon = Color(1, 0, 0.95, 0),
	rare = Color(1, 0.3, 0.7, 1),
	contraband = Color(1, 1, 0.4, 0),
}

-- Single frame texture, tinted per rarity at draw time (same as the logbook /
-- items page / selection window).
local FRAME_KEY = "csr_frame"

-- Resolve an item icon: a "/" means a full DB-mounted path (addon .dds); else a
-- short hud_icons id. Mirrors item_selection.lua's resolution.
local function resolve_icon(icon)
	if type(icon) == "string" and icon:find("/", 1, true) then
		return icon, { 0, 0, 128, 128 }
	end
	return tweak_data.hud_icons:get_icon_data(icon)
end

-- Resolve a loc KEY to text, blanking the engine's "ERROR <key>" placeholder.
local function loc_or_blank(key)
	if not key or not managers.localization then
		return ""
	end
	local s = managers.localization:text(key)
	if s and string.find(s, "^ERROR", 1) then
		return ""
	end
	return s
end

function CrimeSpreeBlackMarketShopPage:init(panel, parent)
	self._panel = panel
	self._parent = parent
	self._cards = {}
	self:_setup()
	-- Expose the live instance so external callers can :refresh() while open.
	_G.CSR_BlackMarketShopPageInstance = self
end

function CrimeSpreeBlackMarketShopPage:_setup()
	-- Restock a fully sold-out lineup on open so the shop never reopens as a dead
	-- end (e.g. the player bought the last card then closed before the deferred
	-- free restock fired). roll_lineup is free (no debit).
	if CSR_Shop.lineup_sold_out and CSR_Shop.lineup_sold_out() then
		CSR_Shop.roll_lineup()
	end
	self:_create_token_counter()
	self:_create_reroll_button()
	self:_create_dialogue_strip()
	self:_create_cards()
	self:_create_owned_strip()
	-- Animate the persisted greeting line typewriter-style on open.
	self:_set_dialogue_line(CSR_Shop.get_or_pick_greeting(), true)
	self:refresh()
end

-- Read-only owned-items strip ABOVE the Black Market box (user request), sized to
-- roughly the item-selection popup width (NOT the full shop width) so it reads as a
-- compact inventory band. Rebuilt by refresh() so a purchase shows up immediately.
--
-- Hosted on the component's OUTER panel (comp._panel), NOT the shop tab panel: the
-- tab panel is nested under the content box's opaque (alpha 0.92) background, where
-- the strip's content layers do not composite through -- hence "tooltip shows but
-- icons don't". The outer panel is top-level (like the selection window's ws panel),
-- so the strip draws cleanly; the component's close() removes the outer panel, which
-- cascades the strip + tooltip away -- no explicit destroy needed.
function CrimeSpreeBlackMarketShopPage:_create_owned_strip()
	if not CSROwnedItemsStrip then
		return
	end
	local comp = self._parent
	local outer = comp and comp._panel
	local box = comp and comp._content_panel
	if not (outer and alive(outer) and box and alive(box)) then
		return
	end
	-- ~3 selection cards wide ((208 + 10) * 3 + 10 = 664).
	local strip_w = 664
	-- Explicit compact height cap: there is plenty of room here, so a box-relative
	-- bound never shrank the strip -- this fixed cap makes the widget shrink its cell
	-- to a compact band. Lower it to shrink further, raise it to grow.
	local COMPACT_STRIP_H = 48
	self._owned_strip = CSROwnedItemsStrip:new({
		parent = outer,
		tooltip_parent = outer,
		width = strip_w,
		-- Header / back button sit at layer 60 on the outer panel; match it so the
		-- strip draws above the content box (layer 10) wherever they meet.
		layer = 60,
		max_height = COMPACT_STRIP_H,
		-- Items hug the left inset (no centring) so the row flows rightward from just
		-- past the header, continuing the header's line.
		align = "left",
		anchor = function(panel)
			panel:set_center_x(box:center_x())
			-- Sit on the "BLACK MARKET" header's line (top-left): centre vertically on
			-- the header, clamped so a strip taller than the header band is not pushed
			-- off the panel top.
			local hdr = comp and comp._header
			local cy = (hdr and alive(hdr) and hdr:center_y()) or 20
			panel:set_center_y(cy)
			if panel:top() < 2 then
				panel:set_top(2)
			end
		end,
	})
end

function CrimeSpreeBlackMarketShopPage:_create_dialogue_strip()
	local strip_w = self._panel:w()
	self._dialogue_panel = self._panel:panel({
		name = "csr_gage_dialogue",
		w = strip_w,
		h = DIALOGUE_HEIGHT,
		x = DIALOGUE_X,
		y = DIALOGUE_TOP,
	})
	self._dialogue_panel:rect({
		color = Color.black,
		alpha = 0.5,
		layer = 0,
	})
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
		color = Color(1, 0.9, 0.9, 0.9),
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

-- Set the dialogue line (a loc key). Displayed with a "> " chevron (PD2 bitmap
-- fonts have no runtime italic). animate=true runs a typewriter reveal.
function CrimeSpreeBlackMarketShopPage:_set_dialogue_line(loc_key, animate)
	if not self._dialogue_text then
		return
	end
	local target = "> " .. loc_or_blank(loc_key)
	-- Skip if already showing this line (avoids restarting the typewriter on
	-- repeated sets, e.g. rapid buy clicks).
	if self._dialogue_target == target then
		return
	end
	self._dialogue_target = target
	if not animate then
		self._dialogue_text:set_text(target)
		return
	end
	-- panel:animate runs the function as a coroutine, resumed each frame with dt.
	-- A new :animate cancels the previous, so reroll/buy mid-animation is safe.
	self._dialogue_text:stop()
	self._dialogue_text:set_text("")
	self._dialogue_text:animate(function(o)
		local delay = 0.2
		local waited = 0
		while waited < delay do
			waited = waited + (coroutine.yield() or 0)
		end
		local total_chars = #target
		local duration = math.max(0.4, total_chars * 0.025)
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

function CrimeSpreeBlackMarketShopPage:_create_token_counter()
	local icon_size = 16
	local font_size = 26
	self._token_text = self._panel:text({
		name = "csr_token_counter",
		text = "",
		font = tweak_data.menu.pd2_large_font,
		font_size = font_size,
		color = Color.white,
		align = "left",
		x = icon_size + 6,
		y = TOOLBAR_TOP,
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

function CrimeSpreeBlackMarketShopPage:_create_reroll_button()
	-- Right-flush "REROLL [icon] N" mirroring the token wallet at the left.
	local font_size = 26
	local icon_size = 16
	local icon_gap = 6
	local cost_gap = 6
	local btn_h = font_size + 4
	local cost_area_w = 48

	local label_text = utf8.to_upper(managers.localization:text("csr_black_market_reroll"))
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
		color = Color.white,
		align = "left",
		x = cost_x,
		y = math.round((btn_h - font_size) / 2),
		w = btn_w - cost_x,
		h = font_size,
		layer = 2,
	})

	self._reroll_cost_x = cost_x
	self._reroll_cost_font_size = font_size
end

function CrimeSpreeBlackMarketShopPage:_create_cards()
	local total_w = CARD_W * 4 + CARD_GAP * 3
	local start_x = math.floor((self._panel:w() - total_w) / 2)

	for i = 1, 4 do
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
		}
	end
end

-- Build the static visual structure of a card. Called once per slot (and again
-- if the slot's item type changes after a reroll).
function CrimeSpreeBlackMarketShopPage:_build_card_visuals(card, entry)
	local panel = card.panel
	local rcolor = RARITY_COLORS[entry.rarity] or Color.white

	-- Dark card background.
	panel:rect({
		name = "card_bg",
		x = 0,
		y = 0,
		w = panel:w(),
		h = panel:h(),
		color = Color.black,
		alpha = 0.55,
		layer = -1,
	})

	local icon_size = 80
	local frame_size = 170
	local frame_center_x = panel:w() / 2
	local frame_center_y = 95

	-- Rarity-coloured frame around the icon.
	local ftex, frect = resolve_icon(FRAME_KEY)
	card.frame = panel:bitmap({
		name = "frame",
		texture = ftex,
		texture_rect = frect,
		w = frame_size,
		h = frame_size,
		color = rcolor,
		layer = 0,
	})
	card.frame:set_center(frame_center_x, frame_center_y)

	-- Icon, centred in the frame.
	local itex, irect = resolve_icon(entry.icon)
	card.icon = panel:bitmap({
		name = "icon",
		texture = itex,
		texture_rect = irect,
		w = icon_size,
		h = icon_size,
		color = Color.white,
		layer = 2,
	})
	card.icon:set_center(frame_center_x, frame_center_y)

	-- Name (rarity colour) + short description (white). U1 defs carry separate
	-- name/desc loc keys.
	local item_name = loc_or_blank(entry.name)
	if item_name == "" then
		item_name = string.upper(tostring(entry.type))
	end
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

	local full_desc = loc_or_blank(entry.desc)
	local main_desc, but_desc = string.match(full_desc, "^(.-)\n(But.+)$")
	card.effect_text = panel:text({
		name = "effect",
		text = main_desc or full_desc,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 20,
		color = Color.white,
		align = "center",
		wrap = true,
		word_wrap = true,
		x = 12,
		y = 220,
		w = panel:w() - 24,
		h = 80,
		layer = 2,
	})
	if but_desc then
		local _, _, _, main_h = card.effect_text:text_rect()
		local but_y = 220 + math.max(main_h and main_h > 4 and main_h or 26, 26)
		card.but_text = panel:text({
			name = "but_text",
			text = but_desc,
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(1, 1, 0.3, 0.3),
			align = "center",
			wrap = true,
			word_wrap = true,
			x = 12,
			y = but_y,
			w = panel:w() - 24,
			h = 40,
			layer = 2,
		})
	end

	-- Price icon + number (bottom-left).
	local price = CSR_Shop.price_for_rarity(entry.rarity)
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
		text = (price and price ~= math.huge) and tostring(price) or "?",
		font = tweak_data.menu.pd2_medium_font,
		font_size = price_font_size,
		color = Color.white,
		align = "left",
		x = 16 + price_icon_size + 4,
		y = panel:h() - 40,
		w = 80,
		h = price_font_size,
		layer = 2,
	})

	-- Buy button (bottom-right): bare blue text, brightens + underlines on hover.
	card.buy_panel = panel:panel({
		name = "buy_btn",
		x = panel:w() - 96,
		y = panel:h() - 42,
		w = 80,
		h = 30,
	})
	card.buy_text = card.buy_panel:text({
		name = "buy_text",
		text = utf8.to_upper(managers.localization:text("csr_black_market_buy")),
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

	-- SOLD overlay (hidden until bought).
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
		color = Color.black,
		alpha = 0.65,
		layer = 0,
	})
	card.sold_overlay:text({
		name = "sold_text",
		text = managers.localization:text("csr_black_market_sold"),
		font = tweak_data.menu.pd2_large_font,
		font_size = 32,
		color = Color(1, 1, 0.3, 0.3),
		align = "center",
		vertical = "center",
		x = 0,
		y = 0,
		w = panel:w(),
		h = panel:h(),
		layer = 1,
	})
end

-- Refresh all dynamic UI to current state. Idempotent.
function CrimeSpreeBlackMarketShopPage:refresh()
	-- Bail if the page panel was destroyed (close removes it; a stale instance
	-- pointer calling :set_text on a dead Diesel object = C++ access violation).
	if not self._panel or not alive(self._panel) then
		return
	end

	local peer_id = CSR_Shop.local_peer_id()
	local wallet = CSR_Shop.tokens(peer_id)

	if self._token_text then
		self._token_text:set_text(tostring(wallet))
	end

	-- Reroll cost + affordability tint (cost number dims red when unaffordable;
	-- the label colour is hover-driven in mouse_moved).
	local reroll_cost = CSR_Shop.reroll_cost(peer_id)
	if self._reroll_cost_text then
		local cost_str = tostring(reroll_cost)
		self._reroll_cost_text:set_text(cost_str)
		self._reroll_cost_text:set_color(wallet >= reroll_cost and Color.white or Color(1, 1, 0.5, 0.5))
		-- Shrink-wrap so the right-flush content actually ends at the panel edge.
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

	local lineup = CSR_Shop.get_lineup(peer_id) or {}
	for i = 1, 4 do
		self:_refresh_card(i, lineup[i], wallet)
	end

	-- Reflect the current inventory (a purchase just added an item) in the strip.
	if self._owned_strip then
		self._owned_strip:rebuild()
	end
end

function CrimeSpreeBlackMarketShopPage:_refresh_card(slot_index, slot, wallet)
	local card = self._cards[slot_index]
	if not card then
		return
	end
	if not slot then
		card.panel:set_visible(false)
		return
	end
	card.panel:set_visible(true)

	local entry = CSR_Shop.item_def(slot.type)
	if not entry then
		card.panel:set_visible(false)
		return
	end

	-- Build visuals on first populate (or rebuild if the slot's type changed
	-- after a reroll).
	if not card.populated or card.populated_type ~= slot.type then
		if card.populated then
			card.panel:clear()
			card.frame, card.icon, card.name_text, card.effect_text = nil, nil, nil, nil
			card.but_text = nil
			card.price_text, card.price_icon = nil, nil
			card.buy_panel, card.buy_text, card.buy_underline = nil, nil, nil
			card.sold_overlay = nil
		end
		self:_build_card_visuals(card, entry)
		card.populated = true
		card.populated_type = slot.type
	end

	-- Sold state.
	if card.sold_overlay then
		card.sold_overlay:set_visible(slot.sold == true)
	end
	if card.buy_panel then
		card.buy_panel:set_visible(not slot.sold)
	end

	-- Price affordability tint.
	if card.price_text then
		local price = CSR_Shop.price_for_rarity(entry.rarity)
		local can_buy = not slot.sold and wallet >= price
		card.price_text:set_color(can_buy and Color.white or Color(1, 1, 0.5, 0.5))
	end
end

-- === Mouse handling ===

function CrimeSpreeBlackMarketShopPage:mouse_pressed(button, x, y)
	if button ~= Idstring("0") then
		return false
	end

	if self._reroll_panel and self._reroll_panel:inside(x, y) then
		self:_on_reroll()
		return true
	end

	for i = 1, 4 do
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

function CrimeSpreeBlackMarketShopPage:mouse_moved(o, x, y)
	-- Owned-strip hover tooltip: a side effect (the strip is non-interactive), so the
	-- buy/reroll hover + return value below are untouched.
	if self._owned_strip then
		self._owned_strip:mouse_moved(x, y)
	end

	local hovered = nil

	if self._reroll_panel and self._reroll_panel:inside(x, y) then
		hovered = "reroll"
	end

	if not hovered then
		for i = 1, 4 do
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
		-- Buy buttons: hovered = bright cyan + underline; rest = default blue.
		for i = 1, 4 do
			local card = self._cards[i]
			if card and card.buy_text and card.buy_underline then
				local is_hot = hovered == "buy_" .. i
				card.buy_text:set_color(
					is_hot and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3
				)
				card.buy_underline:set_visible(is_hot)
			end
		end
		-- Reroll label follows the same brighten-on-hover (no underline).
		if self._reroll_text then
			self._reroll_text:set_color(
				hovered == "reroll" and tweak_data.screen_colors.button_stage_2
					or tweak_data.screen_colors.button_stage_3
			)
		end
		self._last_hovered = hovered
	end

	return false, hovered and "link" or "arrow"
end

-- === Action handlers ===

-- Flash the token counter red->white to signal a denied purchase/reroll.
function CrimeSpreeBlackMarketShopPage:_flash_token_denied()
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

function CrimeSpreeBlackMarketShopPage:_on_reroll()
	if CSR_Shop.reroll(CSR_Shop.local_peer_id()) then
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("stinger_new_weapon")
		end
		self:_set_dialogue_line(CSR_Shop.pick_reroll_line(), true)
		self:refresh()
	else
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("menu_error")
		end
		self:_flash_token_denied()
	end
end

function CrimeSpreeBlackMarketShopPage:_on_buy(slot_index)
	local ok, result = CSR_Shop.buy(CSR_Shop.local_peer_id(), slot_index)
	if not ok then
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("menu_error")
		end
		self:_flash_token_denied()
		return
	end

	if managers.menu_component and managers.menu_component.post_event then
		managers.menu_component:post_event("item_sell")
	end

	-- Normal purchase: confirm and refresh in place.
	if result ~= "sold_out" then
		self:_set_dialogue_line(CSR_Shop.pick_purchase_line(), true)
		self:refresh()
		return
	end

	-- Bought the last card: show the sold-out lineup for a 0.5s beat, then the shop
	-- restocks for FREE. The restock runs via DelayedCalls (ticked on MenuUpdate),
	-- so it fires even if the player closes the menu first -- the lineup never stays
	-- stuck sold-out (the page also self-heals on open). roll_lineup carries no debit.
	self:refresh() -- render all three cards as sold for the beat
	local page = self
	local function restock()
		if CSR_Shop.lineup_sold_out() then
			CSR_Shop.roll_lineup() -- free restock; resets reroll cost to base
		end
		if not alive(page._panel) then
			return -- menu closed during the delay; data already restocked above
		end
		if managers.menu_component and managers.menu_component.post_event then
			managers.menu_component:post_event("stinger_new_weapon")
		end
		page._dialogue_target = nil -- force re-animate even if the line repeats
		page:_set_dialogue_line(CSR_Shop.pick_soldout_line(), true)
		page:refresh()
	end
	if DelayedCalls and DelayedCalls.Add then
		DelayedCalls:Add("csr_black_market_restock", 0.5, restock)
	else
		restock() -- no timer available: restock immediately
	end
end
