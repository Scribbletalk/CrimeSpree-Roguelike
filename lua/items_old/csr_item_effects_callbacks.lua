-- CSR callback escape-hatch — on_tick driver.
--
-- on_apply / on_remove are fired by the manager's lifecycle reconcile
-- (CSRGameManager:reconcile_callback_items, wired to add/remove/run events in
-- init). This file supplies the throttled on_tick pulse: a PostHook on
-- PlayerDamage:update (the same reliable per-frame in-game pulse the regen
-- dispatcher rides) accumulates dt and calls tick_callback_items every
-- TICK_INTERVAL seconds. Consequences by design: on_tick is in-game only and
-- never per-frame (extension API design doc, migration step 4). The per-frame
-- cost here is one add + one compare until the interval elapses.
--
-- Single hook target (playerdamage) -> one chunk load, so the accumulator is a
-- safe file-local.

if not RequiredScript then
	return
end

local TICK_INTERVAL = 0.5

if PlayerDamage and not _G._CSR_ITEM_CALLBACK_TICK_HOOKED then
	_G._CSR_ITEM_CALLBACK_TICK_HOOKED = true

	local accum = 0
	Hooks:PostHook(PlayerDamage, "update", "CSR_CallbackTick", function(self, unit, t, dt)
		local mgr = managers.csr
		if not mgr or not mgr.tick_callback_items then
			return
		end
		accum = accum + dt
		if accum < TICK_INTERVAL then
			return
		end
		local elapsed = accum
		accum = 0
		mgr:tick_callback_items(elapsed)
	end)
end
