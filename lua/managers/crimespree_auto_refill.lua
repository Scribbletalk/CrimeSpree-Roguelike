-- Crime Spree Roguelike - Auto Refill Items
-- Automatically adds a new copy of an item after it is selected
-- This enables infinite generation without pre-loading 200 copies

if not RequiredScript then
	return
end

-- Item templates generated from centralized registry
local ITEM_TEMPLATES = {}
for _, item in ipairs(_G.CSR_ITEM_REGISTRY or {}) do
	-- Key without trailing underscore (e.g. "player_health_boost")
	local key = item.id_prefix:sub(1, -2)
	ITEM_TEMPLATES[key] = { class = item.class, icon = item.icon }
end

-- Returns the item type prefix for a given modifier ID
local function get_item_type_from_id(mod_id)
	if not mod_id then
		return nil
	end

	for type_prefix, _ in pairs(ITEM_TEMPLATES) do
		if string.find(mod_id, type_prefix, 1, true) then
			return type_prefix
		end
	end

	return nil
end

-- Returns the next available numeric ID for the given item type prefix
local function get_next_id_for_type(type_prefix)
	if not managers.crime_spree then
		return 1
	end

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

-- PostHook on add_modifier - replenish the pool with a fresh copy after an item is picked.
-- Use Hooks:PostHook (Critical Rule 1) so other mods can stack their own
-- add_modifier hooks without losing this one or being shadowed by it. The
-- previous raw `local original = ...; function CrimeSpreeManager:add_modifier`
-- pattern made the chained-original captured at file-load order and broke any
-- subsequent PostHook on add_modifier.
if CrimeSpreeManager then
	Hooks:PostHook(CrimeSpreeManager, "add_modifier", "CSR_AutoRefill", function(self, mod_id)
		local item_type = get_item_type_from_id(mod_id)
		if item_type and ITEM_TEMPLATES[item_type] then
			local next_id = get_next_id_for_type(item_type)
			local template = ITEM_TEMPLATES[item_type]

			local new_item = {
				id = item_type .. "_" .. next_id,
				class = template.class,
				icon = template.icon,
				level = 0,
				data = {},
			}

			table.insert(self._global.modifiers.loud, new_item)
		end
	end)
end
