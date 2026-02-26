-- Crime Spree Roguelike - Civilian Alarm Modifier
-- Alarm triggers after killing N civilians (3 tiers)

if not RequiredScript then
	return
end

-- Tier 1: Alarm after 10 civilians
ModifierCSRCivilianAlarm1 = ModifierCSRCivilianAlarm1 or class(ModifierCivilianAlarm)
ModifierCSRCivilianAlarm1.desc_id = "menu_cs_modifier_civilian_alarm_1"

-- Tier 2: Alarm after 7 civilians
ModifierCSRCivilianAlarm2 = ModifierCSRCivilianAlarm2 or class(ModifierCivilianAlarm)
ModifierCSRCivilianAlarm2.desc_id = "menu_cs_modifier_civilian_alarm_2"

-- Tier 3: Alarm after 4 civilians
ModifierCSRCivilianAlarm3 = ModifierCSRCivilianAlarm3 or class(ModifierCivilianAlarm)
ModifierCSRCivilianAlarm3.desc_id = "menu_cs_modifier_civilian_alarm_3"

log("[CSR CivilianAlarm] 3 tier classes created")
