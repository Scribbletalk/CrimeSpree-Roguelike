-- Crime Spree Roguelike — expand the mission-card pool with vanilla heists that
-- base Crime Spree omits. Ported from "More Heists In Crime Spree" (MHiCS),
-- normal heists only (no Holdout). Always on.
--
-- CSR reads tweak_data.crime_spree.missions (3 buckets: 1=stealth, 2=short loud,
-- 3=long loud) and picks one per bucket -> 3 cards. We append the extras after
-- vanilla builds the table. Bucket assignment + ghost derivation mirror MHiCS so
-- card slots keep their stealth/short/long meaning. add = CSR rank reward
-- (<=5 -> +1, <=7 -> +2, else +3).

-- stage_id = { value = add, ghost = optional override (0 loud, 1 stealth, 2 both) }
local EXTRA = {
	vit = { value = 13 },
	family = { value = 6 },
	kenaz = { value = 13 },
	jewelry_store = { value = 4 },
	ukrainian_job = { value = 5 },
	gallery = { value = 4 },
	welcome_to_the_jungle_1_d = { value = 4 },
	dah = { value = 8 },
	nightclub = { value = 5 },
	election_day_1 = { value = 1, ghost = 1 },
	mallcrasher = { value = 4 },
	shoutout_raid = { value = 8 },
	election_day_3 = { value = 6 },
	watchdogs_2_d = { value = 6 },
	crojob2_d = { value = 14 },
	bph = { value = 13 },
	nmh = { value = 13, ghost = 0 },
	des = { value = 14 },
	peta_1 = { value = 14 },
	peta_2 = { value = 14 },
	mex = { value = 14 },
	mex_cooking = { value = 7 },
	fex = { value = 10 },
	chas = { value = 5 },
	sand = { value = 9 },
	chca = { value = 8 },
	pent = { value = 9 },
	ranc = { value = 8 },
	trai = { value = 12 },
	corp = { value = 7 },
	deep = { value = 12 },
}

-- Derive stealth capability from the level's ghost flags (MHiCS repair_ghost_param).
local function resolve_ghost(tweak_data, level_id, override)
	if override ~= nil then
		return override
	end
	local level = tweak_data.levels[level_id]
	if level and (level.ghost_required or level.ghost_required_visual) then
		return 1 -- stealth only
	elseif level and level.ghost_bonus then
		return 2 -- loud + stealth
	end
	return 0 -- loud only
end

-- Buckets a mission belongs to (MHiCS add_mission): 1=stealth, 2=short loud, 3=long loud.
local function buckets_for(ghost, add)
	local b = {}
	if ghost > 0 then
		b[#b + 1] = 1
	end
	if ghost ~= 1 then
		if add <= 10 then
			b[#b + 1] = 2
		end
		if add >= 9 then
			b[#b + 1] = 3
		end
	end
	return b
end

Hooks:PostHook(CrimeSpreeTweakData, "init_missions", "CSR_ExtraHeists_init_missions", function(self, tweak_data)
	if type(self.missions) ~= "table" then
		return
	end
	local added = 0
	for stage_id, params in pairs(EXTRA) do
		local stage = tweak_data.narrative.stages[stage_id]
		if stage then
			local add = params.value or 3
			local ghost = resolve_ghost(tweak_data, stage_id, params.ghost)
			local mission = {
				stage_id = stage_id,
				id = stage_id,
				icon = "csm_" .. stage_id,
				add = add,
				level = stage,
			}
			for _, bucket in ipairs(buckets_for(ghost, add)) do
				self.missions[bucket] = self.missions[bucket] or {}
				table.insert(self.missions[bucket], mission)
			end
			added = added + 1
		end
	end
	if csr_log then
		csr_log("[CSR ExtraHeists] appended " .. tostring(added) .. " extra vanilla heists to mission pool")
	end
end)
