-- Half-a-Glass (common) - Gage package pickup refills ammo and raises max ammo cap.
-- Each pickup grows max by (first% + extra%*(stacks-1)) * pickup_count, then refills refill% of new max.
-- MP: host applies via sync_pickup (own pickup only); clients apply via _pickup hook.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local MAX_AMMO_FIRST = 0.04
local MAX_AMMO_EXTRA = 0.02
local REFILL = 0.15

-- Per-mission state; reset on new player unit.
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

			-- Underbarrels are separate WeaponAmmo gadgets.
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

-- Per-package flag rides on the GageAssignmentBase, GC'd with it.
local function claim_and_apply(gage)
	if gage._csr_hag_done then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
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
	icon_scale = 1.0,
	loc_macros = {
		refill_pct = string.format("%g", REFILL * 100),
		first_pct = string.format("%g", MAX_AMMO_FIRST * 100),
		extra_pct = string.format("%g", MAX_AMMO_EXTRA * 100),
	},

	hooks = {
		["lib/units/pickups/gageassignmentbase"] = function()
			if _G._CSR_HALF_A_GLASS_HOOKED then
				return
			end
			_G._CSR_HALF_A_GLASS_HOOKED = true

			Hooks:PostHook(GageAssignmentBase, "sync_pickup", "CSR_HalfAGlass_SyncPickup", function(self, peer)
				-- Host's own pickup only; non-nil peer = remote client relay, clients use _pickup below.
				if Network:is_client() or peer ~= nil then
					return
				end
				if self._picked_up then
					claim_and_apply(self)
				end
			end)

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
