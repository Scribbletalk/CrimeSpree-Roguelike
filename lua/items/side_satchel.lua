-- Side Satchel (wildcard, passive) — DOUBLES the carry cap of mission specials
-- (C4, keycards, planks…) and +20% move speed while carrying a loot bag. Blacklist
-- excludes items where doubling is meaningless. No cooldown/dispatcher; all effects
-- gate on owns_side_satchel(). Local-player-scoped (remote owners bump locally).

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local CARRY_SPEED_MULT = 1.20 -- +20% movement speed while carrying a bag

-- Doubling is meaningless for these (one tool / already-large vanilla cap).
local BLACKLIST = {
	pku_crowbar = true,
	pku_saw = true,
	cable_tie = true,
}

-- Batched specials whose vanilla quantity is nil — without a backfill the cap
-- formula collapses to 1 and add_special skips its math block. Force-include them.
local FORCE_INCLUDE = {
	planks = true,
	boards = true,
	gas = true,
}

-- Per-heist interaction-block overrides: lift a blacklisted item's pickup block
-- on a specific level where it's genuinely needed twice (Meltdown crowbars).
local HEIST_BLOCK_OVERRIDES = {
	crowbar = { shoutout_raid = true },
	crowbar_stack = { shoutout_raid = true },
}

-- Specials whose vanilla equipment.quantity is nil; backfill quantity=1 so the
-- add_special math branch runs and the doubled cap is reachable.
local QUANTITY_PATCH = {
	planks = true,
	boards = true,
	crowbar = true,
	crowbar_stack = true,
	gas = true,
	bank_manager_key = true,
	president_key = true,
	help_keycard = true,
	c_keys = true,
}

local _quantity_patched = false
local function ensure_quantity_patched()
	if _quantity_patched then
		return
	end
	if not tweak_data or not tweak_data.equipments or not tweak_data.equipments.specials then
		return
	end
	for name, _ in pairs(QUANTITY_PATCH) do
		local eq = tweak_data.equipments.specials[name]
		if eq and not eq.quantity then
			eq.quantity = 1
		end
	end
	_quantity_patched = true
end

local function owns_side_satchel()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return false
	end
	return mgr:owned("side_satchel") > 0
end

local function eligible_for_bump(equipment_name, equipment)
	if not equipment_name or not equipment then
		return false
	end
	return not BLACKLIST[equipment_name]
end

-- Vanilla cap = (max_quantity or quantity or 1). Adding that same value DOUBLES it.
local function doubling_extra(equipment)
	return equipment.max_quantity or equipment.quantity or 1
end

