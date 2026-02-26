-- Crime Spree Roguelike - Custom icons

if not RequiredScript then
	return
end



-- ModPath always exists in BLT, no fallback needed
local mod_path = ModPath

-- Item icons (located in icons/items/ folder)
local dog_tags_file = mod_path .. "assets/guis/textures/icons/items/dog_tags.dds"
local dog_tags_path = "guis/textures/pd2/crime_spree/csr_dog_tags"
local bonnie_chip_file = mod_path .. "assets/guis/textures/icons/items/bonnie_chip.dds"
local bonnie_chip_path = "guis/textures/pd2/crime_spree/csr_bonnie_chip"
local falcogini_keys_file = mod_path .. "assets/guis/textures/icons/items/falcogini_keys.dds"
local falcogini_keys_path = "guis/textures/pd2/crime_spree/csr_falcogini_keys"
local glass_pistol_file = mod_path .. "assets/guis/textures/icons/items/glass_pistol.dds"
local glass_pistol_path = "guis/textures/pd2/crime_spree/csr_glass_pistol"
local bullets_file = mod_path .. "assets/guis/textures/icons/items/bullets.dds"
local bullets_path = "guis/textures/pd2/crime_spree/csr_bullets"
local plush_shark_file = mod_path .. "assets/guis/textures/icons/items/plush_shark.dds"
local plush_shark_path = "guis/textures/pd2/crime_spree/csr_plush_shark"
local toolbox_file = mod_path .. "assets/guis/textures/icons/items/toolbox.dds"
local toolbox_path = "guis/textures/pd2/crime_spree/csr_toolbox"
local dozer_guide_file = mod_path .. "assets/guis/textures/icons/items/dozer_guide.dds"
local dozer_guide_path = "guis/textures/pd2/crime_spree/csr_dozer_guide"
local duct_tape_file = mod_path .. "assets/guis/textures/icons/items/tape.dds"
local duct_tape_path = "guis/textures/pd2/crime_spree/csr_duct_tape"
local escape_plan_file = mod_path .. "assets/guis/textures/icons/items/escape_plan.dds"
local escape_plan_path = "guis/textures/pd2/crime_spree/csr_escape_plan"
local worn_bandaid_file = mod_path .. "assets/guis/textures/icons/items/band_aid.dds"
local worn_bandaid_path = "guis/textures/pd2/crime_spree/csr_worn_bandaid"
local rebar_file = mod_path .. "assets/guis/textures/icons/items/rebar.dds"
local rebar_path = "guis/textures/pd2/crime_spree/csr_rebar"
local overkill_rush_file = mod_path .. "assets/guis/textures/icons/items/overkill_rush.dds"
local overkill_rush_path = "guis/textures/pd2/crime_spree/csr_overkill_rush"
local pink_slip_file = mod_path .. "assets/guis/textures/icons/items/pink_slip.dds"
local pink_slip_path = "guis/textures/pd2/crime_spree/csr_pink_slip"
local jiro_last_wish_file = mod_path .. "assets/guis/textures/icons/items/jiro_letter.dds"
local jiro_last_wish_path = "guis/textures/pd2/crime_spree/csr_jiro_last_wish"
local dearest_possession_file = mod_path .. "assets/guis/textures/icons/items/pendant.dds"
local dearest_possession_path = "guis/textures/pd2/crime_spree/csr_dearest_possession"
local viklund_vinyl_file = mod_path .. "assets/guis/textures/icons/items/vinyl_record.dds"
local viklund_vinyl_path = "guis/textures/pd2/crime_spree/csr_viklund_vinyl"
local equalizer_file = mod_path .. "assets/guis/textures/icons/items/equalizer.dds"
local equalizer_path = "guis/textures/pd2/crime_spree/csr_equalizer"
local crooked_badge_file = mod_path .. "assets/guis/textures/icons/items/crooked_badge.dds"
local crooked_badge_path = "guis/textures/pd2/crime_spree/csr_crooked_badge"
local dead_mans_trigger_file = mod_path .. "assets/guis/textures/icons/items/dead_mans_trigger.dds"
local dead_mans_trigger_path = "guis/textures/pd2/crime_spree/csr_dead_mans_trigger"

-- UI icons (located in icons/CS/ folder)
local crime_spree_icon_file = mod_path .. "assets/guis/textures/icons/CS/crime_spree.dds"
local crime_spree_icon_path = "guis/textures/pd2/crime_spree/csr_cs_icon"
local continental_coin_file = mod_path .. "assets/guis/textures/icons/CS/continental_coin.dds"
local continental_coin_path = "guis/textures/pd2/crime_spree/csr_coin"

-- Frames (located in frame/ folder) - one per rarity tier
local frame_common_file = mod_path .. "assets/guis/textures/frames/csr_frame_common.dds"
local frame_common_path = "guis/textures/pd2/crime_spree/csr_frame_common"
local frame_uncommon_file = mod_path .. "assets/guis/textures/frames/csr_frame_uncommon.dds"
local frame_uncommon_path = "guis/textures/pd2/crime_spree/csr_frame_uncommon"
local frame_rare_file = mod_path .. "assets/guis/textures/frames/csr_frame_rare.dds"
local frame_rare_path = "guis/textures/pd2/crime_spree/csr_frame_rare"
local frame_contraband_file = mod_path .. "assets/guis/textures/frames/csr_frame_contraband.dds"
local frame_contraband_path = "guis/textures/pd2/crime_spree/csr_frame_contraband"

