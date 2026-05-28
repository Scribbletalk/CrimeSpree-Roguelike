-- Suppress per-heist cash payout for CSR (rewards accrue at run completion only).
-- Vanilla MoneyManager:on_mission_completed runs the full payout before any of our
-- at_enter hooks fire, so this MUST be at the source — Hooks:OverrideFunction is
-- the only correct primitive. See csr_vanilla_intercepts.md.

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

Hooks:OverrideFunction(MoneyManager, "on_mission_completed", function(self, num_winners)
	-- CSR: mirror vanilla CS's own short-circuit (clear postponed small loot, then bail).
	if csr_heist_active() then
		managers.loot:clear_postponed_small_loot()

		return
	end

	-- Verbatim vanilla MoneyManager:on_mission_completed below — every non-CSR
	-- path (normal heist / vanilla CS / Skirmish) is byte-for-byte unchanged.
	if managers.crime_spree:is_active() then
		managers.loot:clear_postponed_small_loot()

		return
	end

	if managers.job:skip_money() then
		managers.loot:set_postponed_small_loot()

		return
	end

	local stage_value, job_value, bag_value, vehicle_value, small_value, crew_value, total_payout, risk_table, payout_table, mutators_reduction =
		self:get_real_job_money_values(num_winners)

	managers.loot:clear_postponed_small_loot()
	self:_set_stage_payout(stage_value + risk_table.stage_risk)
	self:_set_job_payout(job_value + risk_table.job_risk)
	self:_set_bag_payout(bag_value + risk_table.bag_risk)
	self:_set_vehicle_payout(vehicle_value + risk_table.vehicle_risk)
	self:_set_small_loot_payout(small_value + risk_table.small_risk)
	self:_set_crew_payout(crew_value)

	self._mutators_reduction = mutators_reduction

	Telemetry:set_mission_payout(total_payout)
	self:_add_to_total(total_payout, nil, TelemetryConst.economy_origin.mission_complete_reward)
end)

csr_log("[CSR] endscreen_economy.lua loaded")
