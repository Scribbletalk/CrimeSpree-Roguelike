-- Override ModifierAssaultExtender:modify_value to support separate deduction
-- values for duration and spawn pool (vanilla uses one shared "deduction" field).
--
-- Uses Hooks:PostHook on init so the override is applied per-instance and
-- cannot be clobbered if Diesel re-loads the vanilla modifier script.
--
-- Safety: tweakdata also includes "deduction" so vanilla modify_value still
-- works correctly even if this override somehow fails to apply.

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

-- Apply override on the class directly (covers instances created before PostHook)
if ModifierAssaultExtender then
	ModifierAssaultExtender.modify_value = csr_modify_value
end

-- Re-apply on every new instance via PostHook on init (survives Diesel re-loads)
Hooks:PostHook(ModifierAssaultExtender, "init", "CSR_AssaultExtenderOverride", function(self)
	self.modify_value = csr_modify_value
end)
