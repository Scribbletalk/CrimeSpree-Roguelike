-- Crime Spree Roguelike - Less Concealment Modifier (V2)
-- Increases detection risk (+3 concealment per tier, up to 24 tiers = +72)
-- Uses vanilla enemy_weapons_hot pattern with listener for proper cache invalidation

if not RequiredScript then
	return
end

-- Single class for all tiers (tier is determined via data.conceal)
ModifierCSRLessConcealment = ModifierCSRLessConcealment or class(CSRBaseModifier)
ModifierCSRLessConcealment.desc_id = "menu_cs_modifier_less_concealment"
ModifierCSRLessConcealment.icon = "crime_spree_concealment"

function ModifierCSRLessConcealment:init(data)
	self._data = data
	self.icon = "crime_spree_concealment"
	self._checked_weapons_hot = false
end

-- Vanilla pattern: check enemy_weapons_hot + register listener for cache invalidation
function ModifierCSRLessConcealment:modify_value(id, value)
	if id ~= "BlackMarketManager:GetConcealment" then
		return value
	end

	if not managers.groupai then
		return value
	end

	local state = managers.groupai:state()
	if not state then
		return value
	end

	local enemy_weapons_hot = state:enemy_weapons_hot()

	-- Register listener once to invalidate concealment cache when alarm triggers
	if not self._checked_weapons_hot then
		self._checked_weapons_hot = true

		if not enemy_weapons_hot and not self._weapons_hot_listener_id then
			self._weapons_hot_listener_id = "CSR_ModifierLessConcealment"

			state:add_listener(self._weapons_hot_listener_id, {
				"enemy_weapons_hot",
			}, callback(self, self, "clbk_enemy_weapons_hot"))
		end
	end

	-- Only increase detection risk when enemy weapons are NOT hot (stealth phase)
	if not enemy_weapons_hot then
		local conceal_increase = 0
		if self._data and self._data.conceal then
			if type(self._data.conceal) == "table" then
				conceal_increase = self._data.conceal[1] or 0
			elseif type(self._data.conceal) == "number" then
				conceal_increase = self._data.conceal
			end
		end

		-- Cap detection risk at 75 (higher values crash the game)
		return math.min(value + conceal_increase, 75)
	end

	return value
end

-- Callback when alarm triggers: invalidate concealment cache so crit builds work in loud
function ModifierCSRLessConcealment:clbk_enemy_weapons_hot()
	if self._weapons_hot_listener_id then
		local state = managers.groupai and managers.groupai:state()
		if state then
			state:remove_listener(self._weapons_hot_listener_id)
		end
		self._weapons_hot_listener_id = nil
	end

	-- Force recalculation of cached detection risk
	if managers.player then
		managers.player:update_cached_detection_risk()
	end

	-- Update concealment for all peers (multiplayer)
	if managers.network and managers.network:session() then
		for _, peer in pairs(managers.network:session():all_peers()) do
			peer:update_concealment()
		end
	end
end
