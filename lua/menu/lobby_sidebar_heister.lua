-- CSRMissionsMenuComponent — Heister feature-panel (extracted from missions_menu.lua).
-- Loads on lib/managers/menu/menucomponentmanager AFTER missions_menu.lua (mod.txt
-- order); adds the Heister panel (player combat-stats table) + its stat helpers to
-- the class. Borrowed by MissionBriefingGui (briefing_sidebar.lua) at runtime.
if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

-- Shared feature-panel inner padding (declared locally in each sidebar file).
local items_panel_padding = 16

-- Player combat characteristics for the Heister feature panel.
--
-- Computed with the SAME formulas the vanilla inventory screen uses for its
-- player-stats table (PlayerInventoryGui:_get_armor_stats in pd2_source). They
-- reflect the player's CURRENT loadout (equipped armor + skills) but NOT the CSR
-- item buffs: item numbers are hidden by design, so this "standard" table shows
-- the player's normal PD2 values. Folding the CSR item contributions into these
-- totals is a later pass (the row layout below does not change for it).
--
-- pcall-isolated at two levels (loadout lookup + each stat): a stat read must
-- never crash the lobby / briefing. On any failure a row falls back to the bare
-- base constant, so the table always renders.
local function csr_round1(n)
	-- format_round's non-integer branch (pd2 playerinventorygui): one decimal,
	-- trailing zeros stripped ("230.0" -> "230", "4.5" -> "4.5").
	return (string.format("%.1f", n):gsub("%.?0+$", ""))
end

-- TOTAL (base + skill) for one stat, line-for-line from the matching branch of
-- _get_armor_stats. `name` = equipped armor id, `upgrade_level` its tier.
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

	-- Equipped armor id + tier + detection risk (head of _get_armor_stats). Guarded:
	-- outside an active loadout these reads can throw.
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

	-- Ordered combat characteristics. `fallback` = bare base constant shown if the
	-- live read errors; `pct` rows append "%". Loc keys are vanilla (bm_menu_*).
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

-- Build / rebuild the Heister feature-panel content: a two-column table of the
-- player's combat characteristics (name left, value right) with a zebra band on
-- alternating rows for readability. Idempotent (prior content torn down first).
-- Borrowed by MissionBriefingGui (briefing_sidebar.lua METHODS_TO_BORROW) so both
-- the lobby and the briefing share it.
function CSRMissionsMenuComponent:_populate_heister_panel()
	if not self._feature_panels or not alive(self._feature_panels.heister) then
		return
	end
	local panel = self._feature_panels.heister

	if self._heister_content and alive(self._heister_content) then
		panel:remove(self._heister_content)
	end
	self._heister_content = nil

	local content = panel:panel({
		layer = 5,
	})
	self._heister_content = content

	local stats = csr_collect_heister_stats()
	local pad = items_panel_padding
	local row_h = tweak_data.menu.pd2_medium_font_size + 8
	local row_gap = 4
	-- Yellow value highlight (4-arg Color per Rule #6), same accent the status bar
	-- uses for its dynamic rank / difficulty values.
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

		-- Zebra band on alternating rows (the same 0.4-black the vanilla inventory
		-- stats table uses).
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
