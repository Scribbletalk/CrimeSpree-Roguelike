-- CSR generic item-effect dispatcher - regen-on-tick side (PlayerDamage).
--
-- Sibling of csr_item_effects.lua (PlayerManager stat_mul),
-- csr_item_effects_weapon.lua (RaycastWeaponBase stat_mul) and
-- csr_item_effects_interaction.lua (BaseInteractionExt stat_mul). Split
-- because each is hooked on a different vanilla file path in mod.txt.
--
-- For every registered item whose effect is
--   { kind = "regen_max_hp_pct",
--     first_pct = <p>,   -- % of max HP per tick at 1 stack
--     max_pct = <p>,     -- hyperbolic asymptote as stacks -> infinity
--     interval = <s> }   -- seconds between ticks
-- this runs a per-item timer on PlayerDamage:update and, when its interval
-- elapses, heals the local player by max_hp * regen_pct(stacks).
--
-- Hyperbolic stacking: k = (max_pct - first_pct) / first_pct, then
-- regen_pct = max_pct * stacks / (stacks + k). At stacks=1 this returns
-- first_pct exactly; as stacks grows it asymptotes to max_pct. Same formula
-- the 6.2 shipping line used (CSR_BandaidRegenPct in core/base_modifier.lua).
--
-- Per-item timers live on self._csr_regen_timers, keyed by item.type, so a
-- future second regen item with a different interval ticks at its own cadence
-- without affecting band-aid. The map is initialised lazily on first update
-- so a PlayerDamage:init hook is unnecessary.
--
-- 6.3-alpha scope: the legacy "block_item_healing" CSR_Settings toggle and the
-- VHUDPlus / WFHud / PocoHud "regen cycle" buff events from
-- player_passives.lua are NOT ported -- both depend on systems
-- (CSR_Settings, HUD-compat) that are scoped out of this slice. They come
-- back when those subsystems port; this file's behaviour is then guarded /
-- accompanied at that point.

if not RequiredScript then
	return
end

local function csr_active_run()
	local mgr = managers and managers.csr
	return mgr and mgr.is_run_active and mgr:is_run_active()
end

if PlayerDamage and not _G._CSR_ITEM_EFFECTS_REGEN_HOOKED then
	_G._CSR_ITEM_EFFECTS_REGEN_HOOKED = true

	Hooks:PostHook(PlayerDamage, "update", "CSR_RegenTick", function(self, unit, t, dt)
		if not csr_active_run() then
			return
		end
		if self:is_downed() or self:dead() then
			return
		end

		local mgr = managers.csr
		if not mgr or not mgr.registered_items then
			return
		end

		self._csr_regen_timers = self._csr_regen_timers or {}

		local heal_total = 0
		local pid = mgr:local_peer_id()
		local max_hp_cached -- read once per tick, only if needed

		for _, item in ipairs(mgr:registered_items()) do
			local e = item.effect
			if e and e.kind == "regen_max_hp_pct" then
				local stacks = mgr:item_count(pid, item.type)
				if stacks > 0 then
					local interval = e.interval or 5
					local timer = (self._csr_regen_timers[item.type] or 0) + dt
					if timer >= interval then
						timer = timer - interval
						local first = e.first_pct or 0.01
						local maxp = e.max_pct or 0.20
						local k = (maxp - first) / first
						local pct = maxp * stacks / (stacks + k)
						max_hp_cached = max_hp_cached or self:_max_health()
						heal_total = heal_total + max_hp_cached * pct
					end
					self._csr_regen_timers[item.type] = timer
				else
					-- Player no longer owns this item-type; reset its timer so a
					-- re-pick doesn't immediately fire a partial cycle.
					self._csr_regen_timers[item.type] = 0
				end
			end
		end

		if heal_total > 0 then
			self:set_health(self:get_real_health() + heal_total)
		end
	end)
end
