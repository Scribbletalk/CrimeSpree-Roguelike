-- Crime Spree Roguelike Alpha 2 - Stats Page (Table Layout)

if not RequiredScript then
	return
end



-- === STATS PAGE CLASS ===
if not CrimeSpreeModifierDetailsPage then
	return
end

CrimeSpreePlayerStatsPage = CrimeSpreePlayerStatsPage or class(CrimeSpreeModifierDetailsPage)

function CrimeSpreePlayerStatsPage:init(name_id, page_panel, fullscreen_panel, parent)
	CrimeSpreePlayerStatsPage.super.init(self, name_id, page_panel, fullscreen_panel, parent)

	self._scroll_offset = 0
	self._scroll_speed = 50
	self._fullscreen_panel = fullscreen_panel

	if self:panel() then
		local panel = self:panel()

		-- Save original parent heights (restore when switching to other tabs)
		local parent_panel = panel:parent()
		if parent_panel then
			self._orig_parent_h = parent_panel:h()
			local gp = parent_panel:parent()
			if gp then
				self._orig_gp_h = gp:h()
			end
		end

		-- Expand our page panel only (parents are expanded/restored in set_active)
		local screen_h = fullscreen_panel and fullscreen_panel:h() or 720
		local new_height = screen_h - panel:world_y() - 20
		panel:set_h(math.max(new_height, 500))
		if panel.set_clip then panel:set_clip(false) end

		panel:clear()
		self:_setup_stats()
	end
end

-- Expand parent panels so stats content is fully visible
function CrimeSpreePlayerStatsPage:_expand_parents()
	local panel = self:panel()
	if not panel then return end

	local parent_panel = panel:parent()
	if parent_panel then
		parent_panel:set_h(math.max(parent_panel:h(), panel:h()))
		if parent_panel.set_clip then parent_panel:set_clip(false) end
		local gp = parent_panel:parent()
		if gp then
			gp:set_h(math.max(gp:h(), panel:h()))
			if gp.set_clip then gp:set_clip(false) end
		end
	end
end

-- Restore parent panels to original size (so other tabs like REWARDS render correctly)
function CrimeSpreePlayerStatsPage:_restore_parents()
	local panel = self:panel()
	if not panel then return end

	local parent_panel = panel:parent()
	if parent_panel and self._orig_parent_h then
		parent_panel:set_h(self._orig_parent_h)
		local gp = parent_panel:parent()
		if gp and self._orig_gp_h then
			gp:set_h(self._orig_gp_h)
		end
	end
end

-- Override set_active: expand parents when STATS tab shown, restore when hidden
function CrimeSpreePlayerStatsPage:set_active(active)
	if active then
		self:_expand_parents()
	else
		self:_restore_parents()
	end
	return CrimeSpreePlayerStatsPage.super.set_active(self, active)
end

-- Count stacks of an item by ID prefix
local function count_stacks(id_prefix)
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		return 0
	end

	local count = 0
	local active_modifiers = managers.crime_spree:active_modifiers() or {}
	for _, mod_data in ipairs(active_modifiers) do
		if mod_data.id and string.find(mod_data.id, id_prefix, 1, true) == 1 then
			count = count + 1
		end
	end
	return count
end

-- Column positions (6 columns)
local COL_STAT = 10
local COL_TOTAL = 160
local COL_BASE = 250
local COL_SKILL = 330
local COL_LEVEL = 410
local COL_ITEMS = 490

-- Colors
local COLOR_HEADER = Color(1, 0.85, 0.1)       -- Yellow
local COLOR_POSITIVE = Color(0.7, 1, 0.7)       -- Green
local COLOR_NEGATIVE = Color(1, 0.5, 0.5)       -- Red
local COLOR_NEUTRAL = Color(0.7, 0.7, 0.7)      -- Gray
local COLOR_WEAPON = Color(0.9, 0.9, 0.9)       -- Light gray
local COLOR_SEPARATOR = Color(0.3, 0.3, 0.3)    -- Dark gray

-- Row heights
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local SEPARATOR_GAP = 10
local SECTION_GAP = 15

