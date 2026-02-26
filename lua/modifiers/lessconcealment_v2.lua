-- Crime Spree Roguelike - Less Concealment Modifier (V2 - Loud Base Class)
-- Increases detection risk (+3 concealment per tier, up to 24 tiers = +72)
-- INHERITS FROM LOUD BASE CLASS so the game does not filter it out on loud missions
-- USES modify_value() with the CORRECT ID: "BlackMarketManager:GetConcealment"

if not RequiredScript then
	return
end


-- Single class for all tiers (tier is determined via data.conceal)
ModifierCSRLessConcealment = ModifierCSRLessConcealment or class(CSRBaseModifier)  -- Standalone base class
ModifierCSRLessConcealment.desc_id = "menu_cs_modifier_less_concealment"
ModifierCSRLessConcealment.icon = "crime_spree_concealment"

function ModifierCSRLessConcealment:init(data)
	-- Set data manually (skipping super.init() to avoid side effects)
	self._data = data
	self.icon = "crime_spree_concealment"
end

-- Override modify_value to implement stealth functionality
function ModifierCSRLessConcealment:modify_value(id, value)
	-- CORRECT ID from vanilla code: "BlackMarketManager:GetConcealment"
	if id == "BlackMarketManager:GetConcealment" then
		-- Guard: modifier only applies in stealth mode
		local in_stealth = managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode()
		if not in_stealth then
			return value
		end

		-- Get the concealment increase amount from data
		local conceal_increase = 0
		if self._data and self._data.conceal then
			-- Check type: may be a number or a table
			if type(self._data.conceal) == "table" then
				conceal_increase = self._data.conceal[1] or 0
			elseif type(self._data.conceal) == "number" then
				conceal_increase = self._data.conceal
			end
		end

		-- Cap detection risk at 75 (higher values crash the game)
		local new_value = math.min(value + conceal_increase, 75)
		return new_value
	end
	return value
end

