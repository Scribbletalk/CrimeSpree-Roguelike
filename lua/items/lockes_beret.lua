-- Locke's Beret (rare) -- every 30s, heals the whole heister team.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/lockesberet.lua). Every INTERVAL seconds heals the
-- local player + (host only) bots, jokers (converted cops) and player-deployed
-- turrets by a hyperbolic %-of-max-HP -- same curve as Worn Band-Aid: first_pct
-- at 1 stack, asymptoting to max_pct. Values mirror the 6.2 constants
-- (first 0.10 / max 0.50 / interval 30).
--
-- MP: the 6.2 cross-peer broadcast (heal every player when any beret owner ticks)
-- is NOT ported -- that's the parked MP-sync slice. Here each owning peer heals
-- its OWN player on its OWN timer; the host heals the shared NPCs (vanilla never
-- syncs NPC heals back). SP = host, so the local player + bots both get healed.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local FIRST_PCT = 0.10
local MAX_PCT = 0.50
local INTERVAL = 30
local K = (MAX_PCT - FIRST_PCT) / FIRST_PCT

local function heal_pct(stacks)
	return MAX_PCT * stacks / (stacks + K)
end

-- Clamp-heal a CopDamage / TeamAIDamage / SentryGunDamage by %-of-max-HP. They
-- share the _HEALTH_INIT / _health / _health_ratio shape.
local function heal_npc(cd, pct)
	if not cd or cd._dead or cd._fatal then
		return
	end
	local max_hp = cd._HEALTH_INIT
	if not max_hp or max_hp <= 0 or not cd._health then
		return
	end
	cd._health = math.min(max_hp, cd._health + max_hp * pct)
	cd._health_ratio = cd._health / max_hp
end

local function apply_team_heal(stacks)
	local pct = heal_pct(stacks)
	if pct <= 0 then
		return
	end

	-- 1) Local player (restore_health takes internal HP; is_static = true).
	local pu = managers.player and managers.player:player_unit()
	if pu and alive(pu) then
		local pd = pu:character_damage()
		if pd and not pd:dead() and not pd:is_downed() and pd._max_health then
			local heal = pd:_max_health() * pct
			if heal > 0 then
				pd:restore_health(heal, true)
			end
		end
	end

	-- 2) Host only: the shared NPC team. Bots come through all_criminals with
	-- record.ai; jokers live in _converted_police; player turrets carry _owner_id
	-- (enemy/hacked turrets don't, so they're skipped).
	if not (Network and Network:is_server()) then
		return
	end
	local groupai = managers.groupai and managers.groupai:state()
	if not groupai then
		return
	end
	for _, record in pairs(groupai:all_criminals() or {}) do
		if record.ai and alive(record.unit) then
			heal_npc(record.unit:character_damage(), pct)
		end
	end
	for _, unit in pairs(groupai._converted_police or {}) do
		if alive(unit) then
			heal_npc(unit:character_damage(), pct)
		end
	end
	for _, unit in pairs(groupai:turrets() or {}) do
		if alive(unit) and unit:base() and unit:base()._owner_id then
			heal_npc(unit:character_damage(), pct)
		end
	end
end

_G.CSR.register_item({
	type = "lockes_beret",
	rarity = "rare",
	name = "csr_logbook_lockes_beret_name",
	desc = "csr_item_lockes_beret_desc",
	full_desc = "csr_logbook_lockes_beret_effect",
	notes = "csr_logbook_lockes_beret_notes",
	icon = "csr_lockes_beret",
	icon_scale = 1.0,

	hooks = {
		-- Local INTERVAL-second timer on PlayerManager:update; every owning peer
		-- runs its own. Per-frame cost is just a couple of guards + a dt add; the
		-- heal loop only runs once per interval.
		["lib/managers/playermanager"] = function()
			if _G._CSR_LOCKES_BERET_HOOKED then
				return
			end
			_G._CSR_LOCKES_BERET_HOOKED = true
			Hooks:PostHook(PlayerManager, "update", "CSR_LockesBeret_Tick", function(self, t, dt)
				local mgr = managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
					self._csr_lockes_t = 0
					return
				end
				local stacks = mgr:owned("lockes_beret")
				if stacks <= 0 then
					self._csr_lockes_t = 0
					return
				end
				local timer = (self._csr_lockes_t or 0) + (dt or 0)
				if timer < INTERVAL then
					self._csr_lockes_t = timer
					return
				end
				self._csr_lockes_t = timer - INTERVAL
				apply_team_heal(stacks)
				if mgr:debug_enabled() then
					mgr:debug_log(
						string.format("lockes_beret team heal (stacks=%d, %.0f%%)", stacks, heal_pct(stacks) * 100)
					)
				end
			end)
		end,
	},
})
