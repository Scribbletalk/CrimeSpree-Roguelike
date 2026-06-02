-- Apply CSR's active loud + stealth modifiers as real engine effects on heist start.
-- Routes through vanilla managers.modifiers; aggregation + host gate live in
-- managers.csr:apply_modifiers. See csr_vanilla_intercepts.md.

if not RequiredScript then
	return
end

local function csr_heist_active()
	if not managers or not managers.job then
		return false
	end
	if managers.job:current_job_id() ~= "crime_spree" then
		return false
	end
	if managers.crime_spree and managers.crime_spree:is_active() then
		return false
	end
	return true
end

if IngameWaitingForPlayersState and not _G._CSR_APPLY_MODIFIERS_HOOKED then
	_G._CSR_APPLY_MODIFIERS_HOOKED = true

	Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_ApplyModifiers", function(self)
		if not managers.csr or not managers.csr.apply_modifiers then
			return
		end
		if not csr_heist_active() then
			return
		end
		managers.csr:apply_modifiers()
	end)
end

csr_log("[CSR] apply_modifiers.lua loaded")
