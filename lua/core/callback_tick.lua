-- CSR callback escape-hatch -- on_tick driver.
--
-- Part of the public extension API (CSR.register_item's on_apply/on_remove/
-- on_tick callbacks). on_apply/on_remove are fired by the manager's lifecycle
-- reconcile (CSRGameManager:reconcile_callback_items, wired in init). This file
-- supplies the throttled on_tick pulse: a PostHook on PlayerDamage:update
-- accumulates dt and calls tick_callback_items every TICK_INTERVAL seconds. So
-- on_tick is in-game only and never per-frame. Until an addon registers a
-- callback item, tick_callback_items loops an empty list -- the per-frame cost is
-- one add + one compare.
--
-- Lives in lua/core (a permanent mod.txt-hooked file), NOT lua/items: that folder
-- is dofile'd item-by-item by the auto-loader and this is API infrastructure, not
-- an item. Single hook target -> one chunk load, so the accumulator is a safe
-- file-local.

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
