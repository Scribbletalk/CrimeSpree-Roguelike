-- Side Satchel - Wildcard item
-- While owned, DOUBLES the carry cap of mission specials.
--   * Keycards / USB / drill parts (qty=1) -> cap 2 (effectively +1)
--   * C4 (qty=4) -> cap 8 (the headline case for Panic Room / Golden Grin)
--   * cable_tie (max=10) -> cap 20, c4_x10 -> cap 20, etc. - scales with vanilla cap
-- Items where doubling is meaningless are blacklisted (saw, crowbar - one is enough).
-- Multi-stack on the satchel itself is irrelevant: wildcards are carry-1 by design.

if not RequiredScript then
	return
end

ModifierSideSatchel = ModifierSideSatchel or class(CSRBaseModifier)
ModifierSideSatchel.desc_id = "csr_side_satchel_desc"
ModifierSideSatchel.icon = "csr_side_satchel"

-- Specials excluded from doubling.
--   pku_crowbar / pku_saw: doubling is meaningless (one tool, one interaction).
--   cable_tie:             vanilla max_quantity is already 10 with skill stacks
--                          on top — doubling to 20 is too generous and not
--                          what the satchel is meant to address.
local CSR_SIDE_SATCHEL_BLACKLIST = {
	pku_crowbar = true,
	pku_saw = true,
	cable_tie = true,
}
_G.CSR_SideSatchel_Blacklist = CSR_SIDE_SATCHEL_BLACKLIST

-- Batched mission specials whose vanilla `quantity` is nil — that makes the cap
-- formula `(max_quantity or quantity or 1) + extra` collapse to 1 for the
-- pickup check, and the special_equipment branch in add_special skips the math
-- block entirely (gated on `equipment.max_quantity or equipment.quantity`).
-- We backfill `quantity = 1` so:
--   1) Pickup interaction prompt gates at doubled vanilla_cap (= 2 for planks).
--   2) The non-transfer add_special branch enters its math block and clamps
--      via `max_amount = (qty) + extra` = 2 with the doubling extra of 1.
--   3) The transfer branch is unaffected — it uses `transfer_quantity` (= 4)
--      and the inner `math.max(transfer_quantity, qty+extra)` keeps vanilla
--      4-at-once batches intact (no nerf for stash heists).
-- Setting quantity=1 (not transfer_quantity=4) is intentional: vanilla's pickup
-- formula treats planks as a 1-cap item, and satchel doubles that to 2. Using
-- transfer_quantity here would balloon the doubled cap to 8 — broken.
local CSR_SIDE_SATCHEL_FORCE_INCLUDE = {
	planks = true,
	boards = true,
	gas = true,
}
_G.CSR_SideSatchel_ForceInclude = CSR_SIDE_SATCHEL_FORCE_INCLUDE

-- Per-heist interaction-blocker overrides. The named special_equipment_block
-- is lifted (during the can_select / can_interact checks) ONLY while the
-- player is on a listed heist and still under the doubled cap. Used for cases
-- where a blacklisted "one tool is enough" item is actually needed twice on
-- a specific map.
--   crowbar / crowbar_stack → shoutout_raid: Meltdown has 2 separate crowbar
--   pickups; vanilla has two interaction variants (gen_pku_crowbar with
--   blocker "crowbar" and gen_pku_crowbar_stack with blocker "crowbar_stack")
--   so we cover both to handle whichever the level actually places.
local CSR_SIDE_SATCHEL_HEIST_BLOCK_OVERRIDES = {
	crowbar = { shoutout_raid = true },
	crowbar_stack = { shoutout_raid = true },
}

-- Items whose vanilla equipment.quantity is nil — that makes add_special's
-- math block (line 4917 in playermanager.lua) be skipped on the 2nd pickup,
-- so the amount never increments and the HUD never updates. We backfill
-- quantity=1 at load and normalize params.amount=1 at pickup time so the
-- math runs correctly. Includes both FORCE_INCLUDE (planks/boards) and
-- HEIST_BLOCK_OVERRIDES (crowbar variants) — anything we want to actually
-- increment past 1 in the inventory needs this patch.
local CSR_SIDE_SATCHEL_QUANTITY_PATCH = {
	planks = true,
	boards = true,
	crowbar = true,
	crowbar_stack = true,
	gas = true,
}

