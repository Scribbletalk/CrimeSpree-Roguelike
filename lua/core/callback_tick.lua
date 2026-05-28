-- Throttled on_tick pulse for items with an on_tick callback.
-- PostHook on PlayerDamage:update accumulates dt and fires every TICK_INTERVAL.

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
