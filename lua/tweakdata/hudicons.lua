-- Crime Spree Roguelike - Custom icons

if not RequiredScript then
	return
end

local mod_path = ModPath

-- Item icons
local dog_tags_file = mod_path .. "assets/gui/items/common/dog_tags.dds"
local dog_tags_path = "guis/textures/pd2/crime_spree/csr_dog_tags"
local bonnie_chip_file = mod_path .. "assets/gui/items/rare/bonnie_lucky_chip.dds"
local bonnie_chip_path = "guis/textures/pd2/crime_spree/csr_bonnie_chip"
local falcogini_keys_file = mod_path .. "assets/gui/items/uncommon/falcogini_keys.dds"
local falcogini_keys_path = "guis/textures/pd2/crime_spree/csr_falcogini_keys"
local glass_pistol_file = mod_path .. "assets/gui/items/contraband/glass_pistol.dds"
local glass_pistol_path = "guis/textures/pd2/crime_spree/csr_glass_pistol"
local bullets_file = mod_path .. "assets/gui/items/uncommon/evidence_rounds.dds"
local bullets_path = "guis/textures/pd2/crime_spree/csr_evidence_rounds"
local plush_shark_file = mod_path .. "assets/gui/items/rare/plush_shark.dds"
local plush_shark_path = "guis/textures/pd2/crime_spree/csr_plush_shark"
local toolbox_file = mod_path .. "assets/gui/items/uncommon/wolf_toolbox.dds"
local toolbox_path = "guis/textures/pd2/crime_spree/csr_toolbox"
local dozer_guide_file = mod_path .. "assets/gui/items/contraband/dozer_guide.dds"
local dozer_guide_path = "guis/textures/pd2/crime_spree/csr_dozer_guide"
local duct_tape_file = mod_path .. "assets/gui/items/common/duct_tape.dds"
local duct_tape_path = "guis/textures/pd2/crime_spree/csr_duct_tape"
local escape_plan_file = mod_path .. "assets/gui/items/common/escape_plan.dds"
local escape_plan_path = "guis/textures/pd2/crime_spree/csr_escape_plan"
local worn_bandaid_file = mod_path .. "assets/gui/items/common/worn_band_aid.dds"
local worn_bandaid_path = "guis/textures/pd2/crime_spree/csr_worn_bandaid"
local rebar_file = mod_path .. "assets/gui/items/common/piece_of_rebar.dds"
local rebar_path = "guis/textures/pd2/crime_spree/csr_rebar"
local overkill_rush_file = mod_path .. "assets/gui/items/uncommon/overkill_rush.dds"
local overkill_rush_path = "guis/textures/pd2/crime_spree/csr_overkill_rush"
local pink_slip_file = mod_path .. "assets/gui/items/uncommon/pink_slip.dds"
local pink_slip_path = "guis/textures/pd2/crime_spree/csr_pink_slip"
local the_edge_file = mod_path .. "assets/gui/items/uncommon/the_edge.dds"
local the_edge_path = "guis/textures/pd2/crime_spree/csr_the_edge"
local jiro_last_wish_file = mod_path .. "assets/gui/items/rare/jiro_last_wish.dds"
local jiro_last_wish_path = "guis/textures/pd2/crime_spree/csr_jiro_last_wish"
local dearest_possession_file = mod_path .. "assets/gui/items/rare/dearest_possession.dds"
local dearest_possession_path = "guis/textures/pd2/crime_spree/csr_dearest_possession"
local viklund_vinyl_file = mod_path .. "assets/gui/items/rare/viklund_vinyl.dds"
local viklund_vinyl_path = "guis/textures/pd2/crime_spree/csr_viklund_vinyl"
local equalizer_file = mod_path .. "assets/gui/items/contraband/equalizer.dds"
local equalizer_path = "guis/textures/pd2/crime_spree/csr_equalizer"
local crooked_badge_file = mod_path .. "assets/gui/items/contraband/crooked_badge.dds"
local crooked_badge_path = "guis/textures/pd2/crime_spree/csr_crooked_badge"
local dead_mans_trigger_file = mod_path .. "assets/gui/items/contraband/dead_mans_trigger.dds"
local dead_mans_trigger_path = "guis/textures/pd2/crime_spree/csr_dead_mans_trigger"
local half_a_glass_file = mod_path .. "assets/gui/items/common/half_a_glass.dds"
local half_a_glass_path = "guis/textures/pd2/crime_spree/csr_half_a_glass"
local cup_of_joe_file = mod_path .. "assets/gui/items/common/cup_of_joe.dds"
local cup_of_joe_path = "guis/textures/pd2/crime_spree/csr_cup_of_joe"
local lockes_beret_file = mod_path .. "assets/gui/items/rare/locke_beret.dds"
local lockes_beret_path = "guis/textures/pd2/crime_spree/csr_lockes_beret"
-- Wildcard icons
local familiar_friend_file = mod_path .. "assets/gui/items/wildcard/familiar_friend.dds"
local familiar_friend_path = "guis/textures/pd2/crime_spree/csr_familiar_friend"
local side_satchel_file = mod_path .. "assets/gui/items/wildcard/side_satchel.dds"
local side_satchel_path = "guis/textures/pd2/crime_spree/csr_side_satchel"
local turron_file = mod_path .. "assets/gui/items/wildcard/turron.dds"
local turron_path = "guis/textures/pd2/crime_spree/csr_turron"
local hippocratic_oath_file = mod_path .. "assets/gui/items/wildcard/hippocratic_oath.dds"
local hippocratic_oath_path = "guis/textures/pd2/crime_spree/csr_hippocratic_oath"
-- Pre-mirrored wildcard icons: texture_rect={w,0,-w,h} un-flips the visual and makes VertexColorTexturedRadial sweep CCW for the recharge animation.
local familiar_friend_mirror_file = mod_path .. "assets/gui/items/wildcard/familiar_friend_mirror.dds"
local familiar_friend_mirror_path = "guis/textures/pd2/crime_spree/csr_familiar_friend_mirror"
local side_satchel_mirror_file = mod_path .. "assets/gui/items/wildcard/side_satchel_mirror.dds"
local side_satchel_mirror_path = "guis/textures/pd2/crime_spree/csr_side_satchel_mirror"
local turron_mirror_file = mod_path .. "assets/gui/items/wildcard/turron_mirror.dds"
local turron_mirror_path = "guis/textures/pd2/crime_spree/csr_turron_mirror"
local hippocratic_oath_mirror_file = mod_path .. "assets/gui/items/wildcard/hippocratic_oath_mirror.dds"
local hippocratic_oath_mirror_path = "guis/textures/pd2/crime_spree/csr_hippocratic_oath_mirror"
-- Modifier icons
local guilty_conscience_file = mod_path .. "assets/gui/modifiers/guilty_conscience.dds"
local guilty_conscience_path = "guis/textures/pd2/crime_spree/csr_guilty_conscience"
local shocking_surprise_file = mod_path .. "assets/gui/modifiers/shocking_surprise.dds"
local shocking_surprise_path = "guis/textures/pd2/crime_spree/csr_shocking_surprise"