function CrimeSpreePlayerStatsPage:_setup_stats()
	local panel = self:panel()
	if not panel then return end

	-- Dark background
	if not self._background then
		self._background = panel:rect({
			name = "csr_stats_background",
			x = 0, y = 0,
			w = panel:w(), h = panel:h(),
			color = Color.black, alpha = 0.4, layer = -1
		})
	end

	-- Content panel
	if not self._content_panel then
		self._content_panel = panel:panel({
			name = "csr_stats_content",
			x = 0, y = 0,
			w = panel:w(), h = panel:h()
		})
	end

	local content = self._content_panel
	content:clear()

	local y = 10
	local lang = (CSR_Settings and CSR_Settings:GetLanguage() or "en")

	-- Check Crime Spree active
	if not managers.crime_spree or not managers.crime_spree:is_active() then
		content:text({
			text = lang == "ru" and "Начните Crime Spree чтобы увидеть статистику." or "Start a Crime Spree to see stats.",
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 10, y = y
		})
		self._content_height = y + 50
		content:set_h(self._content_height)
		return
	end

	-- === DATA CALCULATION ===
	local cs_level = managers.crime_spree:spree_level() or 0

	-- Count item stacks
	local health_stacks = count_stacks("player_health_boost")
	local damage_stacks = count_stacks("player_damage_boost")
	local dozer_stacks = count_stacks("player_dozer_guide")
	local glass_stacks = count_stacks("player_glass_pistol")
	local keys_stacks = count_stacks("player_car_keys")
	local sneakers_stacks = count_stacks("player_escape_plan")
	local duct_tape_stacks = count_stacks("player_duct_tape_")
	local bandaid_stacks = count_stacks("player_worn_bandaid")
	local jiro_stacks = count_stacks("player_jiro_last_wish")

	-- HP: bonus is added to health_skill_multiplier, glass is multiplicative
	-- Game formula: HP = HEALTH_INIT * (vanilla_mult + cs_bonus + dogtags_bonus) * glass_mult
	local cs_hp_bonus_to_mult = cs_level * 0.001  -- added to health_skill_multiplier per level
	local dogtags_hp_bonus_to_mult = health_stacks * 0.1
	local glass_hp_mult = math.pow(0.5, glass_stacks)

	-- Damage: passive additive, glass multiplicative (×1.5 per stack)
	local passive_dmg = cs_level * 0.0005
	local item_dmg_additive = (damage_stacks * 0.1) + (dozer_stacks * 0.05)
	local glass_dmg_mult = math.pow(1.5, glass_stacks)
	local total_dmg_bonus = (1 + passive_dmg + item_dmg_additive) * glass_dmg_mult - 1

	-- Armor: 0.1% per level direct multiplier, glass is multiplicative
	local passive_armor = cs_level * 0.001
	local dozer_armor_bonus = dozer_stacks * 0.5
	local glass_armor_mult = math.pow(0.5, glass_stacks)

	-- Regen
	local passive_regen = cs_level * 0.0001

	-- Dodge (hyperbolic)
	local dodge_bonus = 0
	if keys_stacks > 0 then
		dodge_bonus = (1 - 1 / (1 + keys_stacks / 19)) * 100
	end
	local dodge_penalty = dozer_stacks * 5
	local total_dodge = math.max(0, dodge_bonus - dodge_penalty)

	-- Movement Speed (hyperbolic)
	local speed_bonus = 0
	if sneakers_stacks > 0 then
		speed_bonus = 0.5 * (1 - 1 / (1 + (3 / 47) * sneakers_stacks)) * 100
	end
	local speed_penalty = 0
	if dozer_stacks > 0 then
		speed_penalty = (1 - math.max(0.4, 1 - 0.15 * dozer_stacks)) * 100
	end
	local total_speed = speed_bonus - speed_penalty

	-- Interact Speed
	local total_interact = duct_tape_stacks * 5

	-- === BASE VALUES & SKILL SEPARATION ===
	-- Note: skill values include both perks/skills AND crew bonuses

	-- HP: pure base = 230, skill from perks, crew from upgrades
	local pure_base_hp = 230
	local skill_hp = 0
	local crew_hp = 0

	if managers.player then
		-- Skill multiplier from perks/skills
		if managers.player.health_skill_multiplier then
			local hp_mult = managers.player:health_skill_multiplier() or 1.0
			skill_hp = pure_base_hp * (hp_mult - 1)  -- Absolute bonus from skills
		end

		-- Crew bonuses (crew boosts like Reinforcer: +60 HP)

		-- Try to get crew boost through upgrade_value
		local crew_boost_hp = 0

		if managers.player and managers.player.upgrade_value then
			-- Try different upgrade IDs
			local test_ids = {
				{"team", "health", "health_increase"},
				{"team", "crew_health"},
				{"crew", "health_increase"},
				{"player", "passive_health_increase"},
				{"team", "passive_health_increase"}
			}

			for _, id_parts in ipairs(test_ids) do
				local result = nil
				if #id_parts == 3 then
					result = managers.player:upgrade_value(id_parts[1], id_parts[2], id_parts[3], 0)
				elseif #id_parts == 2 then
					result = managers.player:upgrade_value(id_parts[1], id_parts[2], 0)
				end

				-- Force to number
				result = tonumber(result) or 0


				if result > 0 then
					crew_boost_hp = result
					break
				end
			end
		end

		-- If still not found, check if player has AI crew
		if crew_boost_hp == 0 then
			-- Check if player has AI crew active (safe chain)
			local num_ai = 0
			if managers.groupai then
				local state = managers.groupai:state()
				if state and state.num_AI_criminals then
					num_ai = state:num_AI_criminals() or 0
				end
			end

			if num_ai > 0 then
				crew_boost_hp = 60  -- Hardcoded Reinforcer value
			else
				crew_boost_hp = 0  -- No bots, no boost
			end
		end

		crew_hp = tonumber(crew_boost_hp) or 0
	end

	local total_skill_hp = skill_hp + crew_hp  -- Combined skill + crew
	local base_hp = pure_base_hp + total_skill_hp  -- Total base before CSR

	-- Armor & Movement: read from vanilla PlayerInventoryGui stats (don't calculate manually)
	local base_armor = 0
	local base_movement = 0
	local pure_base_armor = 0
	local skill_armor = 0
	local crew_armor = 0

	if managers.player and tweak_data.player and tweak_data.player.damage then
		local armor_id = managers.blackmarket and managers.blackmarket:equipped_armor(true, true) or "none"

		-- Try to call vanilla _get_armor_stats function directly (returns armor + movement)
		if PlayerInventoryGui and PlayerInventoryGui._get_armor_stats then
			-- Create minimal fake instance to call the method
			local fake_instance = {
				_stats_shown = {
					{name = "armor"},
					{name = "movement"}
				}
			}

			local success, base_stats, mods_stats, skill_stats = pcall(PlayerInventoryGui._get_armor_stats, fake_instance, armor_id)

			if success and base_stats then
				-- Extract armor values
				pure_base_armor = (base_stats and base_stats.armor and base_stats.armor.value) or 0
				skill_armor = (skill_stats and skill_stats.armor and skill_stats.armor.value) or 0

				-- Extract movement values
				local move_base_val = (base_stats and base_stats.movement and base_stats.movement.value) or 0
				local move_skill_val = (skill_stats and skill_stats.movement and skill_stats.movement.value) or 0
				base_movement = move_base_val + move_skill_val

			else
			end
		else
		end

		-- Fallback if vanilla method failed
		if pure_base_armor == 0 then
			local armor_data = tweak_data.blackmarket.armors[armor_id]
			local upgrade_level = armor_data and armor_data.upgrade_level or 0
			local armor_init = tweak_data.player.damage.ARMOR_INIT or 0
			local armor_mod = managers.player:body_armor_value("armor", upgrade_level) or 0
			local display_mult = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 10
			local base_value = (armor_init + armor_mod) * display_mult
			skill_armor = (base_value + managers.player:body_armor_skill_addend(armor_id) * display_mult) * managers.player:body_armor_skill_multiplier(armor_id) - base_value
			pure_base_armor = base_value
		end

		-- Try to get crew boost for armor
		local crew_boost_armor = 0

		if managers.player and managers.player.upgrade_value then
			local test_ids = {
				{"team", "armor", "armor_increase"},
				{"team", "crew_armor"},
				{"crew", "armor_increase"},
				{"player", "passive_armor_increase"},
				{"team", "passive_armor_increase"}
			}

			for _, id_parts in ipairs(test_ids) do
				local result = nil
				if #id_parts == 3 then
					result = managers.player:upgrade_value(id_parts[1], id_parts[2], id_parts[3], 0)
				elseif #id_parts == 2 then
					result = managers.player:upgrade_value(id_parts[1], id_parts[2], 0)
				end

				result = tonumber(result) or 0

				if result > 0 then
					crew_boost_armor = result
					break
				end
			end
		end

		crew_armor = tonumber(crew_boost_armor) or 0

		base_armor = pure_base_armor + skill_armor + crew_armor
	end

	-- Dodge: base dodge from perk deck (no CSR items)
	local base_dodge = 0
	if managers.player and managers.player.upgrade_value then
		base_dodge = (managers.player:upgrade_value("player", "passive_dodge_chance", 0) or 0) * 100
	end

	-- === FINAL VALUES (game-accurate: Glass Pistol applied multiplicatively) ===
	-- vanilla_hp_mult derived from base_hp (includes skill): e.g. 460/230 = 2.0 for Muscle
	local vanilla_hp_mult = (pure_base_hp > 0) and (base_hp / pure_base_hp) or 1.0
	local final_hp = pure_base_hp * (vanilla_hp_mult + cs_hp_bonus_to_mult + dogtags_hp_bonus_to_mult) * glass_hp_mult
	local final_armor = base_armor * (1 + passive_armor + dozer_armor_bonus) * glass_armor_mult
	local final_regen = final_hp * passive_regen
	local final_dodge = base_dodge + total_dodge  -- additive

	-- Column display percentages: show as % of base multiplier (consistent with armor display)
	local passive_hp = cs_hp_bonus_to_mult
	local item_hp = dogtags_hp_bonus_to_mult
	item_hp = item_hp + (glass_hp_mult - 1)  -- glass as -50% in ITEMS column
	local item_armor = dozer_armor_bonus + (glass_armor_mult - 1)  -- glass as -50% in ITEMS column

	-- === HELPER: format value string ===
	local function fmt_pct(val)
		if math.abs(val) < 0.001 then return "\xe2\x80\x94" end
		return string.format("%+.1f%%", val * 100)
	end

	local function color_for(val)
		if val > 0.001 then return COLOR_POSITIVE
		elseif val < -0.001 then return COLOR_NEGATIVE
		else return COLOR_NEUTRAL end
	end

	-- === HELPER: add table row (6 columns) ===
	-- skill_str is absolute value (e.g. "+60"), includes both perks and crew bonuses
	-- total_num/base_num: optional numeric values; if total_num < base_num → force red
	local function add_row(row_y, stat_name, total_str, base_str, skill_str, level_val, items_val, total_num, base_num)
		-- Total color = red if actual TOTAL < actual BASE, else based on combined bonus
		local combined = level_val + items_val
		local total_color
		if total_num ~= nil and base_num ~= nil and total_num < base_num - 0.5 then
			total_color = COLOR_NEGATIVE
		else
			total_color = color_for(combined)
		end

		content:text({
			text = stat_name,
			font = tweak_data.menu.pd2_small_font, font_size = 16,
			color = Color.white,
			x = COL_STAT, y = row_y
		})
		content:text({
			text = total_str,
			font = tweak_data.menu.pd2_small_font, font_size = 16,
			color = total_color,
			x = COL_TOTAL, y = row_y
		})
		content:text({
			text = base_str,
			font = tweak_data.menu.pd2_small_font, font_size = 16,
			color = COLOR_NEUTRAL,
			x = COL_BASE, y = row_y
		})
		content:text({
			text = skill_str or "-",
			font = tweak_data.menu.pd2_small_font, font_size = 16,
			color = COLOR_POSITIVE,
			x = COL_SKILL, y = row_y
		})
		content:text({
			text = fmt_pct(level_val),
			font = tweak_data.menu.pd2_small_font, font_size = 16,
			color = color_for(level_val),
			x = COL_LEVEL, y = row_y
		})
		content:text({
			text = fmt_pct(items_val),
			font = tweak_data.menu.pd2_small_font, font_size = 16,
			color = color_for(items_val),
			x = COL_ITEMS, y = row_y
		})
	end

	-- === TABLE HEADER ===
	local hdr_stat = lang == "ru" and "СТАТ" or "STAT"
	local hdr_total = lang == "ru" and "ИТОГО" or "TOTAL"
	local hdr_base = lang == "ru" and "БАЗА" or "BASE"
	local hdr_skill = lang == "ru" and "СКИЛЛ" or "SKILL"
	local hdr_level = "CS LEVEL"
	local hdr_items = lang == "ru" and "ПРЕДМЕТЫ" or "ITEMS"

	content:text({ text = hdr_stat, font = tweak_data.menu.pd2_medium_font, font_size = 16, color = COLOR_HEADER, x = COL_STAT, y = y })
	content:text({ text = hdr_total, font = tweak_data.menu.pd2_medium_font, font_size = 16, color = COLOR_HEADER, x = COL_TOTAL, y = y })
	content:text({ text = hdr_base, font = tweak_data.menu.pd2_medium_font, font_size = 16, color = COLOR_HEADER, x = COL_BASE, y = y })
	content:text({ text = hdr_skill, font = tweak_data.menu.pd2_medium_font, font_size = 16, color = COLOR_HEADER, x = COL_SKILL, y = y })
	content:text({ text = hdr_level, font = tweak_data.menu.pd2_medium_font, font_size = 16, color = COLOR_HEADER, x = COL_LEVEL, y = y })
	content:text({ text = hdr_items, font = tweak_data.menu.pd2_medium_font, font_size = 16, color = COLOR_HEADER, x = COL_ITEMS, y = y })
	y = y + HEADER_HEIGHT

	-- Separator line
	content:rect({
		x = COL_STAT, y = y,
		w = (COL_ITEMS + 80) - COL_STAT, h = 1,
		color = COLOR_SEPARATOR, alpha = 0.6
	})
	y = y + SEPARATOR_GAP

	-- === STAT ROWS ===
	-- add_row(y, name, total_str, base_str, level_val, items_val)

	-- Armor (MOVED FIRST)
	local armor_label = lang == "ru" and "Броня" or "Armor"
	local total_skill_armor = skill_armor + crew_armor
	local skill_armor_str = total_skill_armor > 0 and string.format("+%.0f", total_skill_armor) or "-"
	add_row(y, armor_label, string.format("%.0f", final_armor), string.format("%.0f", pure_base_armor), skill_armor_str, passive_armor, item_armor, final_armor, pure_base_armor)
	y = y + ROW_HEIGHT

	-- Health (MOVED SECOND) with inline Frenzy/Wolverine cap
	local hp_label = lang == "ru" and "Здоровье" or "Health"
	local skill_hp_str = total_skill_hp > 0 and string.format("+%.0f", total_skill_hp) or "-"

	-- Check for Frenzy/Wolverine cap
	local health_cap = managers.player:upgrade_value("player", "max_health_reduction", 1)
	local hp_total_str
	if health_cap < 1 then
		local cap_percent = math.floor(health_cap * 100)
		local capped_hp = math.floor(final_hp * health_cap)
		hp_total_str = string.format("%.0f (%d%%)", capped_hp, cap_percent)
	else
		hp_total_str = string.format("%.0f", final_hp)
	end

	local effective_hp = (health_cap < 1) and (final_hp * health_cap) or final_hp
	add_row(y, hp_label, hp_total_str, string.format("%.0f", pure_base_hp), skill_hp_str, passive_hp, item_hp, effective_hp, pure_base_hp)
	y = y + ROW_HEIGHT

	-- HP Regen (CS level passive + Worn Band-Aid flat regen)
	local regen_label = lang == "ru" and "Регенерация" or "HP Regen"
	local bandaid_regen = bandaid_stacks * 5  -- flat display HP per 10s
	local total_regen = final_regen + bandaid_regen
	local bandaid_regen_pct = (final_hp > 0) and (bandaid_regen / final_hp) or 0
	add_row(y, regen_label, string.format("%.1f HP/10s", total_regen), "0", "-", passive_regen, bandaid_regen_pct)
	y = y + ROW_HEIGHT

	-- Dodge
	local dodge_label = lang == "ru" and "Уклонение" or "Dodge"
	local dodge_total_str = string.format("%.1f%%", final_dodge)
	local dodge_base_str = base_dodge > 0 and string.format("%.1f%%", base_dodge) or "0%"
	add_row(y, dodge_label, dodge_total_str, dodge_base_str, "-", 0, total_dodge / 100)
	y = y + ROW_HEIGHT

	-- Movement Speed (read from vanilla, no %)
	local speed_label = lang == "ru" and "Скорость" or "Move Speed"
	-- Calculate CSR bonuses to movement (from sneakers/dozer)
	local speed_csr_bonus = 0
	if sneakers_stacks > 0 then
		speed_csr_bonus = speed_csr_bonus + (0.5 * (1 - 1 / (1 + (3 / 47) * sneakers_stacks)))
	end
	if dozer_stacks > 0 then
		speed_csr_bonus = speed_csr_bonus - (1 - math.max(0.4, 1 - 0.15 * dozer_stacks))
	end
	local final_movement = base_movement * (1 + speed_csr_bonus)
	add_row(y, speed_label, string.format("%.1f", final_movement), string.format("%.1f", base_movement), "-", 0, speed_csr_bonus)
	y = y + ROW_HEIGHT

	-- Interact Speed
	local interact_label = lang == "ru" and "Взаимодействие" or "Interact Speed"

	-- Try to get crew ability "Quick" bonus
	local crew_interact = 0

	if managers.player and managers.player.upgrade_value then
		local test_ids = {
			{"team", "crew_interact"},
			{"crew", "interact_speed"},
			{"player", "crew_interact_speed"},
			{"team", "interact", "interact_speed"}
		}

		for _, id_parts in ipairs(test_ids) do
			local result = nil
			if #id_parts == 3 then
				result = managers.player:upgrade_value(id_parts[1], id_parts[2], id_parts[3], 0)
			elseif #id_parts == 2 then
				result = managers.player:upgrade_value(id_parts[1], id_parts[2], 0)
			end

			result = tonumber(result) or 0

			if result > 0 then
				crew_interact = result
				break
			end
		end
	end


	-- Total interact = 100% (base) + crew ability + duct tape items
	local total_interact_speed = 100 + crew_interact + total_interact
	local interact_total_str = string.format("%.1f%%", total_interact_speed)
	local crew_interact_str = crew_interact > 0 and string.format("+%.1f%%", crew_interact) or "-"

	add_row(y, interact_label, interact_total_str, "100%", crew_interact_str, 0, total_interact / 100)
	y = y + ROW_HEIGHT

	-- === WEAPONS SECTION ===
	y = y + SECTION_GAP

	content:text({
		text = "WEAPONS",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_STAT, y = y
	})
	y = y + HEADER_HEIGHT

	-- Separator
	content:rect({
		x = COL_STAT, y = y,
		w = (COL_ITEMS + 80) - COL_STAT, h = 1,
		color = COLOR_SEPARATOR, alpha = 0.6
	})
	y = y + 8

	-- Display damage helper (inventory-style values for guns)
	local function get_display_damage(weapon_tweak)
		if not weapon_tweak or not weapon_tweak.stats then return nil end
		local damage_index = weapon_tweak.stats.damage
		if not damage_index then return nil end

		local damage_table = tweak_data.weapon.stats.damage
		if not damage_table then return nil end

		damage_index = math.clamp(damage_index, 1, #damage_table)
		local multiplier = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 1
		return damage_table[damage_index] * multiplier
	end

	-- Gun items column: evidence + dozer + glass (additive approximation)
	local gun_items_val = item_dmg_additive + (glass_dmg_mult - 1)

	-- Primary
	local equipped_primary = managers.blackmarket:equipped_primary()
	if equipped_primary and equipped_primary.weapon_id then
		local weapon_tweak = tweak_data.weapon[equipped_primary.weapon_id]
		if weapon_tweak then
			local weapon_name = managers.localization:text(weapon_tweak.name_id) or equipped_primary.weapon_id
			local base_dmg = get_display_damage(weapon_tweak)
			if base_dmg then
				local final_dmg = base_dmg * (1 + passive_dmg + item_dmg_additive) * glass_dmg_mult
				add_row(y, weapon_name, string.format("%.0f", final_dmg), string.format("%.0f", base_dmg), "\xe2\x80\x94", passive_dmg, gun_items_val, final_dmg, base_dmg)
				y = y + ROW_HEIGHT
			end
		end
	end

	-- Secondary
	local equipped_secondary = managers.blackmarket:equipped_secondary()
	if equipped_secondary and equipped_secondary.weapon_id then
		local weapon_tweak = tweak_data.weapon[equipped_secondary.weapon_id]
		if weapon_tweak then
			local weapon_name = managers.localization:text(weapon_tweak.name_id) or equipped_secondary.weapon_id
			local base_dmg = get_display_damage(weapon_tweak)
			if base_dmg then
				local final_dmg = base_dmg * (1 + passive_dmg + item_dmg_additive) * glass_dmg_mult
				add_row(y, weapon_name, string.format("%.0f", final_dmg), string.format("%.0f", base_dmg), "\xe2\x80\x94", passive_dmg, gun_items_val, final_dmg, base_dmg)
				y = y + ROW_HEIGHT
			end
		end
	end

	-- Melee (includes Jiro's Last Wish bonus, display multiplier ×10)
	local equipped_melee = managers.blackmarket:equipped_melee_weapon()
	if equipped_melee then
		local melee_tweak = tweak_data.blackmarket.melee_weapons[equipped_melee]
		if melee_tweak and melee_tweak.stats and melee_tweak.stats.max_damage then
			local melee_name = managers.localization:text(melee_tweak.name_id) or equipped_melee
			local display_mult = tweak_data.gui and tweak_data.gui.stats_present_multiplier or 10
			local base_dmg = melee_tweak.stats.max_damage * display_mult
			local melee_item_additive = item_dmg_additive + jiro_stacks * 0.5
			local final_dmg = base_dmg * (1 + passive_dmg + melee_item_additive) * glass_dmg_mult
			local melee_items_val = melee_item_additive + (glass_dmg_mult - 1)
			add_row(y, melee_name, string.format("%.0f", final_dmg), string.format("%.0f", base_dmg), "\xe2\x80\x94", passive_dmg, melee_items_val, final_dmg, base_dmg)
			y = y + ROW_HEIGHT
		end
	end

	-- Bottom padding
	y = y + 50

	self._content_height = y
	content:set_h(self._content_height)
end

function CrimeSpreePlayerStatsPage:mouse_wheel_up(x, y)
	return true
end

function CrimeSpreePlayerStatsPage:mouse_wheel_down(x, y)
	return true
end

function CrimeSpreePlayerStatsPage:update(t, dt)
	CrimeSpreePlayerStatsPage.super.update(self, t, dt)
end

-- Tab registration
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddStatsTab", function(self, tabs_data)
	table.insert(tabs_data, 2, {
		name_id = "menu_csr_stats",
		width_multiplier = 1,
		page_class = "CrimeSpreePlayerStatsPage"
	})
end)

-- Localization
Hooks:Add("LocalizationManagerPostInit", "CSR_StatsPageLocalization", function(loc)
	loc:add_localized_strings({
		menu_csr_stats = "STATS"
	})
end)

