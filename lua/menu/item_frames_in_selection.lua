-- Crime Spree Roguelike - Item rarity frames in the modifier selection popup
-- Adds colored rarity frames behind item icons when choosing between missions.

if not RequiredScript then
	return
end

-- Rarity frame icons and colors (same as items_page.lua)
local RARITY_FRAMES = {
	common     = { frame = "csr_frame_common",     color = Color.white },
	uncommon   = { frame = "csr_frame_uncommon",    color = Color(0, 0.95, 0) },
	rare       = { frame = "csr_frame_rare",        color = Color(0.4, 0.6, 1) },
	contraband = { frame = "csr_frame_contraband",  color = Color(1, 0.4, 0) }
}

-- Modifier ID prefix → rarity
local ITEM_RARITIES = {
	player_health_boost       = "common",
	player_duct_tape          = "common",
	player_escape_plan        = "common",
	player_worn_bandaid       = "common",
	player_piece_of_rebar     = "common",
	player_damage_boost       = "uncommon",
	player_car_keys           = "uncommon",
	player_wolfs_toolbox      = "uncommon",
	player_overkill_rush      = "uncommon",
	player_pink_slip          = "uncommon",
	player_bonnie_chip        = "rare",
	player_plush_shark        = "rare",
	player_jiro_last_wish     = "rare",
	player_dearest_possession = "rare",
	player_viklund_vinyl      = "rare",
	player_dozer_guide        = "contraband",
	player_glass_pistol       = "contraband",
	player_equalizer          = "contraband",
	player_crooked_badge      = "contraband",
	player_dead_mans_trigger  = "contraband"
}

-- Match modifier ID (e.g. "player_health_boost_1") to rarity via prefix
local function get_item_rarity(mod_id)
	if not mod_id then return nil end
	for prefix, rarity in pairs(ITEM_RARITIES) do
		if string.find(mod_id, prefix, 1, true) == 1 then
			return rarity
		end
	end
	return nil
end

-- Add a rarity frame behind the icon on a CrimeSpreeModifierButton
local function add_frame_to_button(btn)
	if not btn or not btn._data or not btn._data.id then return end

	local rarity = get_item_rarity(btn._data.id)
	if not rarity then return end

	local frame_info = RARITY_FRAMES[rarity]
	if not frame_info then return end

	-- Look up frame texture in hud_icons
	if not tweak_data.hud_icons or not tweak_data.hud_icons[frame_info.frame] then return end
	local frame_data = tweak_data.hud_icons[frame_info.frame]

	-- btn._image is the icon container panel (128×128 scaled to 80%)
	local image_panel = btn._image
	if not image_panel then return end

	local panel_w = image_panel:w()
	local panel_h = image_panel:h()

	-- Frame fills the entire image container, behind the icon (layer < 10)
	image_panel:bitmap({
		name = "csr_rarity_frame",
		texture = frame_data.texture,
		texture_rect = frame_data.texture_rect,
		w = panel_w,
		h = panel_h,
		x = 0,
		y = 0,
		color = frame_info.color,
		layer = 5
	})
end

-- Hook: after all modifier buttons are created, add frames to player items
if CrimeSpreeModifiersMenuComponent then
	Hooks:PostHook(CrimeSpreeModifiersMenuComponent, "populate_modifiers", "CSR_AddFramesToButtons", function(self, modifiers)
		if not self._buttons then return end

		for _, btn in ipairs(self._buttons) do
			-- Only CrimeSpreeModifierButton has _data; skip finalize/back CrimeSpreeButton
			if btn._data and btn._data.id then
				add_frame_to_button(btn)
			end
		end
	end)
end
