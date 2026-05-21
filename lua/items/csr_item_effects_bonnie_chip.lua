-- CSR item-effect dispatcher — instakill_on_hit (chance to instakill on a bullet hit).
--
-- effect = { kind = "instakill_on_hit", chance, cooldown }. PreHook on
-- CopDamage:damage_bullet: against a valid enemy, each owned instakill_on_hit
-- item that is off its own cooldown rolls 1-(1-chance)^stacks; if ANY item wins,
-- the attack's damage is amplified so the ORIGINAL damage_bullet lands the kill.
-- That routes the death through vanilla MP networking (a client RPCs the host,
-- the host syncs the death back to every peer); a local self:die() on a client
-- would leave the host's master copy alive and desync. Each item's cooldown is
-- armed on EVERY attempt where it is eligible (win or lose) so high-RPM weapons
-- can't spam rolls.
--
-- Fully composable: any number of instakill_on_hit items (CSR's Bonnie's Lucky
-- Chip plus addon items) roll independently with their own chance and throttle
-- on their own cooldown. For a single item this reduces exactly to the legacy
-- 6.2 behaviour.
--
-- Single hook target (copdamage) -> one chunk load, so the per-type cooldown
-- clocks are safe as a file-local (contrast Overkill Rush, which spans two
-- targets and must park its state on the manager).
--
-- DEFERRED: the 6.2 item also played a positional proc sound (broadcast to
-- peers) and pushed a HUD cooldown pip. Both ride on subsystems not yet ported
-- to 6.3 (CSR_PlaySound / the HUD-compat event shims), so they are intentionally
-- omitted; the instakill itself is complete. Re-add the sound PostHook when the
-- sound subsystem lands.

if not RequiredScript then
	return
end

-- [item.type] = game time of that item's last roll attempt. File-local is safe
-- (single hook target -> single chunk load).
local cooldowns = {}

local function bonnie_chip_try_proc(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() or not mgr.items_of_kind then
		return
	end
	local au = attack_data and attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	-- Target must be a live, non-converted enemy.
	if not cop._unit or not alive(cop._unit) or cop._dead or cop._converted then
		return
	end
	-- Skip civilians and scripted NPCs (npc_*) — instakill is enemy-only.
	local base = cop._unit:base()
	local tweak_table = (base and base._tweak_table) or ""
	local is_npc = type(tweak_table) == "string" and tweak_table:sub(1, 4) == "npc_"
	if CopDamage.is_civilian(tweak_table) or is_npc then
		return
	end

	local items = mgr:items_of_kind("instakill_on_hit")
	if #items == 0 then
		return
	end
	local game = TimerManager and TimerManager:game()
	local now = game and game:time()
	if not now then
		return
	end
	local pid = mgr:local_peer_id()
	local procced = false
	for i = 1, #items do
		local item = items[i]
		local stacks = mgr:item_count(pid, item.type)
		if stacks > 0 then
			local e = item.effect
			local last = cooldowns[item.type]
			if not last or now - last >= (e.cooldown or 1.5) then
				cooldowns[item.type] = now -- arm on every eligible attempt
				-- Independent roll per stack: 1 - (1 - chance)^stacks.
				local total_chance = 1 - (1 - (e.chance or 0.10)) ^ stacks
				if math.random() <= total_chance then
					procced = true
				end
			end
		end
	end

	if procced then
		-- Amplify so the original damage_bullet kills the enemy (vanilla clamps
		-- the applied damage to self._health internally, so the value just needs
		-- to exceed current health).
		attack_data.damage = (cop._health or 1) * 10
	end
end

if CopDamage and not _G._CSR_BONNIE_CHIP_HOOKED then
	_G._CSR_BONNIE_CHIP_HOOKED = true
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Pre", bonnie_chip_try_proc)
end
