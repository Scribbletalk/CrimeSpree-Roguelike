-- Crooked Badge (contraband) -- trade a shorter bleedout for downs back between
-- assaults.
--
-- Per-item-file model (see cup_of_joe.lua). Text fields are localization keys.
-- Ported from 6.2 (modifiers/crookedbadge.lua), two hooks:
--   * PlayerDamage:down_time (chain-wrap, Rule #1 return-value exception): shorten
--     the bleedout timer by a hyperbolic penalty, floored at 5s.
--   * GroupAIStateBesiege:_begin_regroup_task (PostHook, HOST-ONLY): when an
--     assault ends, roll a hyperbolic revive chance and add downs back. Chance can
--     exceed 100% (guaranteed downs + a fractional roll).
--
-- Hyperbolic curves (K = 0.05, from 6.2 crooked_badge_k):
--   revive chance %   = 400 - 370/(1 + K*(stacks-1))   -> 30% @ 1 stack
--   bleedout penalty  = 25  - 15 /(1 + K*(stacks-1))   -> 10s @ 1 stack
--
-- MP DEFERRED: 6.2 also broadcast MSG.ASSAULT_END so each client rolled its own
-- revive (the vanilla assault state machine is host-authoritative -- clients never
-- run _begin_regroup_task). That RPC is part of the parked MP-sync slice; here only
-- the host's local player gets the revive. No per-mission state, so no reset hook.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local K = 0.05

local function revive_chance(stacks)
	return 400 - 370 / (1 + K * (stacks - 1))
end

local function bleedout_penalty(stacks)
	return 25 - 15 / (1 + K * (stacks - 1))
end

-- Add one down if below the max, mirroring vanilla's revive accounting. Vanilla
-- has no add_revive(), so write _revives directly (digest-encoded) and sync.
local function try_add_revive(pd)
	local ok, current = pcall(function()
		return Application:digest_value(pd._revives, false)
	end)
	if not ok or type(current) ~= "number" then
		return
	end
	local bonus = 0
	pcall(function()
		bonus = managers.player:upgrade_value("player", "additional_lives", 0)
	end)
	local max_revives = (pd._lives_init or 1) + bonus
	if current >= max_revives then
		return
	end
	pd._revives = Application:digest_value(math.min(max_revives, current + 1), true)
	pcall(function()
		pd:_send_set_revives()
	end)
end

local function on_assault_end()
	local mgr = managers and managers.csr
	if not (mgr and mgr.is_run_active and mgr:is_run_active()) then
		return
	end
	local stacks = mgr:owned("crooked_badge")
	if stacks <= 0 then
		return
	end
	local player_unit = managers.player and managers.player:player_unit()
	local pd = player_unit and player_unit:character_damage()
	if not pd then
		return
	end
	local chance = revive_chance(stacks) / 100
	local guaranteed = math.floor(chance)
	for _ = 1, guaranteed do
		try_add_revive(pd)
	end
	if math.random() < (chance - guaranteed) then
		try_add_revive(pd)
	end
end

_G.CSR.register_item({
	type = "crooked_badge",
	rarity = "contraband",
	name = "csr_logbook_crooked_badge_name",
	desc = "csr_item_crooked_badge_desc",
	full_desc = "csr_logbook_crooked_badge_effect",
	notes = "csr_logbook_crooked_badge_notes",
	icon = "csr_crooked_badge",
	icon_scale = 1.0,

	hooks = {
		-- Bleedout penalty: shorten down_time(), floored at 5s. Return-value method
		-- -> raw chain-wrap; _G guard stops a double-wrap.
		["lib/units/beings/player/playerdamage"] = function()
			if _G._CSR_CROOKED_BADGE_HOOKED then
				return
			end
			_G._CSR_CROOKED_BADGE_HOOKED = true
			local orig = PlayerDamage.down_time
			if not orig then
				return
			end
			function PlayerDamage:down_time()
				local base = orig(self)
				local mgr = managers and managers.csr
				if not (mgr and mgr.is_run_active and mgr:is_run_active()) or type(base) ~= "number" then
					return base
				end
				local stacks = mgr:owned("crooked_badge")
				if stacks <= 0 then
					return base
				end
				return math.max(5, base - bleedout_penalty(stacks))
			end
		end,

		-- Revive after assault (host-authoritative state machine -> host only).
		["lib/managers/group_ai_states/groupaistatebesiege"] = function()
			if _G._CSR_CROOKED_BADGE_REGROUP_HOOKED then
				return
			end
			_G._CSR_CROOKED_BADGE_REGROUP_HOOKED = true
			Hooks:PostHook(GroupAIStateBesiege, "_begin_regroup_task", "CSR_CrookedBadge_Regroup", function()
				if not Network:is_server() then
					return
				end
				on_assault_end()
			end)
		end,
	},
})
