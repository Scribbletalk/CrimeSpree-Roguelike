-- Crime Spree Roguelike - Promote ElementCarry "remove" to full secure on Highland Mortuary.
-- Highland Mortuary (Reservoir Dogs Day 1, level_id "rvd1") delivers bags via ElementCarry
-- operation="remove": the unit is set_slot(0)'d and vanishes, never going through
-- LootManager:secure. _global.secured stays empty -> HUD counter never updates, cash stinger
-- never plays, tab shows "0 bags secured". In CSR the player only plays one day, so we treat
-- remove == secure on this heist by calling managers.loot:secure() in a PreHook before vanilla
-- deletes the unit (routes through sync_secure_loot: HUD, stinger, _global.secured, achievements).
--
-- MUST stay scoped to rvd1 only: most heists use operation="remove" as part of their normal
-- secure flow, so promoting it globally double-counts every secured bag (gamebreaking exploit).

if not RequiredScript or not ElementCarry then
	return
end

Hooks:PreHook(ElementCarry, "on_executed", "CSR_PromoteRemoveToSecure", function(self, instigator)
	if not self._values or self._values.operation ~= "remove" then
		return
	end
	-- Mission elements fire on host and clients, but LootManager:secure on a client just RPCs the
	-- host. Let only the host trigger; its secure broadcasts via sync_secure_loot to everyone.
	if not Network or not Network:is_server() then
		return
	end
	-- CSR runs the STANDARD gamemode, so crime_spree:is_active() is always false here; gate on the
	-- CSR job/heist detector instead. level_id lives in Global.game_settings (current_job is temp).
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end
	local gs = Global and Global.game_settings
	if not gs or gs.level_id ~= "rvd1" then
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
