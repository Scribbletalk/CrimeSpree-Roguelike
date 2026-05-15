-- CSR mission lifecycle (Slice 7 wiring).
--
-- Hooks MissionEndState:at_enter so a CSR run progresses rank when the player
-- completes a heist. Mirrors the vanilla call site at
-- lib/states/missionendstate.lua:95-101 (success -> on_mission_completed,
-- failure -> on_mission_failed), but routes into managers.csr instead.
--
-- Rank gain on success is read from the vanilla tweak_data.crime_spree.missions
-- entry whose `.level.level_id` matches `managers.job:current_level_id()`.
-- Heists with no matching CS entry (modded maps, vanilla heists never on the CS
-- list) fall back to FALLBACK_RANK_GAIN. Slice 6 removed our vanilla-CS
-- activation, so `tweak_data.crime_spree.missions` is read as static config
-- only -- no dependency on `_global.current_mission` or `_mission_set`.
--
-- Failure path is a log-only stub for this slice. Roguelike end-on-death and
-- vanilla-style rank-regression are both deferred.

local FALLBACK_RANK_GAIN = 5

local function log_csr(msg)
	log("[CSR] " .. tostring(msg))
end

local function compute_rank_gain_for_current_heist()
	if not managers.job or not managers.job:current_job_id() then
		return FALLBACK_RANK_GAIN, "no current job"
	end
	local current_level_id = managers.job:current_level_id()
	if not current_level_id then
		return FALLBACK_RANK_GAIN, "no current level_id"
	end
	local cs_missions = tweak_data and tweak_data.crime_spree and tweak_data.crime_spree.missions
	if type(cs_missions) ~= "table" then
		return FALLBACK_RANK_GAIN, "tweak_data.crime_spree.missions missing"
	end
	for _, bucket in pairs(cs_missions) do
		if type(bucket) == "table" then
			for _, mission in pairs(bucket) do
				local lvl = mission and mission.level
				if lvl and lvl.level_id == current_level_id then
					return mission.add or FALLBACK_RANK_GAIN, "matched " .. tostring(mission.id)
				end
			end
		end
	end
	return FALLBACK_RANK_GAIN, "no CS entry for level_id=" .. tostring(current_level_id)
end

Hooks:PostHook(MissionEndState, "at_enter", "CSR_MissionLifecycle_AtEnter", function(self)
	if self._server_left or self._kicked then
		return
	end
	if not managers.csr or not managers.csr:is_active() then
		return
	end
	if self._success then
		local gain, source = compute_rank_gain_for_current_heist()
		managers.csr:progress_rank(gain)
		log_csr("mission completed: +" .. tostring(gain) .. " rank (source: " .. tostring(source) .. ")")
	else
		log_csr("mission failed (no rank change this slice)")
	end
end)

log_csr("csr_mission_lifecycle.lua loaded (Slice 7 wiring)")
