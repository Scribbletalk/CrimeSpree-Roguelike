-- CSR end-screen economy gate — companion to the end-screen fork.
--
-- CSR grants NO per-heist cash: rewards accrue only at run completion (locked
-- design). Vanilla MoneyManager:on_mission_completed (moneymanager.lua:184-211)
-- already short-circuits for vanilla Crime Spree:
--   if managers.crime_spree:is_active() then
--       managers.loot:clear_postponed_small_loot()
--       return
--   end
-- but that guard is FALSE for a CSR heist (CSR runs a temporary "crime_spree"
-- job and deliberately never enables managers.crime_spree), so without this
-- the full job/bag/loot payout is computed and added to the wallet (:210),
-- driving the left-side cash count-up the player should never see.
--
-- on_mission_completed is called from MissionEndState:at_enter (:134) which
-- runs the WHOLE function before csr_mission_lifecycle's at_enter PostHook
-- fires, so the payout cannot be undone after the fact — it must be gated at
-- the source. A PostHook fires too late and a PreHook cannot abort the
-- original, so the only correct SuperBLT primitive is Hooks:OverrideFunction
-- (same pattern as csr_endscreen_wiring / csr_briefing_wiring): the vanilla
-- body is reproduced verbatim for every non-CSR path.
--
-- No-leak gate (feedback_csr_only_no_vanilla_leak): the CSR early-return is
-- taken ONLY for the run-scoped CSR-heist signal — the active job is the
-- temporary "crime_spree" job AND vanilla CS is NOT active. This is
-- byte-identical to csr_mission_lifecycle.lua:csr_heist_active() /
-- csr_briefing_wiring.lua, NOT the persisted (leaky) managers.csr:is_active()
-- flag. Walked:
--   normal heist  job ~= "crime_spree"                  -> vanilla payout
--   normal + stale csr is_active on disk : same          -> vanilla payout
--   vanilla CS    cs:is_active true (vanilla's own guard) -> vanilla CS path
--   Skirmish      job ~= "crime_spree"                    -> vanilla payout
--   CSR heist     job == "crime_spree", cs:is_active false -> CSR: no payout
-- Host and client both run on_mission_completed locally with the same job
-- state for a CSR heist, so both skip the payout symmetrically; no network
-- packet is involved (feedback_check_host_and_client).

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
	-- CSR: no per-heist cash. Mirror vanilla CS's own short-circuit
	-- (clear postponed small loot, then bail before any payout is set/added).
	if csr_heist_active() then
		managers.loot:clear_postponed_small_loot()

		return
	end

	-- Verbatim vanilla MoneyManager:on_mission_completed — every non-CSR path
	-- (normal heist / vanilla CS / Skirmish) is byte-for-byte unchanged.
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

log("[CSR] csr_endscreen_economy.lua loaded (per-heist cash suppressed for CSR)")
