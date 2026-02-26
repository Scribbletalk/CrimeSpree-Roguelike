-- Crime Spree Roguelike - Civilian Alarm Modifier (V2 - Loud Base Class)
-- Reduces number of civilians required to raise alarm (3 tiers)
-- INHERITS FROM LOUD CLASS so the game doesn't filter it out on loud missions
-- USES OnCivilianKilled() to count kills (same as vanilla ModifierCivilianAlarm)

if not RequiredScript then
	return
end


-- Tier 1: 10 civilians required
ModifierCSRCivilianAlarm1 = ModifierCSRCivilianAlarm1 or class(CSRBaseModifier)  -- LOUD class used as a container!
ModifierCSRCivilianAlarm1.desc_id = "menu_cs_modifier_civilian_alarm_1"
ModifierCSRCivilianAlarm1.icon = "crime_spree_civs_killed"

function ModifierCSRCivilianAlarm1:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_civs_killed"  -- Set icon on the instance
	self._body_count = 0
	self._alarmed = false
end

function ModifierCSRCivilianAlarm1:OnCivilianKilled()
	-- Guard: modifier only active in stealth mode
	local in_stealth = managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode()
	if not in_stealth then
		return
	end

	self._body_count = self._body_count + 1

	if 10 < self._body_count and not self._alarmed then
		managers.groupai:state():on_police_called("civ_too_many_killed")
		self._alarmed = true
	end
end

-- Tier 2: 7 civilians required
ModifierCSRCivilianAlarm2 = ModifierCSRCivilianAlarm2 or class(CSRBaseModifier)
ModifierCSRCivilianAlarm2.desc_id = "menu_cs_modifier_civilian_alarm_2"
ModifierCSRCivilianAlarm2.icon = "crime_spree_civs_killed"

function ModifierCSRCivilianAlarm2:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_civs_killed"  -- Set icon on the instance
	self._body_count = 0
	self._alarmed = false
end

function ModifierCSRCivilianAlarm2:OnCivilianKilled()
	-- Guard: modifier only active in stealth mode
	local in_stealth = managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode()
	if not in_stealth then
		return
	end

	self._body_count = self._body_count + 1

	if 7 < self._body_count and not self._alarmed then
		managers.groupai:state():on_police_called("civ_too_many_killed")
		self._alarmed = true
	end
end

-- Tier 3: 4 civilians required
ModifierCSRCivilianAlarm3 = ModifierCSRCivilianAlarm3 or class(CSRBaseModifier)
ModifierCSRCivilianAlarm3.desc_id = "menu_cs_modifier_civilian_alarm_3"
ModifierCSRCivilianAlarm3.icon = "crime_spree_civs_killed"

function ModifierCSRCivilianAlarm3:init(data)
	-- Initialize data manually
	self._data = data
	self.icon = "crime_spree_civs_killed"  -- Set icon on the instance
	self._body_count = 0
	self._alarmed = false
end

function ModifierCSRCivilianAlarm3:OnCivilianKilled()
	-- Guard: modifier only active in stealth mode
	local in_stealth = managers.groupai and managers.groupai:state() and managers.groupai:state():whisper_mode()
	if not in_stealth then
		return
	end

	self._body_count = self._body_count + 1

	if 4 < self._body_count and not self._alarmed then
		managers.groupai:state():on_police_called("civ_too_many_killed")
		self._alarmed = true
	end
end

