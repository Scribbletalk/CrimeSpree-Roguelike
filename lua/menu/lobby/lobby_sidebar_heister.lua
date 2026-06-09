-- CSRMissionsMenuComponent — Heister feature-panel (extends class from missions_menu.lua).
-- Two sections: PLAYER STATS (vanilla _get_armor_stats formulas) + per-weapon DAMAGE.
-- CSR rank passives + item buffs ARE folded in here as a preview: values are computed as
-- if in_csr_heist() (live owned()/host_rank()), and tinted green (boosted) / red (reduced)
-- vs the un-buffed base. See _populate_heister_panel for the two folding mechanisms.
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
-- Calls vanilla getters: health/stamina/dodge route through fns CSR items hook, so forcing
-- in_csr_heist() true around this (see with_csr_heist_forced) makes those three reflect buffs.
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

-- Raw per-stat values (numbers). Formatting + buff-tinting happen at render.
-- Respects whatever in_csr_heist() returns at call time: gate off = base, forced on = buffed
-- for the three stats routed through a buffed vanilla fn (health / stamina / dodge).
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
		out[#out + 1] = {
			key = d.key,
			label = managers.localization:to_upper_text(d.loc),
			value = math.max(v, 0),
			pct = d.pct,
		}
	end
	return out
end

-- Pin in_csr_heist() to `value` while fn runs so the live item/passive hooks (all gated on it)
-- fold their buffs in (true) or stay out (false). MUST force BOTH directions: when this panel
-- renders inside a heist the live gate is already true, so an un-forced base call would also be
-- buffed → base == buffed → no tint. Restored even on error (instance shadow removed).
local function with_csr_heist(value, fn)
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist) then
		return fn()
	end
	local had = rawget(mgr, "in_csr_heist")
	mgr.in_csr_heist = function()
		return value
	end
	local ok, res = pcall(fn)
	mgr.in_csr_heist = had
	if ok then
		return res
	end
	return nil
end

-- CSR multiplier for stats whose buff hooks a fn this panel never calls (armor, movement).
-- Constants mirror rank_passives.lua + the item files — Rule #13: no shared accumulator exists.
local function csr_stat_offpath_mult(key, mgr, rank)
	if key == "armor" then
		local glass = mgr:owned("glass_pistol")
		return (1 + 0.025 * rank) -- rank_passives ARMOR_PER_RANK
			* ((glass > 0) and 1 / (2 * glass) or 1) -- glass_pistol DIV_PER_STACK (÷2 per stack, linear)
			* (1 + 0.50 * mgr:owned("dozer_guide")) -- dozer_guide ARMOR_BONUS
	elseif key == "movement" then
		local m = 1
		local ep = mgr:owned("escape_plan")
		if ep > 0 then
			m = m * (1 + 0.50 * (1 - 1 / (1 + (3 / 47) * ep))) -- escape_plan hyperbolic speed bonus
		end
		local d = mgr:owned("dozer_guide")
		if d > 0 then
			m = m * math.max(0.40, 1 - 0.15 * d) -- dozer_guide SPEED_MIN / SPEED_PENALTY
		end
		return m
	end
	return 1
end

-- CSR damage multiplier (kind = "ranged" | "melee"). Mirrors the item files + rank DMG_PER_RANK.
local function csr_weapon_dmg_mult(kind, mgr, rank)
	local glass = mgr:owned("glass_pistol")
	local m = (1 + 0.01 * rank) -- rank_passives DMG_PER_RANK
		* ((glass > 0) and 2 * glass or 1) -- glass_pistol DMG_MUL_PER_STACK (×2 per stack, linear)
		* (1 + 0.10 * mgr:owned("evidence_rounds")) -- evidence_rounds PER_STACK
	if kind == "melee" then
		m = m * (1 + 1.0 * mgr:owned("jiro_last_wish")) -- jiro_last_wish MELEE_BONUS_PER_STACK
	end
	return m
end

-- Localized weapon name from an equipped crafted table; prefers the player's custom name.
local function csr_weapon_display_name(category)
	local bm = managers.blackmarket
	local data = (category == "primaries") and bm:equipped_primary() or bm:equipped_secondary()
	local weapon_id = data and data.weapon_id
	if not weapon_id then
		return nil, nil
	end
	local slot = bm:equipped_weapon_slot(category)
	local custom = slot and bm:get_crafted_custom_name(category, slot, false)
	local tw = tweak_data.weapon[weapon_id]
	local name = custom or (tw and tw.name_id and managers.localization:text(tw.name_id)) or weapon_id
	return name, slot
end

