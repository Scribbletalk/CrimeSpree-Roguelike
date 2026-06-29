-- CSRMissionsMenuComponent heister panel: PLAYER STATS + per-weapon DAMAGE preview.
-- CSR rank/item buffs folded in and tinted green/red vs un-buffed base. Borrowed by briefing_sidebar.lua.

if not RequiredScript then
	return
end

if not CSRMissionsMenuComponent then
	return
end

local items_panel_padding = 16

-- One-decimal, trailing zeros stripped ("230.0" -> "230", "4.5" -> "4.5").
local function csr_round1(n)
	return (string.format("%.1f", n):gsub("%.?0+$", ""))
end

-- Run a max-stat multiplier through the modifier system, exactly like PlayerDamage:_raw_max_armor /
-- _raw_max_health do (GageModifierMaxArmor / MaxHealth -- e.g. the Crime Spree increased-armor asset).
-- Safe no-op when no modifiers are active or the manager is absent.
local function csr_modify(id, value)
	local m = managers and managers.modifiers
	if m and m.modify_value then
		return m:modify_value(id, value)
	end
	return value
end

-- Stats PlayerInventoryGui:_get_armor_stats computes. The vanilla fn only reads stat.name, but a
-- faithful list lets third-party _get_armor_stats hooks (balance mods) find every stat they expect.
local CSR_INV_STATS_SHOWN = {
	{ name = "health" },
	{ name = "armor" },
	{ name = "movement" },
	{ name = "dodge" },
	{ name = "stamina" },
	{ name = "concealment" },
	{ name = "crit" },
	{ name = "damage_shake" },
}

-- Player stat totals via the LIVE PlayerInventoryGui:_get_armor_stats -- the exact path the vanilla
-- character screen uses, so any balance mod that hooks it (or the getters it calls) is reflected
-- automatically. We pass a minimal stand-in self (the fn only reads self._stats_shown). Returns
-- { [stat] = display_total } or nil to fall back to the hand-rolled formula.
local function csr_inventory_stat_totals(name)
	if not (name and PlayerInventoryGui and PlayerInventoryGui._get_armor_stats) then
		return nil
	end
	local ok, base_stats, mods_stats, skill_stats =
		pcall(PlayerInventoryGui._get_armor_stats, { _stats_shown = CSR_INV_STATS_SHOWN }, name)
	if not (ok and type(base_stats) == "table" and type(skill_stats) == "table") then
		return nil
	end
	local out = {}
	for _, s in ipairs(CSR_INV_STATS_SHOWN) do
		local b = (base_stats[s.name] and base_stats[s.name].value) or 0
		local m = (mods_stats and mods_stats[s.name] and mods_stats[s.name].value) or 0
		local k = (skill_stats[s.name] and skill_stats[s.name].value) or 0
		out[s.name] = b + m + k
	end
	-- _get_armor_stats omits Frenzy (max_health_reduction lives in PlayerDamage, not the GUI math).
	out.health = out.health * (managers.player:upgrade_value("player", "max_health_reduction", 1) or 1)
	return out
end

-- Per-stat fallback (base + skill), mirrors PlayerInventoryGui:_get_armor_stats math by hand. Used
-- only when the live call above is unavailable. health/armor route through CSR-hooked getters, so
-- with_csr_heist matters.
local function csr_heister_stat_value(stat_name, name, upgrade_level, detection_risk, mult)
	local player = managers.player
	if stat_name == "health" then
		-- Mirror PlayerDamage:_raw_max_health (skill mult -> modifier system), then apply Frenzy's
		-- max_health_reduction on top (playerdamage.lua:966 -- it lives OUTSIDE health_skill_multiplier).
		local base = (tweak_data.player.damage.HEALTH_INIT + player:health_skill_addend()) * mult
		local hmul = csr_modify("PlayerDamage:GetMaxHealth", player:health_skill_multiplier())
		return base * hmul * player:upgrade_value("player", "max_health_reduction", 1)
	elseif stat_name == "armor" then
		-- Mirror PlayerDamage:_raw_max_armor exactly: getters with NO override (engine resolves
		-- equipped_armor(true, true)), and the skill mult run through the modifier system.
		local base = (tweak_data.player.damage.ARMOR_INIT + player:body_armor_value("armor")) * mult
		local amul = csr_modify("PlayerDamage:GetMaxArmor", player:body_armor_skill_multiplier())
		return (base + player:body_armor_skill_addend() * mult) * amul
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

