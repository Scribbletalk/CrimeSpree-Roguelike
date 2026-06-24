-- Stand Out (stealth family) - enemies detect you faster (fills meter sooner, not from farther).
-- Multiplies notice_delay_mul on attention settings; range_mul untouched. Four tiers up to 2x speed.
-- Hooks both PlayerMovement + HuskPlayerMovement so one host covers every player. See csr_modifier_file_pattern.md.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

-- delay_mul = 1/SPEED (lower = faster fill). Display "$n% faster" = (SPEED-1)*100.
local SPEED = { 1.25, 1.5, 1.75, 2.0 }

local function tier(i)
	return {
		loc = "menu_cs_modifier_less_concealment_" .. i,
		data = { delay_mul = 1 / SPEED[i] },
		loc_macros = { n = math.floor((SPEED[i] - 1) * 100 + 0.5) },
	}
end

-- Smallest (strongest) active delay_mul, or nil if inactive. Private field - no collisions.
local function strongest_delay_mul()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist() and mgr.active_modifiers) then
		return nil
	end
	local best
	for _, e in ipairs(mgr:active_modifiers("stealth")) do
		if e.data and e.data.delay_mul and (not best or e.data.delay_mul < best) then
			best = e.data.delay_mul
		end
	end
	return best
end

-- Setting is a fresh clone() per registration, so applying never compounds.
local function apply_notice_speed(setting)
	local m = strongest_delay_mul()
	if m then
		setting.notice_delay_mul = (setting.notice_delay_mul or 1) * m
	end
end

_G.CSR.register_modifier({
	id = "less_concealment", -- unchanged: keeps frozen-spree/save compatibility
	category = "stealth",
	icon = "crime_spree_concealment",
	tiers = { tier(1), tier(2), tier(3), tier(4) },

	hooks = {
		["lib/units/beings/player/playermovement"] = function()
			if _G._CSR_STAND_OUT_PM_HOOKED then
				return
			end
			_G._CSR_STAND_OUT_PM_HOOKED = true
			Hooks:PostHook(
				PlayerMovement,
				"_apply_attention_setting_modifications",
				"CSR_StandOut_PlayerMovement",
				function(self, setting)
					apply_notice_speed(setting)
				end
			)
		end,
		["lib/units/beings/player/huskplayermovement"] = function()
			if _G._CSR_STAND_OUT_HM_HOOKED then
				return
			end
			_G._CSR_STAND_OUT_HM_HOOKED = true
			Hooks:PostHook(
				HuskPlayerMovement,
				"_apply_attention_setting_modifications",
				"CSR_StandOut_HuskPlayerMovement",
				function(self, setting)
					apply_notice_speed(setting)
				end
			)
		end,
	},
})