-- One weapon row per slot: { slot = "PRIMARY", name = "AMCAR", dmg = "120", color = <Color> }.
-- Each slot pcall-guarded — equipped_* / WeaponDescription throw outside an active loadout.
-- mgr/rank drive the CSR damage preview; dmg is the buffed value, color encodes boost/reduce.
local function csr_collect_weapon_rows(mgr, rank)
	local bm = managers.blackmarket
	local mult = (tweak_data.gui and tweak_data.gui.stats_present_multiplier) or 10
	local rows = {}

	local function dmg_color(factor)
		if factor > 1.0001 then
			return tweak_data.screen_colors.stats_positive
		elseif factor < 0.9999 then
			return tweak_data.screen_colors.stats_negative
		end
		return Color.white
	end

	local function gun_row(category, slot_label)
		local out = { slot = slot_label, name = "—", dmg = nil, color = Color.white }
		pcall(function()
			local name, slot = csr_weapon_display_name(category)
			if not name then
				return
			end
			out.name = name
			local data = (category == "primaries") and bm:equipped_primary() or bm:equipped_secondary()
			-- Inventory-accurate base damage = base + mods + skills, same path BlackMarketGui uses.
			local base, mods, skill = WeaponDescription._get_stats(data.weapon_id, category, slot)
			if base and base.damage then
				local v = (base.damage.value or 0)
					+ ((mods and mods.damage and mods.damage.value) or 0)
					+ ((skill and skill.damage and skill.damage.value) or 0)
				local factor = (mgr and csr_weapon_dmg_mult("ranged", mgr, rank)) or 1
				out.dmg = tostring(math.round(v * factor))
				out.color = dmg_color(factor)
			end
		end)
		rows[#rows + 1] = out
	end

	gun_row("primaries", "PRIMARY")
	gun_row("secondaries", "SECONDARY")

	-- Melee: stats expose a min..max range; mirror the BM menu's min–max display.
	local melee = { slot = "MELEE", name = "—", dmg = nil, color = Color.white }
	pcall(function()
		local id = bm:equipped_melee_weapon()
		local tw = id and tweak_data.blackmarket.melee_weapons[id]
		if not tw then
			return
		end
		melee.name = (tw.name_id and managers.localization:text(tw.name_id)) or id
		local st = tw.stats
		if st and st.min_damage then
			local factor = (mgr and csr_weapon_dmg_mult("melee", mgr, rank)) or 1
			local mn = math.round((st.min_damage or 0) * mult * factor)
			local mx = math.round((st.max_damage or st.min_damage or 0) * mult * factor)
			-- "X (Y)": X = uncharged hit (min_damage), Y = full-charge hit (max_damage).
			melee.dmg = (mn == mx) and tostring(mx) or (mn .. " (" .. mx .. ")")
			melee.color = dmg_color(factor)
		end
	end)
	rows[#rows + 1] = melee

	-- Throwable: damage lives in tweak_data.projectiles (NOT .blackmarket.projectiles).
	-- Grenades deal explosion/fire damage, scaled host-side for the whole crew by rank passives
	-- (DMG_PER_RANK) and Glass Pistol (×2/stack AoE) — clients included via host sim. Preview both
	-- + tint. evidence_rounds (firearms/turrets) and jiro (melee) don't touch throwables, so excluded.
	local throwable = { slot = "THROWABLE", name = "—", dmg = nil, color = Color.white }
	pcall(function()
		local id, amount = bm:equipped_grenade()
		local bmtw = id and tweak_data.blackmarket.projectiles[id]
		if not bmtw then
			return
		end
		throwable.name = (bmtw.name_id and managers.localization:text(bmtw.name_id)) or id
		local ptw = tweak_data.projectiles[id]
		if ptw and ptw.damage then
			local glass = (mgr and mgr:owned("glass_pistol")) or 0
			local factor = (1 + 0.01 * rank) -- rank_passives DMG_PER_RANK
				* ((glass > 0) and 2 * glass or 1) -- glass_pistol DMG_MUL_PER_STACK (now scales AoE)
			throwable.dmg = tostring(math.round(ptw.damage * 10 * factor))
			throwable.color = dmg_color(factor)
		elseif amount then
			throwable.dmg = "×" .. tostring(amount)
		end
	end)
	rows[#rows + 1] = throwable

	return rows
end

-- Sectioned panel: PLAYER STATS (5 zebra rows) + per-weapon header + DAMAGE row.
-- Values preview CSR rank passives + item buffs (see folding mechanisms below); each value is
-- tinted green (boosted) / red (reduced) / white (unchanged). Row heights shrink to fit. Idempotent.
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

	local mgr = managers and managers.csr
	local rank = (mgr and mgr.host_rank and mgr:host_rank()) or 0

	-- Mechanism 1 (health/stamina/dodge): the real hooks fold buffs into vanilla getters when the
	-- gate is on. Force BOTH directions so the comparison is valid even mid-heist (live gate true):
	-- base_stats = gate forced OFF (vanilla); buffed_stats = gate forced ON. Distinct tables.
	local base_stats = with_csr_heist(false, csr_collect_heister_stats) or csr_collect_heister_stats()
	local buffed_stats = with_csr_heist(true, csr_collect_heister_stats) or csr_collect_heister_stats()

	-- Mechanism 2 (armor/movement): their buff hooks a fn the menu never calls — layer explicitly.
	if mgr and mgr.owned then
		for _, s in ipairs(buffed_stats) do
			s.value = s.value * csr_stat_offpath_mult(s.key, mgr, rank)
		end
	end

	-- Merge base vs buffed by index → display string + tint.
	local function stat_color(buf, base)
		if buf > base + 0.01 then
			return tweak_data.screen_colors.stats_positive
		elseif buf < base - 0.01 then
			return tweak_data.screen_colors.stats_negative
		end
		return Color.white
	end
	-- health/armor → whole numbers (decimals aren't meaningful); movement/stamina keep one decimal.
	local function fmt_stat(s)
		if s.pct then
			return math.round(s.value) .. "%"
		elseif s.key == "health" or s.key == "armor" then
			return tostring(math.round(s.value))
		end
		return csr_round1(s.value)
	end
	local stats = {}
	for i, s in ipairs(buffed_stats) do
		local base_v = (base_stats[i] and base_stats[i].value) or s.value
		stats[#stats + 1] = {
			label = s.label,
			value = fmt_stat(s),
			color = stat_color(s.value, base_v),
		}
	end

	local weapons = csr_collect_weapon_rows(mgr, rank)
	local pad = items_panel_padding
	local inner_w = panel:w() - pad * 2
	local dim = Color.white:with_alpha(0.5)

	-- Fit check: PLAYER STATS header + one header per weapon are fixed-height; the value rows
	-- (5 stats + 1 DAMAGE per weapon) scale to fill what's left. Shrink line_h on overflow.
	local n_value = #stats + #weapons
	local n_headers = 1 + #weapons
	local hdr_h = tweak_data.menu.pd2_small_font_size + 4
	local row_gap = 3
	local section_gap = 6
	local avail = panel:h() - pad * 2
	local fixed = hdr_h * n_headers + section_gap * #weapons + (n_value + n_headers) * row_gap
	local line_floor = tweak_data.menu.pd2_small_font_size + 2
	local line_h = tweak_data.menu.pd2_medium_font_size + 6
	local max_line = (n_value > 0) and math.floor((avail - fixed) / n_value) or line_h
	line_h = math.max(line_floor, math.min(line_h, max_line))

	local y = pad

	-- Section header: small dim caps with a thin underline; no zebra.
	local function header(label)
		content:text({
			text = label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = dim,
			x = 8,
			y = y,
			w = inner_w - 8,
			h = hdr_h,
			align = "left",
			vertical = "center",
			layer = 2,
		})
		-- Right edge (8 + inner_w) matches the right-aligned value text inside the offset rows below.
		content:rect({
			color = dim,
			x = 8,
			y = y + hdr_h - 1,
			w = inner_w,
			h = 1,
			layer = 1,
		})
		y = y + hdr_h + row_gap
	end

	-- Two-column data row (label left, value right) with optional zebra band.
	-- value_color tints the right-hand value (green boosted / red reduced / white neutral).
	local function value_row(label, value, zebra, indent, value_color)
		local row = content:panel({ x = pad, y = y, w = inner_w, h = line_h, layer = 5 })
		if zebra then
			row:rect({ color = Color.black:with_alpha(0.4), layer = 0 })
		end
		row:text({
			text = label,
			font = tweak_data.menu.pd2_small_font,
			font_size = tweak_data.menu.pd2_small_font_size,
			color = tweak_data.screen_colors.text,
			x = 8 + (indent or 0),
			w = row:w() - 16 - (indent or 0),
			h = row:h(),
			align = "left",
			vertical = "center",
			layer = 2,
		})
		row:text({
			text = value or "—",
			font = tweak_data.menu.pd2_medium_font,
			font_size = tweak_data.menu.pd2_medium_font_size,
			color = value_color or Color.white,
			x = 8,
			w = row:w() - 16,
			h = row:h(),
			align = "right",
			vertical = "center",
			layer = 2,
		})
		y = y + line_h + row_gap
	end

	header("PLAYER STATS")
	for i, s in ipairs(stats) do
		value_row(s.label, s.value, i % 2 == 1, 0, s.color)
	end

	-- Each weapon: its own header (SLOT: name) + divider line, then a DAMAGE row.
	for _, w in ipairs(weapons) do
		y = y + section_gap
		header(w.slot .. ": " .. w.name)
		value_row("DAMAGE", w.dmg, false, 12, w.color)
	end
end
