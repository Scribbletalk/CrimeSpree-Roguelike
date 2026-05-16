-- Crime Spree Roguelike - Settings Manager

_G.CSR_MOD_VERSION = "6.2.0"

CSR_Settings = CSR_Settings or {}

local settings_file = SavePath .. "crime_spree_roguelike.json"

-- Default settings
CSR_Settings.defaults = {
	skip_blackscreen = false, -- Auto-skip heist intro blackscreen
	block_item_healing = false, -- Block healing from items (for Berserker/Frenzy builds)
	bonnie_chip_sound_volume = 1.0, -- Volume for Bonnie's Lucky Chip activation sound
	plush_shark_sound_volume = 1.0, -- Volume for Plush Shark activation sound
	the_edge_sound_volume = 1.0, -- Volume for The Edge activation sound
	lobby_filter = false, -- Filter Crime.Net to only show CSR lobbies + auto-kick non-CSR players
	hud_wildcard_use_bar = false, -- Replace the icon-style wildcard HUD slot with a vertical cooldown bar
	debug_mode = false, -- Verbose logging to BLT log (no gameplay changes)
	-- Heist Specific Settings
	heist_diamond_bile_stay = true, -- Prevent Bile from leaving after 4 bags on The Diamond
	-- VanillaHUD Plus cooldown display (per-item toggles, default ON)
	vhudplus_the_edge = true,
	vhudplus_overkill_rush = true,
	vhudplus_bonnie_chip = true,
	vhudplus_plush_shark = true,
	vhudplus_dead_mans_trigger = true,
	vhudplus_worn_bandaid = true,
	-- Warframe HUD buff display (per-item toggles, default ON)
	wfhud_the_edge = true,
	wfhud_overkill_rush = true,
	wfhud_bonnie_chip = true,
	wfhud_plush_shark = true,
	wfhud_dead_mans_trigger = true,
	wfhud_worn_bandaid = true,
	-- PocoHud3 buff display (per-item toggles, default ON)
	pocohud_the_edge = true,
	pocohud_overkill_rush = true,
	pocohud_bonnie_chip = true,
	pocohud_plush_shark = true,
	pocohud_dead_mans_trigger = true,
	pocohud_worn_bandaid = true,
}

-- Current settings
CSR_Settings.values = {}

function CSR_Settings:Load()
	local file = io.open(settings_file, "r")
	if file then
		local data = file:read("*all")
		file:close()

		local success, settings = pcall(function()
			return json.decode(data)
		end)

		if success and settings then
			self.values = settings
		else
			self.values = clone(self.defaults)
		end
	else
		self.values = clone(self.defaults)
	end

	-- Ensure all default keys exist
	for key, default_value in pairs(self.defaults) do
		if self.values[key] == nil then
			self.values[key] = default_value
		end
	end
end

function CSR_Settings:Save()
	local file = io.open(settings_file, "w")
	if file then
		file:write(json.encode(self.values))
		file:close()
	else
		log("[CSR Settings] ERROR: Could not save settings file")
	end
end

function CSR_Settings:SetValue(key, value)
	self.values[key] = value
	self:Save()
end

function CSR_Settings:IsSkipBlackscreen()
	return self.values.skip_blackscreen or false
end

-- Load settings on init
CSR_Settings:Load()
