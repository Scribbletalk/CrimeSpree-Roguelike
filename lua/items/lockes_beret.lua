-- Locke's Beret (rare) — every 30s, heal the whole heister team a %-of-max-HP.
-- Hyperbolic: 10% @ 1 stack, asymptotes to 50%.
-- Host heals shared NPCs (bots, jokers, deployed turrets); each peer heals its own player.

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

-- CopDamage / TeamAIDamage / SentryGunDamage share the _HEALTH_INIT / _health shape.
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

	-- Local player.
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

	-- Host only: shared NPCs (bots, jokers, player turrets).
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
		["lib/managers/playermanager"] = function()
			if _G._CSR_LOCKES_BERET_HOOKED then
				return
			end
			_G._CSR_LOCKES_BERET_HOOKED = true
			Hooks:PostHook(PlayerManager, "update", "CSR_LockesBeret_Tick", function(self, t, dt)
				local mgr = managers.csr
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
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