-- Collect raw stat values; honors whatever in_csr_heist() returns at call time.
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
		{ key = "armor", loc = "bm_menu_armor", pct = false, fallback = (pd.damage.ARMOR_INIT or 0) * mult },
		{ key = "health", loc = "bm_menu_health", pct = false, fallback = (pd.damage.HEALTH_INIT or 0) * mult },
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

	-- Prefer the live inventory math (mod-aware); fall back to the hand-rolled formula per stat.
	local inv = csr_inventory_stat_totals(name)

	local out = {}
	for _, d in ipairs(defs) do
		local v = inv and inv[d.key]
		if type(v) ~= "number" then
			local ok, hv = pcall(csr_heister_stat_value, d.key, name, upgrade_level, detection_risk, mult)
			v = (ok and type(hv) == "number") and hv or d.fallback
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

-- Shadow in_csr_heist() with a forced return while fn runs, then restore.
-- Must force BOTH directions: mid-heist the live gate is true, so un-forced base == buffed -> no tint.
local function with_csr_heist(value, fn)
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist) then
		return fn()
	end
	local had = rawget(mgr, "in_csr_heist")
	mgr.in_csr_heist = function()
		return value
	end
	-- Also force the cached rank: rank_passives' on-path HP hook (health_skill_multiplier) reads
	-- _G.CSR_active_rank, NOT in_csr_heist(), and PlayerDamage:update never ticks it in menus. So the
	-- buffed pass must see host_rank for the HP-per-rank passive to show; the base pass sees 0.
	local had_rank = _G.CSR_active_rank
	_G.CSR_active_rank = (value and mgr.host_rank and mgr:host_rank()) or 0
	local ok, res = pcall(fn)
	mgr.in_csr_heist = had
	_G.CSR_active_rank = had_rank
	if ok then
		return res
	end
	return nil
end

