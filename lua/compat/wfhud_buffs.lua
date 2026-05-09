-- Crime Spree Roguelike - Warframe HUD Integration
-- Registers item cooldown/buff icons in WFHud's buff list.
-- Each buff can be toggled individually via CSR_Settings.

if not RequiredScript then
	return
end

-- Helpers defined unconditionally: other files guard their calls with
-- `if CSR_WFHudEvent then`, so these must exist even if WFHud is absent
-- (add_buff/remove_buff are called inside pcall to stay safe).

function CSR_WFHudEnabled(key)
	if not CSR_Settings or not CSR_Settings.values then
		return true
	end
	local val = CSR_Settings.values["wfhud_" .. key]
	if val == nil then
		return true
	end
	return val
end

-- key -> skill_map entry descriptor (texture + name + toggle)
local CSR_WFHUD_ENTRIES = {
	the_edge_cd = {
		name_id = "csr_wfhud_name_the_edge",
		texture = "guis/textures/pd2/crime_spree/csr_the_edge",
		toggle = "the_edge",
		is_debuff = true,
	},
	the_edge_invuln = {
		name_id = "csr_wfhud_name_the_edge",
		texture = "guis/textures/pd2/crime_spree/csr_the_edge",
		toggle = "the_edge",
	},
	overkill_rush = {
		name_id = "csr_wfhud_name_overkill_rush",
		texture = "guis/textures/pd2/crime_spree/csr_overkill_rush",
		toggle = "overkill_rush",
	},
	bonnie_chip_cd = {
		name_id = "csr_wfhud_name_bonnie_chip",
		texture = "guis/textures/pd2/crime_spree/csr_bonnie_chip",
		toggle = "bonnie_chip",
		is_debuff = true,
	},
	plush_shark_invuln = {
		name_id = "csr_wfhud_name_plush_shark",
		texture = "guis/textures/pd2/crime_spree/csr_plush_shark",
		toggle = "plush_shark",
	},
	dmt_cd = {
		name_id = "csr_wfhud_name_dead_mans_trigger",
		texture = "guis/textures/pd2/crime_spree/csr_dead_mans_trigger",
		toggle = "dead_mans_trigger",
		is_debuff = true,
	},
	bandaid_regen = {
		name_id = "csr_wfhud_name_worn_bandaid",
		texture = "guis/textures/pd2/crime_spree/csr_worn_bandaid",
		toggle = "worn_bandaid",
	},
}

-- Title Case display names for Warframe HUD (differs from the all-caps
-- logbook/selection names used elsewhere).
Hooks:Add("LocalizationManagerPostInit", "CSR_WFHudNames", function(loc)
	loc:add_localized_strings({
		csr_wfhud_name_the_edge = "The Edge",
		csr_wfhud_name_overkill_rush = "Overkill Rush",
		csr_wfhud_name_bonnie_chip = "Bonnie's Lucky Chip",
		csr_wfhud_name_plush_shark = "Plush Shark",
		csr_wfhud_name_dead_mans_trigger = "Dead Man's Trigger",
		csr_wfhud_name_worn_bandaid = "Worn Band-Aid",
	})
end)

local function value_format_identity(v)
	return tostring(v)
end

local function ensure_registered(id)
	if not WFHud or not WFHud.skill_map then
		return nil
	end
	local entry = CSR_WFHUD_ENTRIES[id]
	if not entry then
		return nil
	end
	WFHud.skill_map.csr = WFHud.skill_map.csr or {}
	local data = WFHud.skill_map.csr[id]
	if not data then
		data = {
			key = "csr." .. id,
			name_id = entry.name_id,
			texture = entry.texture,
			texture_rect = { 0, 0, 128, 128 },
			value_format = value_format_identity,
			custom = true,
			ignore_disabled = true,
			is_debuff = entry.is_debuff,
		}
		WFHud.skill_map.csr[id] = data
	end
	return entry
end

-- Shrink CSR icons inside WFHud's buff list panel.
-- Panel slot size is shared across all buffs, so only the icon bitmap
-- (and its category overlay) are resized — layout stays intact.
local CSR_WFHUD_ICON_SCALE = 0.7
if HUDBuffListItem and not HUDBuffListItem._csr_icon_shrink_hooked then
	HUDBuffListItem._csr_icon_shrink_hooked = true
	Hooks:PostHook(HUDBuffListItem, "init", "CSR_ShrinkIcon", function(self)
		local ud = self._upgrade_data
		if not ud or type(ud.key) ~= "string" or ud.key:sub(1, 4) ~= "csr." then
			return
		end
		if not self._icon then
			return
		end
		local cx, cy = self._icon:center()
		local new_size = self._icon:w() * CSR_WFHUD_ICON_SCALE
		self._icon:set_size(new_size, new_size)
		self._icon:set_center(cx, cy)
		if self._overlay_icon then
			local ov = self._overlay_icon:w() * CSR_WFHUD_ICON_SCALE
			self._overlay_icon:set_size(ov, ov)
			self._overlay_icon:set_left(self._icon:left())
			self._overlay_icon:set_bottom(self._icon:bottom())
		end
	end)
end

-- event: "activate" | "deactivate"
-- data (for activate): { duration = <seconds>, value = <string|number|nil> }
function CSR_WFHudEvent(event, id, data)
	if not WFHud or not WFHud.add_buff then
		return
	end
	local entry = ensure_registered(id)
	if not entry then
		return
	end
	if not CSR_WFHudEnabled(entry.toggle) then
		return
	end

	local ok, err = pcall(function()
		if event == "activate" then
			local duration = data and data.duration
			local value = data and data.value
			WFHud:add_buff("csr", id, value, duration)
		elseif event == "deactivate" then
			WFHud:remove_buff("csr", id)
		end
	end)
	if not ok then
		log("[CSR WFHud] ERROR in " .. tostring(event) .. "/" .. tostring(id) .. ": " .. tostring(err))
	end
end
