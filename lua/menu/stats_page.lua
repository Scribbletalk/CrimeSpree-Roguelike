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

	-- Expose instance so external callers (printer_page) can refresh us after
	-- a printer exchange without waiting for a tab switch.
	_G.CSR_StatsPageInstance = self

	if self:panel() then
		local panel = self:panel()

		-- Expand our page panel to the tall formula (6.0.3 behavior). The
		-- corresponding _expand_parents lift makes the shared parent tall
		-- enough that sibling pages (Items at -140 ≈ 491) keep their bottom
		-- corners inside the parent's visible bounds. Stats's own corners are
		-- built shorter via _corner_h below so they don't fall off-screen.
		local screen_h = fullscreen_panel and fullscreen_panel:h() or 720
		local new_height = screen_h - panel:world_y() - 20
		panel:set_h(math.max(new_height, 500))
		self._corner_h = math.max(screen_h - panel:world_y() - 140, 300)
		if panel.set_clip then
			panel:set_clip(false)
		end

		panel:clear()

		-- In multiplayer as client, delay first setup to let sync data arrive
		if CSR_MP and CSR_MP.is_client and CSR_MP.is_client() and not _G.CSR_MP_HostRank then
			panel:text({
				text = "Syncing...",
				font = tweak_data.menu.pd2_medium_font,
				font_size = 24,
				color = Color(0.6, 0.6, 0.6),
				align = "center",
				vertical = "center",
				w = panel:w(),
				h = panel:h(),
			})
			DelayedCalls:Add("CSR_StatsPageDelayedInit", 0.5, function()
				if alive(panel) then
					panel:clear()
					self:_setup_stats()
				end
			end)
		else
			self:_setup_stats()
		end
	end
end

-- Max-lift parent_panel and gp so stats content is fully visible. Non-destructive:
-- if a sibling already lifted higher, keep their value. Called post-init (filter.lua
-- iteration) and on every set_active(true).
function CrimeSpreePlayerStatsPage:_expand_parents()
	local panel = self:panel()
	if not panel then
		return
	end

	local parent_panel = panel:parent()
	if parent_panel then
		parent_panel:set_h(math.max(parent_panel:h(), panel:h()))
		if parent_panel.set_clip then
			parent_panel:set_clip(false)
		end
		local gp = parent_panel:parent()
		if gp then
			gp:set_h(math.max(gp:h(), panel:h()))
			if gp.set_clip then
				gp:set_clip(false)
			end
		end
	end
end

-- No-op: keep parents expanded so other tabs (Modifiers scroll) are not clipped.
function CrimeSpreePlayerStatsPage:_restore_parents() end

-- Override set_active: expand parents when STATS tab shown, leave them alone when hidden.
function CrimeSpreePlayerStatsPage:set_active(active)
	if active then
		self:_expand_parents()
		self:_setup_stats()
	else
		self:_restore_parents()
	end
	return CrimeSpreePlayerStatsPage.super.set_active(self, active)
end