-- Button icons
local btn_back_file = mod_path .. "assets/gui/buttons/back.dds"
local btn_back_path = "guis/textures/pd2/crime_spree/csr_btn_back"
local btn_close_file = mod_path .. "assets/gui/buttons/close.dds"
local btn_close_path = "guis/textures/pd2/crime_spree/csr_btn_close"

-- Gage token icon (used by shop counter / reroll button / card prices)
local gage_token_file = mod_path .. "assets/gui/gage_token.dds"
local gage_token_path = "guis/textures/pd2/crime_spree/csr_gage_token"

-- Scrap icon (single texture, tinted by rarity at draw time)
local scrap_file = mod_path .. "assets/gui/items/scrap.dds"
local scrap_path = "guis/textures/pd2/crime_spree/csr_scrap"

-- Generic frame (one texture, tinted per rarity at draw time)
local frame_file = mod_path .. "assets/gui/items/item_frame.dds"
local frame_path = "guis/textures/pd2/crime_spree/csr_frame"

-- Mission-card atlas for extra vanilla heists added to the CS pool (see extra_heists.lua).
-- Ported 1:1 from "More Heists In Crime Spree". 7-col grid of 280x140 cells.
local mission_atlas_file = mod_path .. "assets/gui/missions/mission_atlas.texture"
local mission_atlas_path = "guis/textures/pd2/crime_spree/csr_mission_atlas"

-- Plush Shark guardian-invuln fullscreen vignette (blue pulse)
local guilt_vignette_file = mod_path .. "assets/gui/misc/vignette.texture"
local guilt_vignette_path = "guis/textures/pd2/crime_spree/csr_guilt_vignette"

-- Shocking Surprise taser-burst fullscreen overlay (cyan electric arcs)
local shocking_overlay_file = mod_path .. "assets/gui/misc/shocking_surprise_screen_overlay.texture"
local shocking_overlay_path = "guis/textures/pd2/crime_spree/csr_shocking_overlay"

