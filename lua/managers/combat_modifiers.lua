-- CSR combat-modifier application (in-game trigger).
--
-- Applies the active LOUD modifiers (managers.csr:active_modifiers("loud")) as
-- real engine effects when a CSR heist starts, routing them through the vanilla
-- ModifiersManager (managers.modifiers) exactly as vanilla Crime Spree does in
-- CrimeSpreeManager:_setup_modifiers -- the ModifierX classes are already loaded
-- by lib/managers/modifiersmanager. All the aggregation + the host/SP gate live
-- in managers.csr:apply_modifiers; this file is only the trigger.
--
-- Hook point: IngameWaitingForPlayersState:at_enter -- fires once per heist
-- after the level + managers (incl. the freshly-rebuilt managers.modifiers, see
-- setup.lua) are up, before the assault. Vanilla's own _setup_modifiers no-ops
-- for a CSR heist (it early-returns on managers.crime_spree:is_active() == false),
-- and our modifiers go in a separate "csr" category, so the two never collide.
--
-- Gated to CSR heists by the run-scoped job signal (current_job_id ==
-- "crime_spree" with vanilla CS NOT active) -- byte-identical to
-- mission_lifecycle.lua / briefing_wiring.lua, the verified CSR-exclusive signal
-- that does NOT leak into vanilla heists the way the persisted is_active() flag
-- does (feedback_csr_only_no_vanilla_leak).

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

if IngameWaitingForPlayersState and not _G._CSR_COMBAT_MODIFIERS_HOOKED then
	_G._CSR_COMBAT_MODIFIERS_HOOKED = true

	Hooks:PostHook(IngameWaitingForPlayersState, "at_enter", "CSR_ApplyCombatModifiers", function(self)
		if not managers.csr or not managers.csr.apply_modifiers then
			return
		end
		if not csr_heist_active() then
			return
		end
		managers.csr:apply_modifiers()
	end)
end

csr_log("[CSR] combat_modifiers.lua loaded (IngameWaitingForPlayersState modifier application)")
