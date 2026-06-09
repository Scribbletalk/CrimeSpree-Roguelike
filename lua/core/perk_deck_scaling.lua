-- Perk-deck regen scaling: CSR rank passives boost the armor/health that perk decks
-- restore, by the same per-rank factors as max armor / max health
-- (CSR_ARMOR_PER_RANK / CSR_HP_PER_RANK, exported by rank_passives.lua).
--
-- Decks covered:
--   Sociopath (#9)  -- kill-armor regen, two upgrade keys on PlayerManager:upgrade_value.
--   Gambler   (#10) -- loose-ammo-pickup health: self via PlayerManager:temporary_upgrade_value,
--                       team-share reconstructed receiver-side (AmmoClip:sync_net_event).
--   Grinder   (#11) -- damage-to-hot regen: per-tick heal rate (player.damage_to_hot) read
--                       fresh every tick, scaled on PlayerManager:upgrade_value. Local-only.
--   Ex-Pres.  (#13) -- per-kill stored-health (player.armor_health_store_amount) AND the store
--                       cap multiplier (player.armor_max_health_store_multiplier), both on
--                       PlayerManager:upgrade_value. The cap = body_armor_value("skill_max_health_store")
--                       x armor_max_health_store_multiplier; rank_passives only scales _max_armor (not
--                       body_armor_value), so we lift the ceiling via the multiplier instead -- the
--                       armor dependency (body_armor_value) is preserved. Local-only.
--   Tag Team  (#20) -- kill-heal: owner via PlayerManager:upgrade_value(tag_team_base),
--                       tagged via HuskPlayerBase:upgrade_value (owner is a remote husk).
--                       Damage absorption (aced): owner-only via PlayerManager:upgrade_value
--                       (tag_team_damage_absorption {kill_gain,max}); scaled by armor-per-rank.
--   Anarchist (#15) -- armor-on-damage-dealt: PlayerManager:upgrade_value(damage_to_armor), an
--                       array of {armor_value, target_tick} pairs (one per armor tier). Scale only
--                       armor_value by armor-per-rank. Read once at PlayerDamage:init -> locks at
--                       spawn. Local-only (own unit's restore_armor), no husk path. (Segmented
--                       armor scaling deferred -- not done here.)
--   Biker     (#16) -- per-kill flat heal: PlayerManager:upgrade_value(wild_health_amount) scaled by
--                       HP-per-rank, wild_armor_amount scaled by armor-per-rank. Both scalars read
--                       fresh per kill in _on_enemy_killed; is_static restore on own unit. Local-only.
--   Maniac    (#14) -- cocaine-stack damage absorption: PlayerManager:get_best_cocaine_damage_absorption
--                       returns FLAT mitigation (own or shared-best); scaled by armor-per-rank. Wrapped
--                       at the cocaine getter, not damage_absorption(), so Tag Team isn't double-scaled.
--                       Local-only (own client's incoming damage).
--
-- Hooked on 4 scripts (see mod.txt): playermanager, ammoclip, huskplayerbase, playerdamage. Each
-- wrap is _G-flag guarded so it installs exactly once. All wraps are no-ops outside a CSR heist.

if not RequiredScript then
	return
end

-- Rank we're playing at; mirrors rank_passives.lua. host_rank() so clients scale off the
-- host's synced rank. 0 outside a CSR heist -> every wrap below is a no-op.
local function run_rank()
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return 0
	end
	return (mgr.host_rank and mgr:host_rank()) or 0
end

local function hp_mult(r)
	return 1 + (_G.CSR_HP_PER_RANK or 0) * r
end

local function armor_mult(r)
	return 1 + (_G.CSR_ARMOR_PER_RANK or 0) * r
end

-- Per-scale debug tracing, controlled by the mod-options debug toggle (_G.CSR_DEBUG, set from
-- CSRGameManager._debug). Gate on it before string.format too: the wraps below sit on hot paths
-- (per-kill / per-damage-tick / per-loose-ammo-pickup), so skip the format cost when debug is off.
local function dbg(fmt, ...)
	if _G.CSR_DEBUG then
		csr_log(string.format(fmt, ...))
	end
end

-- Tag Team's kill-heal lives in tag_team_base.kill_health_gain. Return a shallow copy with
-- only that field scaled, so other consumers (radius/distance targeting) stay untouched.
local function scale_tag_team_base(v, mult)
	local copy = {}
	for k, val in pairs(v) do
		copy[k] = val
	end
	copy.kill_health_gain = v.kill_health_gain * mult
	return copy
end

-- Tag Team's (aced) damage absorption is a {kill_gain, max} table: kill_gain is added to a
-- running total per kill, clamped to max. Both are flat damage mitigation (armor-like), so
-- scale both -- scaling kill_gain alone would just reach the same ceiling faster.
local function scale_tag_team_absorption(v, mult)
	local copy = {}
	for k, val in pairs(v) do
		copy[k] = val
	end
	copy.kill_gain = v.kill_gain * mult
	copy.max = v.max * mult
	return copy
end

-- Anarchist's armor-on-damage is an array of {armor_value, target_tick} pairs, one per equipped
-- armor tier (PlayerDamage indexes it by the worn armor's upgrade_level). Scale only armor_value
-- ([1]); target_tick ([2]) is the regen interval, not an amount. Copy each pair so tweak_data
-- stays untouched.
local function scale_damage_to_armor(v, mult)
	local copy = {}
	for i, pair in ipairs(v) do
		copy[i] = { pair[1] * mult, pair[2] }
	end
	return copy
end

-- PlayerManager:upgrade_value -- Sociopath kill-armor (number) + Tag Team owner heal (table).
-- MP-safe: the killshot/activation runs on the acting player's own client, upgrade_value is
-- local, run_rank() uses the synced host rank -- same model as rank_passives _max_armor.
-- Key-gated first so the hot path (every other upgrade) is a single compare + tail call.
if PlayerManager and not _G._CSR_PerkScale_Upgrade then
	_G._CSR_PerkScale_Upgrade = true
	local orig = PlayerManager.upgrade_value
	if orig then
		function PlayerManager:upgrade_value(category, upgrade, default)
			if category == "player" then
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
					-- Owner-only (the tagged side never reads absorption). Runs on the acting
					-- player's own client, so scaling here is MP-safe like the tag_team_base owner
					-- branch. Getter is only called when the owner has the aced upgrade -> no leak.
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
					-- Anarchist: armor restored per damage-tick dealt. Read once at
					-- PlayerDamage:init and cached, so it locks at spawn (in-heist -> run_rank
					-- valid). Local-only (own unit's restore_armor), no husk path. Scale by
					-- armor-per-rank -- it's flat armor regen.
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
					-- Anarchist segmented armor (the deck core): after taking damage, regen armor_value
					-- armor every target_tick seconds, segment by segment. Same {armor_value, target_tick}
					-- shape as damage_to_armor; read once at PlayerDamage:_init_armor_grinding_data -> locks
					-- at spawn/revive. Local-only (change_armor on own unit). Scale only armor_value by
					-- armor-per-rank; target_tick (interval) untouched so refill time tracks scaled max armor.
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
					-- Biker: flat health restored per kill (is_static -> absolute HP, not a max-HP
					-- fraction, so no double-dip with max-HP scaling). Read fresh every kill in
					-- PlayerManager:_on_enemy_killed; local restore on own unit -> MP-safe. HP-per-rank.
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
					-- Biker: flat armor restored per kill. Same path/locality as wild_health_amount;
					-- scale by armor-per-rank.
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
				end
			end
			return orig(self, category, upgrade, default)
		end
	end
end

-- PlayerManager:temporary_upgrade_value -- Gambler self-heal. Returns the {min,max} pair
-- AmmoClip feeds to math.random; scale both ends -> a fresh table (never mutate tweak_data).
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

-- AmmoClip:sync_net_event -- Gambler team-share heal. The receiver rebuilds the heal from a
-- clamped wire value (no upgrade_value getter to wrap), so bump the shared multiplier in
-- place around the original call. Only the heal branch reads it; ammo-share / grenade ignore
-- it. pcall guarantees restore -- the multiplier is global (also read by self-heal), so a
-- stuck value would cross-contaminate.
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

-- HuskPlayerBase:upgrade_value -- Tag Team tagged-heal. On the tagged player's client the
-- owner is a remote husk, so the heal base comes from this getter, not PlayerManager. Scale
-- the same kill_health_gain field. Tagged-heal is MP-only (a bot tagged bails earlier).
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
			end
			return orig(self, category, upgrade)
		end
	end
end

-- PlayerDamage:_init_armor_grinding_data -- Anarchist segmented-armor TIER fix. Vanilla caches the
-- grinding {armor_value, target_tick} indexed by equipped_armor(true, true).upgrade_level at spawn;
-- chk_player_state=true makes equipped_armor return the DEFAULT armor (level_1) while the player is
-- briefly "civilian" at spawn, so heavy armor wrongly grinds at the suit's tier-1 rate. Recompute
-- from the actually-worn armor (equipped_armor() -- no civilian/kit override), reading the already-
-- rank-scaled grinding array back through our PlayerManager:upgrade_value wrap.
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

-- PlayerManager:get_best_cocaine_damage_absorption -- Maniac (#14) damage absorption. Cocaine
-- stacks convert to FLAT damage mitigation (subtracted from incoming attack_data.damage in
-- PlayerDamage, not a %); this getter returns the local player's effective absorption (own or the
-- best teammate's, since Maniac shares). Scale it by armor-per-rank -- same lane as armor. Returns
-- (absorption, best_peer_id); preserve both. Called with the local peer id from
-- PlayerManager:damage_absorption on the acting client -> MP-safe (host_rank synced). Wrapped at
-- the cocaine-only getter (not damage_absorption()) so Tag Team's _damage_absorption isn't
-- double-scaled. Return-value hook -- no PostHook can carry the return.
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
