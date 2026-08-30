-- Extended Assault (loud) — police assaults last longer ONLY; the spawn pool is
-- left at vanilla (no extra enemies). Hostages/converts shrink the duration
-- extension (duration_deduction, capped at max_hostages).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

local DURATION_PCT = 40
local DED_PCT = 5
local MAX_HOSTAGES = 4

_G.CSR.register_modifier({
	id = "assault_extender",
	category = "loud",
	loc = "csr_modifier_assault_extender",
	icon = "crime_spree_heavies",
	class = "ModifierAssaultExtender",
	data = {
		duration = { DURATION_PCT, "add" },
		deduction = { 4, "add" },
		duration_deduction = { DED_PCT, "add" },
		max_hostages = { MAX_HOSTAGES, "none" },
	},
	loc_macros = { pct = DURATION_PCT, ded_pct = DED_PCT, max_hst = MAX_HOSTAGES },

	hooks = {
		-- Replace modify_value so it extends ONLY the sustain DURATION and leaves
		-- the spawn allowance at vanilla (no extra enemies). duration_deduction
		-- shrinks the extension per held hostage/convert; falls back to the base
		-- "deduction" field if absent.
		["lib/modifiers/modifierassaultextender"] = function()
			if _G._CSR_ASSAULT_EXTENDER_HOOKED then
				return
			end
			_G._CSR_ASSAULT_EXTENDER_HOOKED = true

			-- Vanilla Crime Spree instantiates this same class. Keep its modify_value and delegate
			-- to it outside a CSR heist, so a plain Crime Spree run keeps vanilla assault balance.
			local vanilla_modify_value = ModifierAssaultExtender.modify_value

			local function csr_modify_value(self, id, value, ...)
				local mgr = managers and managers.csr
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
					if vanilla_modify_value then
						return vanilla_modify_value(self, id, value, ...)
					end
					return value
				end
				if id == "GroupAIStateBesiege:SustainEndTime" then
					self:_update_hostage_time()
					local extension = self:value("duration") * 0.01
					local ded_per = self:value("duration_deduction") or self:value("deduction") or 4
					local deduction = ded_per * 0.01 * self._hostage_average_count
					return value + self._base_duration * (extension - deduction)
				end
				-- SustainSpawnAllowance (and everything else) passes through untouched: NO extra spawns.
				return value
			end

			ModifierAssaultExtender.modify_value = csr_modify_value
			Hooks:PostHook(ModifierAssaultExtender, "init", "CSR_AssaultExtender_Override", function(self)
				self.modify_value = csr_modify_value
			end)
		end,
	},
})