-- Load textures
if DB and DB.create_entry then
	DB:create_entry(Idstring("texture"), Idstring(dog_tags_path), dog_tags_file)

	DB:create_entry(Idstring("texture"), Idstring(bonnie_chip_path), bonnie_chip_file)

	DB:create_entry(Idstring("texture"), Idstring(falcogini_keys_path), falcogini_keys_file)

	DB:create_entry(Idstring("texture"), Idstring(glass_pistol_path), glass_pistol_file)

	DB:create_entry(Idstring("texture"), Idstring(bullets_path), bullets_file)

	DB:create_entry(Idstring("texture"), Idstring(plush_shark_path), plush_shark_file)

	DB:create_entry(Idstring("texture"), Idstring(toolbox_path), toolbox_file)

	DB:create_entry(Idstring("texture"), Idstring(dozer_guide_path), dozer_guide_file)

	DB:create_entry(Idstring("texture"), Idstring(duct_tape_path), duct_tape_file)

	DB:create_entry(Idstring("texture"), Idstring(escape_plan_path), escape_plan_file)

	DB:create_entry(Idstring("texture"), Idstring(worn_bandaid_path), worn_bandaid_file)

	DB:create_entry(Idstring("texture"), Idstring(rebar_path), rebar_file)

	DB:create_entry(Idstring("texture"), Idstring(overkill_rush_path), overkill_rush_file)

	DB:create_entry(Idstring("texture"), Idstring(pink_slip_path), pink_slip_file)

	DB:create_entry(Idstring("texture"), Idstring(jiro_last_wish_path), jiro_last_wish_file)

	DB:create_entry(Idstring("texture"), Idstring(dearest_possession_path), dearest_possession_file)

	DB:create_entry(Idstring("texture"), Idstring(viklund_vinyl_path), viklund_vinyl_file)

	DB:create_entry(Idstring("texture"), Idstring(equalizer_path), equalizer_file)

	DB:create_entry(Idstring("texture"), Idstring(crooked_badge_path), crooked_badge_file)

	DB:create_entry(Idstring("texture"), Idstring(dead_mans_trigger_path), dead_mans_trigger_file)

	-- UI icons (Crime Spree + coins)
	DB:create_entry(Idstring("texture"), Idstring(crime_spree_icon_path), crime_spree_icon_file)

	DB:create_entry(Idstring("texture"), Idstring(continental_coin_path), continental_coin_file)

	-- Frames for all rarity tiers
	DB:create_entry(Idstring("texture"), Idstring(frame_common_path), frame_common_file)

	DB:create_entry(Idstring("texture"), Idstring(frame_uncommon_path), frame_uncommon_file)

	DB:create_entry(Idstring("texture"), Idstring(frame_rare_path), frame_rare_file)

	DB:create_entry(Idstring("texture"), Idstring(frame_contraband_path), frame_contraband_file)
end

-- Override init the same way Restoration mod does it
local old_icons_init = HudIconsTweakData.init
function HudIconsTweakData:init()
	old_icons_init(self)

	-- Add icons directly into self (not into self.textures!)
	self.csr_dog_tags = {
		texture = dog_tags_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_bonnie_chip = {
		texture = bonnie_chip_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_falcogini_keys = {
		texture = falcogini_keys_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_glass_pistol = {
		texture = glass_pistol_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_bullets = {
		texture = bullets_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_plush_shark = {
		texture = plush_shark_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_toolbox = {
		texture = toolbox_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_dozer_guide = {
		texture = dozer_guide_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_duct_tape = {
		texture = duct_tape_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_escape_plan = {
		texture = escape_plan_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_jiro_last_wish = {
		texture = jiro_last_wish_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_dearest_possession = {
		texture = dearest_possession_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_worn_bandaid = {
		texture = worn_bandaid_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_rebar = {
		texture = rebar_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_overkill_rush = {
		texture = overkill_rush_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_pink_slip = {
		texture = pink_slip_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_viklund_vinyl = {
		texture = viklund_vinyl_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_equalizer = {
		texture = equalizer_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_crooked_badge = {
		texture = crooked_badge_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_dead_mans_trigger = {
		texture = dead_mans_trigger_path,
		texture_rect = {0, 0, 128, 128}
	}

	-- UI icons (Crime Spree + coins) - NO texture_rect, engine determines it automatically
	self.csr_cs_icon = {
		texture = crime_spree_icon_path
	}

	self.csr_coin = {
		texture = continental_coin_path
	}

	-- Frames for all rarity tiers
	self.csr_frame_common = {
		texture = frame_common_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_frame_uncommon = {
		texture = frame_uncommon_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_frame_rare = {
		texture = frame_rare_path,
		texture_rect = {0, 0, 128, 128}
	}

	self.csr_frame_contraband = {
		texture = frame_contraband_path,
		texture_rect = {0, 0, 128, 128}
	}

	-- v2.50: REMOVED vanilla CS modifier icon overrides (lines 220-276 from v2.49)
	-- Vanilla registers its own icons correctly via DLC system
	-- Our override broke them because DLC texture paths don't work from mods
end

