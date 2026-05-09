-- Crime Spree Roguelike - LOCKE'S BERET
-- Periodic team heal: every 30s heals everyone on the heister team
-- (local player, remote players, bots, jokers/converted cops, player-deployed turrets)
-- by hyperbolic % of max HP (5% at 1 stack, asymptote 50%).
--
-- Each peer with stacks > 0 runs its own local 30s timer. On tick:
--   1. Heal own local player.
--   2. If host: heal NPC team units (bots / jokers / turrets).
--   3. Broadcast MSG.LOCKES_HEAL(stacks) so every other peer heals their own player.
--
-- On receive (any peer): same as 1 + 2 using the sender's stack count.
-- The host always handles NPCs because vanilla doesn't sync those heals back.

if not RequiredScript then
	return
end

local function CSR_log(msg)
	if _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.debug_mode then
		log(msg)
	end
end

ModifierLockesBeret = ModifierLockesBeret or class(CSRBaseModifier)
ModifierLockesBeret.desc_id = "csr_lockes_beret_desc"

function ModifierLockesBeret:init(data)
	ModifierLockesBeret.super.init(self, data)
end

-- Heal a TeamAIDamage / CopDamage unit by clamped %-of-max.
local function heal_npc(cd, heal_pct)
	if not cd or cd._dead or cd._fatal then
		return
	end
	local max_hp = cd._HEALTH_INIT
	if not max_hp or max_hp <= 0 or not cd._health then
		return
	end
	cd._health = math.min(max_hp, cd._health + max_hp * heal_pct)
	cd._health_ratio = cd._health / max_hp
end

-- Apply the team heal originating from a peer with `stacks` Locke's Berets.
-- Heals the LOCAL player. If running on host, also heals bots/jokers/turrets.
function _G.CSR_LockesBeret_ApplyTeamHeal(stacks)
	CSR_log("[CSR][Beret] ApplyTeamHeal called stacks=" .. tostring(stacks))
	if not stacks or stacks <= 0 then
		CSR_log("[CSR][Beret] ABORT: invalid stacks")
		return
	end
	if not managers.crime_spree or not (managers.crime_spree:is_active() or managers.crime_spree:in_progress()) then
		CSR_log("[CSR][Beret] ABORT: CS not active/in_progress")
		return
	end

	local heal_pct = _G.CSR_LockesBeretHealPct(stacks)
	CSR_log("[CSR][Beret] heal_pct=" .. tostring(heal_pct) .. " (" .. tostring(heal_pct * 100) .. "% of max HP)")
	if heal_pct <= 0 then
		CSR_log("[CSR][Beret] ABORT: heal_pct <= 0")
		return
	end

	-- 1) Heal own local player (PlayerDamage:restore_health takes internal HP).
	-- block_item_healing skips ONLY the local-player heal (Berserker/Frenzy builds);
	-- NPC healing below is unaffected.
	local block_self = _G.CSR_Settings and _G.CSR_Settings.values and _G.CSR_Settings.values.block_item_healing
	if block_self then
		CSR_log("[CSR][Beret] self heal BLOCKED by block_item_healing setting")
	else
		local pu = managers.player and managers.player:player_unit()
		if pu and alive(pu) then
			local pd = pu:character_damage()
			if pd and not pd:dead() and not pd:is_downed() and pd._max_health then
				local max_hp = pd:_max_health()
				local heal = max_hp * heal_pct
				CSR_log(
					"[CSR][Beret] self heal: max_hp="
						.. tostring(max_hp)
						.. " heal="
						.. tostring(heal)
						.. " hp_before="
						.. tostring(pd._health)
				)
				if heal > 0 then
					pd:restore_health(heal, true)
					CSR_log("[CSR][Beret] self heal applied, hp_after=" .. tostring(pd._health))
				end
			else
				CSR_log("[CSR][Beret] self heal SKIPPED: dead/downed/no max_health")
			end
		else
			CSR_log("[CSR][Beret] self heal SKIPPED: no player unit")
		end
	end

	-- 2) Host-only: heal NPC team units.
	if not Network or not Network:is_server() then
		CSR_log("[CSR][Beret] NPC heal SKIPPED: not host")
		return
	end

	local groupai = managers.groupai and managers.groupai:state()
	if not groupai then
		CSR_log("[CSR][Beret] NPC heal ABORT: no groupai")
		return
	end

	local bot_count, joker_count, turret_count = 0, 0, 0

	-- Bots (TeamAI) come through all_criminals() with record.ai = true.
	for _, record in pairs(groupai:all_criminals() or {}) do
		if record.ai and alive(record.unit) then
			heal_npc(record.unit:character_damage(), heal_pct)
			bot_count = bot_count + 1
		end
	end

	-- Jokers (converted cops) live in _converted_police, not _criminals.
	for _, unit in pairs(groupai._converted_police or {}) do
		if alive(unit) then
			heal_npc(unit:character_damage(), heal_pct)
			joker_count = joker_count + 1
		end
	end

	-- Player-deployed sentry guns. _owner_id is set when a peer deploys a sentry;
	-- enemy SWAT turrets / hacked turrets don't have _owner_id, so they're skipped.
	-- SentryGunDamage uses _HEALTH_INIT / _health / _health_ratio (same shape as
	-- TeamAIDamage / CopDamage), so the heal_npc helper above handles it directly.
	for _, unit in pairs(groupai:turrets() or {}) do
		if alive(unit) and unit:base() and unit:base()._owner_id then
			heal_npc(unit:character_damage(), heal_pct)
			turret_count = turret_count + 1
		end
	end

	CSR_log(
		"[CSR][Beret] host healed NPCs: bots="
			.. tostring(bot_count)
			.. " jokers="
			.. tostring(joker_count)
			.. " turrets="
			.. tostring(turret_count)
	)
