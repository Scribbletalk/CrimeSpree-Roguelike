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
}
_G.CSR_SideSatchel_ForceInclude = CSR_SIDE_SATCHEL_FORCE_INCLUDE

local _quantity_patched = false
local function ensure_quantity_patched()
	if _quantity_patched then
		return
	end
	if not tweak_data or not tweak_data.equipments or not tweak_data.equipments.specials then
		return
	end
	for name, _ in pairs(CSR_SIDE_SATCHEL_FORCE_INCLUDE) do
		local eq = tweak_data.equipments.specials[name]
		if eq and not eq.quantity then
			eq.quantity = 1
		end
	end
	_quantity_patched = true
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log("[CSR SideSatchel] " .. tostring(msg))
	end
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
		if not CSR_SIDE_SATCHEL_FORCE_INCLUDE[blocker] then
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
end

-- Some custom heists grant force-included specials via add_special({name=...})
-- with no amount or transfer flag. Vanilla then routes through the non-respawn
-- branch: `math.min(amount + extra, cap + extra)` with `amount = equipment.quantity`
-- (= 1 after our patch for planks/boards). With doubling extra=1, that yields
-- min(2, 2) = 2 from a single grant — wrong, the room should fill on the SECOND
-- pickup, not the first. Set params.amount = equipment.quantity here so vanilla
-- treats it as a respawn-style grant: `math.min(params.amount, cap+extra)` =
-- `min(1, 2)` = 1. The transfer path (real stash pickup) is untouched — it has
-- its own clamp via transfer_quantity that respects extra correctly.
-- Non-force-included items (c4, etc.) are NOT touched here: vanilla's no-amount
-- grant for c4 produces min(4+4, 4+4) = 8, which IS the desired "fill to doubled
-- cap" behavior for those grants.
if PlayerManager and not _G._CSR_SIDE_SATCHEL_PM_ADD_SPECIAL_HOOKED then
	_G._CSR_SIDE_SATCHEL_PM_ADD_SPECIAL_HOOKED = true
	local original_add_special = PlayerManager.add_special
	if original_add_special then
		function PlayerManager:add_special(params)
			if
				params
				and not params.amount
				and not params.transfer
				and not params.dropped_out
				and CSR_SIDE_SATCHEL_FORCE_INCLUDE[params.equipment or params.name or ""]
				and owns_side_satchel()
			then
				-- Force the source amount equal to equipment.quantity so we
				-- get +cap-room only, not +cap-room AND +cap-room-amount.
				local name = params.equipment or params.name
				local eq = tweak_data and tweak_data.equipments and tweak_data.equipments.specials[name]
				if eq and eq.quantity then
					params.amount = eq.quantity
				end
			end
			return original_add_special(self, params)
		end
	end
end
