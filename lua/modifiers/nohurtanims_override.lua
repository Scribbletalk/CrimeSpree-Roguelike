-- Override vanilla No Hurt Anims modifier: probability-based instead of guaranteed block
-- Vanilla: enemies NEVER stagger from damage (100% block)
-- CSR: configurable block chance via CSR_ItemConstants.no_hurt_anims_block_chance
--
-- Approach: wrap ModifiersManager:modify_value. When vanilla returns nil for
-- CopMovement:HurtType (= stagger was blocked), roll dice and potentially
-- restore the original hurt_type so the stagger plays normally.

if not RequiredScript then
	return
end

if not ModifiersManager then
	return
end

local original_modify_value = ModifiersManager.modify_value

function ModifiersManager:modify_value(id, value, ...)
	local result = original_modify_value(self, id, value, ...)

	if id == "CopMovement:HurtType" and result == nil and value ~= nil then
		local C = _G.CSR_ItemConstants or {}
		local block_chance = C.no_hurt_anims_block_chance or 0.50
		if math.random() >= block_chance then
			return value
		end
	end

	return result
end
