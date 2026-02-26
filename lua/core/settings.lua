-- Crime Spree Roguelike - Settings Manager

CSR_Settings = CSR_Settings or {}

local settings_file = SavePath .. "crime_spree_roguelike.json"

-- Default settings
CSR_Settings.defaults = {
	language = "en",  -- "en" or "ru"
	skip_blackscreen = false  -- Auto-skip heist intro blackscreen
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

function CSR_Settings:GetLanguage()
	return self.values.language or "en"
end

function CSR_Settings:IsSkipBlackscreen()
	return self.values.skip_blackscreen or false
end

-- Load settings on init
CSR_Settings:Load()
