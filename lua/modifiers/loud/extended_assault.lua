-- Extended Assault (loud) — police assaults last longer and have a larger spawn
-- pool; hostages/converts shrink each axis at its own rate (separate
-- duration_deduction / spawn_deduction, capped at max_hostages).
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
		spawn_pool = { 20, "add" },
		deduction = { 4, "add" },
		duration_deduction = { 5, "add" },
		spawn_deduction = { 2.5, "add" },
		max_hostages = { 4, "none" },
	},

	hooks = {
		-- Vanilla ModifierAssaultExtender shares one "deduction" field between
		-- duration and spawn pool. Replace modify_value so each axis reads its
		-- own deduction (falls back to "deduction" if the split keys are absent,
		-- so this is harmless if applied to a non-CSR instance).
		["lib/modifiers/modifierassaultextender"] = function()
			if _G._CSR_ASSAULT_EXTENDER_HOOKED then
				return
			end
			_G._CSR_ASSAULT_EXTENDER_HOOKED = true

			local function csr_modify_value(self, id, value, ...)
				if id == "GroupAIStateBesiege:SustainEndTime" then
					self:_update_hostage_time()
					local extension = self:value("duration") * 0.01
					local ded_per = self:value("duration_deduction") or self:value("deduction") or 4
					local deduction = ded_per * 0.01 * self._hostage_average_count
					return value + self._base_duration * (extension - deduction)
				elseif id == "GroupAIStateBesiege:SustainSpawnAllowance" then
					self:_update_hostage_time()
					local base_pool = ...
					local extension = self:value("spawn_pool") * 0.01
					local ded_per = self:value("spawn_deduction") or self:value("deduction") or 4
					local deduction = ded_per * 0.01 * self._hostage_average_count
					return value + math.floor(base_pool * (extension - deduction))
				end
				return value
			end

			ModifierAssaultExtender.modify_value = csr_modify_value
			Hooks:PostHook(ModifierAssaultExtender, "init", "CSR_AssaultExtender_Override", function(self)
				self.modify_value = csr_modify_value
			end)
		end,
	},
})
