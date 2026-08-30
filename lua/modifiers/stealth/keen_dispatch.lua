-- Keen Dispatch (stealth family) - shrinks pager response window. Vanilla: 2 calls x 6s = 12s total.
-- Each tier subtracts `count` seconds PER CALL (total drop = 2*count); tiers give 10/8/6/4s.
-- Host-only (apply_modifiers); custom class defined when vanilla modifier file loads.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local T1, T2, T3, T4 = 1, 2, 3, 4
local EHI_BASE_TIME = 12 -- vanilla 2 calls * 6s; verified in EHI InteractionExt.lua

-- Highest active Keen Dispatch tier's per-call seconds (0 if inactive / not in a CSR heist).
local function active_pager_count()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist() and mgr.active_modifiers) then
		return 0
	end
	local best = 0
	for _, e in ipairs(mgr:active_modifiers("stealth")) do
		if e.class == "ModifierCSRPagerResponse" and e.data and e.data.count then
			best = math.max(best, e.data.count[1] or 0)
		end
	end
	return best
end

_G.CSR.register_modifier({
	id = "less_pagers",
	category = "stealth",
	icon = "crime_spree_pager",
	class = "ModifierCSRPagerResponse",
	tiers = {
		{ loc = "csr_modifier_less_pagers_1", data = { count = { T1, "max" } }, loc_macros = { n = T1 * 2 } },
		{ loc = "csr_modifier_less_pagers_2", data = { count = { T2, "max" } }, loc_macros = { n = T2 * 2 } },
		{ loc = "csr_modifier_less_pagers_3", data = { count = { T3, "max" } }, loc_macros = { n = T3 * 2 } },
		{ loc = "csr_modifier_less_pagers_4", data = { count = { T4, "max" } }, loc_macros = { n = T4 * 2 } },
	},
	hooks = {
		-- Define the custom class after vanilla modifier file loads (BaseModifier exists).
		-- apply_modifiers restores pristine baseline before each apply, so subtraction never compounds.
		["lib/modifiers/modifierlesspagers"] = function()
			if _G.ModifierCSRPagerResponse then
				return
			end
			ModifierCSRPagerResponse = class(BaseModifier)
			ModifierCSRPagerResponse._type = "ModifierCSRPagerResponse"
			ModifierCSRPagerResponse.name_id = "none"
			ModifierCSRPagerResponse.default_value = "count"
			ModifierCSRPagerResponse.stealth = true

			function ModifierCSRPagerResponse:init(data)
				ModifierCSRPagerResponse.super.init(self, data)
				local seconds = self:value() or 0
				local cd = tweak_data.player.alarm_pager.call_duration
				cd[1][1], cd[1][2] = cd[1][1] - seconds, cd[1][2] - seconds
				cd[2][1], cd[2][2] = cd[2][1] - seconds, cd[2][2] - seconds
			end
		end,
		-- EHI compat: sync pager countdown to the shortened window; nil-guarded (EHI optional).
		["lib/states/ingamewaitingforplayers"] = function()
			if _G._CSR_KEEN_DISPATCH_EHI_HOOKED then
				return
			end
			_G._CSR_KEEN_DISPATCH_EHI_HOOKED = true
			Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_KeenDispatch_EHI", function()
				local total = EHI_BASE_TIME - 2 * active_pager_count()
				if _G.EHIPagerTracker then
					_G.EHIPagerTracker._forced_time = total
				end
				if _G.EHIPagerWaypoint then
					_G.EHIPagerWaypoint._forced_time = total
				end
			end)
		end,
	},
})
