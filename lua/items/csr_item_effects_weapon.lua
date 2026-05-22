-- CSR item-effect dispatcher — weapon-damage items.
--
-- Home for items whose effect is "more / conditional weapon damage", regardless
-- of which engine class implements them. Three concerns live here, so a modder
-- studying weapon-damage items reads ONE file instead of hunting several:
--   1. RaycastWeaponBase:_get_current_damage — flat damage stat_mul (Evidence Rounds)
--   2. CopDamage:damage_*  (PreHook) — first-hit-per-enemy amplify (Piece of Rebar)
--   3. CopDamage:damage_bullet (PreHook) — chance-to-instakill amplify (Bonnie's Lucky Chip)
-- Concerns 2 and 3 share a shape: a PreHook that conditionally multiplies
-- attack_data.damage before vanilla resolves the hit (a kill effect would PostHook
-- instead and lives in csr_item_effects_kill.lua).
--
-- This file is hooked on BOTH raycastweaponbase AND copdamage, so its chunk loads
-- twice (a SuperBLT script under N hook_ids loads N times, and file-locals are NOT
-- shared across loads). Evidence Rounds and Rebar keep no shared mutable file-local
-- (manager + a per-enemy CopDamage-instance flag). Bonnie's per-type cooldown IS a
-- file-local, which is still safe: its proc closure is installed exactly once (under
-- the copdamage load, _CSR_BONNIE_CHIP_HOOKED guard) and nothing else references it,
-- so there is no cross-load state to share. The only once-only work is hook
-- installation, each fenced by its own _G._CSR_*_HOOKED guard (which also stops a
-- hot-reload from compounding). Each block runs only when its class exists in that
-- load, so load order is irrelevant.

if not RequiredScript then
	return
end

-- ============ RaycastWeaponBase — damage stat_mul (Evidence Rounds) ============
--
-- Sibling of csr_item_effects_playerstats.lua (PlayerManager-side). Scales _get_current_damage
-- by (1 + managers.csr:sum_stat_mul("damage")) — the established CSR damage
-- convention (legacy Evidence Rounds did damage*(1+bonus)). The summing logic lives
-- once on the manager (registry-indexed by effect.kind). Because stat="damage" is
-- ALL damage, csr_item_effects_melee.lua adds the same bonus to melee swings.
--
-- Critical Rule #1 exception: _get_current_damage returns a value (PostHook can't
-- carry it). Raw chain wrap per the CSR return-value convention
-- (feedback_rule1_return_value_exception).
if RaycastWeaponBase and not _G._CSR_ITEM_EFFECTS_WEAPON_HOOKED then
	_G._CSR_ITEM_EFFECTS_WEAPON_HOOKED = true

	local orig_get_current_damage = RaycastWeaponBase._get_current_damage
	if orig_get_current_damage then
		function RaycastWeaponBase:_get_current_damage(...)
			local damage = orig_get_current_damage(self, ...)
			if type(damage) ~= "number" then
				return damage
			end
			local mgr = managers.csr
			local bonus = mgr and mgr:sum_stat_mul("damage") or 0
			if bonus ~= 0 then
				damage = damage * (1 + bonus)
			end
			return damage
		end
	end
end