end

-- Local 30s tick driver. Runs on every peer who owns Locke's Beret.
if PlayerManager then
	Hooks:PostHook(PlayerManager, "update", "CSR_LockesBeret_Tick", function(self, t, dt)
		if not managers.crime_spree or not managers.crime_spree:is_active() then
			return
		end
		if not CSR_ActiveBuffs or not CSR_ActiveBuffs.lockes_beret_stacks then
			self._csr_lockes_beret_t = 0
			return
		end

		local C = _G.CSR_ItemConstants or {}
		local interval = C.lockes_beret_interval or 30

		self._csr_lockes_beret_t = (self._csr_lockes_beret_t or 0) + (dt or 0)
		if self._csr_lockes_beret_t < interval then
			return
		end
		self._csr_lockes_beret_t = 0

		local stacks = CSR_ActiveBuffs.lockes_beret_stacks
		CSR_log("[CSR][Beret] tick fired (interval=" .. tostring(interval) .. "s) stacks=" .. tostring(stacks))
		if not stacks or stacks <= 0 then
			CSR_log("[CSR][Beret] tick ABORT: no stacks")
			return
		end

		-- Heal locally + (if host) NPCs.
		_G.CSR_LockesBeret_ApplyTeamHeal(stacks)

		-- Broadcast to other peers so each heals own local player.
		-- Host receiving from clients will additionally heal NPCs in the receive handler.
		if
			_G.CSR_MP
			and CSR_MP.is_multiplayer
			and CSR_MP.is_multiplayer()
			and CSR_MP.MSG
			and CSR_MP.MSG.LOCKES_HEAL
			and LuaNetworking
		then
			CSR_log("[CSR][Beret] broadcasting LOCKES_HEAL to peers stacks=" .. tostring(stacks))
			LuaNetworking:SendToPeers(CSR_MP.MSG.LOCKES_HEAL, tostring(stacks))
		else
			CSR_log("[CSR][Beret] no broadcast (singleplayer or MP layer missing)")
		end
	end)
end

CSR_log("[CSR] LOCKE'S BERET modifier loaded!")
