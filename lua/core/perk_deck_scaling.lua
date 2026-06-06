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
--
-- Hooked on 3 scripts (see mod.txt): playermanager, ammoclip, huskplayerbase. Each wrap
-- is _G-flag guarded so it installs exactly once. All wraps are no-ops outside a CSR heist.

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

-- Per-scale debug tracing. OFF in normal play: the wraps below sit on hot paths
-- (per-kill / per-damage-tick / per-loose-ammo-pickup), so gate the string.format behind
-- DEBUG to avoid GC churn. Flip to true while testing a perk deck's scaling.
local DEBUG = false
local function dbg(fmt, ...)
	if DEBUG then
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

csr_log("[CSR] perk_deck_scaling.lua loaded")