-- ============ CopDamage — first_hit_damage (Piece of Rebar) ============
--
-- effect = { kind = "first_hit_damage", base_bonus, extra_bonus }. PreHook on the
-- four CopDamage damage_* paths: the FIRST time the local player damages a given
-- enemy, the attack's damage is multiplied by (1 + total_bonus). A per-enemy flag
-- (cop._csr_rebar_hit) makes it once-per-unit; the flag rides on the CopDamage
-- instance and is GC'd with the unit, so no global hit-table or death-cleanup hook
-- is needed (same convention as the kill foundation's cop._csr_kill_handled).
--
-- MP: amplifying attack_data.damage inside a PreHook on the ATTACKER's local
-- damage_* call routes the higher damage through vanilla's own networking — the
-- proven path Bonnie's Lucky Chip uses. The is_local_player attacker gate means
-- each peer amplifies only its own first-hits, and the host never re-amplifies a
-- client's already-amplified hit (on the host the attacker is not is_local_player).
--
-- Fully composable: every owned first_hit_damage item contributes
-- base_bonus + (stacks-1)*extra_bonus, summed. A single item reduces to the 6.2 line.

-- Summed first-hit damage bonus across owned first_hit_damage items (0 if none).
local function rebar_total_bonus(mgr, pid)
	local items = mgr:items_of_kind("first_hit_damage")
	local total = 0
	for i = 1, #items do
		local e = items[i].effect
		local stacks = mgr:item_count(pid, items[i].type)
		if stacks > 0 then
			total = total + (e.base_bonus or 0) + (stacks - 1) * (e.extra_bonus or 0)
		end
	end
	return total
end

local function rebar_apply_first_hit(cop, attack_data)
	local mgr = managers and managers.csr
	if not mgr or not mgr.is_run_active or not mgr:is_run_active() or not mgr.items_of_kind then
		return
	end
	if not attack_data or not attack_data.damage then
		return
	end
	-- Local-player attacker only: the host resolves bots' and remote peers' damage
	-- too, and without this their first hit on an enemy would consume the buff and
	-- mis-scale it with the host's own stacks.
	local au = attack_data.attacker_unit
	if not au or not au:base() or au:base().is_local_player ~= true then
		return
	end
	-- Once per enemy unit (flag lives on the CopDamage instance).
	if cop._csr_rebar_hit then
		return
	end

	local bonus = rebar_total_bonus(mgr, mgr:local_peer_id())
	if bonus <= 0 then
		return
	end

	cop._csr_rebar_hit = true
	attack_data.damage = attack_data.damage * (1 + bonus)
	if mgr:debug_enabled() then
		mgr:debug_log(string.format("rebar first-hit +%.0f%% damage", bonus * 100))
	end
end

if CopDamage and not _G._CSR_REBAR_HOOKED then
	_G._CSR_REBAR_HOOKED = true

	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_Rebar_Bullet", rebar_apply_first_hit)
	if CopDamage.damage_melee then
		Hooks:PreHook(CopDamage, "damage_melee", "CSR_Rebar_Melee", rebar_apply_first_hit)
	end
	if CopDamage.damage_dot then
		Hooks:PreHook(CopDamage, "damage_dot", "CSR_Rebar_Dot", rebar_apply_first_hit)
	end
	if CopDamage.damage_explosion then
		Hooks:PreHook(CopDamage, "damage_explosion", "CSR_Rebar_Explosion", rebar_apply_first_hit)
	end
end

-- ============ CopDamage — instakill_on_hit (Bonnie's Lucky Chip) ============
--
-- effect = { kind = "instakill_on_hit", chance, cooldown }. PreHook on
-- CopDamage:damage_bullet: against a valid enemy, each owned instakill_on_hit item
-- off its own cooldown rolls 1-(1-chance)^stacks; if ANY item wins, the attack's
-- damage is amplified so the ORIGINAL damage_bullet lands the kill. That routes the
-- death through vanilla MP networking (a client RPCs the host, the host syncs the
-- death back); a local self:die() on a client would desync. Each item's cooldown is
-- armed on EVERY eligible attempt (win or lose) so high-RPM weapons can't spam rolls.
--
-- Fully composable: any number of instakill_on_hit items roll independently on
-- their own chance + cooldown. A single item reduces to the legacy 6.2 behaviour.
--
-- DEFERRED: the 6.2 item also played a positional proc sound (broadcast to peers)
-- and a HUD cooldown pip. Both ride on subsystems not yet ported (CSR_PlaySound /
-- HUD-compat shims), so they are omitted; the instakill itself is complete.

-- [item.type] = game time of that item's last roll attempt. File-local despite the
-- two-load file: the proc closure is installed exactly once (copdamage load) and
-- nothing else reads this table, so there is no cross-load state to share.
local bonnie_cooldowns = {}

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
			local last = bonnie_cooldowns[item.type]
			if not last or now - last >= (e.cooldown or 1.5) then
				bonnie_cooldowns[item.type] = now -- arm on every eligible attempt
				-- Independent roll per stack: 1 - (1 - chance)^stacks.
				local total_chance = 1 - (1 - (e.chance or 0.10)) ^ stacks
				if math.random() <= total_chance then
					procced = true
				end
			end
		end
	end

	if procced then
		-- Amplify so the original damage_bullet kills the enemy (vanilla clamps the
		-- applied damage to self._health internally, so the value just needs to
		-- exceed current health).
		attack_data.damage = (cop._health or 1) * 10
		if mgr:debug_enabled() then
			mgr:debug_log("bonnie_chip INSTAKILL proc")
		end
	end
end

if CopDamage and not _G._CSR_BONNIE_CHIP_HOOKED then
	_G._CSR_BONNIE_CHIP_HOOKED = true
	Hooks:PreHook(CopDamage, "damage_bullet", "CSR_BonnieChip_Pre", bonnie_chip_try_proc)
end
