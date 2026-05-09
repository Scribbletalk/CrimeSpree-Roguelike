-- Crime Spree Roguelike - Matchmaking Integration
-- 1. Sets "csr_mod" lobby attribute so CSR players can find CSR lobbies
-- 2. Filters Crime.Net to only show CSR lobbies in CS mode
-- 3. Auto-kicks players without CSR mod (handshake timeout)

if not RequiredScript then
	return
end

local required = string.lower(RequiredScript)

----------------------------------------------
-- LAYER 1: Lobby attribute (host side)
-- Set csr_mod=1 on the lobby so CSR clients can filter for it
----------------------------------------------
if required == "lib/managers/crimespreemanager" then
	Hooks:PostHook(
		CrimeSpreeManager,
		"apply_matchmake_attributes",
		"CSR_SetModAttribute",
		function(self, lobby_attributes)
			if self:in_progress() and self:is_active() then
				lobby_attributes.csr_mod = 1
			end
		end
	)
end

----------------------------------------------
-- LAYER 2: Lobby filter (client side)
-- Override add_crimenet_server_job to block non-CSR CS lobbies
----------------------------------------------
if required == "lib/managers/crimenetmanager" then
	local function has_csr_mod(mods_data)
		if not mods_data then
			return false
		end
		if type(mods_data) == "table" then
			for _, entry in pairs(mods_data) do
				if type(entry) == "table" then
					for _, v in pairs(entry) do
						if type(v) == "string" and v:find("Crime Spree Roguelike") then
							return true
						end
					end
				elseif type(entry) == "string" and entry:find("Crime Spree Roguelike") then
					return true
				end
			end
		elseif type(mods_data) == "string" then
			return mods_data:find("Crime Spree Roguelike") ~= nil
		end
		return false
	end

	local _original_add_crimenet_server_job = MenuComponentManager.add_crimenet_server_job

	function MenuComponentManager:add_crimenet_server_job(data)
		if CSR_Settings and CSR_Settings.values.lobby_filter then
			if data and data.is_crime_spree and not has_csr_mod(data.mods) then
				return
			end
		end
		return _original_add_crimenet_server_job(self, data)
	end
end

----------------------------------------------
-- LAYER 3: Auto-kick (host side)
-- If a peer doesn't send CSR_Handshake within timeout, kick them
----------------------------------------------
if required == "lib/managers/crimespreemanager" then
	local VERIFY_TIMEOUT = 5 -- seconds
	_G.CSR_PendingVerification = _G.CSR_PendingVerification or {}

	Hooks:PostHook(CrimeSpreeManager, "on_peer_finished_loading", "CSR_VerifyPeerMod", function(self, peer)
		if not CSR_Settings or not CSR_Settings.values.lobby_filter then
			return
		end
		if not CSR_MP or not CSR_MP.is_host() or not peer then
			return
		end
		if
			not managers.crime_spree
			or not managers.crime_spree:is_active()
			or not managers.crime_spree:in_progress()
		then
			return
		end

		local pid = peer:id()
		if not pid or pid == 1 then
			return
		end

		_G.CSR_PendingVerification[pid] = true

		DelayedCalls:Add("CSR_VerifyPeer_" .. tostring(pid), VERIFY_TIMEOUT, function()
			if not _G.CSR_PendingVerification[pid] then
				return
			end

			_G.CSR_PendingVerification[pid] = nil

			local session = managers.network and managers.network:session()
			if not session then
				return
			end

			local target_peer = session:peer(pid)
			if not target_peer then
				return
			end

			local name = target_peer:name() or "Unknown"
			log("[CSR] Kicking peer " .. tostring(pid) .. " (" .. name .. ") — CSR mod not detected")

			-- Chat message visible to everyone including the kicked player
			if managers.chat then
				managers.chat:send_message(
					1,
					managers.network.account:username_id(),
					name .. " was kicked: Crime Spree Roguelike mod required (modworkshop.net/mod/55473)"
				)
			end

			-- Kick after delay so chat message is visible before disconnect
			DelayedCalls:Add("CSR_KickPeer_" .. tostring(pid), 5, function()
				local s = managers.network and managers.network:session()
				if not s then
					return
				end

				local p = s:peer(pid)
				if not p then
					return
				end

				s:send_to_peers("kick_peer", pid, 0)
				s:on_peer_kicked(p, pid, 0)
			end)
		end)
	end)

	Hooks:PostHook(CrimeSpreeManager, "on_left_lobby", "CSR_ClearVerification", function(self)
		_G.CSR_PendingVerification = {}
	end)
end
