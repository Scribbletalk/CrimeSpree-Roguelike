-- CSRMissionsMenuComponent — Heister feature-panel (extends class from missions_menu.lua).
-- Shows the player's combat characteristics using vanilla _get_armor_stats formulas.
-- CSR item buffs are NOT folded in by design (standard table).
-- Borrowed by MissionBriefingGui (briefing_sidebar.lua METHODS_TO_BORROW).

if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

local items_panel_padding = 16

-- One-decimal with trailing zeros stripped ("230.0" → "230", "4.5" → "4.5").
local function csr_round1(n)
	return (string.format("%.1f", n):gsub("%.?0+$", ""))
end

-- TOTAL (base + skill) for one stat, mirrors PlayerInventoryGui:_get_armor_stats.
local function csr_heister_stat_value(stat_name, name, upgrade_level, detection_risk, mult)
	local player = managers.player
	if stat_name == "health" then
		local base = (tweak_data.player.damage.HEALTH_INIT + player:health_skill_addend()) * mult
		return base * player:health_skill_multiplier()
	elseif stat_name == "armor" then
		local base = (tweak_data.player.damage.ARMOR_INIT + player:body_armor_value("armor", upgrade_level)) * mult
		return (base + player:body_armor_skill_addend(name) * mult) * player:body_armor_skill_multiplier(name)
	elseif stat_name == "movement" then
		local base = tweak_data.player.movement_state.standard.movement.speed.STANDARD_MAX / 100 * mult
		return base * player:movement_speed_multiplier(false, false, upgrade_level, 1)
	elseif stat_name == "dodge" then
		return player:body_armor_value("dodge", upgrade_level) * 100
			+ player:skill_dodge_chance(false, false, false, name, detection_risk) * 100
	elseif stat_name == "stamina" then
		local base = tweak_data.player.movement_state.stamina.STAMINA_INIT
		return base * player:body_armor_value("stamina", upgrade_level) * player:stamina_multiplier()
	end
	return 0
end

local function csr_collect_heister_stats()
	local mult = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local pd = tweak_data.player

	-- pcall-guarded: outside an active loadout these throw.
	local name, upgrade_level, detection_risk = nil, 0, 0
	pcall(function()
		name = managers.blackmarket:equipped_armor()
		local tw = name and tweak_data.blackmarket.armors[name]
		upgrade_level = (tw and tw.upgrade_level) or 0
		local dr = managers.blackmarket:get_suspicion_offset_from_custom_data(
			{ armors = name },
			pd.SUSPICION_OFFSET_LERP or 0.75
		)
		detection_risk = math.round(dr * 100)
	end)

	-- pct rows append "%". Loc keys are vanilla bm_menu_*.
	local defs = {
		{ key = "health", loc = "bm_menu_health", pct = false, fallback = (pd.damage.HEALTH_INIT or 0) * mult },
		{ key = "armor", loc = "bm_menu_armor", pct = false, fallback = (pd.damage.ARMOR_INIT or 0) * mult },
		{
			key = "movement",
			loc = "bm_menu_movement",
			pct = false,
			fallback = (pd.movement_state.standard.movement.speed.STANDARD_MAX or 0) / 100 * mult,
		},
		{ key = "dodge", loc = "bm_menu_dodge", pct = true, fallback = 0 },
		{
			key = "stamina",
			loc = "bm_menu_stamina",
			pct = false,
			fallback = pd.movement_state.stamina.STAMINA_INIT or 0,
		},
	}

	local out = {}
	for _, d in ipairs(defs) do
		local ok, v = pcall(csr_heister_stat_value, d.key, name, upgrade_level, detection_risk, mult)
		if not ok or type(v) ~= "number" then
			v = d.fallback
		end
		v = math.max(v, 0)
		out[#out + 1] = {
			label = managers.localization:to_upper_text(d.loc),
			value = d.pct and (math.round(v) .. "%") or csr_round1(v),
		}
	end
	return out
end

-- Two-column stat table with zebra band on alternating rows. Idempotent.
function CSRMissionsMenuComponent:_populate_heister_panel()
	if not self._feature_panels or not alive(self._feature_panels.heister) then
		return
	end
	local panel = self._feature_panels.heister

	if self._heister_content and alive(self._heister_content) then
		panel:remove(self._heister_content)
	end
	self._heister_content = nil

	local content = panel:panel({ layer = 5 })
	self._heister_content = content

	local stats = csr_collect_heister_stats()
	local pad = items_panel_padding
	local row_h = tweak_data.menu.pd2_medium_font_size + 8
	local row_gap = 4
	local highlight = Color(1, 1, 1, 0)
	local y = pad

	for i, s in ipairs(stats) do
		local row = content:panel({
			x = pad,
			y = y,
			w = panel:w() - pad * 2,
			h = row_h,
			layer = 5,
		})

		if i % 2 == 1 then
			row:rect({
				color = Color.black:with_alpha(0.4),
				layer = 0,
			})
		end

		row:text({
			name = "stat_name",
			text = s.label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			x = 8,
			w = row:w() - 16,
			h = row:h(),
			align = "left",
			vertical = "center",
			layer = 2,
		})
		row:text({
			name = "stat_value",
			text = s.value,
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = highlight,
			x = 8,
			w = row:w() - 16,
			h = row:h(),
			align = "right",
			vertical = "center",
			layer = 2,
		})

		y = y + row_h + row_gap
	end
end
