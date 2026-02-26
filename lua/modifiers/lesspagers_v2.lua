-- Crime Spree Roguelike - Less Pagers Modifier (V2 - Loud Base Class)
-- Reduces number of pagers available (4 tiers)
-- INHERITS FROM LOUD CLASS so the game does not filter it out on loud missions
-- USES init() to modify tweak_data (same as vanilla ModifierLessPagers)

if not RequiredScript then
	return
end


-- Tier 1: 1 less pager (3 available)
ModifierCSRLessPagers1 = ModifierCSRLessPagers1 or class(CSRBaseModifier)  -- LOUD class used as a container!
ModifierCSRLessPagers1.desc_id = "menu_cs_modifier_less_pagers_1"
ModifierCSRLessPagers1.icon = "crime_spree_pager"

function ModifierCSRLessPagers1:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_pager"  -- Set icon for this instance

	-- Copy logic from vanilla ModifierLessPagers
	local max_pagers = 0
	for i, val in ipairs(tweak_data.player.alarm_pager.bluff_success_chance) do
		if val > 0 then
			max_pagers = math.max(max_pagers, i)
		end
	end

	max_pagers = max_pagers - 1  -- Tier 1: -1 pager

	local new_pagers_data = {}
	for i = 1, max_pagers, 1 do
		table.insert(new_pagers_data, 1)
	end
	table.insert(new_pagers_data, 0)

	tweak_data.player.alarm_pager.bluff_success_chance = new_pagers_data
	tweak_data.player.alarm_pager.bluff_success_chance_w_skill = new_pagers_data
end

-- Tier 2: 2 less pagers (2 available)
ModifierCSRLessPagers2 = ModifierCSRLessPagers2 or class(CSRBaseModifier)
ModifierCSRLessPagers2.desc_id = "menu_cs_modifier_less_pagers_2"
ModifierCSRLessPagers2.icon = "crime_spree_pager"

function ModifierCSRLessPagers2:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_pager"  -- Set icon for this instance

	local max_pagers = 0
	for i, val in ipairs(tweak_data.player.alarm_pager.bluff_success_chance) do
		if val > 0 then
			max_pagers = math.max(max_pagers, i)
		end
	end

	max_pagers = max_pagers - 2  -- Tier 2: -2 pagers

	local new_pagers_data = {}
	for i = 1, max_pagers, 1 do
		table.insert(new_pagers_data, 1)
	end
	table.insert(new_pagers_data, 0)

	tweak_data.player.alarm_pager.bluff_success_chance = new_pagers_data
	tweak_data.player.alarm_pager.bluff_success_chance_w_skill = new_pagers_data
end

-- Tier 3: 3 less pagers (1 available)
ModifierCSRLessPagers3 = ModifierCSRLessPagers3 or class(CSRBaseModifier)
ModifierCSRLessPagers3.desc_id = "menu_cs_modifier_less_pagers_3"
ModifierCSRLessPagers3.icon = "crime_spree_pager"

function ModifierCSRLessPagers3:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_pager"  -- Set icon for this instance

	local max_pagers = 0
	for i, val in ipairs(tweak_data.player.alarm_pager.bluff_success_chance) do
		if val > 0 then
			max_pagers = math.max(max_pagers, i)
		end
	end

	max_pagers = max_pagers - 3  -- Tier 3: -3 pagers

	local new_pagers_data = {}
	for i = 1, max_pagers, 1 do
		table.insert(new_pagers_data, 1)
	end
	table.insert(new_pagers_data, 0)

	tweak_data.player.alarm_pager.bluff_success_chance = new_pagers_data
	tweak_data.player.alarm_pager.bluff_success_chance_w_skill = new_pagers_data
end

-- Tier 4: 4 less pagers (0 available)
ModifierCSRLessPagers4 = ModifierCSRLessPagers4 or class(CSRBaseModifier)
ModifierCSRLessPagers4.desc_id = "menu_cs_modifier_less_pagers_4"
ModifierCSRLessPagers4.icon = "crime_spree_pager"

function ModifierCSRLessPagers4:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_pager"  -- Set icon for this instance

	local max_pagers = 0
	for i, val in ipairs(tweak_data.player.alarm_pager.bluff_success_chance) do
		if val > 0 then
			max_pagers = math.max(max_pagers, i)
		end
	end

	max_pagers = max_pagers - 4  -- Tier 4: -4 pagers

	local new_pagers_data = {}
	for i = 1, max_pagers, 1 do
		table.insert(new_pagers_data, 1)
	end
	table.insert(new_pagers_data, 0)

	tweak_data.player.alarm_pager.bluff_success_chance = new_pagers_data
	tweak_data.player.alarm_pager.bluff_success_chance_w_skill = new_pagers_data
end