local _quantity_patched = false
local function ensure_quantity_patched()
	if _quantity_patched then
		return
	end
	if not tweak_data or not tweak_data.equipments or not tweak_data.equipments.specials then
		return
	end
	for name, _ in pairs(CSR_SIDE_SATCHEL_QUANTITY_PATCH) do
		local eq = tweak_data.equipments.specials[name]
		if eq and not eq.quantity then
			eq.quantity = 1
		end
	end
	_quantity_patched = true
end

local function owns_side_satchel()
	if not managers or not managers.crime_spree or not managers.crime_spree:is_active() then
		return false
	end
	if not _G.CSR_CountStacks then
		return false
	end
	return CSR_CountStacks("player_side_satchel_") > 0
end

-- True for any mission special that benefits from a doubled carry cap.
-- Doubling design: scope is broad — only the blacklist is excluded.
-- Planks/boards still need force-include because their vanilla quantity is nil.
local function eligible_for_bump(equipment_name, equipment)
	if not equipment_name or not equipment then
		return false
	end
	if CSR_SIDE_SATCHEL_BLACKLIST[equipment_name] then
		return false
	end
	return true
end

-- Vanilla cap = `(max_quantity or quantity or 1)`. To DOUBLE the cap we add
-- that same value as our extra, so total cap becomes 2*vanilla_cap + skill_extras.
-- C4 (qty=4) -> +4 extra -> cap 8. Keycards (qty=nil -> 1) -> +1 extra -> cap 2.
-- cable_tie (max=10) -> +10 extra -> cap 20.
local function doubling_extra(equipment)
	return equipment.max_quantity or equipment.quantity or 1
end

-- Inject doubling extra for eligible specials. Hook chain:
-- 1. _equipped_upgrade_value: adds (max or qty or 1) to vanilla's cap formula
--    `(max or qty or 1) + extra`, producing 2*vanilla_cap + skill_extras.
-- 2. add_special PreHook:     normalizes params.amount for force-included
--    items so the no-amount grant branch returns one item, not the doubled cap.
if PlayerManager and not _G._CSR_SIDE_SATCHEL_PM_HOOKED then
	_G._CSR_SIDE_SATCHEL_PM_HOOKED = true
	-- Patch the cap math by overriding _equipped_upgrade_value (vanilla reads
	-- this then sums it with upgrade_value(name, "quantity") into `extra`).
	-- Vanilla's body returns 0 unless equipment.extra_quantity is defined
	-- (only cable_tie has it), so for c4/keycards/etc. our extra stacks cleanly.
	local original_equipped_upgrade_value = PlayerManager._equipped_upgrade_value
	if original_equipped_upgrade_value then
		function PlayerManager:_equipped_upgrade_value(equipment, ...)
			ensure_quantity_patched()
			local base = original_equipped_upgrade_value(self, equipment, ...)
			if not equipment or type(equipment) ~= "table" then
				return base
			end
			-- Resolve the equipment_name by reverse lookup from the table ref.
			local equipment_name = nil
			if tweak_data and tweak_data.equipments and tweak_data.equipments.specials then
				for k, v in pairs(tweak_data.equipments.specials) do
					if v == equipment then
						equipment_name = k
						break
					end
				end
			end
			if not eligible_for_bump(equipment_name, equipment) then
				return base
			end
			if not owns_side_satchel() then
				return base
			end
			return (base or 0) + doubling_extra(equipment)
		end
	end
end

-- Lift the special_equipment_block on stash pickup interactions for
-- force-included batched specials, but ONLY while we have less than the raised
-- cap. Vanilla blocks the pickup once you have any planks at all, which makes
-- the +1 cap room unreachable. We swap the block field temporarily during the
-- can_select / can_interact / _interact_blocked checks so the prompt appears
-- when there's still room, then restore it so the rest of the code (including
-- the actual pickup grant path) sees vanilla state.
if BaseInteractionExt and not _G._CSR_SIDE_SATCHEL_INT_HOOKED then
	_G._CSR_SIDE_SATCHEL_INT_HOOKED = true
	local function pickup_should_unblock(self)
		if not owns_side_satchel() then
			return nil
		end
		local td = self._tweak_data
		if not td or not td.special_equipment_block then
			return nil
		end
		-- Only unblock when there's no `special_equipment` field — that's the
		-- pickup interaction (block-only). The barricade interaction has both
		-- `special_equipment = "planks"` (consume) AND no block, so we don't
		-- touch it.
		if td.special_equipment then
			return nil
		end
		local blocker = td.special_equipment_block
		if type(blocker) == "table" then
			blocker = blocker[1]
		end
		-- Allow either: (a) blocker in FORCE_INCLUDE, or (b) blocker has a
		-- heist-scoped override matching the current level_id.
		local lvl = managers.job and managers.job.current_level_id and managers.job:current_level_id()
		local allowed = CSR_SIDE_SATCHEL_FORCE_INCLUDE[blocker] == true
		if not allowed then
			local overrides = CSR_SIDE_SATCHEL_HEIST_BLOCK_OVERRIDES[blocker]
			if overrides then
				allowed = lvl and overrides[lvl] == true or false
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
		-- Doubled cap: vanilla cap + our doubling extra = 2 * vanilla cap.
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

	-- _interact_blocked is the THIRD gate (can_select and can_interact let the
	-- prompt appear, but interact_start re-checks via _interact_blocked before
	-- actually granting the pickup). Vanilla SpecialEquipmentInteractionExt
	-- gates here on can_pickup_equipment(self._special_equipment). If a heist
	-- override applies, force-unblock while under the doubled cap.
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
			local overrides = CSR_SIDE_SATCHEL_HEIST_BLOCK_OVERRIDES[eq_name]
			if not overrides then
				return blocked, skip_hint, custom_hint
			end
			local lvl = managers.job and managers.job.current_level_id and managers.job:current_level_id()
			if not (lvl and overrides[lvl] == true) then
				return blocked, skip_hint, custom_hint
			end
			if not owns_side_satchel() then
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
end