-- Load textures
if DB and DB.create_entry then
	DB:create_entry(Idstring("texture"), Idstring(dog_tags_path), dog_tags_file)

	DB:create_entry(Idstring("texture"), Idstring(bonnie_chip_path), bonnie_chip_file)

	DB:create_entry(Idstring("texture"), Idstring(falcogini_keys_path), falcogini_keys_file)

	DB:create_entry(Idstring("texture"), Idstring(glass_pistol_path), glass_pistol_file)

	DB:create_entry(Idstring("texture"), Idstring(bullets_path), bullets_file)

	DB:create_entry(Idstring("texture"), Idstring(plush_shark_path), plush_shark_file)
	DB:create_entry(Idstring("texture"), Idstring(guilt_vignette_path), guilt_vignette_file)
	DB:create_entry(Idstring("texture"), Idstring(shocking_overlay_path), shocking_overlay_file)

	DB:create_entry(Idstring("texture"), Idstring(toolbox_path), toolbox_file)

	DB:create_entry(Idstring("texture"), Idstring(dozer_guide_path), dozer_guide_file)

	DB:create_entry(Idstring("texture"), Idstring(duct_tape_path), duct_tape_file)

	DB:create_entry(Idstring("texture"), Idstring(escape_plan_path), escape_plan_file)

	DB:create_entry(Idstring("texture"), Idstring(worn_bandaid_path), worn_bandaid_file)

	DB:create_entry(Idstring("texture"), Idstring(rebar_path), rebar_file)

	DB:create_entry(Idstring("texture"), Idstring(overkill_rush_path), overkill_rush_file)

	DB:create_entry(Idstring("texture"), Idstring(pink_slip_path), pink_slip_file)
	DB:create_entry(Idstring("texture"), Idstring(the_edge_path), the_edge_file)

	DB:create_entry(Idstring("texture"), Idstring(jiro_last_wish_path), jiro_last_wish_file)

	DB:create_entry(Idstring("texture"), Idstring(dearest_possession_path), dearest_possession_file)

	DB:create_entry(Idstring("texture"), Idstring(viklund_vinyl_path), viklund_vinyl_file)

	DB:create_entry(Idstring("texture"), Idstring(equalizer_path), equalizer_file)

	DB:create_entry(Idstring("texture"), Idstring(crooked_badge_path), crooked_badge_file)

	DB:create_entry(Idstring("texture"), Idstring(dead_mans_trigger_path), dead_mans_trigger_file)

	DB:create_entry(Idstring("texture"), Idstring(half_a_glass_path), half_a_glass_file)

	DB:create_entry(Idstring("texture"), Idstring(cup_of_joe_path), cup_of_joe_file)

	DB:create_entry(Idstring("texture"), Idstring(lockes_beret_path), lockes_beret_file)

	-- Wildcard items
	DB:create_entry(Idstring("texture"), Idstring(familiar_friend_path), familiar_friend_file)
	DB:create_entry(Idstring("texture"), Idstring(side_satchel_path), side_satchel_file)
	DB:create_entry(Idstring("texture"), Idstring(turron_path), turron_file)
	DB:create_entry(Idstring("texture"), Idstring(hippocratic_oath_path), hippocratic_oath_file)

	-- Pre-mirrored wildcard icons (HUD slot CCW recharge — see comment above).
	DB:create_entry(Idstring("texture"), Idstring(familiar_friend_mirror_path), familiar_friend_mirror_file)
	DB:create_entry(Idstring("texture"), Idstring(side_satchel_mirror_path), side_satchel_mirror_file)
	DB:create_entry(Idstring("texture"), Idstring(turron_mirror_path), turron_mirror_file)
	DB:create_entry(Idstring("texture"), Idstring(hippocratic_oath_mirror_path), hippocratic_oath_mirror_file)

	-- Modifier icons
	DB:create_entry(Idstring("texture"), Idstring(guilty_conscience_path), guilty_conscience_file)
	DB:create_entry(Idstring("texture"), Idstring(shocking_surprise_path), shocking_surprise_file)

	DB:create_entry(Idstring("texture"), Idstring(scrap_path), scrap_file)

	-- Button icons
	DB:create_entry(Idstring("texture"), Idstring(btn_back_path), btn_back_file)
	DB:create_entry(Idstring("texture"), Idstring(btn_close_path), btn_close_file)

	-- Gage token icon
	DB:create_entry(Idstring("texture"), Idstring(gage_token_path), gage_token_file)

	-- Generic frame
	DB:create_entry(Idstring("texture"), Idstring(frame_path), frame_file)

	-- Mission-card atlas (extra vanilla heists)
	DB:create_entry(Idstring("texture"), Idstring(mission_atlas_path), mission_atlas_file)
end

