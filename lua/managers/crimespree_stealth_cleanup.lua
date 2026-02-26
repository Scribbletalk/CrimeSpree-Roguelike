-- Crime Spree Roguelike - Stealth Tier Cleanup
-- Removes lower tiers of stealth modifiers when a higher tier is applied

if not RequiredScript then
	return
end



-- Table of tiered stealth modifiers
local stealth_tier_prefixes = {
	"csr_less_pagers_",        -- Less Pagers (4 tiers)
	"csr_civilian_alarm_",     -- Civilian Alarm (3 tiers)
	"csr_less_concealment_"    -- Less Concealment (24 tiers)
}

-- Extract the base prefix and tier number from a modifier ID
local function parse_modifier_id(mod_id)
	if not mod_id then return nil, nil end

	for _, prefix in ipairs(stealth_tier_prefixes) do
		if string.find(mod_id, prefix, 1, true) then
			-- Extract the tier number (trailing digits)
			local tier = tonumber(string.match(mod_id, "_(%d+)$"))
			return prefix, tier
		end
	end

	return nil, nil
end

-- Remove a modifier from the list by its ID
local function remove_modifier_by_id(modifiers_list, mod_id)
	if not modifiers_list or not mod_id then return false end

	for i = #modifiers_list, 1, -1 do
		if modifiers_list[i].id == mod_id then
			table.remove(modifiers_list, i)
			return true
		end
	end

	return false
end

-- Hook on modifier addition
Hooks:PostHook(CrimeSpreeManager, "add_modifier", "CSR_CleanupStealthTiers", function(self, id, message)
	if not id then return end

	local prefix, new_tier = parse_modifier_id(id)

	if not prefix or not new_tier then
		return  -- Not a tiered stealth modifier
	end


	-- Remove all lower tiers of this modifier
	local removed_count = 0

	for tier = 1, new_tier - 1 do
		local old_id = prefix .. tier
		local removed = remove_modifier_by_id(self._global.modifiers, old_id)

		if removed then
			removed_count = removed_count + 1
		end
	end

	if removed_count > 0 then
	end
end)

