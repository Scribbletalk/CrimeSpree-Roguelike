-- Highland Mortuary (rvd1) delivers bags via ElementCarry operation="remove", bypassing LootManager:secure.
-- Result: HUD counter stays 0, cash stinger never plays. Fix: call loot:secure() in a PreHook before
-- vanilla deletes the unit. SCOPED TO rvd1 ONLY - globally promoting "remove" double-counts all bags.

if not RequiredScript or not ElementCarry then
	return
end

Hooks:PreHook(ElementCarry, "on_executed", "CSR_PromoteRemoveToSecure", function(self, instigator)
	if not self._values or self._values.operation ~= "remove" then
		return
	end
	-- Host-only: loot:secure() on a client just RPCs the host anyway; avoid double-counting.
	if not Network or not Network:is_server() then
		return
	end
	-- CSR runs STANDARD gamemode so crime_spree:is_active() is always false; use in_csr_heist().
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
