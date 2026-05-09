-- Crime Spree Roguelike - PocoHud3 Integration
-- Registers item cooldown/buff icons in PocoHud3's buff panel.
-- Each buff can be toggled individually via CSR_Settings.

if not RequiredScript then
	return
end

-- Helpers defined unconditionally: other files guard their calls with
-- `if CSR_PocoHudEvent then`, so these must exist even if PocoHud3 is absent.

function CSR_PocoHudEnabled(key)
	if not CSR_Settings or not CSR_Settings.values then
		return true
	end
	local val = CSR_Settings.values["pocohud_" .. key]
	if val == nil then
		return true
	end
	return val
end

-- id -> descriptor (texture + toggle + good/debuff flag)
-- good = true → green tint (positive buff); good = false → red tint (cooldown/debuff)
local CSR_POCOHUD_ENTRIES = {
	the_edge_cd = {
		texture = "guis/textures/pd2/crime_spree/csr_the_edge",
		toggle = "the_edge",
		good = false,
	},
	the_edge_invuln = {
		texture = "guis/textures/pd2/crime_spree/csr_the_edge",
		toggle = "the_edge",
		good = true,
	},
	overkill_rush = {
		texture = "guis/textures/pd2/crime_spree/csr_overkill_rush",
		toggle = "overkill_rush",
		good = true,
	},
	bonnie_chip_cd = {
		texture = "guis/textures/pd2/crime_spree/csr_bonnie_chip",
		toggle = "bonnie_chip",
		good = false,
	},
	plush_shark_invuln = {
		texture = "guis/textures/pd2/crime_spree/csr_plush_shark",
		toggle = "plush_shark",
		good = true,
	},
	dmt_cd = {
		texture = "guis/textures/pd2/crime_spree/csr_dead_mans_trigger",
		toggle = "dead_mans_trigger",
		good = false,
	},
	bandaid_regen = {
		texture = "guis/textures/pd2/crime_spree/csr_worn_bandaid",
		toggle = "worn_bandaid",
		good = true,
	},
}

local function poco_instance()
	-- PocoHud3 global can be nil (not loaded), true (loaded but closed), or the HUD instance.
	if type(PocoHud3) ~= "table" then
		return nil
	end
	if not PocoHud3.Buff3 or not PocoHud3.RemoveBuff then
		return nil
	end
	return PocoHud3
end

-- event: "activate" | "deactivate"
-- data (for activate): { duration = <seconds>, value = <string|nil> }
function CSR_PocoHudEvent(event, id, data)
	local entry = CSR_POCOHUD_ENTRIES[id]
	if not entry then
		return
	end
	if not CSR_PocoHudEnabled(entry.toggle) then
		return
	end
	local hud = poco_instance()
	if not hud then
		return
	end

	local key = "csr_" .. id

	local ok, err = pcall(function()
		if event == "activate" then
			local duration = data and data.duration or 0
			if duration <= 0 then
				return
			end
			local value = data and data.value
			hud:Buff3({
				key = key,
				icon = entry.texture,
				iconRect = { 0, 0, 128, 128 },
				text = value and tostring(value) or "",
				t = duration,
				good = entry.good,
			})
		elseif event == "deactivate" then
			hud:RemoveBuff(key)
		end
	end)
	if not ok then
		log("[CSR PocoHud] ERROR in " .. tostring(event) .. "/" .. tostring(id) .. ": " .. tostring(err))
	end
end
