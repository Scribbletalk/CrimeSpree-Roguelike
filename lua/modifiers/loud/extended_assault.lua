-- Extended Assault (loud) — police assaults last longer ONLY; the spawn pool is
-- left at vanilla (no extra enemies). Hostages/converts shrink the duration
-- extension (duration_deduction, capped at max_hostages).
if not (_G.CSR and _G.CSR.register_modifier) then
	return
end

_G.CSR.register_modifier({
	id = "assault_extender",
	category = "loud",
	loc = "menu_cs_modifier_assault_extender",
	icon = "crime_spree_heavies",
	class = "ModifierAssaultExtender",
	data = {
		duration = { 40, "add" },
		deduction = { 4, "add" },
		duration_deduction = { 5, "add" },
		max_hostages = { 4, "none" },
	},

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

			local function csr_modify_value(self, id, value)
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
