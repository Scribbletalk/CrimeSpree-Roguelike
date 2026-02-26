-- Crime Spree Roguelike - Auto Refill Items
-- Automatically adds a new copy of an item after it is selected
-- This enables infinite generation without pre-loading 200 copies

if not RequiredScript then
	return
end



-- Item templates used for generating new copies
local ITEM_TEMPLATES = {
	player_health_boost = { class = "ModifierDogTags", icon = "csr_dog_tags" },
	player_damage_boost = { class = "ModifierEvidenceRounds", icon = "csr_bullets" },
	player_dozer_guide = { class = "ModifierDozerGuide", icon = "csr_dozer_guide" },
	player_bonnie_chip = { class = "ModifierBonniesLuckyChip", icon = "csr_bonnie_chip" },
	player_glass_pistol = { class = "ModifierGlassCannon", icon = "csr_glass_pistol" },
	player_car_keys = { class = "ModifierCarKeys", icon = "csr_falcogini_keys" },
	player_plush_shark = { class = "ModifierPlushShark", icon = "csr_plush_shark" },
	player_wolfs_toolbox = { class = "ModifierWolfsToolbox", icon = "csr_toolbox" },
	player_duct_tape = { class = "ModifierDuctTape", icon = "csr_duct_tape" },
	player_escape_plan = { class = "ModifierEscapePlan", icon = "csr_escape_plan" },
	player_jiro_last_wish = { class = "ModifierJiroLastWish", icon = "csr_jiro_last_wish" },
	player_dearest_possession = { class = "ModifierDearestPossession", icon = "csr_dearest_possession" },
	player_viklund_vinyl = { class = "ModifierViklundVinyl", icon = "csr_viklund_vinyl" },
	player_equalizer = { class = "ModifierEqualizer", icon = "csr_equalizer" },
	player_crooked_badge = { class = "ModifierCrookedBadge", icon = "csr_crooked_badge" },
	player_dead_mans_trigger = { class = "ModifierDeadMansTrigger", icon = "csr_dead_mans_trigger" }
}

-- Returns the item type prefix for a given modifier ID
local function get_item_type_from_id(mod_id)
	if not mod_id then return nil end

	for type_prefix, _ in pairs(ITEM_TEMPLATES) do
		if string.find(mod_id, type_prefix, 1, true) then
			return type_prefix
		end
	end

	return nil
end

-- Returns the next available numeric ID for the given item type prefix
local function get_next_id_for_type(type_prefix)
	if not managers.crime_spree then return 1 end

	local active_mods = managers.crime_spree:active_modifiers() or {}
	local max_id = 0

	for _, mod in ipairs(active_mods) do
		if mod.id and string.find(mod.id, type_prefix, 1, true) then
			local num_str = string.match(mod.id, "_(%d+)$")
			if num_str then
				local num = tonumber(num_str)
				if num and num > max_id then
					max_id = num
				end
			end
		end
	end

	return max_id + 1
end

-- Hook on add_modifier - replenish the pool with a fresh copy after an item is picked
if CrimeSpreeManager then
	local original_add_modifier = CrimeSpreeManager.add_modifier

	function CrimeSpreeManager:add_modifier(mod_id, ...)
		-- Call the original function
		local result = original_add_modifier(self, mod_id, ...)

		-- Check if this is one of our managed items
		local item_type = get_item_type_from_id(mod_id)
		if item_type and ITEM_TEMPLATES[item_type] then
			-- Get the next available ID for this item type
			local next_id = get_next_id_for_type(item_type)
			local template = ITEM_TEMPLATES[item_type]

			-- Build the new item entry
			local new_item = {
				id = item_type .. "_" .. next_id,
				class = template.class,
				icon = template.icon,
				level = 0,
				data = {}
			}

			-- Insert the new copy into modifiers.loud
			table.insert(self._global.modifiers.loud, new_item)

		end

		return result
	end

end

