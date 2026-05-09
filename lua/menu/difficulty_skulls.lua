-- Crime Spree Roguelike - Difficulty skull icons in CS menu
-- Adds "DIFFICULTY" label + skull icons below the "CRIME SPREE: X" title.
-- Applied to both the active CS lobby screen and the lobby creation screen.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

-- How many skulls are lit per difficulty (out of 6 total)
local DIFFICULTY_SKULLS = {
	normal = 0,
	hard = 1,
	very_hard = 2,
	overkill = 3,
	mayhem = 4,
	death_wish = 5,
	death_sentence = 6,
}
local TOTAL_SKULLS = 6

-- Skull icons from hud_difficultymarkers_2 (same as vanilla contract screen)
-- Each skull has a unique icon; skulls 4+ have horns
local SKULL_ICONS = {
	"risk_swat",
	"risk_fbi",
	"risk_death_squad",
	"risk_easy_wish",
	"risk_murder_squad",
	"risk_sm_wish",
}

local function add_difficulty_skulls(self)
	-- CrimeSpreeDetailsMenuComponent uses _title_text
	-- CrimeSpreeContractMenuComponent uses _contact_text_header
	-- On client, _subtitle_text ("MY CRIME SPREE LEVEL X") sits below _title_text
	-- Position skulls below the lowest title element
	local title = self._subtitle_text or self._title_text or self._contact_text_header
	if not title or not alive(title) then
		return
	end

	-- Priority for clients: host's difficulty from handshake is authoritative.
	-- Priority for host: _global.selected_difficulty (set by UI) beats CSR_CurrentDifficulty
	-- (old seed), so the display updates immediately when the user picks a new difficulty.
	local is_client = _G.CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
	local difficulty
	if is_client then
		difficulty = _G.CSR_MP_HostDifficulty
			or _G.CSR_CurrentDifficulty
			or (managers.crime_spree and managers.crime_spree._global and managers.crime_spree._global.selected_difficulty)
			or "overkill"
	else
		difficulty = (
			managers.crime_spree
			and managers.crime_spree._global
			and managers.crime_spree._global.selected_difficulty
		)
			or _G.CSR_CurrentDifficulty
			or "overkill"
	end

	local lit = DIFFICULTY_SKULLS[difficulty] or 3
	local skull_s = 18
	local spacing = skull_s + 2
	local base_x = title:x()
	local base_y = title:bottom() + 4
	CSR_log(
		"[CSR Skulls] difficulty="
			.. tostring(difficulty)
			.. " lit="
			.. tostring(lit)
			.. " base_x="
			.. tostring(base_x)
			.. " base_y="
			.. tostring(base_y)
			.. " panel_w="
			.. tostring(self._panel:w())
			.. " panel_h="
			.. tostring(self._panel:h())
	)

	local label = self._panel:text({
		name = "csr_difficulty_label",
		text = "DIFFICULTY:",
		font = tweak_data.menu.pd2_medium_font,
		font_size = tweak_data.menu.pd2_medium_font_size,
		color = Color(0.82, 0.82, 0.82),
		x = base_x,
		y = base_y,
		layer = 10,
	})
	local _, _, lw, lh = label:text_rect()
	label:set_size(lw, lh)
	label:set_center_y(base_y + skull_s / 2)

	local skulls_x = base_x + lw + 6

	for i = 1, TOTAL_SKULLS do
		local active = i <= lit
		local icon_name = SKULL_ICONS[i]
		local texture, rect = tweak_data.hud_icons:get_icon_data(icon_name)
		self._panel:bitmap({
			name = "csr_difficulty_skull_" .. i,
			texture = texture,
			texture_rect = rect,
			w = skull_s,
			h = skull_s,
			x = skulls_x + (i - 1) * spacing,
			y = base_y,
			alpha = active and 1 or 0.5,
			blend_mode = active and "add" or "normal",
			color = active and tweak_data.screen_colors.risk or Color.black,
			layer = 10,
		})
	end
end

-- Active CS lobby screen (ITEMS/STATS/MODIFIERS tabs)
if CrimeSpreeDetailsMenuComponent then
	Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "_setup", "CSR_AddDifficultySkulls", function(self)
		-- Push tabs panel down to make room for skulls
		-- Client has subtitle ("MY CRIME SPREE") so needs more space
		local is_client = CSR_MP and CSR_MP.is_client and CSR_MP.is_client()
		local shift = is_client and 44 or 22
		if self._tabs_panel and alive(self._tabs_panel) then
			self._tabs_panel:move(0, shift)
		end
		if self._page_panel and alive(self._page_panel) then
			self._page_panel:move(0, shift)
			self._page_panel:set_h(self._page_panel:h() - shift)
		end

		-- On client, delay first skull creation to let MP sync set the correct difficulty
		if CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and not _G.CSR_MP_HostRank then
			DelayedCalls:Add("CSR_SkullsDelayedInit", 0.5, function()
				if self._panel and alive(self._panel) then
					add_difficulty_skulls(self)
				end
			end)
		else
			add_difficulty_skulls(self)
		end
	end)
end

-- Lobby creation screen (contract details + GAME SETTINGS)
-- Only show skulls when continuing an existing Crime Spree, not when starting a new one
if CrimeSpreeContractMenuComponent then
	Hooks:PostHook(CrimeSpreeContractMenuComponent, "_setup", "CSR_AddDifficultySkullsContract", function(self)
		if not managers.crime_spree or not managers.crime_spree:in_progress() then
			return
		end

		local shift = 22
		if self._contract_panel and alive(self._contract_panel) then
			self._contract_panel:move(0, shift)
			self._contract_panel:set_h(self._contract_panel:h() - shift)
		end

		add_difficulty_skulls(self)
	end)
end
