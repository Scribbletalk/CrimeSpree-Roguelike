-- Crime Spree Roguelike - Random Heist button
-- Adds a "RANDOM HEIST" button to the mission selection screen. Picks
-- one of the currently displayed heists via an animated roulette that
-- cycles the highlight left-to-right, decelerates, and commits the
-- choice through vanilla :_select_mission (which broadcasts to peers).

if not RequiredScript then
	return
end

if not CrimeSpreeMissionsMenuComponent then
	return
end

local ROLL_DURATION = 1.0
local BASE_FULL_PASSES = 2
local BTN_LABEL = "RANDOM HEIST"

local function _alive(o)
	return o and alive(o)
end

Hooks:PostHook(CrimeSpreeMissionsMenuComponent, "_setup", "CSR_random_heist_setup", function(self)
	if not _alive(self._panel) then
		return
	end
	if not self._buttons or #self._buttons == 0 then
		return
	end
	if not self:_is_host() then
		return
	end
	if not _alive(self._title_panel) then
		return
	end

	local font = tweak_data.menu.pd2_medium_font
	local font_size = tweak_data.menu.pd2_medium_font_size
	local title = self._title_panel
	local cards = self._buttons_panel

	local btn_h = font_size + 4

	-- Share the vanilla title's row: the title text is left-aligned within that
	-- row, leaving the centre empty for our button. Title stays untouched.
	local btn_panel = self._panel:panel({
		layer = 55,
		h = btn_h,
		w = cards:w(),
	})
	btn_panel:set_center_x(cards:center_x())
	btn_panel:set_bottom(title:bottom())

	local btn_text = btn_panel:text({
		text = BTN_LABEL,
		align = "center",
		halign = "center",
		vertical = "center",
		valign = "center",
		font = font,
		font_size = font_size,
		color = tweak_data.screen_colors.button_stage_3,
		layer = 56,
	})

	self._csr_random_btn_panel = btn_panel
	self._csr_random_btn_text = btn_text
	self._csr_is_rolling = false

	if managers.crime_spree and managers.crime_spree.server_has_failed and managers.crime_spree:server_has_failed() then
		btn_panel:set_visible(false)
	end
end)

local function _btn_inside(self, x, y)
	local p = self._csr_random_btn_panel
	return _alive(p) and p:visible() and p:inside(x, y)
end

local function _set_btn_hover(self, hover)
	local t = self._csr_random_btn_text
	if _alive(t) then
		t:set_color(hover and tweak_data.screen_colors.button_stage_2 or tweak_data.screen_colors.button_stage_3)
	end
end

Hooks:PostHook(CrimeSpreeMissionsMenuComponent, "refresh", "CSR_random_heist_refresh", function(self)
	local p = self._csr_random_btn_panel
	if not _alive(p) then
		return
	end
	local hide = managers.crime_spree
		and managers.crime_spree.server_has_failed
		and managers.crime_spree:server_has_failed()
	p:set_visible(not hide)
end)

local original_mouse_moved = CrimeSpreeMissionsMenuComponent.mouse_moved
function CrimeSpreeMissionsMenuComponent:mouse_moved(o, x, y)
	local hover_random = _btn_inside(self, x, y)
	_set_btn_hover(self, hover_random)

	if self._csr_is_rolling then
		return hover_random, hover_random and "link" or nil
	end

	local used, pointer = original_mouse_moved(self, o, x, y)
	if hover_random and not used then
		return true, "link"
	end
	return used, pointer
end

local original_confirm_pressed = CrimeSpreeMissionsMenuComponent.confirm_pressed
function CrimeSpreeMissionsMenuComponent:confirm_pressed()
	if self._csr_is_rolling then
		return nil
	end
	return original_confirm_pressed(self)
end

-- NOTE: MenuComponentManager dispatches mouse_pressed with (button, x, y) only —
-- no leading `o` parameter (see menucomponentmanager.lua:1693). Vanilla declares
-- (o, button, x, y) but ignores all of them, which hides the mismatch. We must
-- match the dispatch shape to read the real button/x/y.
local original_mouse_pressed = CrimeSpreeMissionsMenuComponent.mouse_pressed
function CrimeSpreeMissionsMenuComponent:mouse_pressed(button, x, y)
	if self._csr_is_rolling then
		return nil
	end

	local is_left = button == Idstring("0")
	if is_left and _btn_inside(self, x, y) and self:_is_host() then
		local failed = managers.crime_spree
			and managers.crime_spree.server_has_failed
			and managers.crime_spree:server_has_failed()
		if failed then
			return nil
		end
		self:csr_start_random_roulette()
		return true
	end

	return original_mouse_pressed(self, button, x, y)
end

function CrimeSpreeMissionsMenuComponent:csr_start_random_roulette()
	if self._csr_is_rolling then
		return
	end
	if not self._buttons or #self._buttons == 0 then
		return
	end
	if not self:_is_host() then
		return
	end
	if not _alive(self._panel) then
		return
	end

	local n = #self._buttons
	local final_idx = math.random(1, n)
	local total_steps = BASE_FULL_PASSES * n + final_idx

	self._csr_is_rolling = true

	-- Clear BOTH selected (hover) and active (chosen) state on every button so
	-- the roulette animation starts from a clean visual. We also nil out
	-- self._selected_button so the eventual _select_mission(final_idx) call
	-- doesn't try to deselect a stale index (vanilla bails early on nil, which
	-- would otherwise leave the prior chosen heist's active border on screen).
	for _, b in ipairs(self._buttons) do
		if b then
			if b.set_selected then
				b:set_selected(false)
			end
			if b.set_active then
				b:set_active(false)
			end
		end
	end
	self._selected_button = nil

	if managers.menu_component then
		managers.menu_component:post_event("menu_enter")
	end

	local comp = self
	self._panel:animate(function(o)
		local last_step = 0
		over(ROLL_DURATION, function(p)
			if not _alive(comp._panel) then
				return
			end
			if not comp._buttons then
				return
			end
			local eased = 1 - math.pow(1 - p, 3)
			local progress = eased * total_steps
			local step = math.min(total_steps, math.floor(progress) + 1)
			if step ~= last_step then
				last_step = step
				local idx = ((step - 1) % n) + 1
				for j, b in ipairs(comp._buttons) do
					if b and b.set_selected then
						b:set_selected(j == idx)
					end
				end
				if managers.menu_component then
					managers.menu_component:post_event("highlight")
				end
			end
		end)

		if not _alive(comp._panel) or not comp._buttons then
			comp._csr_is_rolling = false
			return
		end

		for _, b in ipairs(comp._buttons) do
			if b and b.set_selected then
				b:set_selected(false)
			end
		end
		-- _selected_button was nil'd at roll start so _select_mission doesn't
		-- try to deselect a stale index. Call it now to commit & broadcast.
		comp:_select_mission(final_idx)
		comp._csr_is_rolling = false
	end)
end
