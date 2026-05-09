-- Crime Spree Roguelike - Modifiers tab sub-tabs (Loud / Stealth)
-- Splits the vanilla modifiers list into two toggleable scroll panels

if not RequiredScript then
	return
end

if not CrimeSpreeModifierDetailsPage then
	return
end

-- Stealth modifier prefixes (same as forced_mods_notification.lua)
local STEALTH_PREFIXES = { "csr_less_pagers_", "csr_civilian_alarm_", "csr_less_concealment_" }

local function is_stealth_modifier(mod_id)
	if not mod_id then
		return false
	end
	for _, prefix in ipairs(STEALTH_PREFIXES) do
		if string.find(mod_id, prefix, 1, true) == 1 then
			return true
		end
	end
	return false
end

local padding = 10
-- Matches the sub-tab styling used by Gage's Services (gage_services_page.lua):
-- text-only buttons, rarity-blue underline on active, soft grey idle / warm white hover.
local SUBTAB_FONT = tweak_data.menu.pd2_medium_font
local SUBTAB_FONT_SIZE = tweak_data.menu.pd2_medium_font_size
local SUBTAB_H = SUBTAB_FONT_SIZE + 12
local SUBTAB_H_PAD = 14
local SUBTAB_GAP = 24

-- Build a scroll panel populated with the given modifiers list
local function build_scroll(page, parent, modifiers, is_tab)
	-- Temporarily enable UI filter so server_active_modifiers returns filtered data
	-- (add_modifiers_panel reads modifiers from the parameter, not from the manager)
	local scroll_h = CrimeSpreeModifierDetailsPage.add_modifiers_panel(page, parent, modifiers, is_tab)
	return scroll_h
end

-- Filter modifiers into loud and stealth lists
local function split_modifiers(modifiers)
	local loud = {}
	local stealth = {}
	for _, mod in ipairs(modifiers) do
		if is_stealth_modifier(mod.id) then
			table.insert(stealth, mod)
		else
			table.insert(loud, mod)
		end
	end
	return loud, stealth
end

-- Create a sub-tab button matching the Gage's Services style: text-only,
-- active state shown via rarity-blue underline + warm-white text, idle text
-- greyed. Returns (panel, panel_w) so the caller can lay buttons out with
-- their natural widths (STEALTH is wider than LOUD).
local function create_subtab_button(parent, text_str, x, active)
	local btn_panel = parent:panel({
		x = x,
		y = 0,
		h = SUBTAB_H,
		layer = 7,
	})

	local btn_text = btn_panel:text({
		name = "label",
		text = text_str,
		font = SUBTAB_FONT,
		font_size = SUBTAB_FONT_SIZE,
		color = active and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3,
		layer = 8,
	})
	BlackMarketGui.make_fine_text(nil, btn_text)
	local tw = btn_text:w()
	local th = btn_text:h()
	local panel_w = tw + SUBTAB_H_PAD * 2
	btn_panel:set_w(panel_w)
	btn_text:set_x((panel_w - tw) * 0.5)
	btn_text:set_y((SUBTAB_H - th) * 0.5)

	btn_panel:rect({
		name = "underline",
		h = 2,
		w = panel_w - 6,
		x = 3,
		y = SUBTAB_H - 3,
		color = tweak_data.screen_colors.button_stage_2,
		visible = active and true or false,
		layer = 9,
	})

	return btn_panel, panel_w
end

local function set_button_active(btn_panel, active)
	if not btn_panel or not alive(btn_panel) then
		return
	end
	local label = btn_panel:child("label")
	local underline = btn_panel:child("underline")
	if label then
		label:set_color(active and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3)
	end
	if underline then
		underline:set_visible(active and true or false)
	end
end

local function set_button_hover(btn_panel, hover, is_active)
	if not btn_panel or not alive(btn_panel) then
		return
	end
	-- Active button stays on stage_2; idle button tints stage_2 on hover, stage_3 otherwise.
	local label = btn_panel:child("label")
	if label then
		if is_active or hover then
			label:set_color(tweak_data.screen_colors.button_stage_2)
		else
			label:set_color(tweak_data.screen_colors.button_stage_3)
		end
	end
end

-- Suppress "Crime Spree Suspended" banner for CSR clients with higher rank than host.
-- The vanilla init() checks server_spree_level() < spree_level() to show the banner.
-- We temporarily raise peer_spree_levels[1] to the client's own rank so the check passes.
-- This is safe: peer_spree_levels is set once on join and only changes on host rank-up.
-- Previous approach (overriding server_spree_level method) caused a freeze because
-- update() detected the change every frame and called init() in a tight loop.
-- This PreHook approach is one-shot per init() call — no recursion possible.
Hooks:PreHook(CrimeSpreeModifierDetailsPage, "init", "CSR_SuppressSuspendedBanner", function(self)
	if not CSR_MP or not CSR_MP.is_client or not CSR_MP.is_client() then
		return
	end
	local cs = managers.crime_spree
	if not cs then
		return
	end
	local local_rank = cs:spree_level() or 0
	local server_rank = cs:server_spree_level() or 0
	if local_rank > server_rank and cs._global and cs._global.peer_spree_levels then
		cs._global.peer_spree_levels[1] = local_rank
	end
end)