-- Decorative bottom corners. Stats's page panel is taller (~611) than the
-- popup's visible bounds, so build the BoxGuiObject inside a sized sub-panel
-- (_corner_h, matched to items_page's height ≈ 491) so the bottom corners
-- land inside the visible area instead of below it.
function CrimeSpreePlayerStatsPage:_create_corners()
	local panel = self:panel()
	if not panel then
		return
	end
	if not BoxGuiObject then
		return
	end
	if self._box_panel and alive(self._box_panel) then
		panel:remove(self._box_panel)
	end
	local box_h = self._corner_h or panel:h()
	self._box_panel = panel:panel({
		name = "csr_stats_corners",
		x = 0,
		y = 0,
		w = panel:w(),
		h = box_h,
		layer = 2,
	})
	self._box = BoxGuiObject:new(self._box_panel, {
		sides = { 1, 1, 1, 1 },
		color = Color.white,
	})
end

-- Count stacks of an item by ID prefix
local function count_stacks(id_prefix)
	return CSR_CountStacks(id_prefix)
end

-- Column positions (6 columns) — shared by both Player Stats and Weapons tables
local COL_STAT = 10
local COL_TOTAL = 200
local COL_BASE = 290
local COL_SKILL = 370
local COL_LEVEL = 450
local COL_ITEMS = 530

-- Colors
local COLOR_HEADER = Color(1, 0.85, 0.1) -- Yellow
local COLOR_POSITIVE = Color(0.7, 1, 0.7) -- Green
local COLOR_NEGATIVE = Color(1, 0.5, 0.5) -- Red
local COLOR_NEUTRAL = Color(0.7, 0.7, 0.7) -- Gray
local COLOR_WEAPON = Color(0.9, 0.9, 0.9) -- Light gray
local COLOR_SEPARATOR = Color(0.3, 0.3, 0.3) -- Dark gray

-- Row heights
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local SEPARATOR_GAP = 10
local SECTION_GAP = 15

function CrimeSpreePlayerStatsPage:_setup_stats()
	local panel = self:panel()
	if not panel or not alive(panel) then
		return
	end

	-- Dark background (alive check: panel:clear() in delayed init destroys children)
	if not self._background or not alive(self._background) then
		self._background = panel:rect({
			name = "csr_stats_background",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
			color = Color.black,
			alpha = 0.4,
			layer = -1,
		})
	end

	-- Content panel (alive check: panel:clear() in delayed init destroys children)
	if not self._content_panel or not alive(self._content_panel) then
		self._content_panel = panel:panel({
			name = "csr_stats_content",
			x = 0,
			y = 0,
			w = panel:w(),
			h = panel:h(),
		})
	end

	local content = self._content_panel
	content:clear()

	local y = 10

	-- Check Crime Spree active. Use is_active() OR in_progress() so the placeholder
	-- doesn't replace the real stats during transitions where is_active() flickers
	-- off (Golden Grin civilian->mask, etc.) — see pd2_cs_is_active_vs_in_progress.
	local cs = managers.crime_spree
	local cs_running = cs and ((cs.is_active and cs:is_active()) or (cs.in_progress and cs:in_progress()))
	if not cs_running then
		content:text({
			text = "Start a Crime Spree to see stats.",
			font = tweak_data.menu.pd2_medium_font,
			font_size = 20,
			color = Color(0.5, 0.5, 0.5),
			x = 10,
			y = y,
		})
		self._content_height = y + 50
		content:set_h(self._content_height)
		return
	end

	-- === DATA CALCULATION ===
	-- In multiplayer as client, use best available host rank
	local cs_level
	if CSR_MP and CSR_MP.is_client and CSR_MP.is_client() then
		local vanilla_level = managers.crime_spree:server_spree_level() or 0
		local csr_level = _G.CSR_MP_HostRank or 0
		cs_level = math.max(vanilla_level, csr_level)
	else
		cs_level = managers.crime_spree:spree_level() or 0
	end

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

	local C = _G.CSR_ItemConstants or {}

	-- HP: bonus is added to health_skill_multiplier, glass is multiplicative
	-- Game formula: HP = HEALTH_INIT * (vanilla_mult + cs_bonus + dogtags_bonus) * glass_mult
	local cs_hp_bonus_to_mult = cs_level * (C.passive_hp_per_level or 0.001)
	local dogtags_hp_bonus_to_mult = health_stacks * (C.dog_tags_hp_bonus or 0.1)
	local glass_hp_mult = math.pow(1 / (C.glass_pistol_div_per_stack or 2), glass_stacks)

	-- Damage: passive additive, glass multiplicative
	local passive_dmg = cs_level * (C.passive_damage_per_level or 0.0004)

	local item_dmg_additive = (damage_stacks * (C.ap_rounds_damage_bonus or 0.05))
		+ (dozer_stacks * (C.dozer_damage_bonus or 0.05))
	local glass_dmg_mult = math.pow((C.glass_pistol_dmg_per_stack or 1.5), glass_stacks)
	local total_dmg_bonus = (1 + passive_dmg + item_dmg_additive) * glass_dmg_mult - 1

	-- Armor: per level direct multiplier, glass is multiplicative
	local passive_armor = cs_level * (C.passive_armor_per_level or 0.001)
	local dozer_armor_bonus = dozer_stacks * (C.dozer_armor_bonus or 0.5)
	local glass_armor_mult = math.pow(1 / (C.glass_pistol_div_per_stack or 2), glass_stacks)

	-- Regen (disabled by Berserker/Frenzy)
	local has_berserker = managers.player
		and (
			managers.player:has_category_upgrade("player", "damage_health_ratio_multiplier")
			or managers.player:has_category_upgrade("player", "melee_damage_health_ratio_multiplier")
			or managers.player:has_category_upgrade("player", "max_health_reduction")
		)
	-- Flat display HP per tick (not a percentage of max HP)
	local passive_regen_flat = has_berserker and 0 or (cs_level * (C.passive_regen_flat_per_level or 0.02))

	-- Dodge (hyperbolic)
	local dodge_bonus = 0
	if keys_stacks > 0 then
		dodge_bonus = (1 - 1 / (1 + keys_stacks / (C.car_keys_k_den or 32))) * 100
	end
	local dodge_penalty = dozer_stacks * (C.dozer_dodge_penalty or 5)
	local total_dodge = math.max(0, dodge_bonus - dodge_penalty)

	-- Movement Speed (hyperbolic)
	local speed_bonus = 0
	if sneakers_stacks > 0 then
		local ep_k = (C.escape_plan_k_num or 3) / (C.escape_plan_k_den or 47)
		speed_bonus = (C.escape_plan_cap or 0.50) * (1 - 1 / (1 + ep_k * sneakers_stacks)) * 100
	end
	local speed_penalty = 0
	if dozer_stacks > 0 then
		speed_penalty = (1 - math.max((C.dozer_speed_min or 0.40), 1 - (C.dozer_speed_penalty or 0.15) * dozer_stacks))
			* 100
	end
	local total_speed = speed_bonus - speed_penalty

	-- Interact Speed
	local total_interact = duct_tape_stacks * (C.duct_tape_speed_bonus or 0.05) * 100

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
			skill_hp = pure_base_hp * (hp_mult - 1) -- Absolute bonus from skills
		end

		-- Crew bonuses (crew boosts like Reinforcer: +60 HP)

		-- Try to get crew boost through upgrade_value
		local crew_boost_hp = 0

		if managers.player and managers.player.upgrade_value then
			-- Try different upgrade IDs
			local test_ids = {
				{ "team", "health", "health_increase" },
				{ "team", "crew_health" },
				{ "crew", "health_increase" },
				{ "player", "passive_health_increase" },
				{ "team", "passive_health_increase" },
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
				crew_boost_hp = 60 -- Hardcoded Reinforcer value
			else
				crew_boost_hp = 0 -- No bots, no boost
			end
		end

		crew_hp = tonumber(crew_boost_hp) or 0
	end

	local total_skill_hp = skill_hp + crew_hp -- Combined skill + crew
	local base_hp = pure_base_hp + total_skill_hp -- Total base before CSR

	-- Armor & Movement: read from vanilla PlayerInventoryGui stats (don't calculate manually)
	local base_armor = 0
	local base_movement = 0
	local pure_base_armor = 0
	local skill_armor = 0
	local crew_armor = 0

	if managers.player and tweak_data.player and tweak_data.player.damage then
		-- Use (false, false) to get the actual equipped armor for display,
		-- not the mission-start armor (which accounts for armor bags / civilian state)
		local armor_id = managers.blackmarket and managers.blackmarket:equipped_armor(false, false) or "none"

		-- Try to call vanilla _get_armor_stats function directly (returns armor + movement)
		if PlayerInventoryGui and PlayerInventoryGui._get_armor_stats then
			-- Create minimal fake instance to call the method
			local fake_instance = {
				_stats_shown = {
					{ name = "armor" },
					{ name = "movement" },
				},
			}

			local success, base_stats, mods_stats, skill_stats =
				pcall(PlayerInventoryGui._get_armor_stats, fake_instance, armor_id)

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
			skill_armor = (base_value + managers.player:body_armor_skill_addend(armor_id) * display_mult)
					* managers.player:body_armor_skill_multiplier(armor_id)
				- base_value
			pure_base_armor = base_value
		end

		-- Try to get crew boost for armor
		local crew_boost_armor = 0

		if managers.player and managers.player.upgrade_value then
			local test_ids = {
				{ "team", "armor", "armor_increase" },
				{ "team", "crew_armor" },
				{ "crew", "armor_increase" },
				{ "player", "passive_armor_increase" },
				{ "team", "passive_armor_increase" },
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

	-- Armor-to-health conversion (Stoic perk deck and similar).
	-- Applied in _max_armor() AFTER all skill multipliers, so _get_armor_stats /
	-- body_armor_skill_multiplier don't capture it. We detect the actual ratio
	-- from the live player unit when possible; fall back to upgrade_value otherwise.
	local armor_to_health_factor = 0
	pcall(function()
		if not managers.player:has_category_upgrade("player", "armor_to_health_conversion") then
			return
		end
		-- Try live player unit: compare _raw_max_armor (before conversion) with
		-- vanilla _max_armor (after conversion) to get the real factor.
		-- This respects any mod that changes the conversion formula.
		local player_unit = managers.player:player_unit()
		if player_unit and alive(player_unit) then
			local pd = player_unit:character_damage()
			if pd and pd._raw_max_armor and pd._max_armor then
				-- Call raw (pre-conversion) and final (post-conversion) via vanilla
				-- Use _csr_in_max_armor flag to get vanilla result without CSR bonuses
				pd._csr_in_max_armor = true
				local raw = pd:_raw_max_armor()
				local converted = pd:_max_armor()
				pd._csr_in_max_armor = false
				if raw and raw > 0 and converted then
					armor_to_health_factor = math.max(0, math.min(1, 1 - converted / raw))
				end
			end
		end
		-- Fallback: read upgrade value and apply vanilla formula (value * 0.01)
		if armor_to_health_factor == 0 then
			local raw_value = tonumber(managers.player:upgrade_value("player", "armor_to_health_conversion", 0)) or 0
			armor_to_health_factor = math.max(0, math.min(1, raw_value * 0.01))
		end
	end)

	if armor_to_health_factor > 0 then
		local armor_converted = base_armor * armor_to_health_factor
		-- Armor reduced by conversion (perk effect → goes into SKILL column)
		skill_armor = skill_armor - armor_converted
		base_armor = base_armor - armor_converted
		-- Converted armor becomes health
		skill_hp = skill_hp + armor_converted
		total_skill_hp = skill_hp + crew_hp
		base_hp = pure_base_hp + total_skill_hp
	end

	-- Dodge: split armor component (BASE) from skill/perk contribution (SKILL)
	local base_dodge = 0 -- armor base dodge from body_armor_value("dodge")
	local skill_dodge = 0 -- skills + perk deck contribution
	local vanilla_dodge = 0 -- full pre-CSR dodge (used in formula)
	if managers.player then
		-- Armor dodge: body_armor_value reads from tweak_data directly (works in menu)
		-- Suit (level_1) = 0.05 (5%), heavier armors go negative
		pcall(function()
			base_dodge = (managers.player:body_armor_value("dodge") or 0) * 100
		end)
		-- Skill component: full vanilla dodge (perk deck, skills, Copycat, tier, detection risk, crew, etc.)
		-- csr_base_dodge_chance() calls the original skill_dodge_chance() before CSR additions
		pcall(function()
			skill_dodge = (managers.player:csr_base_dodge_chance() or 0) * 100
		end)
		vanilla_dodge = math.max(0, skill_dodge + base_dodge)
	end

	-- === FINAL VALUES (game-accurate: Glass Pistol applied multiplicatively) ===
	-- vanilla_hp_mult derived from base_hp (includes skill): e.g. 460/230 = 2.0 for Muscle
	local vanilla_hp_mult = (pure_base_hp > 0) and (base_hp / pure_base_hp) or 1.0
	local final_hp = pure_base_hp * (vanilla_hp_mult + cs_hp_bonus_to_mult + dogtags_hp_bonus_to_mult) * glass_hp_mult
	local final_armor = base_armor * (1 + passive_armor + dozer_armor_bonus) * glass_armor_mult
	local final_regen = passive_regen_flat
	-- Multiplicative combination (mirrors skill_dodge_chance hook in playermanager.lua):
	-- final = 1 - (1 - vanilla) * (1 - keys_bonus), then subtract dozer penalty
	local vanilla_dodge_frac = vanilla_dodge / 100
	local keys_bonus_frac = dodge_bonus / 100
	local after_keys = 1 - (1 - vanilla_dodge_frac) * (1 - keys_bonus_frac)
	local final_dodge = math.max(0, after_keys * 100 - dodge_penalty)

	-- Column display percentages: show as % of base multiplier (consistent with armor display)
	local passive_hp = cs_hp_bonus_to_mult
	local item_hp = dogtags_hp_bonus_to_mult
	item_hp = item_hp + (glass_hp_mult - 1) -- glass as -50% in ITEMS column
	local item_armor = dozer_armor_bonus + (glass_armor_mult - 1) -- glass as -50% in ITEMS column

	-- === HELPER: format value string ===
	local function fmt_pct(val)
		if math.abs(val) < 0.001 then
			return "\xe2\x80\x94"
		end
		return string.format("%+.1f%%", val * 100)
	end

	local function color_for(val)
		if val > 0.001 then
			return COLOR_POSITIVE
		elseif val < -0.001 then
			return COLOR_NEGATIVE
		else
			return COLOR_NEUTRAL
		end
	end

	-- === HELPER: add table row (6 columns) ===
	-- skill_str is absolute value (e.g. "+60"), includes both perks and crew bonuses
	-- skill_color: optional override for SKILL column color (defaults to COLOR_POSITIVE)
	-- total_num/base_num: optional numeric values; if total_num < base_num → force red
	local function add_row(
		row_y,
		stat_name,
		total_str,
		base_str,
		skill_str,
		level_val,
		items_val,
		total_num,
		base_num,
		skill_color,
		level_str_override
	)
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
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = Color.white,
			x = COL_STAT,
			y = row_y,
		})
		content:text({
			text = total_str,
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = total_color,
			x = COL_TOTAL,
			y = row_y,
		})
		content:text({
			text = base_str,
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = COLOR_NEUTRAL,
			x = COL_BASE,
			y = row_y,
		})
		content:text({
			text = skill_str or "\xe2\x80\x94",
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = skill_color or COLOR_POSITIVE,
			x = COL_SKILL,
			y = row_y,
		})
		content:text({
			text = level_str_override or fmt_pct(level_val),
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = color_for(level_val),
			x = COL_LEVEL,
			y = row_y,
		})
		content:text({
			text = fmt_pct(items_val),
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = color_for(items_val),
			x = COL_ITEMS,
			y = row_y,
		})
	end

	-- === TABLE HEADER ===
	local hdr_stat = "PLAYER STATS"
	local hdr_total = "TOTAL"
	local hdr_base = "BASE"
	local hdr_skill = "SKILL"
	local hdr_level = "CS RANK"
	local hdr_items = "ITEMS"

	content:text({
		text = hdr_stat,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_STAT,
		y = y,
	})
	content:text({
		text = hdr_total,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_TOTAL,
		y = y,
	})
	content:text({
		text = hdr_base,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_BASE,
		y = y,
	})
	content:text({
		text = hdr_skill,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_SKILL,
		y = y,
	})
	content:text({
		text = hdr_level,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_LEVEL,
		y = y,
	})
	content:text({
		text = hdr_items,
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_ITEMS,
		y = y,
	})
	y = y + HEADER_HEIGHT

	-- Separator line
	content:rect({
		x = COL_STAT,
		y = y,
		w = (COL_ITEMS + 80) - COL_STAT,
		h = 1,
		color = COLOR_SEPARATOR,
		alpha = 0.6,
	})
	y = y + SEPARATOR_GAP

	-- === STAT ROWS ===
	-- add_row(y, name, total_str, base_str, level_val, items_val)

	-- Armor (MOVED FIRST)
	local armor_label = "Armor"
	local total_skill_armor = skill_armor + crew_armor
	local skill_armor_str, skill_armor_color
	if math.abs(total_skill_armor) > 0.5 then
		skill_armor_str = string.format("%+.0f", total_skill_armor)
		skill_armor_color = total_skill_armor > 0 and COLOR_POSITIVE or COLOR_NEGATIVE
	else
		skill_armor_str = "\xe2\x80\x94"
		skill_armor_color = COLOR_NEUTRAL
	end
	add_row(
		y,
		armor_label,
		string.format("%.0f", final_armor),
		string.format("%.0f", pure_base_armor),
		skill_armor_str,
		passive_armor,
		item_armor,
		final_armor,
		pure_base_armor,
		skill_armor_color
	)
	y = y + ROW_HEIGHT

	-- Health (MOVED SECOND) with inline Frenzy/Wolverine cap
	local hp_label = "Health"
	local skill_hp_str, skill_hp_color
	if math.abs(total_skill_hp) > 0.5 then
		skill_hp_str = string.format("%+.0f", total_skill_hp)
		skill_hp_color = total_skill_hp > 0 and COLOR_POSITIVE or COLOR_NEGATIVE
	else
		skill_hp_str = "\xe2\x80\x94"
		skill_hp_color = COLOR_NEUTRAL
	end

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
	add_row(
		y,
		hp_label,
		hp_total_str,
		string.format("%.0f", pure_base_hp),
		skill_hp_str,
		passive_hp,
		item_hp,
		effective_hp,
		pure_base_hp,
		skill_hp_color
	)
	y = y + ROW_HEIGHT

	-- HP Regen (CS level passive flat + Worn Band-Aid hyperbolic % of max HP)
	local regen_label = "Health Regeneration"
	local bandaid_regen_pct = CSR_BandaidRegenPct(bandaid_stacks)
	local bandaid_regen = final_hp * bandaid_regen_pct
	local total_regen = final_regen + bandaid_regen
	local passive_regen_pct = (final_hp > 0) and (final_regen / final_hp) or 0
	local passive_regen_level_str = final_regen > 0.05 and string.format("+%.1f HP", final_regen) or "-"
	add_row(
		y,
		regen_label,
		string.format("%.1f HP/%gs", total_regen, C.passive_regen_interval or 5.0),
		"0",
		"-",
		passive_regen_pct,
		bandaid_regen_pct,
		nil,
		nil,
		nil,
		passive_regen_level_str
	)
	if has_berserker then
		content:text({
			text = "OFF",
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = COLOR_NEGATIVE,
			x = COL_LEVEL,
			y = y,
		})
	end
	y = y + ROW_HEIGHT

	-- Dodge
	local dodge_label = "Dodge"
	local dodge_total_str = string.format("%.1f%%", final_dodge)
	local dodge_base_str = math.abs(base_dodge) > 0.05 and string.format("%.1f%%", base_dodge) or "0%"
	local dodge_skill_str = skill_dodge > 0.05 and string.format("+%.1f%%", skill_dodge) or "-"
	add_row(y, dodge_label, dodge_total_str, dodge_base_str, dodge_skill_str, 0, (final_dodge - vanilla_dodge) / 100)
	y = y + ROW_HEIGHT

	-- Movement Speed (read from vanilla, no %)
	local speed_label = "Move Speed"
	-- Calculate CSR bonuses to movement (from sneakers/dozer)
	local speed_csr_bonus = 0
	if sneakers_stacks > 0 then
		local ep_k = (C.escape_plan_k_num or 3) / (C.escape_plan_k_den or 47)
		speed_csr_bonus = speed_csr_bonus + ((C.escape_plan_cap or 0.50) * (1 - 1 / (1 + ep_k * sneakers_stacks)))
	end
	if dozer_stacks > 0 then
		speed_csr_bonus = speed_csr_bonus
			- (1 - math.max((C.dozer_speed_min or 0.40), 1 - (C.dozer_speed_penalty or 0.15) * dozer_stacks))
	end
	local final_movement = base_movement * (1 + speed_csr_bonus)
	add_row(
		y,
		speed_label,
		string.format("%.1f", final_movement),
		string.format("%.1f", base_movement),
		"-",
		0,
		speed_csr_bonus
	)
	y = y + ROW_HEIGHT

	-- Interact Speed
	local interact_label = "Interact Speed"

	-- Crew ability "Quick" — check henchman loadouts for crew_interact
	-- Values from tweakdata: {0.75, 0.5, 0.25} indexed by AI count
	-- 1 bot = 0.75x time (25% faster), 2 = 0.5x (50%), 3 = 0.25x (75%)
	local crew_time_mult = 1
	local has_crew_interact = false
	local ai_count = 0
	if managers.blackmarket and managers.blackmarket.henchman_loadout then
		for i = 1, 3 do
			local ok, loadout = pcall(function()
				return managers.blackmarket:henchman_loadout(i)
			end)
			if ok and loadout then
				ai_count = ai_count + 1
				if loadout.ability == "crew_interact" then
					has_crew_interact = true
				end
			end
		end
	end
	if has_crew_interact and ai_count > 0 then
		local vals = tweak_data
			and tweak_data.upgrades
			and tweak_data.upgrades.values
			and tweak_data.upgrades.values.team
			and tweak_data.upgrades.values.team.crew_interact
		if vals and vals[1] and vals[1][ai_count] then
			crew_time_mult = vals[1][ai_count]
		end
	end

	-- Convert crew time multiplier to speed bonus %: 0.25x time = 75% faster
	local crew_speed_bonus = 0
	if crew_time_mult > 0 and crew_time_mult < 1 then
		crew_speed_bonus = (1 - crew_time_mult) * 100
	end

	-- Game adds bonuses in speed-space: crew + duct tape (additive)
	local total_interact_speed = 100 + crew_speed_bonus + total_interact
	local interact_total_str = string.format("%.1f%%", total_interact_speed)
	local crew_interact_str = crew_speed_bonus > 0 and string.format("+%.1f%%", crew_speed_bonus) or "-"

	add_row(y, interact_label, interact_total_str, "100%", crew_interact_str, 0, total_interact / 100)
	y = y + ROW_HEIGHT

	-- Bonus Drop Chance row removed (feature disabled)

	-- === WEAPONS SECTION ===
	y = y + SECTION_GAP

	-- Divider between Player Stats and Weapons
	content:rect({
		x = COL_STAT,
		y = y,
		w = (COL_ITEMS + 80) - COL_STAT,
		h = 2,
		color = Color.white,
		alpha = 0.8,
	})
	y = y + SECTION_GAP

	-- Weapon section label only (columns match Player Stats above, no need to repeat headers)
	content:text({
		text = "WEAPONS",
		font = tweak_data.menu.pd2_medium_font,
		font_size = 16,
		color = COLOR_HEADER,
		x = COL_STAT,
		y = y,
	})
	y = y + HEADER_HEIGHT

	content:rect({ x = COL_STAT, y = y, w = (COL_ITEMS + 80) - COL_STAT, h = 1, color = COLOR_SEPARATOR, alpha = 0.6 })
	y = y + 8

	-- Add one weapon row (same 6 columns as Player Stats)
	local function add_weapon_row(row_y, name, total_str, base_str, level_val, items_val, total_num, base_num)
		local combined = level_val + items_val
		local total_color
		if total_num ~= nil and base_num ~= nil and total_num < base_num - 0.5 then
			total_color = COLOR_NEGATIVE
		else
			total_color = color_for(combined)
		end
		content:text({
			text = name,
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = Color.white,
			x = COL_STAT,
			y = row_y,
		})
		content:text({
			text = total_str,
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = total_color,
			x = COL_TOTAL,
			y = row_y,
		})
		content:text({
			text = base_str,
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = COLOR_NEUTRAL,
			x = COL_BASE,
			y = row_y,
		})
		content:text({
			text = "\xe2\x80\x94",
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = COLOR_NEUTRAL,
			x = COL_SKILL,
			y = row_y,
		})
		content:text({
			text = fmt_pct(level_val),
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = color_for(level_val),
			x = COL_LEVEL,
			y = row_y,
		})
		content:text({
			text = fmt_pct(items_val),
			font = tweak_data.menu.pd2_small_font,
			font_size = 16,
			color = color_for(items_val),
			x = COL_ITEMS,
			y = row_y,
		})
	end

	-- Display damage helper: uses WeaponDescription._get_stats to include all mod contributions.
	-- Returns the full vanilla damage (base tweakdata + mods + skills) as shown in the inventory UI.
	local function get_weapon_full_damage(weapon_id, category)
		if WeaponDescription and WeaponDescription._get_stats then
			local slot = nil
			pcall(function()
				slot = managers.blackmarket:equipped_weapon_slot(category)
			end)
			local ok, base_stats, mods_stats, skill_stats =
				pcall(WeaponDescription._get_stats, weapon_id, category, slot)
			if ok and base_stats and base_stats.damage then
				local base_dmg = base_stats.damage.value or 0
				local mods_dmg = (mods_stats and mods_stats.damage and mods_stats.damage.value) or 0
				local skill_dmg = (skill_stats and skill_stats.damage and skill_stats.damage.value) or 0
				return base_dmg + mods_dmg + skill_dmg
			end
		end
		-- Fallback: tweakdata base only (no mods)
		local wt = tweak_data.weapon[weapon_id]
		if not wt or not wt.stats or not wt.stats.damage then
			return nil
		end
		local dt = tweak_data.weapon.stats.damage
		if not dt then
			return nil
		end
		return dt[math.clamp(wt.stats.damage, 1, #dt)] * 10
	end

	-- Gun items column: evidence + dozer + glass (additive approximation)
	local gun_items_val = item_dmg_additive + (glass_dmg_mult - 1)

	-- Primary
	local equipped_primary = managers.blackmarket:equipped_primary()
	if equipped_primary and equipped_primary.weapon_id then
		local weapon_tweak = tweak_data.weapon[equipped_primary.weapon_id]
		if weapon_tweak then
			local weapon_name = managers.localization:text(weapon_tweak.name_id) or equipped_primary.weapon_id
			local base_dmg = get_weapon_full_damage(equipped_primary.weapon_id, "primaries")
			if base_dmg then
				local final_dmg = base_dmg * (1 + passive_dmg + item_dmg_additive) * glass_dmg_mult
				add_weapon_row(
					y,
					weapon_name,
					string.format("%.0f", final_dmg),
					string.format("%.0f", base_dmg),
					passive_dmg,
					gun_items_val,
					final_dmg,
					base_dmg
				)
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
			local base_dmg = get_weapon_full_damage(equipped_secondary.weapon_id, "secondaries")
			if base_dmg then
				local final_dmg = base_dmg * (1 + passive_dmg + item_dmg_additive) * glass_dmg_mult
				add_weapon_row(
					y,
					weapon_name,
					string.format("%.0f", final_dmg),
					string.format("%.0f", base_dmg),
					passive_dmg,
					gun_items_val,
					final_dmg,
					base_dmg
				)
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
			local base_dmg = melee_tweak.stats.max_damage * 10
			local melee_item_additive = item_dmg_additive + jiro_stacks * (C.jiro_melee_bonus or 0.5)
			local final_dmg = base_dmg * (1 + passive_dmg + melee_item_additive) * glass_dmg_mult
			local melee_items_val = melee_item_additive + (glass_dmg_mult - 1)
			add_weapon_row(
				y,
				melee_name,
				string.format("%.0f", final_dmg),
				string.format("%.0f", base_dmg),
				passive_dmg,
				melee_items_val,
				final_dmg,
				base_dmg
			)
			y = y + ROW_HEIGHT
		end
	end

	-- Throwable (only damaging throwables; status-effect ones like Smoke/ECM
	-- have no damage value and are skipped). Bonuses applied: passive CS rank
	-- damage + AP Rounds (additive). Glass Pistol is ranged-only, Dozer's
	-- Guide is weapon-only, Jiro is melee-only — none affect throwables.
	local equipped_throwable = managers.blackmarket and managers.blackmarket:equipped_grenade()
	if equipped_throwable and tweak_data.projectiles and tweak_data.projectiles[equipped_throwable] then
		local proj_tweak = tweak_data.projectiles[equipped_throwable]
		if proj_tweak.damage and proj_tweak.damage > 0 then
			local bm_proj_tweak = tweak_data.blackmarket.projectiles
				and tweak_data.blackmarket.projectiles[equipped_throwable]
			local name_id = (bm_proj_tweak and bm_proj_tweak.name_id) or proj_tweak.name_id
			local throwable_name = name_id and managers.localization:text(name_id) or equipped_throwable
			local base_dmg = proj_tweak.damage * 10
			local throwable_item_additive = damage_stacks * (C.ap_rounds_damage_bonus or 0.05)
			local final_dmg = base_dmg * (1 + passive_dmg + throwable_item_additive)
			add_weapon_row(
				y,
				throwable_name,
				string.format("%.0f", final_dmg),
				string.format("%.0f", base_dmg),
				passive_dmg,
				throwable_item_additive,
				final_dmg,
				base_dmg
			)
			y = y + ROW_HEIGHT
		end
	end

	-- Bottom padding
	y = y + 50

	self._content_height = y
	content:set_h(self._content_height)

	self:_create_corners()
end

function CrimeSpreePlayerStatsPage:mouse_wheel_up(x, y)
	return true
end

function CrimeSpreePlayerStatsPage:mouse_wheel_down(x, y)
	return true
end

function CrimeSpreePlayerStatsPage:update(t, dt)
	-- Do NOT call super.update: parent's _next_text and _scroll are destroyed by panel:clear() in init,
	-- calling super.update on a non-host causes a C++ access violation when server_spree_level changes.
end

-- Tab registration
Hooks:PostHook(CrimeSpreeDetailsMenuComponent, "populate_tabs_data", "CSR_AddStatsTab", function(self, tabs_data)
	table.insert(tabs_data, 2, {
		name_id = "menu_csr_stats",
		width_multiplier = 1,
		page_class = "CrimeSpreePlayerStatsPage",
	})
end)

-- Localization
Hooks:Add("LocalizationManagerPostInit", "CSR_StatsPageLocalization", function(loc)
	loc:add_localized_strings({
		menu_csr_stats = "STATS",
	})
end)
