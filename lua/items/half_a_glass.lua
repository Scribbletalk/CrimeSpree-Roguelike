-- Half-a-Glass (common) -- picking up a Gage package refills ammo and raises max ammo.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Core mechanic ported 1:1 from 6.2 (units/pickups/halfaglass_pickup.lua). The
-- 6.2 proximity-CONTOUR highlight on nearby Gage packages is intentionally NOT
-- ported: it needs the custom CONTOUR material_config DB entries that lived in
-- seed_manager.lua (un-ported in U1). The item works fully without it, and the
-- effect text never mentioned it.
--
-- On each Gage package pickup, for primary + secondary (+ an attached
-- underbarrel): raise max ammo by first% + (stacks-1)*extra%, computed from the
-- CAPTURED base max and multiplied by the running pickup count (so repeated
-- pickups stack), then instantly refill refill% of the new max. Values mirror
-- the 6.2 constants (first 0.04 / extra 0.02 / refill 0.15).
--
-- MP authority (mirrors 6.2): the host (incl. SP) handles every pickup via
-- sync_pickup; a picking CLIENT applies via _pickup (the host's own pickup goes
-- _pickup -> sync_pickup, so sync_pickup carries SP). Each peer applies to its
-- OWN local player (local-player-scoped, like every U1 item). A per-package flag
-- (self._csr_hag_done) keeps it to exactly one application per package even if
-- both hooks observe the same pickup. Full MP-sync is the parked slice.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local MAX_AMMO_FIRST = 0.04
local MAX_AMMO_EXTRA = 0.02
local REFILL = 0.15

-- Per-mission state, reset on each game load (this file is dofile'd once per
-- load, so its chunk locals are fresh per session). base_ammo captures the
-- original max ammo per weapon slot so the bonus is always from base, not
-- compounding off an already-boosted max.
local base_ammo = {}
local pickups = 0
local last_pu_key = nil

local function apply_ammo_bonus(stacks)
	local pu = managers.player and managers.player:player_unit()
	if not pu or not alive(pu) then
		return
	end
	local inv = pu:inventory()
	if not inv then
		return
	end

	-- New mission = new player unit: reset the per-mission accumulators so the
	-- max-ammo boost starts fresh ("for the rest of the mission", not the run).
	local pu_key = pu:key()
	if pu_key ~= last_pu_key then
		base_ammo = {}
		pickups = 0
		last_pu_key = pu_key
	end

	pickups = pickups + 1
	local pct = MAX_AMMO_FIRST + (stacks - 1) * MAX_AMMO_EXTRA

	for i = 1, 2 do
		pcall(function()
			local weapon_unit = inv:unit_by_selection(i)
			if not weapon_unit or not alive(weapon_unit) then
				return
			end
			local base = weapon_unit:base()
			if not base or not base.get_ammo_max then
				return
			end

			if not base_ammo[i] then
				base_ammo[i] = base:get_ammo_max()
			end
			local base_max = base_ammo[i]
			if not base_max or base_max <= 0 then
				return
			end

			local new_max = base_max + math.ceil(base_max * pct * pickups)
			base:set_ammo_max(new_max)
			base:add_ammo_to_pool(math.ceil(new_max * REFILL), i)

			-- Underbarrel weapons are separate WeaponAmmo gadgets; the main
			-- weapon's ammo calls don't touch them.
			if managers.weapon_factory and base._parts then
				local ub_part = managers.weapon_factory:get_part_from_weapon_by_type("underbarrel", base._parts)
				if ub_part and ub_part.unit and alive(ub_part.unit) then
					local ub_base = ub_part.unit:base()
					local ub_ammo = ub_base and ub_base.ammo_base and ub_base:ammo_base()
					if ub_ammo then
						local ub_key = "ub_" .. i
						if not base_ammo[ub_key] then
							base_ammo[ub_key] = ub_ammo:get_ammo_max()
						end
						local ub_base_max = base_ammo[ub_key]
						if ub_base_max and ub_base_max > 0 then
							local ub_new_max = ub_base_max + math.ceil(ub_base_max * pct * pickups)
							ub_ammo:set_ammo_max(ub_new_max)
							local ub_refill = math.ceil(ub_new_max * REFILL)
							ub_ammo:set_ammo_total(math.min(ub_ammo:get_ammo_total() + ub_refill, ub_new_max))
						end
					end
				end
			end
		end)
	end
end

-- Claim the package once and apply (run-active + owned gated). The per-package
-- flag rides on the GageAssignmentBase instance and is GC'd with it.
local function claim_and_apply(gage)
	if gage._csr_hag_done then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
		return
	end
	local stacks = mgr:owned("half_a_glass")
	if stacks <= 0 then
		return
	end
	gage._csr_hag_done = true
	apply_ammo_bonus(stacks)
end

_G.CSR.register_item({
	type = "half_a_glass",
	rarity = "common",
	name = "csr_logbook_half_a_glass_name",
	desc = "csr_item_half_a_glass_desc",
	full_desc = "csr_logbook_half_a_glass_effect",
	notes = "csr_logbook_half_a_glass_notes",
	icon = "csr_half_a_glass",

	hooks = {
		["lib/units/pickups/gageassignmentbase"] = function()
			if _G._CSR_HALF_A_GLASS_HOOKED then
				return
			end
			_G._CSR_HALF_A_GLASS_HOOKED = true

			-- Host (incl. SP): runs for every pickup; _picked_up is true only on a
			-- valid one (set inside vanilla sync_pickup before our PostHook).
			Hooks:PostHook(GageAssignmentBase, "sync_pickup", "CSR_HalfAGlass_SyncPickup", function(self)
				if self._picked_up then
					claim_and_apply(self)
				end
			end)

			-- Picking CLIENT only (the host's own pickup is carried by sync_pickup
			-- above, which _pickup calls directly when Network:is_server()).
			Hooks:PostHook(GageAssignmentBase, "_pickup", "CSR_HalfAGlass_Pickup", function(self, unit)
				if not Network:is_client() then
					return
				end
				local is_local = false
				pcall(function()
					is_local = unit and alive(unit) and unit:base() and unit:base().is_local_player == true
				end)
				if is_local then
					claim_and_apply(self)
				end
			end)
		end,
	},
})
