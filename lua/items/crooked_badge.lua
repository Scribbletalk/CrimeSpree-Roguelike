-- Crooked Badge (contraband) — shorter bleedout in exchange for downs back between assaults.

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

-- Vanilla has no add_revive(); write _revives directly (digest-encoded) and sync.
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
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
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
		-- Bleedout penalty, floored at 5s.
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
				if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) or type(base) ~= "number" then
					return base
				end
				local stacks = mgr:owned("crooked_badge")
				if stacks <= 0 then
					return base
				end
				return math.max(5, base - bleedout_penalty(stacks))
			end
		end,

		-- Revive after assault — host-authoritative state machine.
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
