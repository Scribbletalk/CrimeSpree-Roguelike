-- Crime Spree Roguelike - Promote ElementCarry "remove" to full secure on Highland Mortuary.
-- Highland Mortuary (Reservoir Dogs Day 1, level_id "rvd1") delivers bags by calling
-- ElementCarry with operation="remove" — the unit is set_slot(0)'d and vanishes, never going
-- through LootManager:secure. _global.secured stays empty, the HUD bag counter never updates,
-- the cash stinger never plays, and the tab menu shows "0 bags secured".
-- In Crime Spree the player only plays one day, so we treat remove == secure on this heist:
-- we call managers.loot:secure(...) from a PreHook before vanilla deletes the unit. That
-- routes through the normal sync_secure_loot path (HUD update, stinger sound, _global.secured
-- entry, achievement triggers) so the player gets identical feedback to a vanilla secure.
--
-- IMPORTANT: This MUST stay scoped to rvd1 only. Most other heists also use
-- ElementCarry operation="remove" as part of their normal secure flow, so promoting it
-- globally double-counts every secured bag (1 secure registers as 2 — confirmed
-- gamebreaking exploit on Lost in Transit, Go Bank, Border Crystal, etc.).

if not RequiredScript or not ElementCarry then
	return
end

Hooks:PreHook(ElementCarry, "on_executed", "CSR_PromoteRemoveToSecure", function(self, instigator)
	if not self._values or self._values.operation ~= "remove" then
		return
	end
	-- Mission elements fire on both host and clients (client_on_executed → on_executed),
	-- but LootManager:secure on a client just RPCs the host. Let only the host trigger,
	-- since the host's secure broadcasts via sync_secure_loot to everyone.
	if not Network or not Network:is_server() then
		return
	end
	-- Use is_active() OR in_progress() to survive transient flickers
	-- (e.g. Golden Grin civilian → mask transition).
	local cs = managers and managers.crime_spree
	local in_cs = cs and (cs:is_active() or (cs.in_progress and cs:in_progress()))
	if not in_cs then
		return
	end
	-- Highland Mortuary (Reservoir Dogs Day 1) only. Other heists use "remove" as part
	-- of their normal secure flow; promoting there double-counts bags.
	local level_id = managers.job and managers.job.current_level_id and managers.job:current_level_id()
	if level_id ~= "rvd1" then
		return
	end
	if not alive(instigator) then
		return
	end
	local carry_ext = instigator:carry_data()
	if not carry_ext then
		return
	end
	local carry_id = carry_ext:carry_id()
	if not carry_id then
		return
	end
	local carry_data = tweak_data.carry[carry_id]
	if not carry_data or tweak_data.carry.small_loot[carry_id] or carry_data.is_vehicle then
		return
	end
	local mult = carry_ext.multiplier and carry_ext:multiplier() or 1
	local peer_id = carry_ext.latest_peer_id and carry_ext:latest_peer_id() or nil
	managers.loot:secure(carry_id, mult, false, peer_id)
end)
