-- Stand Out (stealth family) — enemies identify you faster while in stealth.
-- Reworked from the vanilla ModifierLessConcealment detection-risk wrapper into a
-- pure notice-SPEED knob: multiplies each attention setting's notice_delay_mul so
-- guards fill the detection meter faster, WITHOUT seeing you from further away
-- (range_mul is left untouched). Four tiers scale the notice rate up to 2x.
-- Host-authoritative: AI detection runs host-side, so hooking both the local
-- player and husk (guest) attention settings lets one host cover every player.
-- See csr_modifier_file_pattern.md / csr_modifier_mechanic_via_hooks.md.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

-- Notice-rate multiplier per tier; delay_mul = 1/SPEED (lower delay = faster
-- notice). Display "$n% faster" = (SPEED-1)*100 -> 25 / 50 / 75 / 100.
local SPEED = { 1.25, 1.5, 1.75, 2.0 }

local function tier(i)
	return {
		loc = "menu_cs_modifier_less_concealment_" .. i,
		data = { delay_mul = 1 / SPEED[i] },
		loc_macros = { n = math.floor((SPEED[i] - 1) * 100 + 0.5) },
	}
end

-- Strongest active tier's delay_mul (the smallest), or nil if Stand Out is not
-- active. delay_mul is our private field, so no other stealth modifier matches.
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

-- Multiply notice_delay_mul on a freshly-cloned attention setting. Idempotent:
-- the setting is a clone() per registration, so re-running never compounds.
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
