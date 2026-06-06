-- Keen Dispatch (stealth family) — shorter pager response window (less time to answer).
-- Reworked from the old "fewer pagers" effect. A pager rings nr_of_calls times (vanilla 2), each
-- waiting call_duration seconds (vanilla 6) before the next; the alarm trips after the last one.
-- Total answer window = 2 * 6 = 12s. Each tier shrinks call_duration by `count`s (per call), so the
-- total window drops by 2*count: tiers give 10/8/6/4s. data.count = seconds removed PER CALL; "max"
-- so the highest active tier wins. Effect is host-only (apply_modifiers); the custom class is defined
-- when the vanilla modifier file loads. The display number ($n) and EHI tracker both reflect the
-- TOTAL window (2*count), which is what the player actually experiences.
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local T1, T2, T3, T4 = 1, 2, 3, 4
local EHI_BASE_TIME = 12 -- EHI's pager tracker default (= vanilla 2 calls * 6s); verified in EHI InteractionExt.lua

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
		{ loc = "menu_cs_modifier_less_pagers_1", data = { count = { T1, "max" } }, loc_macros = { n = T1 * 2 } },
		{ loc = "menu_cs_modifier_less_pagers_2", data = { count = { T2, "max" } }, loc_macros = { n = T2 * 2 } },
		{ loc = "menu_cs_modifier_less_pagers_3", data = { count = { T3, "max" } }, loc_macros = { n = T3 * 2 } },
		{ loc = "menu_cs_modifier_less_pagers_4", data = { count = { T4, "max" } }, loc_macros = { n = T4 * 2 } },
	},
	hooks = {
		-- Define the custom class once the vanilla modifier file has executed (BaseModifier exists).
		-- Mirrors ModifierLessPagers' one-shot init shape; reads from the pristine baseline that
		-- apply_modifiers restores before every apply, so the subtraction never compounds.
		["lib/modifiers/modifierlesspagers"] = function()
			if _G.ModifierCSRPagerResponse then
				return
			end
			ModifierCSRPagerResponse = class(BaseModifier)
			ModifierCSRPagerResponse._type = "ModifierCSRPagerResponse"
			ModifierCSRPagerResponse.name_id = "none"
			ModifierCSRPagerResponse.desc_id = "menu_cs_modifier_pagers"
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
		-- Extra Heist Info support: sync EHI's pager countdown to the real (shortened) total window.
		-- Runs on EVERY client (EHI display is local; the pager mechanic itself is host-authoritative),
		-- and auto-restores to EHI_BASE_TIME when inactive / outside a CSR heist. Nil-guarded: EHI's
		-- classes only exist if installed with the pager option enabled.
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
