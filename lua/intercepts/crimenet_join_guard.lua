-- Crime Spree Roguelike lobby isolation (browser side): hide vanilla Crime Spree lobbies from the CSR
-- player's Crime.Net browser, so the Crime Spree category shows only CSR lobbies. A lobby counts as CSR
-- when its broadcast mod list (data.mods, a pipe-delimited "Display|Folder|..." string, confirmed Task 0)
-- contains this mod's folder name. Joining a vanilla CS lobby anyway (e.g. via a Steam invite that
-- bypasses the browser) is blocked separately at on_enter_lobby in lobby_routing.lua.

if not RequiredScript or not MenuComponentManager then
	return
end

if _G._CSR_BROWSER_HIDE_WRAPPED then
	return
end
_G._CSR_BROWSER_HIDE_WRAPPED = true

-- True if the lobby's broadcast mod list names this mod (folder name "CrimeSpree-Roguelike" is version
-- stable, unlike the display name which carries the version suffix). data.mods is a string in practice;
-- the table branch is a defensive fallback for other matchmaking paths.
local function has_csr_mod(mods_data)
	if not mods_data then
		return false
	end
	if type(mods_data) == "string" then
		return mods_data:find("CrimeSpree-Roguelike") ~= nil
	end
	if type(mods_data) == "table" then
		for _, entry in pairs(mods_data) do
			if type(entry) == "string" and entry:find("CrimeSpree-Roguelike") then
				return true
			elseif type(entry) == "table" then
				for _, v in pairs(entry) do
					if type(v) == "string" and v:find("CrimeSpree-Roguelike") then
						return true
					end
				end
			end
		end
	end
	return false
end

-- A Crime Spree lobby that is NOT a CSR lobby = a vanilla CS lobby a CSR player must not see/join.
local function is_foreign_crime_spree(data)
	return data and data.is_crime_spree and not has_csr_mod(data.mods)
end

local _orig_add = MenuComponentManager.add_crimenet_server_job
function MenuComponentManager:add_crimenet_server_job(data, ...)
	if is_foreign_crime_spree(data) then
		return -- hide a vanilla Crime Spree lobby.
	end
	return _orig_add(self, data, ...)
end
