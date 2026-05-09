-- Crime Spree Roguelike - VanillaHUD Plus / WolfHUD Integration
-- Registers item cooldown/buff icons in VHUDPlus's buff display system.
-- Each buff can be toggled individually via CSR_Settings.
--
-- WOLFHUD COMPAT NOTE:
-- Legacy WolfHUD (pre-VanillaHUD-Plus fork) shares the HUDList API but its
-- BuffItemBase:init differs and crashes on unknown MAP entries with a C++
-- access violation in set_color (uncatchable by pcall). When we detect
-- WolfHUD WITHOUT VHUDPlus, we bail out of MAP registration entirely —
-- no buff icons under WolfHUD, but no crashes either.

if not RequiredScript then
	return
end

-- Define helpers BEFORE the HUDList check so they're always available.
-- Other files guard calls with `if CSR_VHUDPlusEvent then`, so these must exist
-- even if VHUDPlus is not installed (gameinfo:event is wrapped in pcall).

function CSR_VHUDPlusEnabled(buff_key)
	if not CSR_Settings or not CSR_Settings.values then
		return true
	end
	local val = CSR_Settings.values["vhudplus_" .. buff_key]
	if val == nil then
		return true
	end
	return val
end

-- WolfHUD-without-VHUDPlus detection: legacy WolfHUD's BuffItemBase crashes
-- on our MAP entries. If WolfHUD is installed but VHUDPlus is not, suppress
-- all buff events to avoid the access violation.
local function _csr_is_wolfhud_only()
	local has_vhudplus = _G.VHUDPlus ~= nil
	local has_wolfhud = _G.WolfHUD ~= nil
	return has_wolfhud and not has_vhudplus
end

function CSR_VHUDPlusEvent(source, event, id, data)
	if not managers.gameinfo then
		return
	end

	-- WolfHUD legacy: skip the entire integration to dodge the C++ AV.
	if _csr_is_wolfhud_only() then
		return
	end

	-- Mechanic files pass t = TimerManager:game():time() which resets each mission.
	-- VHUDPlus checks expiration against Application:time() (uptime since launch).
	-- Without this fix, expire_t (game_time + duration) is always below
	-- Application:time(), so the buff expires instantly and never appears.
	local fixed_data = data
	if data and data.t and event == "activate" then
		fixed_data = {}
		for k, v in pairs(data) do
			fixed_data[k] = v
		end
		fixed_data.t = Application:time()
	end

	local ok, err = pcall(function()
		managers.gameinfo:event(source, event, id, fixed_data)
	end)
	if not ok then
		log("[CSR VHUDPlus] ERROR in " .. tostring(event) .. "/" .. tostring(id) .. ": " .. tostring(err))
	end
end

-- Only register MAP entries if VHUDPlus's HUDList system is loaded
if not HUDList or not HUDList.BuffItemBase or not HUDList.BuffItemBase.MAP then
	return
end

-- Skip MAP registration under legacy WolfHUD.
if _csr_is_wolfhud_only() then
	log("[CSR VHUDPlus] WolfHUD detected without VHUDPlus — skipping MAP registration to avoid set_color C++ AV")
	return
end

log("[CSR VHUDPlus] MAP found, registering entries")

local MAP = HUDList.BuffItemBase.MAP

-- Defensive: bitmap{} expects a Color object. If ListOptions returns nil or a
-- string (some VHUDPlus init failure modes), fall back to Color.white — never
-- to a string literal. Passing a string crashes set_color in C++.
local function _ensure_color(value, fallback)
	if type(value) == "userdata" then
		return value
	end
	return fallback or Color.white
end

local std_color = _ensure_color(
	HUDListManager and HUDListManager.ListOptions and HUDListManager.ListOptions.buff_icon_color_standard,
	Color.white
)

-- The Edge: 120s cooldown after emergency heal
MAP.csr_the_edge_cd = {
	hud_tweak = "csr_the_edge",
	class = "TimedBuffItem",
	priority = 5,
	color = std_color,
	ignore = not CSR_VHUDPlusEnabled("the_edge"),
}

-- The Edge: 0.5s invulnerability window (brief, separate icon with debuff color)
local debuff_color = _ensure_color(
	HUDListManager and HUDListManager.ListOptions and HUDListManager.ListOptions.buff_icon_color_debuff_fix,
	Color.white
)
MAP.csr_the_edge_invuln = {
	hud_tweak = "csr_the_edge",
	class = "TimedBuffItem",
	priority = 6,
	color = debuff_color,
	ignore = not CSR_VHUDPlusEnabled("the_edge"),
}

-- Overkill Rush: 4s kill streak timer with stacks
MAP.csr_overkill_rush = {
	hud_tweak = "csr_overkill_rush",
	class = "TimedBuffItem",
	priority = 5,
	color = std_color,
	ignore = not CSR_VHUDPlusEnabled("overkill_rush"),
}

-- Bonnie's Lucky Chip: 1.5s cooldown after instakill
MAP.csr_bonnie_chip_cd = {
	hud_tweak = "csr_bonnie_chip",
	class = "TimedBuffItem",
	priority = 5,
	color = std_color,
	ignore = not CSR_VHUDPlusEnabled("bonnie_chip"),
}

-- Plush Shark: invulnerability duration (10-50s)
MAP.csr_plush_shark_invuln = {
	hud_tweak = "csr_plush_shark",
	class = "TimedBuffItem",
	priority = 6,
	color = std_color,
	ignore = not CSR_VHUDPlusEnabled("plush_shark"),
}

-- Dead Man's Trigger: 1s re-entry cooldown
MAP.csr_dmt_cd = {
	hud_tweak = "csr_dead_mans_trigger",
	class = "TimedBuffItem",
	priority = 4,
	color = std_color,
	ignore = not CSR_VHUDPlusEnabled("dead_mans_trigger"),
}

-- Worn Band-Aid: regen cycle timer
MAP.csr_bandaid_regen = {
	hud_tweak = "csr_worn_bandaid",
	class = "TimedBuffItem",
	priority = 4,
	color = std_color,
	ignore = not CSR_VHUDPlusEnabled("worn_bandaid"),
}