_G.CSR.register_item({
	type = "side_satchel",
	rarity = "wildcard",
	name = "csr_logbook_side_satchel_name",
	desc = "csr_item_side_satchel_desc",
	full_desc = "csr_logbook_side_satchel_effect",
	notes = "csr_logbook_side_satchel_notes",
	icon = "csr_side_satchel",
	icon_scale = 1.0,

	-- $carry_speed_pct fills csr_logbook_side_satchel_effect.
	loc_macros = {
		carry_speed_pct = string.format("%g", (CARRY_SPEED_MULT - 1) * 100),
	},

	hooks = {
		["lib/managers/playermanager"] = function()
			if _G._CSR_SIDE_SATCHEL_PM_HOOKED then
				return
			end
			_G._CSR_SIDE_SATCHEL_PM_HOOKED = true

			-- 1. Cap math: add a doubling extra to vanilla's (max or qty or 1) + extra.
			local original_equipped_upgrade_value = PlayerManager._equipped_upgrade_value
			if original_equipped_upgrade_value then
				function PlayerManager:_equipped_upgrade_value(equipment, ...)
					ensure_quantity_patched()
					local base = original_equipped_upgrade_value(self, equipment, ...)
					if type(equipment) ~= "table" then
						return base
					end
					-- Reverse-lookup the equipment_name from the table ref.
					local equipment_name = nil
					if tweak_data and tweak_data.equipments and tweak_data.equipments.specials then
						for k, v in pairs(tweak_data.equipments.specials) do
							if v == equipment then
								equipment_name = k
								break
							end
						end
					end
					if not eligible_for_bump(equipment_name, equipment) or not owns_side_satchel() then
						return base
					end
					return (base or 0) + doubling_extra(equipment)
				end
			end

			-- 2. +20% movement speed while carrying a loot bag. movement_speed_multiplier
			-- is the single funnel sprint/walk/crouch/strafe all read from.
			local original_speed_mul = PlayerManager.movement_speed_multiplier
			if original_speed_mul then
				function PlayerManager:movement_speed_multiplier(...)
					local mul = original_speed_mul(self, ...)
					if not owns_side_satchel() then
						return mul
					end
					-- get_my_carry_data() returns a TABLE while carrying; literal `true`
					-- only in the offline/no-session edge case. Type-check guards it.
					local carry = self.get_my_carry_data and self:get_my_carry_data()
					if type(carry) ~= "table" then
						return mul
					end
					return mul + (CARRY_SPEED_MULT - 1)
				end
			end

			-- 3. STORE double, don't DUPE on pickup. Pin params.amount to equipment.quantity
			-- so a single pickup grants vanilla qty; the doubled cap is reached by picking
			-- up twice. Skips transfer / dropped_out (stash + respawn-drop paths).
			local original_add_special = PlayerManager.add_special
			if original_add_special then
				function PlayerManager:add_special(params)
					if params and not params.transfer and not params.dropped_out and owns_side_satchel() then
						local name = params.equipment or params.name
						if name then
							ensure_quantity_patched()
							local eq = tweak_data
								and tweak_data.equipments
								and tweak_data.equipments.specials
								and tweak_data.equipments.specials[name]
							if eq and eq.quantity and eligible_for_bump(name, eq) then
								if not params.amount or params.amount > eq.quantity then
									params.amount = eq.quantity
								end
							end
						end
					end
					return original_add_special(self, params)
				end
			end
		end,

		["lib/units/interactions/interactionext"] = function()
			if _G._CSR_SIDE_SATCHEL_INT_HOOKED then
				return
			end
			_G._CSR_SIDE_SATCHEL_INT_HOOKED = true

			-- Vanilla blocks a stash pickup once you hold any of the special at all,
			-- making the +1 cap room unreachable. Temporarily clear the block during
			-- the can_select / can_interact checks when we're under the doubled cap.
			local function pickup_should_unblock(self)
				if not owns_side_satchel() then
					return nil
				end
				local td = self._tweak_data
				if not td or not td.special_equipment_block then
					return nil
				end
				-- Only the block-only pickup interaction (no special_equipment field =
				-- consume). The barricade interaction has both — don't touch it.
				if td.special_equipment then
					return nil
				end
				local blocker = td.special_equipment_block
				if type(blocker) == "table" then
					blocker = blocker[1]
				end
				local lvl = managers.job and managers.job.current_level_id and managers.job:current_level_id()
				local allowed = FORCE_INCLUDE[blocker] == true
				if not allowed then
					local overrides = HEIST_BLOCK_OVERRIDES[blocker]
					if overrides then
						allowed = (lvl and overrides[lvl] == true) or false
					end
				end
				if not allowed then
					return nil
				end
				ensure_quantity_patched()
				local eq = tweak_data and tweak_data.equipments and tweak_data.equipments.specials[blocker]
				if not eq then
					return nil
				end
				local cap = 2 * (eq.max_quantity or eq.quantity or 1)
				local owned = managers.player._equipment.specials[blocker]
				local current = 0
				if owned and owned.amount then
					current = Application:digest_value(owned.amount, false) or 0
				end
				if current >= cap then
					return nil
				end
				return td
			end

			local function with_unblock(self, fn, ...)
				local td = pickup_should_unblock(self)
				if not td then
					return fn(self, ...)
				end
				local saved = td.special_equipment_block
				td.special_equipment_block = nil
				local ok, a, b = pcall(fn, self, ...)
				td.special_equipment_block = saved
				if not ok then
					error(a)
				end
				return a, b
			end

			local original_can_select = BaseInteractionExt.can_select
			function BaseInteractionExt:can_select(...)
				return with_unblock(self, original_can_select, ...)
			end

			local original_can_interact = BaseInteractionExt.can_interact
			function BaseInteractionExt:can_interact(...)
				return with_unblock(self, original_can_interact, ...)
			end

			if MultipleChoiceInteractionExt then
				local original_mc_can_interact = MultipleChoiceInteractionExt.can_interact
				function MultipleChoiceInteractionExt:can_interact(...)
					return with_unblock(self, original_mc_can_interact, ...)
				end
			end

			-- _interact_blocked is the third gate (re-checked at interact_start). Force-
			-- unblock under the doubled cap for heist-override specials only.
			if SpecialEquipmentInteractionExt then
				local original_intblock = SpecialEquipmentInteractionExt._interact_blocked
				function SpecialEquipmentInteractionExt:_interact_blocked(player)
					local blocked, skip_hint, custom_hint = original_intblock(self, player)
					if not blocked then
						return blocked, skip_hint, custom_hint
					end
					local eq_name = self._special_equipment
					if not eq_name then
						return blocked, skip_hint, custom_hint
					end
					local overrides = HEIST_BLOCK_OVERRIDES[eq_name]
					if not overrides then
						return blocked, skip_hint, custom_hint
					end
					local lvl = managers.job and managers.job.current_level_id and managers.job:current_level_id()
					if not (lvl and overrides[lvl] == true) or not owns_side_satchel() then
						return blocked, skip_hint, custom_hint
					end
					local eq = tweak_data
						and tweak_data.equipments
						and tweak_data.equipments.specials
						and tweak_data.equipments.specials[eq_name]
					if not eq then
						return blocked, skip_hint, custom_hint
					end
					local cap = 2 * (eq.max_quantity or eq.quantity or 1)
					local owned = managers.player
						and managers.player._equipment
						and managers.player._equipment.specials
						and managers.player._equipment.specials[eq_name]
					local current = 0
					if owned and owned.amount then
						current = Application:digest_value(owned.amount, false) or 0
					end
					if current < cap then
						return false, false, nil
					end
					return blocked, skip_hint, custom_hint
				end
			end
		end,
	},
})