-- Passive bag-carry speed bump: while a loot bag is on the player's back,
-- movement speed gets an additive +20% bonus. Hooks `movement_speed_multiplier`
-- — the single funnel that sprint/walk/crouch/strafe all read from, so one
-- override covers every locomotion mode. Runs on the local PlayerManager for
-- the local player only; husk movement on other peers is sync'd via vanilla
-- network position updates so the bump propagates automatically. Other Side
-- Satchel owners on remote machines apply their own bump locally.
if PlayerManager and not _G._CSR_SIDE_SATCHEL_PM_SPEED_HOOKED then
	_G._CSR_SIDE_SATCHEL_PM_SPEED_HOOKED = true
	local original_speed_mul = PlayerManager.movement_speed_multiplier
	if original_speed_mul and _G.CSR_SafeOverride then
		CSR_SafeOverride(
			PlayerManager,
			"movement_speed_multiplier",
			"Side Satchel",
			original_speed_mul,
			function(self, ...)
				local mul = original_speed_mul(self, ...)
				if not owns_side_satchel() then
					return mul
				end
				-- get_my_carry_data() returns a TABLE when actually carrying;
				-- it returns literal `true` only in the offline/no-network-
				-- session edge case (vanilla fallback). Type-check guards
				-- against false positives in non-heist contexts.
				local carry = self.get_my_carry_data and self:get_my_carry_data()
				if type(carry) ~= "table" then
					return mul
				end
				local C = _G.CSR_ItemConstants or {}
				local bonus = (C.side_satchel_carry_speed_mult or 1.20) - 1
				return mul + bonus
			end
		)
	end
end

-- Side Satchel's design: STORE double, don't DUPE on pickup. A single pickup
-- interaction grants vanilla quantity (4 for c4, 3 for c4_x3, etc.); the doubled
-- cap is reached by picking up TWICE.
--
-- Without clamping, vanilla's no-amount branch (playermanager.lua:4690) routes
-- through `math.min(amount + extra, cap + extra)` with amount = equipment.quantity
-- (4) and extra = +4 (our doubling) = min(8, 8) = 8 in one pickup — satchel
-- becomes a duper, not a saddlebag.
--
-- Fix: pin params.amount to equipment.quantity for every eligible special.
-- That forces the respawn-style branch `math.min(params.amount, cap + extra)`
-- = `min(4, 8)` = 4 on the first pickup; the special_equipment math branch
-- tops up to 8 on the second.
--
-- Clamping designer-set amounts (e.g. Meltdown crowbar amount=2) down to
-- equipment.quantity matches vanilla's own clamp-to-cap on those pickups —
-- the satchel doesn't lift the per-pickup limit, only the storage cap.
--
-- Untouched paths: transfer (stash uses transfer_quantity intentionally),
-- dropped_out (respawn drop). Blacklisted items and items without eq.quantity
-- (keycards / USBs / blueprints — never enter the math branch) are skipped via
-- eligible_for_bump + the eq.quantity guard.
if PlayerManager and not _G._CSR_SIDE_SATCHEL_PM_ADD_SPECIAL_HOOKED then
	_G._CSR_SIDE_SATCHEL_PM_ADD_SPECIAL_HOOKED = true
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
end
