-- CSR item-effect dispatcher - kill events (CopDamage).
--
-- PostHooks the four damage paths that can land a kill, computes "local player
-- just killed an enemy" once per corpse, then dispatches to every kill-driven
-- effect kind. First kind: heal_on_kill (Pink Slip). Future kill items
-- (drill-timer cut, fire-rate streak, instakill) hook in here too.

if not RequiredScript then
	return
end

local function csr_run_active()
	local mgr = managers and managers.csr
	return mgr and mgr.is_run_active and mgr:is_run_active()
end

-- Sum of heal (internal HP units) across owned heal_on_kill items. Per-kill
-- heal = max_hp*base_pct + (base_flat + (stacks-1)*extra_flat) display HP, the
-- flat part divided by the display scale (vanilla = 10) to reach internal units.
local function csr_kill_heal_internal(mgr, pid, dmg)
	local scale = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local max_hp = dmg:_max_health()
	local total = 0
	local items = mgr:items_of_kind("heal_on_kill")
	for i = 1, #items do
		local e = items[i].effect
		local stacks = mgr:item_count(pid, items[i].type)
		if stacks > 0 then
			local display = max_hp * scale * (e.base_pct or 0) + (e.base_flat or 0) + (stacks - 1) * (e.extra_flat or 0)
			total = total + display / scale
		end
	end
	return total
end

-- Shared handler for every damage_* PostHook. cop = the CopDamage being hit.
local function on_enemy_damage(cop, attack_data)
	if not csr_run_active() then
		return
	end
	if not cop._dead or cop._csr_kill_handled then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	cop._csr_kill_handled = true

	local mgr = managers.csr
	if not mgr or not mgr.items_of_kind then
		return
	end
	local pu = managers.player and managers.player:player_unit()
	if not pu or not alive(pu) then
		return
	end
	local dmg = pu:character_damage()
	if not dmg then
		return
	end

	local heal = csr_kill_heal_internal(mgr, mgr:local_peer_id(), dmg)
	if heal > 0 then
		dmg:set_health(dmg:get_real_health() + heal)
		if mgr:debug_enabled() then
			mgr:debug_log(string.format("pink_slip heal +%.2f (internal) on kill", heal))
		end
	end
end

if CopDamage and not _G._CSR_ITEM_EFFECTS_KILL_HOOKED then
	_G._CSR_ITEM_EFFECTS_KILL_HOOKED = true

	Hooks:PostHook(CopDamage, "damage_bullet", "CSR_KillEvent_Bullet", on_enemy_damage)
	if CopDamage.damage_melee then
		Hooks:PostHook(CopDamage, "damage_melee", "CSR_KillEvent_Melee", on_enemy_damage)
	end
	if CopDamage.damage_explosion then
		Hooks:PostHook(CopDamage, "damage_explosion", "CSR_KillEvent_Explosion", on_enemy_damage)
	end
	if CopDamage.damage_dot then
		Hooks:PostHook(CopDamage, "damage_dot", "CSR_KillEvent_Dot", on_enemy_damage)
	end
end