-- Fold the multiplier every owned item contributes to one off-path stat, via its optional
-- stat_preview descriptor (fn(count) -> { <stat_key> = multiplier, ... }). No item is named here,
-- so any item -- including third-party addon items -- that declares stat_preview is reflected
-- automatically. Pure multipliers compose order-independently (Critical Rule #13: no accumulator).
-- stat_key is one of: armor, movement, damage_ranged, damage_melee, damage_throwable.
local function csr_item_preview_mult(mgr, stat_key)
	local mult = 1
	local owned = mgr.player_items and mgr:player_items(mgr:local_peer_id())
	if type(owned) ~= "table" then
		return mult
	end
	for itype, count in pairs(owned) do
		if type(count) == "number" and count > 0 then
			local def = mgr.item_def and mgr:item_def(itype)
			local sp = def and def.stat_preview
			if sp then
				-- pcall: a buggy addon descriptor must not blank the whole panel.
				local ok, contrib = pcall(sp, count)
				local m = ok and type(contrib) == "table" and contrib[stat_key]
				if type(m) == "number" and m > 0 then
					mult = mult * m
				end
			end
		end
	end
	return mult
end

-- Per-rank passive multiplier for an off-path stat. Reads the constants rank_passives.lua exports
-- (_G.CSR_ARMOR_PER_RANK / _G.CSR_DMG_PER_RANK) so the panel never drifts from the balance source.
-- Health is on-path (auto-folded) and movement has no rank scaling, so neither is handled here.
local function csr_rank_mult(stat_key, rank)
	if stat_key == "armor" then
		return 1 + (_G.CSR_ARMOR_PER_RANK or 0) * rank
	elseif stat_key == "damage" then
		return 1 + (_G.CSR_DMG_PER_RANK or 0) * rank
	end
	return 1
end

-- Localized weapon name; prefers player's custom name over tweak_data name_id.
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

-- Build weapon rows { slot, name, dmg, color } for primary/secondary/melee/throwable.
-- Each slot is pcall-guarded; dmg is the CSR-buffed value, color encodes boost/reduce.
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
			-- Inventory-accurate base = base + mods + skills, same path BlackMarketGui uses.
			local base, mods, skill = WeaponDescription._get_stats(data.weapon_id, category, slot)
			if base and base.damage then
				local v = (base.damage.value or 0)
					+ ((mods and mods.damage and mods.damage.value) or 0)
					+ ((skill and skill.damage and skill.damage.value) or 0)
				local factor = (mgr and csr_item_preview_mult(mgr, "damage_ranged") * csr_rank_mult("damage", rank))
					or 1
				out.dmg = tostring(math.round(v * factor))
				out.color = dmg_color(factor)
			end
		end)
		rows[#rows + 1] = out
	end

	gun_row("primaries", "PRIMARY")
	gun_row("secondaries", "SECONDARY")

	-- Melee exposes min..max; mirror the BM menu min-max display.
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
			local factor = (mgr and csr_item_preview_mult(mgr, "damage_melee") * csr_rank_mult("damage", rank)) or 1
			local mn = math.round((st.min_damage or 0) * mult * factor)
			local mx = math.round((st.max_damage or st.min_damage or 0) * mult * factor)
			-- "X (Y)": X = uncharged (min_damage), Y = full-charge (max_damage).
			melee.dmg = (mn == mx) and tostring(mx) or (mn .. " (" .. mx .. ")")
			melee.color = dmg_color(factor)
		end
	end)
	rows[#rows + 1] = melee

	-- Throwable damage is in tweak_data.projectiles (NOT .blackmarket.projectiles).
	-- Grenade dmg is host-sim'd for the whole crew; evidence_rounds/jiro don't apply to throwables.
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
			local factor = (mgr and csr_item_preview_mult(mgr, "damage_throwable") * csr_rank_mult("damage", rank)) or 1
			throwable.dmg = tostring(math.round(ptw.damage * 10 * factor))
			throwable.color = dmg_color(factor)
		elseif amount then
			throwable.dmg = "×" .. tostring(amount)
		end
	end)
	rows[#rows + 1] = throwable

	return rows
end

-- Build PLAYER STATS + per-weapon DAMAGE sections. Idempotent; clears previous content first.
-- Two folding mechanisms: (1) shadow in_csr_heist for health/stamina/dodge; (2) explicit mult for armor/movement.
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

	-- Force gate OFF for base, ON for buffed; both calls needed even mid-heist (live gate is true).
	local base_stats = with_csr_heist(false, csr_collect_heister_stats) or csr_collect_heister_stats()
	local buffed_stats = with_csr_heist(true, csr_collect_heister_stats) or csr_collect_heister_stats()

	-- Armor/movement: their CSR hooks bypass this panel's call path, so fold the off-path item
	-- multipliers (+ rank for armor) here. health/stamina/dodge are on-path -> already in buffed_stats.
	if mgr and mgr.player_items then
		for _, s in ipairs(buffed_stats) do
			if s.key == "armor" then
				s.value = s.value * csr_item_preview_mult(mgr, "armor") * csr_rank_mult("armor", rank)
			elseif s.key == "movement" then
				s.value = s.value * csr_item_preview_mult(mgr, "movement")
			end
		end
	end

	local function stat_color(buf, base)
		if buf > base + 0.01 then
			return tweak_data.screen_colors.stats_positive
		elseif buf < base - 0.01 then
			return tweak_data.screen_colors.stats_negative
		end
		return Color.white
	end
	-- health/armor as integers; movement/stamina keep one decimal.
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

	-- Headers are fixed height; value rows scale to fill remaining space, clamped to pd2_small+2.
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

	-- Small dim caps label + 1px underline; no zebra.
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
		-- Underline spans full inner_w to align with right-aligned values in rows below.
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

	-- Two-column row: label left, value right; optional zebra band; value_color for buff tint.
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

	for _, w in ipairs(weapons) do
		y = y + section_gap
		header(w.slot .. ": " .. w.name)
		value_row("DAMAGE", w.dmg, false, 12, w.color)
	end
end