-- Only apply to the vanilla MODIFIERS page, not our subclasses (ITEMS, STATS, etc.)
-- Check by verifying init hasn't been overridden by a subclass
Hooks:PostHook(CrimeSpreeModifierDetailsPage, "init", "CSR_ModifiersSubtabs", function(self)
	-- Skip subclasses: their init is different from CrimeSpreeModifierDetailsPage.init
	if self.init ~= CrimeSpreeModifierDetailsPage.init then
		return
	end

	-- Skip if no scroll was created (e.g. CS not active)
	if not self._scroll then
		return
	end
	if not alive(self:panel()) then
		return
	end

	-- Get all modifiers (with UI filter enabled)
	CSR_FilterForUI = true
	local all_modifiers = managers.crime_spree:server_active_modifiers() or {}
	CSR_FilterForUI = false

	local loud_mods, stealth_mods = split_modifiers(all_modifiers)

	-- Find the modifiers_panel (parent of the scroll's outer panel)
	local modifiers_panel = self._scroll:panel():parent()
	if not modifiers_panel or not alive(modifiers_panel) then
		return
	end

	-- Destroy the vanilla scroll — we'll create two new ones
	modifiers_panel:clear()
	self._scroll = nil

	-- Create sub-tab buttons panel at the top of modifiers_panel
	local tabs_panel = modifiers_panel:panel({
		x = 0,
		y = 0,
		w = modifiers_panel:w(),
		h = SUBTAB_H,
		layer = 10,
	})

	-- Divider line flush with the bottom of the subtab row (same as Gage's Services)
	tabs_panel:rect({
		name = "divider",
		h = 1,
		w = tabs_panel:w(),
		y = SUBTAB_H - 1,
		color = Color(1, 0.25, 0.25, 0.25),
		layer = 6,
	})

	-- Buttons are sized to their natural text width, so lay them out sequentially.
	local loud_btn, loud_w = create_subtab_button(tabs_panel, "LOUD", padding, true)
	local stealth_btn = create_subtab_button(tabs_panel, "STEALTH", padding + loud_w + SUBTAB_GAP, false)

	-- Create two scroll containers below the sub-tabs
	local scroll_y = SUBTAB_H + SUBTAB_GAP
	local scroll_h = modifiers_panel:h() - scroll_y

	local loud_container = modifiers_panel:panel({
		x = 0,
		y = scroll_y,
		w = modifiers_panel:w(),
		h = scroll_h,
	})

	local stealth_container = modifiers_panel:panel({
		x = 0,
		y = scroll_y,
		w = modifiers_panel:w(),
		h = scroll_h,
	})

	-- Build scroll panels with filtered modifiers
	build_scroll(self, loud_container, loud_mods, true)
	local loud_scroll = self._scroll

	build_scroll(self, stealth_container, stealth_mods, true)
	local stealth_scroll = self._scroll

	-- Default: LOUD active
	stealth_container:set_visible(false)
	self._scroll = loud_scroll

	-- Store state on the page instance
	self._csr_subtab = "loud"
	self._csr_loud_scroll = loud_scroll
	self._csr_stealth_scroll = stealth_scroll
	self._csr_loud_container = loud_container
	self._csr_stealth_container = stealth_container
	self._csr_loud_btn = loud_btn
	self._csr_stealth_btn = stealth_btn
end)

-- Switch sub-tab
local function switch_subtab(self, tab_name)
	if self._csr_subtab == tab_name then
		return
	end
	self._csr_subtab = tab_name

	local is_loud = tab_name == "loud"

	if self._csr_loud_container and alive(self._csr_loud_container) then
		self._csr_loud_container:set_visible(is_loud)
	end
	if self._csr_stealth_container and alive(self._csr_stealth_container) then
		self._csr_stealth_container:set_visible(not is_loud)
	end

	self._scroll = is_loud and self._csr_loud_scroll or self._csr_stealth_scroll

	set_button_active(self._csr_loud_btn, is_loud)
	set_button_active(self._csr_stealth_btn, not is_loud)
end

-- Diesel `set_visible(false)` only hides pixels — `:inside(x, y)` still returns
-- true on hidden panels (see diesel_visibility_vs_hittest.md), and the menu
-- system dispatches mouse_clicked / mouse_moved to inactive pages too. Without
-- this gate, clicking where LOUD/STEALTH would be is honored from any tab.
local function modifiers_page_visible(self)
	local panel = self:panel()
	return panel and alive(panel) and panel:visible()
end

-- Handle clicks on sub-tab buttons
Hooks:PostHook(CrimeSpreeModifierDetailsPage, "mouse_clicked", "CSR_SubtabClick", function(self, o, button, x, y)
	if button ~= Idstring("0") then
		return
	end
	if not self._csr_loud_btn then
		return
	end
	if not modifiers_page_visible(self) then
		return
	end

	if alive(self._csr_loud_btn) and self._csr_loud_btn:inside(x, y) then
		switch_subtab(self, "loud")
		return
	end
	if alive(self._csr_stealth_btn) and self._csr_stealth_btn:inside(x, y) then
		switch_subtab(self, "stealth")
		return
	end
end)

-- Handle hover on sub-tab buttons: retint the label to warm-white on hover
-- (matches Gage's Services style) and request the pointer cursor.
Hooks:PostHook(CrimeSpreeModifierDetailsPage, "mouse_moved", "CSR_SubtabHover", function(self, o, x, y)
	if not self._csr_loud_btn then
		return
	end
	if not modifiers_page_visible(self) then
		return
	end

	local loud_inside = alive(self._csr_loud_btn) and self._csr_loud_btn:inside(x, y)
	local stealth_inside = alive(self._csr_stealth_btn) and self._csr_stealth_btn:inside(x, y)

	local is_loud_active = self._csr_subtab == "loud"
	set_button_hover(self._csr_loud_btn, loud_inside, is_loud_active)
	set_button_hover(self._csr_stealth_btn, stealth_inside, not is_loud_active)

	if loud_inside or stealth_inside then
		return true, "link"
	end
end)