local old_icons_init = HudIconsTweakData.init
function HudIconsTweakData:init()
	old_icons_init(self)

	-- Add icons directly into self (not into self.textures!)
	self.csr_dog_tags = {
		texture = dog_tags_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_scrap = {
		texture = scrap_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_bonnie_chip = {
		texture = bonnie_chip_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_falcogini_keys = {
		texture = falcogini_keys_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_glass_pistol = {
		texture = glass_pistol_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_evidence_rounds = {
		texture = bullets_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_plush_shark = {
		texture = plush_shark_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_toolbox = {
		texture = toolbox_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_dozer_guide = {
		texture = dozer_guide_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_duct_tape = {
		texture = duct_tape_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_escape_plan = {
		texture = escape_plan_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_jiro_last_wish = {
		texture = jiro_last_wish_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_dearest_possession = {
		texture = dearest_possession_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_worn_bandaid = {
		texture = worn_bandaid_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_cup_of_joe = {
		texture = cup_of_joe_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_rebar = {
		texture = rebar_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_overkill_rush = {
		texture = overkill_rush_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_pink_slip = {
		texture = pink_slip_path,
		texture_rect = { 0, 0, 128, 128 },
	}
	self.csr_the_edge = {
		texture = the_edge_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_viklund_vinyl = {
		texture = viklund_vinyl_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_equalizer = {
		texture = equalizer_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_crooked_badge = {
		texture = crooked_badge_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_dead_mans_trigger = {
		texture = dead_mans_trigger_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_half_a_glass = {
		texture = half_a_glass_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_lockes_beret = {
		texture = lockes_beret_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	-- Wildcard items
	self.csr_familiar_friend = {
		texture = familiar_friend_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_side_satchel = {
		texture = side_satchel_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_turron = {
		texture = turron_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_hippocratic_oath = {
		texture = hippocratic_oath_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	-- Pre-mirrored wildcard icons (HUD slot CCW recharge — see DB section above)
	self.csr_familiar_friend_mirror = {
		texture = familiar_friend_mirror_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_side_satchel_mirror = {
		texture = side_satchel_mirror_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_turron_mirror = {
		texture = turron_mirror_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	self.csr_hippocratic_oath_mirror = {
		texture = hippocratic_oath_mirror_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	-- Generic frame (tinted per rarity at draw time)
	self.csr_frame = {
		texture = frame_path,
		texture_rect = { 0, 0, 256, 256 },
	}

	-- Modifier icons
	self.csr_guilty_conscience = {
		texture = guilty_conscience_path,
		texture_rect = { 0, 0, 128, 128 },
	}
	self.csr_shocking_surprise = {
		texture = shocking_surprise_path,
		texture_rect = { 0, 0, 128, 128 },
	}

	-- Mission-card icons for the extra vanilla heists (see extra_heists.lua).
	-- {col, row} into the 280x140-cell atlas; keys are "csm_<stage_id>" to match
	-- the mission.icon field. Mapping is 1:1 with "More Heists In Crime Spree".
	local csm_w, csm_h = 280, 140
	local atlas_cells = {
		vit = { 2, 0 },
		family = { 3, 0 },
		kenaz = { 4, 0 },
		jewelry_store = { 5, 0 },
		gallery = { 6, 0 },
		nightclub = { 1, 1 },
		mallcrasher = { 4, 1 },
		shoutout_raid = { 5, 1 },
		crojob2_d = { 0, 2 },
		bph = { 1, 2 },
		nmh = { 2, 2 },
		des = { 3, 2 },
		peta_1 = { 4, 2 },
		peta_2 = { 5, 2 },
		watchdogs_2_d = { 6, 2 },
		election_day_3 = { 0, 3 },
		mex = { 1, 3 },
		mex_cooking = { 2, 3 },
		fex = { 5, 3 },
		chas = { 6, 3 },
		sand = { 0, 4 },
		chca = { 1, 4 },
		pent = { 2, 4 },
		ranc = { 3, 4 },
		trai = { 4, 4 },
		corp = { 5, 4 },
		deep = { 6, 4 },
	}
	for id, cell in pairs(atlas_cells) do
		self["csm_" .. id] = {
			texture = mission_atlas_path,
			texture_rect = { csm_w * cell[1], csm_h * cell[2], csm_w, csm_h },
		}
	end
	-- Extras that reuse an existing vanilla card icon (atlas has no cell for them).
	self.csm_ukrainian_job = self.csm_jewelry_store
	self.csm_welcome_to_the_jungle_1_d = self.csm_bigoil_1
	self.csm_election_day_1 = self.csm_election_1
	-- dah reuses vanilla self.csm_dah (no entry needed).

	-- Vanilla CS modifier icons intentionally NOT overridden; DLC texture paths don't work from mods
end

csr_log("[CSR Logbook] hudicons.lua loaded; DB available=" .. tostring(DB ~= nil and DB.create_entry ~= nil))
