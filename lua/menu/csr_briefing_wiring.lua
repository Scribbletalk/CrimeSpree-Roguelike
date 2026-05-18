-- CSR mission-briefing routing — companion to csr_mission_briefing.lua.
--
-- Vanilla HUDManager:setup_mission_briefing_hud (lib/managers/hudmanagerpd2.lua)
-- is only two lines and has NO early-return: it unconditionally instantiates
-- HUDMissionBriefing:new(...). So the csr_missions_wiring.lua trick (PostHook a
-- vanilla fn that early-returns when not CSR, then build ours) does NOT apply
-- here — a PostHook would fire only AFTER vanilla already crashed inside
-- HUDMissionBriefing:init, and a PreHook cannot abort the original
-- (verified mods/base/req/core/Hooks.lua:252-286: the original is always
-- called; pre_call's return is used only if nothing else returns).
--
-- The only SuperBLT primitive that can swap the instantiated class without
-- letting the crashing vanilla path run is Hooks:OverrideFunction
-- (Hooks.lua:195) — it replaces the function while preserving any other mod's
-- pre/post hooks on it. The two-line vanilla body is reproduced verbatim for
-- every non-CSR path, so vanilla / vanilla Crime Spree / Skirmish are
-- byte-for-byte untouched.
--
-- No-leak gate (feedback_csr_only_no_vanilla_leak): we route to the fork ONLY
-- when the active job is the temporary "crime_spree" job AND
-- managers.crime_spree is NOT active. Vanilla Crime Spree always enables that
-- manager; CSR (Slice 6) deliberately never does — so this pair is a
-- run-scoped CSR-exclusive signal, NOT the persisted (leaky)
-- managers.csr:is_active() flag. Walked:
--   normal heist : current_job_id ~= "crime_spree"        -> vanilla
--   normal + stale csr is_active=true on disk : same      -> vanilla
--   vanilla CS   : job == "crime_spree", cs:is_active true -> vanilla
--   Skirmish     : job ~= "crime_spree"                    -> vanilla
--   CSR heist    : job == "crime_spree", cs:is_active false -> CSRMissionBriefing
-- Host and client are symmetric: both run setup_mission_briefing_hud locally
-- and both have the same job/manager state for a CSR heist, so both route to
-- the fork; neither sends nor depends on a network packet here.

if not RequiredScript then
	return
end

-- True only for a CSR-launched heist (the temporary crime_spree job with
-- vanilla Crime Spree NOT enabled). Defensive nil-guards: outside a heist
-- managers.job has no current job (current_job_id returns nil ~= "crime_spree"
-- -> false), so this is a safe no-op everywhere but a real CSR heist.
local function csr_briefing_active()
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

Hooks:OverrideFunction(HUDManager, "setup_mission_briefing_hud", function(self)
	local hud = managers.hud:script(IngameWaitingForPlayersState.GUI_FULLSCREEN)
	local workspace = self:workspace("fullscreen_workspace", "menu")

	if csr_briefing_active() and CSRMissionBriefing then
		self._hud_mission_briefing = CSRMissionBriefing:new(hud, workspace)
		log("[CSR] wiring: mission briefing built from CSRMissionBriefing")
		return
	end

	-- Verbatim vanilla HUDManager:setup_mission_briefing_hud body — every
	-- non-CSR path (normal heist / vanilla CS / Skirmish) is unchanged.
	self._hud_mission_briefing = HUDMissionBriefing:new(hud, workspace)
end)

log("[CSR] csr_briefing_wiring.lua loaded (setup_mission_briefing_hud routing)")
