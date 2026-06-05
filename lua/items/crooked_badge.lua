-- Crooked Badge (contraband) — shorter bleedout in exchange for downs back between assaults.

if not (_G.CSR and _G.CSR.register_item) then
	return
end

local K = 1.0

local function revive_chance(stacks)
	return 100 - 50 / (1 + K * (stacks - 1))
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

local function local_peer_id()
	local mgr = managers and managers.csr
	if mgr and mgr.local_peer_id then
		return mgr:local_peer_id()
	end
	return 1
end

-- True if the given peer owns Crooked Badge (local via owned(), remote via synced counts).
local function peer_owns_badge(peer_id)
	local mgr = managers and managers.csr
	if not mgr then
		return false
	end
	if peer_id == local_peer_id() then
		return (mgr.owned and mgr:owned("crooked_badge") or 0) > 0
	end
	local counts = mgr.player_items and mgr:player_items(peer_id)
	return type(counts) == "table" and (counts["crooked_badge"] or 0) > 0
end

local function send_badge_revive(peer_id)
	if not (LuaNetworking and _G.CSR_MP and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.BADGE_REVIVE) then
		return
	end
	pcall(function()
		LuaNetworking:SendToPeer(peer_id, CSR_MP.ITEM_MSG.BADGE_REVIVE, "")
	end)
end

-- Roll + grant assault-end revives on the LOCAL player, using the local owner's stacks.
-- Used by the host for its own player and by every remote owner on the host's ping.
local function grant_local_revives()
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

-- Host-authoritative dispatch: grant the host's own revives locally, then ping every
-- remote owner so each rolls + grants on its own machine (revives are locally authoritative).
local function host_on_assault_end()
	if not Network:is_server() then
		return
	end
	local mgr = managers and managers.csr
	if not (mgr and mgr.in_csr_heist and mgr:in_csr_heist()) then
		return
	end
	grant_local_revives()
	local session = managers.network and managers.network:session()
	if not session then
		return
	end
	for _, peer in pairs(session:peers() or {}) do
		local pid = peer and peer:id()
		if pid and pid ~= local_peer_id() and peer_owns_badge(pid) then
			send_badge_revive(pid)
		end
	end
end

-- Register the remote-owner handler once (runs on all peers; guests are the receivers).
local mp_handler_registered = false
local function ensure_mp_handler()
	if mp_handler_registered then
		return
	end
	if not (_G.CSR_MP and CSR_MP.register_handler and CSR_MP.ITEM_MSG and CSR_MP.ITEM_MSG.BADGE_REVIVE) then
		return
	end
	mp_handler_registered = true
	CSR_MP.register_handler(CSR_MP.ITEM_MSG.BADGE_REVIVE, function(sender, data, sender_num, is_from_host)
		if not is_from_host then
			return
		end
		grant_local_revives()
	end)
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
			-- Register the MP handler on every peer (loads before any assault ends; guests receive the ping).
			ensure_mp_handler()
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
				host_on_assault_end()
			end)
		end,
	},
})
