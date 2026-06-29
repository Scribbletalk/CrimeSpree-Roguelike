-- Perk-deck regen scaling: rank passives boost the armor/health that perk decks restore, by the
-- same per-rank factors as max armor/health (CSR_ARMOR_PER_RANK / CSR_HP_PER_RANK from rank_passives).
-- Covers 11 decks (Sociopath, Gambler, Grinder, Ex-Pres, Maniac, Anarchist, Biker, Kingpin, Tag Team,
-- Hacker, Copycat); Kingpin is the one NERF. Hooked on 4 scripts (mod.txt), each _G-flag-guarded once,
-- no-op outside a CSR heist. Per-deck map + rationale: see csr_perk_deck_scaling_deep_dive.md.

if not RequiredScript then
	return
end

-- Per-frame cached rank (refreshed by rank_passives.lua's PlayerDamage:update hook). Reading a
-- global avoids re-running in_csr_heist()/host_rank() on every upgrade getter. 0 outside a CSR heist.
local function run_rank()
	return _G.CSR_active_rank or 0
end

local function hp_mult(r)
	return 1 + (_G.CSR_HP_PER_RANK or 0) * r
end

local function armor_mult(r)
	return 1 + (_G.CSR_ARMOR_PER_RANK or 0) * r
end

-- Kingpin (#17) NERF: enemy damage climbs ~5%/rank under CSR, so the injector overheal->cooldown
-- threshold must climb the same. Kingpin-specific, not a rank_passives export.
local INJECTOR_THRESHOLD_PER_RANK = 0.05

-- Debug tracing gated on _G.CSR_DEBUG; checked before string.format since the wraps sit on hot paths.
local function dbg(fmt, ...)
	if _G.CSR_DEBUG then
		csr_log(string.format(fmt, ...))
	end
end

-- Scale Tag Team's kill_health_gain; shallow copy so other fields (radius/targeting) stay untouched.
local function scale_tag_team_base(v, mult)
	local copy = {}
	for k, val in pairs(v) do
		copy[k] = val
	end
	copy.kill_health_gain = v.kill_health_gain * mult
	return copy
end

-- Tag Team (aced) absorption {kill_gain, max}: scale both - kill_gain alone just hits max faster.
local function scale_tag_team_absorption(v, mult)
	local copy = {}
	for k, val in pairs(v) do
		copy[k] = val
	end
	copy.kill_gain = v.kill_gain * mult
	copy.max = v.max * mult
	return copy
end

-- Anarchist armor-on-damage: array of {armor_value, target_tick} pairs per armor tier. Scale only
-- armor_value [1] (target_tick [2] is the interval); copy each pair so tweak_data stays untouched.
local function scale_damage_to_armor(v, mult)
	local copy = {}
	for i, pair in ipairs(v) do
		copy[i] = { pair[1] * mult, pair[2] }
	end
	return copy
end

-- Only these player-category upgrades are scaled; gate on a hash lookup so the ~13-branch
-- elseif chain (and run_rank) is skipped for every other upgrade_value("player", ...) call.
local SCALED_PLAYER_UPGRADES = {
	killshot_regen_armor_bonus = true,
	killshot_close_regen_armor_bonus = true,
	damage_to_hot = true,
	armor_health_store_amount = true,
	armor_max_health_store_multiplier = true,
	tag_team_base = true,
	tag_team_damage_absorption = true,
	damage_to_armor = true,
	armor_grinding = true,
	wild_health_amount = true,
	wild_armor_amount = true,
	chico_injector_health_to_speed = true,
	headshot_regen_health_bonus = true,
}

-- PlayerManager:upgrade_value - all local-getter decks. Key-gated so unrelated upgrades tail-call.
-- MP-safe: runs on the acting player's own client; run_rank() uses synced host rank.
if PlayerManager and not _G._CSR_PerkScale_Upgrade then
	_G._CSR_PerkScale_Upgrade = true
	local orig = PlayerManager.upgrade_value
	if orig then
		function PlayerManager:upgrade_value(category, upgrade, default)
			if category == "player" and SCALED_PLAYER_UPGRADES[upgrade] then
				if upgrade == "killshot_regen_armor_bonus" or upgrade == "killshot_close_regen_armor_bonus" then
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_ARMOR_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg("[CSR][perk_armor] Sociopath %s %g -> %g (rank %d, x%g)", upgrade, v, scaled, r, mult)
						return scaled
					end
					return v
				elseif upgrade == "damage_to_hot" then
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_HP_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg("[CSR][perk_heal] Grinder damage_to_hot %g -> %g (rank %d, x%g)", v, scaled, r, mult)
						return scaled
					end
					return v
				elseif upgrade == "armor_health_store_amount" then
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_HP_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg(
							"[CSR][perk_heal] ExPresident armor_health_store_amount %g -> %g (rank %d, x%g)",
							v,
							scaled,
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "armor_max_health_store_multiplier" then
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_HP_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg(
							"[CSR][perk_heal] ExPresident armor_max_health_store_multiplier %g -> %g (rank %d, x%g)",
							v,
							scaled,
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "tag_team_base" then
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					if r > 0 and type(v) == "table" and type(v.kill_health_gain) == "number" then
						local mult = hp_mult(r)
						local scaled = scale_tag_team_base(v, mult)
						dbg(
							"[CSR][perk_heal] TagTeam owner kill_health_gain %g -> %g (rank %d, x%g)",
							v.kill_health_gain,
							scaled.kill_health_gain,
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "tag_team_damage_absorption" then
					-- Owner-only (tagged side never reads this); getter only fires when aced -> no leak.
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					if r > 0 and type(v) == "table" and type(v.kill_gain) == "number" and type(v.max) == "number" then
						local mult = armor_mult(r)
						local scaled = scale_tag_team_absorption(v, mult)
						dbg(
							"[CSR][perk_armor] TagTeam absorption kill_gain %g->%g max %g->%g (rank %d, x%g)",
							v.kill_gain,
							scaled.kill_gain,
							v.max,
							scaled.max,
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "damage_to_armor" then
					-- Anarchist flat armor regen per damage-tick. Cached at spawn, local-only.
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					if r > 0 and type(v) == "table" and type(v[1]) == "table" and type(v[1][1]) == "number" then
						local mult = armor_mult(r)
						local scaled = scale_damage_to_armor(v, mult)
						dbg(
							"[CSR][perk_armor] Anarchist damage_to_armor armor %g -> %g (rank %d, x%g)",
							v[1][1],
							scaled[1][1],
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "armor_grinding" then
					-- Anarchist segmented regen. Scale armor_value only; keep target_tick so refill time tracks scaled max.
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					if r > 0 and type(v) == "table" and type(v[1]) == "table" and type(v[1][1]) == "number" then
						local mult = armor_mult(r)
						local scaled = scale_damage_to_armor(v, mult)
						dbg(
							"[CSR][perk_armor] Anarchist armor_grinding armor %g -> %g (rank %d, x%g)",
							v[1][1],
							scaled[1][1],
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "wild_health_amount" then
					-- Biker flat HP per kill (absolute, no double-dip with max-HP scaling).
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_HP_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg("[CSR][perk_heal] Biker wild_health_amount %g -> %g (rank %d, x%g)", v, scaled, r, mult)
						return scaled
					end
					return v
				elseif upgrade == "wild_armor_amount" then
					-- Biker flat armor per kill; same path as wild_health_amount.
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_ARMOR_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg("[CSR][perk_armor] Biker wild_armor_amount %g -> %g (rank %d, x%g)", v, scaled, r, mult)
						return scaled
					end
					return v
				elseif upgrade == "chico_injector_health_to_speed" then
					-- Kingpin NERF: raise overheal threshold by 5%/rank so cooldown drain stays meaningful vs CSR damage growth.
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					if r > 0 and type(v) == "table" and type(v[1]) == "number" and v[1] > 0 then
						local mult = 1 + INJECTOR_THRESHOLD_PER_RANK * r
						local scaled = { v[1] * mult, v[2] }
						dbg(
							"[CSR][perk_nerf] Kingpin injector threshold %g -> %g (rank %d, x%g)",
							v[1],
							scaled[1],
							r,
							mult
						)
						return scaled
					end
					return v
				elseif upgrade == "headshot_regen_health_bonus" then
					-- Copycat flat HP per headshot; absolute value, read fresh each hit.
					local v = orig(self, category, upgrade, default)
					local r = run_rank()
					local per = _G.CSR_HP_PER_RANK or 0
					if r > 0 and per > 0 and type(v) == "number" and v > 0 then
						local mult = 1 + per * r
						local scaled = v * mult
						dbg(
							"[CSR][perk_heal] Copycat headshot_regen_health_bonus %g -> %g (rank %d, x%g)",
							v,
							scaled,
							r,
							mult
						)
						return scaled
					end
					return v
				end
			end
			return orig(self, category, upgrade, default)
		end
	end
end

-- PlayerManager:upgrade_value_nil -- Hacker self ECM heal-on-kill. Routed here (not upgrade_value) when unowned -> nil-guard required.
if PlayerManager and not _G._CSR_PerkScale_UpgradeNil then
	_G._CSR_PerkScale_UpgradeNil = true
	local orig = PlayerManager.upgrade_value_nil
	if orig then
		function PlayerManager:upgrade_value_nil(category, upgrade)
			if category == "player" and upgrade == "pocket_ecm_heal_on_kill" then
				local v = orig(self, category, upgrade)
				local r = run_rank()
				local per = _G.CSR_HP_PER_RANK or 0
				if r > 0 and per > 0 and type(v) == "number" and v > 0 then
					local mult = 1 + per * r
					local scaled = v * mult
					dbg("[CSR][perk_heal] Hacker self pocket_ecm_heal %g -> %g (rank %d, x%g)", v, scaled, r, mult)
					return scaled
				end
				return v
			end
			return orig(self, category, upgrade)
		end
	end
end

-- PlayerManager:temporary_upgrade_value -- Gambler self-heal {min,max}; scale both ends via fresh table.
if PlayerManager and not _G._CSR_PerkScale_TempUpgrade then
	_G._CSR_PerkScale_TempUpgrade = true
	local orig = PlayerManager.temporary_upgrade_value
	if orig then
		function PlayerManager:temporary_upgrade_value(category, upgrade, default)
			if category == "temporary" and upgrade == "loose_ammo_restore_health" then
				local v = orig(self, category, upgrade, default)
				local r = run_rank()
				local per = _G.CSR_HP_PER_RANK or 0
				if r > 0 and per > 0 and type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then
					local mult = 1 + per * r
					local scaled = { v[1] * mult, v[2] * mult }
					dbg(
						"[CSR][perk_heal] Gambler self {%g,%g} -> {%g,%g} (rank %d, x%g)",
						v[1],
						v[2],
						scaled[1],
						scaled[2],
						r,
						mult
					)
					return scaled
				end
				return v
			end
			return orig(self, category, upgrade, default)
		end
	end
end

-- AmmoClip:sync_net_event -- Gambler team-share heal. No getter to wrap; patch the shared multiplier around orig, pcall-restore to prevent cross-contamination.
if AmmoClip and not _G._CSR_PerkScale_AmmoShare then
	_G._CSR_PerkScale_AmmoShare = true
	local orig = AmmoClip.sync_net_event
	if orig then
		function AmmoClip:sync_net_event(event, peer)
			local td = tweak_data and tweak_data.upgrades and tweak_data.upgrades.loose_ammo_restore_health_values
			local heal_event = type(event) == "number"
				and event > AmmoClip.EVENT_IDS.bonnie_share_ammo
				and event ~= AmmoClip.EVENT_IDS.register_grenade
			if heal_event and td and type(td.multiplier) == "number" then
				local r = run_rank()
				local per = _G.CSR_HP_PER_RANK or 0
				if r > 0 and per > 0 then
					local saved = td.multiplier
					local mult = 1 + per * r
					td.multiplier = saved * mult
					dbg(
						"[CSR][perk_heal] Gambler team-share multiplier %g -> %g (rank %d, x%g)",
						saved,
						td.multiplier,
						r,
						mult
					)
					local ok, err = pcall(orig, self, event, peer)
					td.multiplier = saved
					if not ok then
						error(err)
					end
					return
				end
			end
			return orig(self, event, peer)
		end
	end
end

-- HuskPlayerBase:upgrade_value -- Tag Team tagged-heal. Owner is a remote husk on teammate clients, so heal comes here not PlayerManager.
if HuskPlayerBase and not _G._CSR_PerkScale_Husk then
	_G._CSR_PerkScale_Husk = true
	local orig = HuskPlayerBase.upgrade_value
	if orig then
		function HuskPlayerBase:upgrade_value(category, upgrade)
			if category == "player" and upgrade == "tag_team_base" then
				local v = orig(self, category, upgrade)
				local r = run_rank()
				if r > 0 and type(v) == "table" and type(v.kill_health_gain) == "number" then
					local mult = hp_mult(r)
					local scaled = scale_tag_team_base(v, mult)
					dbg(
						"[CSR][perk_heal] TagTeam tagged kill_health_gain %g -> %g (rank %d, x%g)",
						v.kill_health_gain,
						scaled.kill_health_gain,
						r,
						mult
					)
					return scaled
				end
				return v
			elseif category == "team" and upgrade == "pocket_ecm_heal_on_kill" then
				-- Hacker team heal-on-kill; owner is remote husk -> husk getter, not PlayerManager.
				local v = orig(self, category, upgrade)
				local r = run_rank()
				local per = _G.CSR_HP_PER_RANK or 0
				if r > 0 and per > 0 and type(v) == "number" and v > 0 then
					local mult = 1 + per * r
					local scaled = v * mult
					dbg("[CSR][perk_heal] Hacker team pocket_ecm_heal %g -> %g (rank %d, x%g)", v, scaled, r, mult)
					return scaled
				end
				return v
			end
			return orig(self, category, upgrade)
		end
	end
end

-- PlayerDamage:_init_armor_grinding_data -- Anarchist tier fix. Vanilla's equipped_armor(true,true) returns
-- level_1 while player is "civilian" at spawn -> heavy armor grinds at tier-1 rate. Recompute from actual armor.
if PlayerDamage and not _G._CSR_PerkScale_Grind then
	_G._CSR_PerkScale_Grind = true
	local orig = PlayerDamage._init_armor_grinding_data
	if orig then
		function PlayerDamage:_init_armor_grinding_data(...)
			local ret = orig(self, ...)
			if self._armor_grinding and managers.player and managers.blackmarket then
				local data = managers.player:upgrade_value("player", "armor_grinding", nil)
				local armor_id = managers.blackmarket:equipped_armor()
				local armor_tw = armor_id and tweak_data.blackmarket.armors[armor_id]
				local idx = armor_tw and armor_tw.upgrade_level
				if type(data) == "table" and idx and type(data[idx]) == "table" then
					self._armor_grinding.armor_value = data[idx][1]
					self._armor_grinding.target_tick = data[idx][2]
					dbg(
						"[CSR][perk_armor] Anarchist armor_grinding RE-IDX armor=%s idx=%d -> value=%g tick=%g",
						tostring(armor_id),
						idx,
						data[idx][1],
						data[idx][2]
					)
				end
			end
			return ret
		end
	end
end

-- PlayerManager:get_best_cocaine_damage_absorption -- Maniac flat damage mitigation. Wrapped at the cocaine getter (not damage_absorption) so Tag Team isn't double-scaled.
if PlayerManager and not _G._CSR_PerkScale_Cocaine then
	_G._CSR_PerkScale_Cocaine = true
	local orig = PlayerManager.get_best_cocaine_damage_absorption
	if orig then
		function PlayerManager:get_best_cocaine_damage_absorption(my_peer_id)
			local absorption, best_peer_id = orig(self, my_peer_id)
			local r = run_rank()
			local per = _G.CSR_ARMOR_PER_RANK or 0
			if r > 0 and per > 0 and type(absorption) == "number" and absorption > 0 then
				local mult = 1 + per * r
				local scaled = absorption * mult
				dbg("[CSR][perk_armor] Maniac cocaine absorption %g -> %g (rank %d, x%g)", absorption, scaled, r, mult)
				return scaled, best_peer_id
			end
			return absorption, best_peer_id
		end
	end
end

csr_log("[CSR] perk_deck_scaling.lua loaded")
